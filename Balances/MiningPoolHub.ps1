using module ..\Include.psm1

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Request = [PSCustomObject]@{}

if(!$API_Key) {
    Write-Warning "Pool API ($Name) has failed - no API key specified."
    return
}

try {
    $Request = Invoke-RestMethod "http://miningpoolhub.com/index.php?page=api&action=getuserallbalances&api_key=$API_Key" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    
}
catch {
    Write-Warning "Pool API ($Name) has failed. "
}

if (($Request.getuserallbalances.data | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Warning "Pool API ($Name) returned nothing. "
    return
}

$Request.getuserallbalances.data | Foreach-Object {
    $coinname = $_.coin
    # For coins that don't match the name on the exchange, fix up the coin name.
    switch -wildcard ($_.coin) {
        "bitcoin" {$coinname = 'BTC'}
        "myriadcoin-*" {$coinname = 'myriad'}
    }

    [PSCustomObject]@{
        'currency' = $coinname
        'balance' = $_.confirmed
        'pending' = $_.unconfirmed + $_.ae_confirmed + $_.ae_unconfirmed + $_.exchange
        'total' = $_.confirmed + $_.unconfirmed + $_.ae_confirmed + $_.ae_unconfirmed + $_.exchange
    }
}
