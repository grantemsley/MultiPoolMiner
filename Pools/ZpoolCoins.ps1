using module ..\Include.psm1

param(
    [alias("Wallet")]
    [String]$BTC, 
    [alias("WorkerName")]
    [String]$Worker, 
    [TimeSpan]$StatSpan
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$PoolCoins_Request = [PSCustomObject]@{}

try {
    $PoolCoins_Request = Invoke-RestMethod "http://www.zpool.ca/api/currencies" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
}
catch {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

if (($PoolCoins_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

$PoolCoins_Regions = "us"

#Pool allows payout in BTC & any currency available in API. Define the desired payout currency in $Config.$Pool.<Currency>
$PoolCoins_Currencies = @("BTC") + ($PoolCoins_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name) | Select-Object -Unique | Where-Object {Get-Variable $_ -ValueOnly -ErrorAction SilentlyContinue}

#Mine any coin defined in array $Config.$Pool.Coins[]
$PoolCoins_MiningCurrencies = ($PoolCoins_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name) | Where-Object {$Coins.count -eq 0 -or $Coins -icontains $PoolCoins_Request.$_.name} | Select-Object -Unique
#On Zpool all $PoolCoins_Request.$_.hashrate is 0, use workers instead
$PoolCoins_MiningCurrencies | Where-Object {$DisabledCoins -inotcontains $PoolCoins_Request.$_.name -and $DisabledAlgorithms -inotcontains (Get-Algorithm $PoolCoins_Request.$_.algo) -and $PoolCoins_Request.$_.workers -gt 0} | ForEach-Object {
    $PoolCoins_Host = "mine.zpool.ca"
    $PoolCoins_Port = $PoolCoins_Request.$_.port
    $PoolCoins_Algorithm = $PoolCoins_Request.$_.algo
    $PoolCoins_Algorithm_Norm = Get-Algorithm $PoolCoins_Algorithm
    $PoolCoins_Coin = $PoolCoins_Request.$_.name

    $Divisor = 1000000

    switch ($PoolCoins_Algorithm_Norm) {
        "blake2s" {$Divisor *= 1000}
        "blakecoin" {$Divisor *= 1000}
        "decred" {$Divisor *= 1000}
        "equihash" {$Divisor /= 1000}
        "quark" {$Divisor *= 1000}
        "qubit" {$Divisor *= 1000}
        "scrypt" {$Divisor *= 1000}
        "x11" {$Divisor *= 1000}
    }

    if ((Get-Stat -Name "$($Name)_$($PoolCoins_Algorithm_Norm)_Profit") -eq $null) {$Stat = Set-Stat -Name "$($Name)_$($PoolCoins_Algorithm_Norm)_Profit" -Value ([Double]$PoolCoins_Request.$_.estimate_last24h / $Divisor) -Duration (New-TimeSpan -Days 1)}
    else {$Stat = Set-Stat -Name "$($Name)_$($PoolCoins_Algorithm_Norm)_Profit" -Value ([Double]$PoolCoins_Request.$_.estimate_current / $Divisor) -Duration $StatSpan -ChangeDetection $true}

    $PoolCoins_Regions | ForEach-Object {
        $PoolCoins_Region = $_
        $PoolCoins_Region_Norm = Get-Region $PoolCoins_Region

        $PoolCoins_Currencies | ForEach-Object {
            [PSCustomObject]@{
                Algorithm     = $PoolCoins_Algorithm_Norm
                Info          = $PoolCoins_Coin
                Price         = $Stat.Live
                StablePrice   = $Stat.Week
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = "$PoolCoins_Algorithm.$PoolCoins_Host"
                Port          = $PoolCoins_Port
                User          = Get-Variable $_ -ValueOnly
                Pass          = "$Worker,c=$_"
                Region        = $PoolCoins_Region_Norm
                SSL           = $false
                Updated       = $Stat.Updated
            }
        }
    }
}