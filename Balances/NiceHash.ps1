using module ..\Include.psm1

param($Config)
$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName
$MyConfig = $Config.Pools.$Name

$Request = [PSCustomObject]@{}

if(!$MyConfig.BTC) {
  Write-Log -Level Warn "Pool API ($Name) has failed - no wallet address specified."
  return
}


try {
    
    $Request = Invoke-RestMethod "https://api.nicehash.com/api?method=balance&id=$($MyConfig.API_ID)&key=$($MyConfig.API_Key)" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    
   #NH API does not total all of your balances for each algo up, so you have to do it with another call then total them manually.
    $UnpaidRequest = Invoke-RestMethod "https://api.nicehash.com/api?method=stats.provider&addr=$($MyConfig.BTC)"  -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    
        $sum = 0
        $UnpaidRequest.result.stats.balance | Foreach { $sum += $_}
        #$sum 
    
}
catch {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
}





if (($Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

[PSCustomObject]@{
  "currency" = 'BTC'
  "balance" = $Request.result.balance_confirmed
  "pending" = $sum
  "total" = [int]$Request.result.balance_confirmed + $sum
  'lastupdated' = (Get-Date)
}