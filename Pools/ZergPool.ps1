using module ..\Include.psm1

param(
    [alias("Wallet")]
    [String]$BTC, 
    [alias("WorkerName")]
    [String]$Worker, 
    [TimeSpan]$StatSpan
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$PoolRegions = "us", "europe"
$PoolAPIStatusUri = "http://api.zergpool.com:8080/api/status"


if (-not (Test-Port -Hostname ([Uri]$PoolAPIStatusUri).Host -Port ([Uri]$PoolAPIStatusUri).Port -Timeout 500)) {
    Write-Log -Level Warn "Pool API ($Name) [StatusUri] is down. "
    return
}

if (-not (Test-Port -Hostname ([Uri]$PoolAPIStatusUri).Host -Port ([Uri]$PoolAPIStatusUri).Port -Timeout 500)) {
    Write-Log -Level Warn "Pool API ($Name) [StatusUri] is down. "
    return
}

# Guaranteed payout currencies
$Payout_Currencies = @("BTC", "DASH", "LTC") | Where-Object {Get-Variable $_ -ValueOnly -ErrorAction SilentlyContinue}

if ($Payout_Currencies) {

    $APIStatusRequest = [PSCustomObject]@{}
    try {
        $APIStatusRequest = Invoke-RestMethod $PoolAPIStatusUri -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        Write-Log -Level Warn "Pool API ($Name) has failed. "
        return
    }

    if (($APIStatusRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
        Write-Log -Level Warn "Pool API ($Name) [StatusUri] returned nothing. "
        return
    }

    $APIStatusRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$APIStatusRequest.$_.hashrate -GT 0} | ForEach-Object {
        
        $PoolHost       = "mine.zergpool.com"
        $Port           = $APIStatusRequest.$_.port
        $Algorithm      = $APIStatusRequest.$_.name
        $Workers        = $APIStatusRequest.$_.workers
        $Fee            = $APIStatusRequest.$Algorithm.Fees / 100
        $CoinName       = ""

        $Divisor = 1000000000 * [Double]$APIStatusRequest.$Algorithm.mbtc_mh_factor
        if ($Divisor -eq 0) {
            Write-Log -Level Info "$($Name): Unable to determine divisor for algorithm $Algorithm. "
            return
        }

        #Define CoinNames for new Equihash algorithms
        if ($Algorithm -eq "Equihash144btcz") {$Algorithm = "Equihash144"; $CoinName = "Bitcoinz"}
        if ($Algorithm -eq "Equihash144safe") {$Algorithm = "Equihash144"; $CoinName = "Safecoin"}
        if ($Algorithm -eq "Equihash144xsg")  {$Algorithm = "Equihash144"; $CoinName = "Snowgem"}
        if ($Algorithm -eq "Equihash144zel")  {$Algorithm = "Equihash144"; $CoinName = "Zelcash"}
        if ($Algorithm -eq "Equihash192")     {$CoinName = "Zerocoin"}
    
        $Algorithm_Norm = Get-Algorithm $Algorithm

        if ((Get-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit") -eq $null) {$Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$APIStatusRequest.$_.estimate_last24h / $Divisor) -Duration (New-TimeSpan -Days 1)}
        else {$Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$APIStatusRequest.$_.estimate_current / $Divisor) -Duration $StatSpan -ChangeDetection $true}

        $PoolRegions | ForEach-Object {
            $Region = $_
            $Region_Norm = Get-Region $Region

            $Payout_Currencies | ForEach-Object {
                #Option 1
                [PSCustomObject]@{
                    Algorithm     = $Algorithm_Norm
                    CoinName      = $CoinName
                    Price         = $Stat.Live
                    StablePrice   = $Stat.Week
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+tcp"
                    Host          = "$Algorithm.$PoolHost"
                    Port          = $Port
                    User          = Get-Variable $_ -ValueOnly
                    Pass          = "$Worker,c=$_"
                    Region        = $Region_Norm
                    SSL           = $false
                    Updated       = $Stat.Updated
                    Fee           = $Fee
                    Workers       = $Workers
                }
            }
        }
    }
}
