using module ..\Include.psm1

param(
    [alias("Wallet")]
    [String]$BTC, 
    [alias("WorkerName")]
    [String]$Worker, 
    [TimeSpan]$StatSpan
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Pool_Request = [PSCustomObject]@{}

try {
    $Pool_Request = Invoke-RestMethod "http://api.nicehash.com/api?method=simplemultialgo.info" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
}
catch {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

if (($Pool_Request.result.simplemultialgo | Measure-Object).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

$Pool_Regions = "eu", "usa", "hk", "jp", "in", "br"

$Pool_Request.result.simplemultialgo | Where-Object {$DisabledAlgorithms -inotcontains (Get-Algorithm $_.name)} | ForEach-Object {
    $Pool_Host = "nicehash.com"
    $Pool_Port = $_.port
    $Pool_Algorithm = $_.name
    $Pool_Algorithm_Norm = Get-Algorithm $Pool_Algorithm
    $Pool_Coin = ""

    if ($Pool_Algorithm_Norm -eq "Sia") {$Pool_Algorithm_Norm = "SiaNiceHash"} #temp fix
    if ($Pool_Algorithm_Norm -eq "Decred") {$Pool_Algorithm_Norm = "DecredNiceHash"} #temp fix

    $Divisor = 1000000000

    $Stat = Set-Stat -Name "$($Name)_$($Pool_Algorithm_Norm)_Profit" -Value ([Double]$_.paying / $Divisor) -Duration $StatSpan -ChangeDetection $true

    $Pool_Regions | ForEach-Object {
        $Pool_Region = $_
        $Pool_Region_Norm = Get-Region $Pool_Region

        if ($BTC) {
            [PSCustomObject]@{
                Algorithm     = $Pool_Algorithm_Norm
                Info          = $Pool_Coin
                Price         = $Stat.Live
                StablePrice   = $Stat.Week
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = "$Pool_Algorithm.$Pool_Region.$Pool_Host"
                Port          = $Pool_Port
                User          = "$BTC.$Worker"
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
                    Host          = "$Pool_Algorithm.$Pool_Region.$Pool_Host"
                    Port          = $Pool_Port + 30000
                    User          = "$BTC.$Worker"
                    Pass          = "x"
                    Region        = $Pool_Region_Norm
                    SSL           = $true
                    Updated       = $Stat.Updated
                }
            }
        }
    }
}