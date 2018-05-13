using module ..\Include.psm1

param(
    [PSCustomObject]$Config,
    [TimeSpan]$StatSpan
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName
$Regions = "europe", "us-east", "asia"

# Default pool config values, these need to be present for pool logic
$Default_PoolFee = 0.9
$Config.Pools.$Name | Add-Member PoolFee $Default_PoolFee -ErrorAction SilentlyContinue # ignore error if value exists

$Pool_APIUrl = "http://miningpoolhub.com/index.php?page=api&action=getminingandprofitsstatistics&$(Get-Date -Format "yyyy-MM-dd_HH-mm")"

if ($Config.InfoOnly) {
    # Just return info about the pool for use in setup
    $Description  = "This version lets MultiPoolMiner determine which coin to mine. The regular MiningPoolHub pool may work better, since it lets the pool avoid switching early and losing shares."
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
        return
    }

    # Define the settings this pool uses.
    $SupportedAlgorithms = @($APIRequest.return | Foreach-Object {Get-Algorithm $_.algo} | Select-Object -Unique | Sort-Object)
    $Settings = @(
        [PSCustomObject]@{
            Name        = "Worker"
            Required    = $true
            Default     = $Worker
            ControlType = "String"
            Description = "Worker name to report to pool "
            Tooltip     = ""    
        },
        [PSCustomObject]@{
            Name        = "Username"
            Required    = $true
            Default     = $User
            ControlType = "String"
            Description = "$($Name) username"
            Tooltip     = "Registration at pool required"    
        },
        [PSCustomObject]@{
            Name        = "API_Key"
            Required    = $false
            Default     = $Worker
            ControlType = "String"
            Description = "Used to retrieve balances"
            Tooltip     = "API key can be found on the web page"    
        },
        [PSCustomObject]@{
            Name        = "IgnorePoolFee"
            Required    = $false
            ControlType = "Bool"
            Default     = $false
            Description = "Tick to disable pool fee calculation for this pool"
            Tooltip     = "If ticked MPM will NOT take pool fees into account"
        },
        [PSCustomObject]@{
            Name        = "PricePenaltyFactor"
            Required    = $false
            ControlType = "double"
            Decimals    = 2
            Min         = 0.01
            Max         = 1
            Default     = 1
            Description = "This adds a multiplicator on estimations presented by the pool. "
            Tooltip     = "If not set then the default of 1 (no penalty) is used."
        },
        [PSCustomObject]@{
            Name        = "ExcludeCoin"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of excluded coins for this miner. "
            Tooltip     = "Case insensitive, leave empty to mine all coins"
        },
        [PSCustomObject]@{
            Name        = "Coin"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of coins this miner will mine. All other coins will be ignored. "
            Tooltip     = "Case insensitive, leave empty to mine all coins"    
        },
        [PSCustomObject]@{
            Name        = "ExcludeAlgorithm"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of excluded algorithms for this miner. "
            Tooltip     = "Case insensitive, leave empty to mine all algorithms"
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
        $APIRequest = Invoke-RestMethod $Pool_APIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        Write-Log -Level Warn "Pool API ($Name) has failed. "
        return
    }

    if ($APIRequest.return.count -le 1) {
        Write-Log -Level Warn "Pool API ($Name) returned nothing. "
        return
    }

    $APIRequest.return | ForEach-Object { # Add well formatted coin name, remove algorithm part
        $_ | Add-Member name ((Get-Culture).TextInfo.ToTitleCase(($_.coin_name -replace "-", " " -replace "_", " ")) -replace " ")
    }

    $APIRequest.return | 
        # allow well defined coins only
        Where-Object {$Config.Pools.$Name.Coin.Count -eq 0 -or ($Config.Pools.$Name.Coin -icontains $_.coin_name)} |

        # filter excluded coins
        Where-Object {$Config.Pools.$Name.ExcludeCoin -inotcontains $_.coin_name} |

        # filter excluded algorithms
        Where-Object {$Config.Pools.$Name.ExcludeAlgorithm -inotcontains (Get-Algorithm $_.algo)} |

        ForEach-Object {
        $PoolHost       = $_.host
        $Hosts          = $_.host_list.split(";")
        $Port           = $_.port
        $Algorithm      = $_.algo
        $Algorithm_Norm = Get-Algorithm $Algorithm
        $CoinName       = $_.name

        # leave fee empty if IgnorePoolFee
        if (-not $Config.IgnorePoolFee -and -not $Config.Pools.$Name.IgnorePoolFee) {$FeeInPercent = $APIRequest.$Algorithm.Fees}
        if ($FeeInPercent) {$FeeFactor = 1 - $FeeInPercent / 100} else {$FeeFactor = 1}

        $PricePenaltyFactor = $Config.Pools.$Name.PricePenaltyFactor
        if ($PricePenaltyFactor -le 0 -or $PricePenaltyFactor -gt 1) {$PricePenaltyFactor = 1}

        if ($Algorithm_Norm -eq "Sia") {$Algorithm_Norm = "SiaClaymore"} #temp fix

        $Divisor = 1000000000

        $Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$_.profit / $Divisor) -Duration $StatSpan -ChangeDetection $true

        $Regions | ForEach-Object {
            $Region = $_
            $Region_Norm = Get-Region ($Region -replace "^us-east$", "us")

            if ($Algorithm_Norm -eq "CryptonightV7") {
                [PSCustomObject]@{
                    Algorithm     = $Algorithm_Norm
                    Info          = $CoinName
                    Price         = $Stat.Live * $FeeFactor * $PricePenaltyFactor
                    StablePrice   = $Stat.Week * $FeeFactor * $PricePenaltyFactor
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+tcp"
                    Host          = "$($Region).cryptonight-$($Poolhost)"
                    Port          = $Port
                    User          = "$($Config.User).$($Config.Worker)"
                    Pass          = "x"
                    Region        = $Region_Norm
                    SSL           = $false
                    Updated       = $Stat.Updated
                    Fee           = $FeeInPercent
                }
                [PSCustomObject]@{
                    Algorithm     = $Algorithm_Norm
                    Info          = $CoinName
                    Price         = $Stat.Live * $FeeFactor * $PricePenaltyFactor
                    StablePrice   = $Stat.Week * $FeeFactor * $PricePenaltyFactor
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+ssl"
                    Host          = "$($Region).cryptonight-$($Poolhost)"
                    Port          = $Port
                    User          = "$($Config.User).$($Config.Worker)"
                    Pass          = "x"
                    Region        = $Region_Norm
                    SSL           = $true
                    Updated       = $Stat.Updated
                    Fee           = $FeeInPercent
                }
            }
            else {
                [PSCustomObject]@{
                    Algorithm     = $Algorithm_Norm
                    Info          = $CoinName
                    Price         = $Stat.Live * $FeeFactor * $PricePenaltyFactor
                    StablePrice   = $Stat.Week * $FeeFactor * $PricePenaltyFactor
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+tcp"
                    Host          = $Hosts | Sort-Object -Descending {$_ -ilike "$Region*"} | Select-Object -First 1
                    Port          = $Port
                    User          = "$($Config.User).$($Config.Worker)"
                    Pass          = "x"
                    Region        = $Region_Norm
                    SSL           = $false
                    Updated       = $Stat.Updated
                    Fee           = $FeeInPercent
                }

                if ($Algorithm_Norm -eq "Equihash") {
                    [PSCustomObject]@{
                        Algorithm     = $Algorithm_Norm
                        Info          = $CoinName
                        Price         = $Stat.Live * $FeeFactor * $PricePenaltyFactor
                        StablePrice   = $Stat.Week * $FeeFactor * $PricePenaltyFactor
                        MarginOfError = $Stat.Week_Fluctuation
                        Protocol      = "stratum+ssl"
                        Host          = $Hosts | Sort-Object -Descending {$_ -ilike "$Region*"} | Select-Object -First 1
                        Port          = $Port
                        User          = "$($Config.User).$($Config.Worker)"
                        Pass          = "x"
                        Region        = $Region_Norm
                        SSL           = $true
                        Updated       = $Stat.Updated
                        Fee           = $FeeInPercent
                    }
                }

                if ($Algorithm_Norm -eq "Ethash" -and $CoinName -NotLike "*ethereum*") {
                    [PSCustomObject]@{
                        Algorithm     = "$($Algorithm_Norm)2gb"
                        Info          = $CoinName
                        Price         = $Stat.Live * $FeeFactor * $PricePenaltyFactor
                        StablePrice   = $Stat.Week * $FeeFactor * $PricePenaltyFactor
                        MarginOfError = $Stat.Week_Fluctuation
                        Protocol      = "stratum+tcp"
                        Host          = $Hosts | Sort-Object -Descending {$_ -ilike "$Region*"} | Select-Object -First 1
                        Port          = $Port
                        User          = "$($Config.User).$($Config.Worker)"
                        Pass          = "x"
                        Region        = $Region_Norm
                        SSL           = $false
                        Updated       = $Stat.Updated
                        Fee           = $FeeInPercent
                    }
                }
            }
        }
    }
}
Sleep 0