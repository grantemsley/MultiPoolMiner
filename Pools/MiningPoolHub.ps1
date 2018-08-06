using module ..\Include.psm1

param(
    [alias("UserName")]
    [String]$User, 
    [alias("WorkerName")]
    [String]$Worker, 
    [TimeSpan]$StatSpan
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$PoolRegions = "europe", "us-east", "asia"
$PoolAPIUri= "http://miningpoolhub.com/index.php?page=api&action=getautoswitchingandprofitsstatistics&$(Get-Date -Format "yyyy-MM-dd_HH-mm")"

if (-not (Test-Port -Hostname ([Uri]$PoolAPIUri).Host -Port ([Uri]$PoolAPIUri).Port -Timeout 500)) {
    Write-Log -Level Warn "Pool API ($Name) is down. "
    return
}

if ($User) {

    $APIStatusRequest = [PSCustomObject]@{}

    try {
        $APIRequest = Invoke-RestMethod $PoolAPIUri-UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        Write-Log -Level Warn "Pool API ($Name) has failed. "
        return
    }

    if ($APIRequest.return.count -le 1) {
        Write-Log -Level Warn "Pool API ($Name) returned nothing. "
        return
    }

    $APIRequest.return | ForEach-Object {

        $PoolHosts      = $_.all_host_list.split(";")
        $Port           = $_.algo_switch_port
        $Algorithm      = $_.algo
        $Algorithm_Norm = Get-Algorithm $Algorithm
        $CoinName       = (Get-Culture).TextInfo.ToTitleCase(($_.current_mining_coin -replace "-", " " -replace "_", " ")) -replace " "

        if ($Algorithm_Norm -eq "Sia") {$Algorithm_Norm = "SiaClaymore"} #temp fix

        $Divisor = 1000000000

        $Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$_.profit / $Divisor) -Duration $StatSpan -ChangeDetection $true

        $PoolRegions | ForEach-Object {
            $Region = $_
            $Region_Norm = Get-Region ($Region -replace "^us-east$", "us")

            [PSCustomObject]@{
                Algorithm     = $Algorithm_Norm
                CoinName      = $CoinName
                Price         = $Stat.Live
                StablePrice   = $Stat.Week
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = $PoolHosts | Sort-Object -Descending {$_ -ilike "$Region*"} | Select-Object -First 1
                Port          = $Port
                User          = "$User.$Worker"
                Pass          = "x"
                Region        = $Region_Norm 
                SSL           = $false
                Updated       = $Stat.Updated
                Fee           = 0.9 / 100
            }
            [PSCustomObject]@{
                Algorithm     = $Algorithm_Norm
                CoinName      = $CoinName
                Price         = $Stat.Live
                StablePrice   = $Stat.Week
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+ssl"
                Host          = $PoolHosts | Sort-Object -Descending {$_ -ilike "$Region*"} | Select-Object -First 1
                Port          = $Port
                User          = "$User.$Worker"
                Pass          = "x"
                Region        = $Region_Norm
                SSL           = $true
                Updated       = $Stat.Updated
                Fee           = 0.9 / 100
            }
        }
    }
}
