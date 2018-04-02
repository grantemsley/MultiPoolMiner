using module ..\Include.psm1

param(
    [alias("UserName")]
    [String]$User, 
    [alias("WorkerName")]
    [String]$Worker, 
    [TimeSpan]$StatSpan,
    [bool]$Info = $false,
    [PSCustomObject]$Config
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

# Default pool config values, these need to be present for pool logic
$Default_PoolFee = 0.9
$Config.Pools.$Name | Add-Member PoolFee $Default_PoolFee -ErrorAction SilentlyContinue # ignore error if value exists

$Pool_APIUrl = "http://miningpoolhub.com/index.php?page=api&action=getautoswitchingandprofitsstatistics"

if ($Info) {
    # Just return info about the pool for use in setup
    $Description  = "Payout and automatic conversion is configured through their website"
    $WebSite      = "https://miningpoolhub.com"
    $Note         = "Registration required" 

    try {
        $APIRequest = Invoke-RestMethod $Pool_APIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        Write-Log -Level Warn "Pool API ($Name) has failed. "
    }

    if ($APIRequest.return.count -le 1) {
        Write-Warning  "Unable to load supported algorithms and currencies for ($Name) - may not be able to configure all pool settings"
    }

    # Define the settings this pool uses.
    $SupportedAlgorithms = @($APIRequest.return | Foreach-Object {Get-Algorithm $_.algo} | Select-Object -Unique | Sort-Object)
    $Settings = @(
        [PSCustomObject]@{
            Name        = "Worker"
            Required    = $true
            Default     = $Worker
            ControlType = "string"
            Description = "Worker name to report to pool "
            Tooltip     = ""    
        },
        [PSCustomObject]@{
            Name        = "Username"
            Required    = $true
            Default     = $User
            ControlType = "string"
            Description = "$($Name) username"
            Tooltip     = "Registration at pool required"    
        },
        [PSCustomObject]@{
            Name        = "API_Key"
            Required    = $false
            Default     = $Worker
            ControlType = "string"
            Description = "Used to retrieve balances"
            Tooltip     = "API key can be found on the web page"    
        },
        [PSCustomObject]@{
            Name        = "DisabledAlgorithm"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of disabled algorithms for this miner. "
            Tooltip     = "Case insensitive, leave empty to mine all algorithms"
        },
        [PSCustomObject]@{
            Name        = "DisabledCoin"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of disabled coins for this miner. "
            Tooltip     = "Case insensitive, leave empty to mine all coins"
        },
        [PSCustomObject]@{
            Name        = "PoolFee"
            Required    = $false
            ControlType = "double"
            Min         = 0
            Max         = 100
            Fractions   = 2
            Default     = $Default_PoolFee
            Description = "Pool fee (in %)`nSet to 0 to ignore pool fees"
            Tooltip     = "$($Name) applies same fee for all algorithms"
        }
    )

    return [PSCustomObject]@{
        Name        = $Name
        WebSite     = $WebSite
        Description = $Description
        Algorithms  = $SupportedAlgorithms
        Note        = $Note
        Settings    = $Settings
    }
}

if ($User) {
    try {
        $APIRequest = Invoke-RestMethod $Pool_APIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop # required for fees
    }
    catch {
        Write-Log -Level Warn "Pool API ($Name) has failed. "
        return
    }

    if ($APIRequest.return.count -le 1) {
        Write-Log -Level Warn "Pool API ($Name) returned nothing. "
        return
    }

    $Regions = "europe", "us", "asia"

    $APIRequest.return | 
        # filter disabled algorithms
        Where-Object {$Config.Pools.$Name.DisabledAlgorithm -inotcontains (Get-Algorithm $_)} |

        # filter disabled coins
        Where-Object {$Config.Pools.$Name.DisabledCoin -inotcontains (Get-Culture).TextInfo.ToTitleCase(($_.current_mining_coin -replace "-", " " -replace "_", " ")) -replace " "} |
        
        ForEach-Object {
        $Hosts          = $_.all_host_list.split(";")
        $Port           = $_.algo_switch_port
        $Algorithm      = $_.algo
        $Algorithm_Norm = Get-Algorithm $Algorithm
        $Coin           = (Get-Culture).TextInfo.ToTitleCase(($_.current_mining_coin -replace "-", " " -replace "_", " ")) -replace " "
        
        # leave fee empty if IgnorePoolFee
        if (-not $Config.IgnorePoolFee -and $Config.Pools.$Name.PoolFee -gt 0) {
            $FeeInPercent = $Config.Pools.$Name.PoolFee
        }
        
        if ($FeeInPercent) {
            $FeeFactor = 1 - $FeeInPercent / 100
        }
        else {
            $FeeFactor = 1
        }

        if ($Algorithm_Norm -eq "Sia") {$Algorithm_Norm = "SiaClaymore"} #temp fix

        $Divisor = 1000000000

        $Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$_.profit / $Divisor) -Duration $StatSpan -ChangeDetection $true

        $Regions | ForEach-Object {
            $Region = $_
            $Region_Norm = Get-Region $Region

            [PSCustomObject]@{
                Algorithm     = $Algorithm_Norm
                Info          = $Coin
                Price         = $Stat.Live * $FeeFactor
                StablePrice   = $Stat.Week * $FeeFactor
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = $Hosts | Sort-Object -Descending {$_ -ilike "$Region*"} | Select-Object -First 1
                Port          = $Port
                User          = "$User.$Worker"
                Pass          = "x"
                Region        = $Region_Norm
                SSL           = $false
                Updated       = $Stat.Updated
                Fee           = $FeeInPercent
            }

            if ($Algorithm_Norm -eq "Cryptonight" -or $Algorithm_Norm -eq "Equihash") {
                [PSCustomObject]@{
                    Algorithm     = "$($Algorithm_Norm)2gb"
                    Info          = $Coin
                    Price         = $Stat.Live * $FeeFactor
                    StablePrice   = $Stat.Week * $FeeFactor
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+ssl"
                    Host          = $Hosts | Sort-Object -Descending {$_ -ilike "$Region*"} | Select-Object -First 1
                    Port          = $Port
                    User          = "$User.$Worker"
                    Pass          = "x"
                    Region        = $Region_Norm
                    SSL           = $true
                    Updated       = $Stat.Updated
                    Fee           = $FeeInPercent
               }
            }
        }
    }
}