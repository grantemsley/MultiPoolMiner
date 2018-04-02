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
    
   #NH API does not total all of your balances for each algo up, so you have to do it with another call then total them manually.
    $UnpaidRequest = Invoke-RestMethod "https://api.nicehash.com/api?method=stats.provider&addr=$($MyConfig.BTC)"  -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    
        $sum = 0
        $UnpaidRequest.result.stats.balance | Foreach { $sum += $_}
        #$sum 
    
}
catch {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
}

[PSCustomObject]@{
  "currency" = 'BTC'
  "balance" = $sum
  "pending" = 0
  "total" = $sum
  'lastupdated' = (Get-Date)
}