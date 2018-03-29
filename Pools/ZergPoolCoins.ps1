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
    $PoolCoins_Request = Invoke-RestMethod "http://api.zergpool.com:8080/api/currencies" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
}
catch {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

if (($PoolCoins_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

$PoolCoins_Regions = "us", "europe"

#Pool allows payout in BTC, LTC & any currency available in API. Define desired payout currency in $Config.$Pool.<Currency>
$PoolCoins_Currencies = @("BTC", "LTC") + ($PoolCoins_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name) | Select-Object -Unique | Where-Object {Get-Variable $_ -ValueOnly -ErrorAction SilentlyContinue}

#Mine any coin defined in array $Config.$Pool.Coins[]
$PoolCoins_MiningCurrencies = ($PoolCoins_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name) | Foreach-Object {if ($PoolCoins_Request.$_.Symbol) {$PoolCoins_Request.$_.Symbol} else {$_}} | Select-Object -Unique # filter ...-algo
$PoolCoins_MiningCurrencies | Where-Object {$DisabledCoins -inotcontains $PoolCoins_Request.$_.name -and $DisabledAlgorithms -inotcontains (Get-Algorithm $PoolCoins_Request.$_.algo) -and ($Coins.count -eq 0 -or $Coins -icontains $PoolCoins_Request.$_.name) -and $PoolCoins_Request.$_.hashrate -gt 0} | ForEach-Object {
    $PoolCoins_Host = "mine.zergpool.com"
    $PoolCoins_Port = $PoolCoins_Request.$_.port
    $PoolCoins_Algorithm = $PoolCoins_Request.$_.algo
    $PoolCoins_Algorithm_Norm = Get-Algorithm $PoolCoins_Algorithm
    $PoolCoins_Coin = $PoolCoins_Request.$_.name
    $PoolCoins_Currency = $_

    $Divisor = 1000000000

    switch ($PoolCoins_Algorithm_Norm) {
        "blake2s" {$Divisor *= 1000}
        "blakecoin" {$Divisor *= 1000}
        "decred" {$Divisor *= 1000}
        "equihash" {$Divisor /= 1000}
        "keccak" {$Divisor *= 1000}
        "keccakc" {$Divisor *= 1000}
        "quark" {$Divisor *= 1000}
        "qubit" {$Divisor *= 1000}
        "scrypt" {$Divisor *= 1000}
        "x11" {$Divisor *= 1000}
    }

    $Stat = Set-Stat -Name "$($Name)_$($_)_Profit" -Value ([Double]$PoolCoins_Request.$_.estimate / $Divisor) -Duration $StatSpan -ChangeDetection $true

    $PoolCoins_Regions | ForEach-Object {
        $PoolCoins_Region = $_
        $PoolCoins_Region_Norm = Get-Region $PoolCoins_Region

        if (Get-Variable $PoolCoins_Currency -ValueOnly -ErrorAction SilentlyContinue) {
            #Option 3
            [PSCustomObject]@{
                Algorithm     = $PoolCoins_Algorithm_Norm
                Info          = $PoolCoins_Coin
                Price         = $Stat.Live
                StablePrice   = $Stat.Week
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = "$PoolCoins_Algorithm.$PoolCoins_Host"
                Port          = $PoolCoins_Port
                User          = Get-Variable $PoolCoins_Currency -ValueOnly
                Pass          = "$Worker,c=$PoolCoins_Currency,mc=$PoolCoins_Currency"
                Region        = $PoolCoins_Region_Norm
                SSL           = $false
                Updated       = $Stat.Updated
            }
        }
        elseif ($PoolCoins_Request.$PoolCoins_Currency.noautotrade -eq 0) {
            $PoolCoins_Currencies | ForEach-Object {
                #Option 2
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
                    Pass          = "$Worker,c=$_,mc=$PoolCoins_Currency"
                    Region        = $PoolCoins_Region_Norm
                    SSL           = $false
                    Updated       = $Stat.Updated
                }
            }
        }
    }
}
