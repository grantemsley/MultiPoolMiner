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
$PoolAPIStatusUri = "http://www.zpool.ca/api"

if (-not (Test-Port -Hostname ([Uri]$PoolAPIStatusUri).Host -Port ([Uri]$PoolAPIStatusUri).Port -Timeout 500)) {
    Write-Log -Level Warn "Pool API ($Name) [StatusUri] is down. "
    return
}

# Guaranteed payout currencies
$Payout_Currencies = @("BTC", "LTC", "DASH") | Where-Object {Get-Variable $_ -ValueOnly -ErrorAction SilentlyContinue}

if ($Payout_Currencies) {

    $APIStatusRequest = [PSCustomObject]@{}
    try {
        $APIStatusRequest = Invoke-RestMethod $PoolAPIStatusUri -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        Write-Log -Level Warn "Pool API ($Name) [StatusUri] has failed. "
        return
    }

    if (($APIStatusRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
        Write-Log -Level Warn "Pool API ($Name) [StatusUri] returned nothing. "
        return
    }

    $APIStatusRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$APIStatusRequest.$_.hashrate -GT 0} | ForEach-Object {

        $PoolHost       = "mine.zpool.ca"
        $Port           = $APIStatusRequest.$_.port
        $Algorithm      = $APIStatusRequest.$_.name
        $Algorithm_Norm = Get-Algorithm $Algorithm
        $CoinName       = ""
        $Workers        = $APIStatusRequest.$_.workers
        $Fee            = $APIStatusRequest.$_.Fees / 100

        $Divisor = 1000000 * [Double]$APIStatusRequest.$_.mbtc_mh_factor

        if ((Get-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit") -eq $null) {$Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$APIStatusRequest.$_.estimate_last24h / $Divisor) -Duration (New-TimeSpan -Days 1)}
        else {$Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$APIStatusRequest.$_.estimate_current / $Divisor) -Duration $StatSpan -ChangeDetection $true}

        $PoolRegions | ForEach-Object {
            $Region = $_
            $Region_Norm = Get-Region $Region

            $Payout_Currencies | ForEach-Object {
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
