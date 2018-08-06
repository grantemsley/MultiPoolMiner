using module ..\Include.psm1

param(
    [alias("Wallet")]
    [String]$BTC, 
    [alias("WorkerName")]
    [String]$Worker, 
    [TimeSpan]$StatSpan
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$PoolRegions = "eu", "usa", "hk", "jp", "in", "br"
$PoolAPIUri = "http://api.nicehash.com/api?method=simplemultialgo.info"

if (-not (Test-Port -Hostname ([Uri]$PoolAPIUri).Host -Port ([Uri]$PoolAPIUri).Port -Timeout 500)) {
    Write-Log -Level Warn "Pool API ($Name) is down. "
    return
}

#Pool currenctly allows payout in BTC only
$Payout_Currencies = @("BTC") | Where-Object {Get-Variable $_ -ErrorAction SilentlyContinue}

if ($Payout_Currencies) {

    $APIStatusRequest = [PSCustomObject]@{}

    try {
        $APIRequest = Invoke-RestMethod $PoolAPIUri -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        Write-Log -Level Warn "Pool API ($Name) has failed. "
        return
    }

    if ($APIRequest.result.simplemultialgo.count -le 1) {
        Write-Log -Level Warn "Pool API ($Name) returned nothing. "
        return
    }

    $APIRequest.result.simplemultialgo | Where-Object {$_.paying -gt 0} <# algos paying 0 fail stratum #> | ForEach-Object {
        $PoolHost = "nicehash.com"
        $Port = $_.port
        $Algorithm = $_.name
        $Algorithm_Norm = Get-Algorithm $Algorithm
        $Currency = ""
        
        if ($IsInternalWallet) {$Fee = 0.01} else {$Fee = 0.03}
        
        if ($Algorithm_Norm -eq "blake256r14") {$Algorithm_Norm = "DecredNiceHash"} #temp fix
        if ($Algorithm_Norm -eq "Sia") {$Algorithm_Norm = "SiaNiceHash"} #temp fix

        $Divisor = 1000000000

        $Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$_.paying / $Divisor) -Duration $StatSpan -ChangeDetection $true

        $PoolRegions | ForEach-Object {
            $Region = $_
            $Region_Norm = Get-Region $Region

            $Payout_Currencies | ForEach-Object {
                [PSCustomObject]@{
                    Algorithm     = $Algorithm_Norm
                    CoinName      = $Currency
                    Price         = $Stat.Live
                    StablePrice   = $Stat.Week
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+tcp"
                    Host          = "$Algorithm.$Region.$PoolHost"
                    Port          = $Port
                    User          = "$(Get-Variable $_ -ValueOnly).$Worker"
                    Pass          = "x"
                    Region        = $Region_Norm
                    SSL           = $false
                    Updated       = $Stat.Updated
                    Fee           = $Fee
                }
                [PSCustomObject]@{
                    Algorithm     = "$($Algorithm_Norm)-NHMP"
                    CoinName      = $Currency
                    Price         = $Stat.Live
                    StablePrice   = $Stat.Week
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+tcp"
                    Host          = "nhmp.$($Region.ToLower()).nicehash.com"
                    Port          = 3200
                    User          = "$(Get-Variable $_ -ValueOnly).$Worker"
                    Pass          = "x"
                    Region        = $Region_Norm
                    SSL           = $false
                    Updated       = $Stat.Updated
                    Fee           = $Fee
                }

                if ($Algorithm_Norm -eq "CryptonightV7" -or $Algorithm_Norm -eq "Equihash") {
                    [PSCustomObject]@{
                        Algorithm     = $Algorithm_Norm
                        CoinName      = $Currency
                        Price         = $Stat.Live
                        StablePrice   = $Stat.Week
                        MarginOfError = $Stat.Week_Fluctuation
                        Protocol      = "stratum+ssl"
                        Host          = "$Algorithm.$Region.$PoolHost"
                        Port          = $Port + 30000
                        User          = "$(Get-Variable $_ -ValueOnly).$Worker"
                        Pass          = "x"
                        Region        = $Region_Norm
                        SSL           = $true
                        Updated       = $Stat.Updated
                        Fee           = $Fee
                    }
                    [PSCustomObject]@{
                        Algorithm     = "$($Algorithm_Norm)-NHMP"
                        CoinName      = $Currency
                        Price         = $Stat.Live
                        StablePrice   = $Stat.Week
                        MarginOfError = $Stat.Week_Fluctuation
                        Protocol      = "stratum+ssl"
                        Host          = "nhmp.$($Region.ToLower()).nicehash.com"
                        Port          = 3200
                        User          = "$(Get-Variable $_ -ValueOnly).$Worker"
                        Pass          = "x"
                        Region        = $Region_Norm
                        SSL           = $true
                        Updated       = $Stat.Updated
                        Fee           = $Fee
                    }
                }
            }
        }
    }
}
