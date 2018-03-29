using module ..\Include.psm1

param(
    [alias("UserName")]
    [String]$User, 
    [alias("WorkerName")]
    [String]$Worker, 
    [TimeSpan]$StatSpan,
    [bool]$Info = $false
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Pool_Request = [PSCustomObject]@{}

if ($Info) {
    # Just return info about the pool for use in setup
    $SupportedAlgorithms = @()
    try {
        $Pool_Request = Invoke-RestMethod "http://miningpoolhub.com/index.php?page=api&action=getautoswitchingandprofitsstatistics" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $Pool_Request.return | Foreach-Object {
            $SupportedAlgorithms += Get-Algorithm $_.algo
        }
    } Catch {
        Write-Warning "Unable to load supported algorithms for $Name - may not be able to configure all pool settings"
        $SupportedAlgorithms = @()
    }

    return [PSCustomObject]@{
        Name = $Name
        Website = "https://miningpoolhub.com"
        Description = "Payout and automatic conversion is configured through their website"
        Algorithms = $SupportedAlgorithms
        Note = "Registration required" # Note is shown beside each pool in setup
        # Define the settings this pool uses.
        Settings = @(
            @{Name='Username'; Required=$true; Description='MiningPoolHub username'},
            @{Name='Worker'; Required=$true; Description='Worker name to report to pool'},
            @{Name='API_Key'; Required=$false; Description='Used to retrieve balances'}
        )
    }
}

try {
    $Pool_Request = Invoke-RestMethod "http://miningpoolhub.com/index.php?page=api&action=getautoswitchingandprofitsstatistics" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
}
catch {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

if (($Pool_Request.return | Measure-Object).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

$Pool_Regions = "europe", "us", "asia"

$Pool_Request.return | Where-Object {$DisabledCoins -inotcontains $_.current_mining_coin -and $DisabledAlgorithms -inotcontains (Get-Algorithm $_.algo)} | ForEach-Object {
    $Pool_Hosts = $_.all_host_list.split(";")
    $Pool_Port = $_.algo_switch_port
    $Pool_Algorithm = $_.algo
    $Pool_Algorithm_Norm = Get-Algorithm $Pool_Algorithm
    $Pool_Coin = (Get-Culture).TextInfo.ToTitleCase(($_.current_mining_coin -replace "-", " " -replace "_", " ")) -replace " "

    if ($Pool_Algorithm_Norm -eq "Sia") {$Pool_Algorithm_Norm = "SiaClaymore"} #temp fix

    $Divisor = 1000000000

    $Stat = Set-Stat -Name "$($Name)_$($Pool_Algorithm_Norm)_Profit" -Value ([Double]$_.profit / $Divisor) -Duration $StatSpan -ChangeDetection $true

    $Pool_Regions | ForEach-Object {
        $Pool_Region = $_
        $Pool_Region_Norm = Get-Region $Pool_Region

        if ($User) {
            [PSCustomObject]@{
                Algorithm     = $Pool_Algorithm_Norm
                Info          = $Pool_Coin
                Price         = $Stat.Live
                StablePrice   = $Stat.Week
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = $Pool_Hosts | Sort-Object -Descending {$_ -ilike "$Pool_Region*"} | Select-Object -First 1
                Port          = $Pool_Port
                User          = "$User.$Worker"
                Pass          = "x"
                Region        = $Pool_Region_Norm
                SSL           = $false
                Updated       = $Stat.Updated
            }

            if ($Pool_Algorithm_Norm -eq "Cryptonight" -or $Pool_Algorithm_Norm -eq "Equihash") {
                [PSCustomObject]@{
                    Algorithm     = $Pool_Algorithm_Norm
                    Info          = $Pool_Coin
                    Price         = $Stat.Live
                    StablePrice   = $Stat.Week
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+ssl"
                    Host          = $Pool_Hosts | Sort-Object -Descending {$_ -ilike "$Pool_Region*"} | Select-Object -First 1
                    Port          = $Pool_Port
                    User          = "$User.$Worker"
                    Pass          = "x"
                    Region        = $Pool_Region_Norm
                    SSL           = $true
                    Updated       = $Stat.Updated
                }
            }
        }
    }
}
