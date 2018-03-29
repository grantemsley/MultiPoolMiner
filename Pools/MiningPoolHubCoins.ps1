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

$PoolCoins_Request = [PSCustomObject]@{}

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
        Description = "This version lets MultiPoolMiner determine which coin to miner. The regular MiningPoolHub pool may work better, since it lets the pool avoid switching early and losing shares."
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
    $PoolCoins_Request = Invoke-RestMethod "http://miningpoolhub.com/index.php?page=api&action=getminingandprofitsstatistics" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
}
catch {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

if (($PoolCoins_Request.return | Measure-Object).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

$PoolCoins_Regions = "europe", "us", "asia"

$PoolCoins_Request.return | Where-Object {$DisabledCoins -inotcontains $_.coin_name -and $DisabledAlgorithms -inotcontains (Get-Algorithm $_.algo) -and $_.pool_hash -gt 0} |ForEach-Object {
    $PoolCoins_Hosts = $_.host_list.split(";")
    $PoolCoins_Port = $_.port
    $PoolCoins_Algorithm = $_.algo
    $PoolCoins_Algorithm_Norm = Get-Algorithm $PoolCoins_Algorithm
    $PoolCoins_Coin = (Get-Culture).TextInfo.ToTitleCase(($_.coin_name -replace "-", " " -replace "_", " ")) -replace " "

    if ($PoolCoins_Algorithm_Norm -eq "Sia") {$PoolCoins_Algorithm_Norm = "SiaClaymore"} #temp fix

    $Divisor = 1000000000

    $Stat = Set-Stat -Name "$($Name)_$($PoolCoins_Coin)_Profit" -Value ([Double]$_.profit / $Divisor) -Duration $StatSpan -ChangeDetection $true

    $PoolCoins_Regions | ForEach-Object {
        $PoolCoins_Region = $_
        $PoolCoins_Region_Norm = Get-Region $PoolCoins_Region

        if ($User) {
            [PSCustomObject]@{
                Algorithm     = $PoolCoins_Algorithm_Norm
                Info          = $PoolCoins_Coin
                Price         = $Stat.Live
                StablePrice   = $Stat.Week
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = $PoolCoins_Hosts | Sort-Object -Descending {$_ -ilike "$PoolCoins_Region*"} | Select-Object -First 1
                Port          = $PoolCoins_Port
                User          = "$User.$Worker"
                Pass          = "x"
                Region        = $PoolCoins_Region_Norm
                SSL           = $false
                Updated       = $Stat.Updated
            }

            if ($PoolCoins_Algorithm_Norm -eq "Cryptonight" -or $PoolCoins_Algorithm_Norm -eq "Equihash") {
                [PSCustomObject]@{
                    Algorithm     = $PoolCoins_Algorithm_Norm
                    Info          = $PoolCoins_Coin
                    Price         = $Stat.Live
                    StablePrice   = $Stat.Week
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+ssl"
                    Host          = $PoolCoins_Hosts | Sort-Object -Descending {$_ -ilike "$PoolCoins_Region*"} | Select-Object -First 1
                    Port          = $PoolCoins_Port
                    User          = "$User.$Worker"
                    Pass          = "x"
                    Region        = $PoolCoins_Region_Norm
                    SSL           = $true
                    Updated       = $Stat.Updated
                }
            }

            if ($PoolCoins_Algorithm_Norm -eq "Ethash" -and $PoolCoins_Coin -NotLike "*ethereum*") {
                [PSCustomObject]@{
                    Algorithm     = "$($PoolCoins_Algorithm_Norm)2gb"
                    Info          = $PoolCoins_Coin
                    Price         = $Stat.Live
                    StablePrice   = $Stat.Week
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+tcp"
                    Host          = $PoolCoins_Hosts | Sort-Object -Descending {$_ -ilike "$PoolCoins_Region*"} | Select-Object -First 1
                    Port          = $PoolCoins_Port
                    User          = "$User.$Worker"
                    Pass          = "x"
                    Region        = $PoolCoins_Region_Norm
                    SSL           = $false
                    Updated       = $Stat.Updated
                }
            }

            if ($PoolCoins_Algorithm_Norm -eq "Cryptonight" -or $PoolCoins_Algorithm_Norm -eq "Equihash") {
                [PSCustomObject]@{
                    Algorithm     = "$($PoolCoins_Algorithm_Norm)2gb"
                    Info          = $PoolCoins_Coin
                    Price         = $Stat.Live
                    StablePrice   = $Stat.Week
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+ssl"
                    Host          = $PoolCoins_Hosts | Sort-Object -Descending {$_ -ilike "$PoolCoins_Region*"} | Select-Object -First 1
                    Port          = $PoolCoins_Port
                    User          = "$User.$Worker"
                    Pass          = "x"
                    Region        = $PoolCoins_Region_Norm
                    SSL           = $true
                    Updated       = $Stat.Updated
                }
            }
        }
    }
}