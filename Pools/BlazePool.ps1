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
    $Pool_Request = Invoke-RestMethod "http://api.blazepool.com/status" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
}
catch {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

if (($Pool_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

$Pool_Regions = "us"

#Pool allows payout in BTC only
$Pool_Currencies = @("BTC") | Select-Object -Unique | Where-Object {Get-Variable $_ -ValueOnly -ErrorAction SilentlyContinue}

$Pool_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$DisabledAlgorithms -inotcontains (Get-Algorithm $Pool_Request.$_.name) -and $Pool_Request.$_.hashrate -gt 0 -and [Double]$Pool_Request.$_.estimate_current -gt 0} | ForEach-Object {
    $Pool_Host = "$_.mine.blazepool.com"
    $Pool_Port = $Pool_Request.$_.port
    $Pool_Algorithm = $Pool_Request.$_.name
    $Pool_Algorithm_Norm = Get-Algorithm $Pool_Algorithm
    $Pool_Coin = ""

    $Divisor = 1000000

    switch ($Pool_Algorithm_Norm) {
        "equihash"  {$Divisor /= 1000}
        "blake2s"   {$Divisor *= 1000}
        "blakecoin" {$Divisor *= 1000}
        "decred"    {$Divisor *= 1000}
        "keccak"    {$Divisor *= 1000}
    }
    
    if ((Get-Stat -Name "$($Name)_$($Pool_Algorithm_Norm)_Profit") -eq $null) {$Stat = Set-Stat -Name "$($Name)_$($Pool_Algorithm_Norm)_Profit" -Value ([Double]$Pool_Request.$_.estimate_last24h / $Divisor) -Duration (New-TimeSpan -Days 1)}
    else {$Stat = Set-Stat -Name "$($Name)_$($Pool_Algorithm_Norm)_Profit" -Value ([Double]$Pool_Request.$_.estimate_current / $Divisor) -Duration $StatSpan -ChangeDetection $true}

    $Pool_Regions | ForEach-Object {
        $Pool_Region = $_
        $Pool_Region_Norm = Get-Region $Pool_Region

        $Pool_Currencies | Where-Object {Get-Variable $_ -ValueOnly} | ForEach-Object {
            [PSCustomObject]@{
                Algorithm     = $Pool_Algorithm_Norm
                Info          = $Pool_Coin
                Price         = $Stat.Live
                StablePrice   = $Stat.Week
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = $Pool_Host
                Port          = $Pool_Port
                User          = Get-Variable $_ -ValueOnly
                Pass          = "ID=$Worker,c=$_"
                Region        = $Pool_Region_Norm
                SSL           = $false
                Updated       = $Stat.Updated
            }
        }
    }
}
