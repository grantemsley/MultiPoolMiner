using module ..\Include.psm1

param(
    [alias("Wallet")]
    [String]$BTC, 
    [alias("WorkerName")]
    [String]$Worker, 
    [TimeSpan]$StatSpan
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$PoolRegions = "us"
$PoolAPIStatusUri = "http://api.yiimp.eu/api/status"
$PoolAPICurrenciesUri = "http://api.yiimp.eu/api/currencies"

$APIStatusRequest = [PSCustomObject]@{}
$APICurrenciesRequest = [PSCustomObject]@{}

if (-not (Test-Port -Hostname ([Uri]$PoolAPIStatusUri).Host -Port ([Uri]$PoolAPIStatusUri).Port -Timeout 500)) {
    Write-Log -Level Warn "Pool API ($Name) [StatusUri] is down. "
    return
}
if (-not (Test-Port -Hostname ([Uri]$PoolAPICurrenciesUri).Host -Port ([Uri]$PoolAPICurrenciesUri).Port -Timeout 500)) {
    Write-Log -Level Warn "Pool API ($Name) [CurrenciesUri] is down. "
    return
}

try {
    $APIStatusRequest = Invoke-RestMethod $PoolAPIStatusUri -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    $APICurrenciesRequest = Invoke-RestMethod $PoolAPICurrenciesUri -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
}
catch {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
}

if (($APIStatusRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) [StatusUri] returned nothing. "
    return
}

if (($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) [CurrenciesUri] returned nothing. "
    return
}

#Pool allows payout in any currency available in API
$APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Sort-Object | Select-Object -Unique | Where-Object {$APICurrenciesRequest.$_.hashrate -GT 0 -and (Get-Variable $_ -ErrorAction SilentlyContinue)} | Foreach-Object {

    $APICurrenciesRequest.$_ | Add-Member Symbol $_ -ErrorAction SilentlyContinue

    $PoolHost       = "yiimp.eu"
    $Port           = $APICurrenciesRequest.$_.port
    $Algorithm      = $APICurrenciesRequest.$_.algo
    $Algorithm_Norm = Get-Algorithm $Algorithm
    $CoinName       = $APICurrenciesRequest.$_.name
    $Currency       = $APICurrenciesRequest.$_.symbol
    $Workers        = $APICurrenciesRequest.$_.workers
    $Fee            = $APIStatusRequest.$Algorithm.Fees / 100

    $Divisor = 1000000 * [Double]$APIStatusRequest.$Algorithm.mbtc_mh_factor

    $Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$APICurrenciesRequest.$_.estimate / $Divisor) -Duration $StatSpan -ChangeDetection $true

    $PoolRegions | ForEach-Object {
        $Region = $_
        $Region_Norm = Get-Region $Region

        [PSCustomObject]@{
            Algorithm     = $Algorithm_Norm
            CoinName      = $CoinName
            Price         = $Stat.Live
            StablePrice   = $Stat.Week
            MarginOfError = $Stat.Week_Fluctuation
            Protocol      = "stratum+tcp"
            Host          = $PoolHost
            Port          = $Port
            User          = Get-Variable $Currency -ValueOnly
            Pass          = "$Worker,c=$Currency"
            Region        = $Region_Norm
            SSL           = $false
            Updated       = $Stat.Updated
            Fee           = $Fee
            Workers       = $Workers
            Currency      = $Currency
        }
    }
}
