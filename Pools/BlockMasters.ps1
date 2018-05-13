using module ..\Include.psm1

param(
    [PSCustomObject]$Config,
    [TimeSpan]$StatSpan
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName
$Regions = "us"

$Pool_APIUrl = "http://blockmasters.co/api/status"
$Pool_CurrenciesAPIUrl = "http://blockmasters.co/api/currencies"
$WebSite = "http://www.blockmasters.co"

# Guaranteed payout currencies
$Payout_Currencies = @("BTC", "DOGE", "LTC")
$Description = "Pool allows payout in $($Payout_Currencies -join ", ") & any currency available in API"
$Note = "To receive payouts specify at least one valid wallet" # Note is shown beside each pool in setup

try {
    $APICurrenciesRequest = Invoke-RestMethod $Pool_CurrenciesAPIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
}
catch {
    Write-Log -Level Warn "Pool API [Currencies] ($Name) has failed. "
}

#Pool allows payout in any currency available in API too
$Payout_Currencies = $Payout_Currencies + @($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Foreach-Object {
    if ($APICurrenciesRequest.$_.symbol) {$APICurrenciesRequest.$_.symbol} else {$_} # filter ...-algo
} | Select-Object -Unique | Sort-Object )

# Just return info about the pool for use in setup
if ($Config.InfoOnly) {return Get-PoolConfigTemplate}

try {
    $APIRequest = Invoke-RestMethod $Pool_APIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop # required for fees
}
catch {
    Write-Log -Level Warn "Pool API [Algorithms] ($Name) has failed. "
    return
}

if (($APIRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1 -or ($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

# Add BTC as currency if no other currency is defined in config
if (-not $Config.Pools.$Name.Wallets.BTC) {$Config.Pools.$Name.Wallets | Add-Member BTC $Config.Wallet}

$APIRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | 

    # do not mine if there is no one else is mining (undesired quasi-solo-mining)
    Where-Object {$APIRequest.$_.hashrate -gt 0} |

    # a minimum of $MinWorkers is required. Low worker numbers will cause long delays until payout
    Where-Object {$APIRequest.$_.workers -gt $Config.Pools.$Name.MinWorker} |

    # filter excluded algorithms (pool and global  definition)
    Where-Object {$Config.Pools.$Name.ExcludeAlgorithm -inotcontains (Get-Algorithm $_)} |

    ForEach-Object {

    $Pool_Host      = "blockmasters.co"
    $Port           = $APIRequest.$_.port
    $Algorithm      = $APIRequest.$_.name
    $Algorithm_Norm = Get-Algorithm $Algorithm
    $CoinName       = ""
    $Workers        = $APIRequest.$_.workers

    # leave fee empty if IgnorePoolFee
    if (-not $Config.IgnorePoolFee -and -not $Config.Pools.$Name.IgnorePoolFee) {$FeeInPercent = $APIRequest.$Algorithm.Fees}
    if ($FeeInPercent) {$FeeFactor = 1 - $FeeInPercent / 100} else {$FeeFactor = 1}

    $PricePenaltyFactor = $Config.Pools.$Name.PricePenaltyFactor
    if ($PricePenaltyFactor -le 0 -or $PricePenaltyFactor -gt 1) {$PricePenaltyFactor = 1}

    $PricePenaltyFactor = $Config.Pools.$Name.PricePenaltyFactor
    if ($PricePenaltyFactor -le 0 -or $PricePenaltyFactor -gt 1) {
        $PricePenaltyFactor = 1
    }

    $Divisor = 1000000

    switch ($Algorithm_Norm) {
        "blake2s"   {$Divisor *= 1000}
        "blakecoin" {$Divisor *= 1000}
        "decred"    {$Divisor *= 1000}
        "equihash"  {$Divisor /= 1000}
        "quark"     {$Divisor *= 1000}
        "qubit"     {$Divisor *= 1000}
        "scrypt"    {$Divisor *= 1000}
        "x11"       {$Divisor *= 1000}
    }

    if ((Get-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit") -eq $null) {$Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$APIRequest.$_.estimate_last24h / $Divisor) -Duration (New-TimeSpan -Days 1)}
    else {$Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$APIRequest.$_.estimate_current / $Divisor) -Duration $StatSpan -ChangeDetection $true}

    $Regions | ForEach-Object {
        $Region = $_
        $Region_Norm = Get-Region $Region

        $Payout_Currencies | Where-Object {$Config.Pools.$Name.Wallets.$_} | ForEach-Object {
            [PSCustomObject]@{
                Algorithm     = $Algorithm_Norm
                Info          = $CoinName
                Price         = $Stat.Live * $FeeFactor * $PricePenaltyFactor
                StablePrice   = $Stat.Week * $FeeFactor * $PricePenaltyFactor
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = $Pool_Host
                Port          = $Port
                User          = $Config.Pools.$Name.Wallets.$_
                Pass          = "$($Config.Worker),c=$_"
                Region        = $Region_Norm
                SSL           = $false
                Updated       = $Stat.Updated
                Fee           = $FeeInPercent
                Workers       = $Workers
            }
        }
    }
}