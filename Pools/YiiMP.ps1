using module ..\Include.psm1

param(
    [alias("WorkerName")]
    [String]$Worker, 
    [TimeSpan]$StatSpan
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$PoolCoins_Request = [PSCustomObject]@{}

try {
    $PoolCoins_Request = Invoke-RestMethod "http://api.yiimp.eu/api/currencies" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
}
catch {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

if (($PoolCoins_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

$Pool_Regions = "us"

#Pool allows payout in any currency available in API. Define the desired payout currency in $Config.$Pool.<Currency>
$Pool_Currencies = ($PoolCoins_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name) | Select-Object -Unique | Where-Object {Get-Variable $_ -ValueOnly -ErrorAction SilentlyContinue}

$Pool_Currencies | Where-Object {$DisabledAlgorithms -inotcontains (Get-Algorithm $PoolCoins_Request.$_.algo) -and $PoolCoins_Request.$_.hashrate -gt 0} | ForEach-Object {
    $Pool_Host = "yiimp.eu"
    $Pool_Port = $PoolCoins_Request.$_.port
    $Pool_Algorithm = $PoolCoins_Request.$_.algo
    $Pool_Algorithm_Norm = Get-Algorithm $Pool_Algorithm
    $Pool_Coin = $PoolCoins_Request.$_.name
    $Pool_Currency = $_

    $Divisor = 1000000000

    switch ($Pool_Algorithm_Norm) {
        "blake2s" {$Divisor *= 1000}
        "blakecoin" {$Divisor *= 1000}
        "decred" {$Divisor *= 1000}
        "equihash" {$Divisor /= 1000}
        "quark" {$Divisor *= 1000}
        "qubit" {$Divisor *= 1000}
        "scrypt" {$Divisor *= 1000}
        "x11" {$Divisor *= 1000}
    }

    $Stat = Set-Stat -Name "$($Name)_$($_)_Profit" -Value ([Double]$PoolCoins_Request.$_.estimate / $Divisor) -Duration $StatSpan -ChangeDetection $true

    $Pool_Regions | ForEach-Object {
        $Pool_Region = $_
        $Pool_Region_Norm = Get-Region $Pool_Region

        [PSCustomObject]@{
            Algorithm     = $Pool_Algorithm_Norm
            Info          = $Pool_Coin
            Price         = $Stat.Live
            StablePrice   = $Stat.Week
            MarginOfError = $Stat.Week_Fluctuation
            Protocol      = "stratum+tcp"
            Host          = $Pool_Host
            Port          = $Pool_Port
            User          = Get-Variable $Pool_Currency -ValueOnly
            Pass          = "$Worker,c=$Pool_Currency"
            Region        = $Pool_Region_Norm
            SSL           = $false
            Updated       = $Stat.Updated
        }
    }
}