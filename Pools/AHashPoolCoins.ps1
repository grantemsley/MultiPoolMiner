using module ..\Include.psm1

param(
    [alias("Wallet")]
    [String]$BTC, 
    [alias("WorkerName")]
    [String]$Worker, 
    [TimeSpan]$StatSpan,
    [bool]$Info = $false,
    [PSCustomObject]$Config
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Pool_APIUrl           = "http://www.ahashpool.com/api/status"
$Pool_CurrenciesAPIUrl = "http://www.ahashpool.com/api/currencies"

if ($Info) {
    # Just return info about the pool for use in setup
    $Description  = "Pool allows payout in BTC only"
    $WebSite      = "http://www.ahashpool.com"
    $Note         = "To receive payouts specify a valid BTC wallet" # Note is shown beside each pool in setup

    try {
        $APICurrenciesRequest = Invoke-RestMethod $Pool_CurrenciesAPIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        Write-Log -Level Warn "Pool API ($Name) has failed. "
    }

    if (($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
        Write-Warning  "Unable to load supported algorithms and currencies for ($Name) - may not be able to configure all pool settings"
    }

    # Define the settings this pool uses.
    $SupportedAlgorithms = @($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Foreach-Object {Get-Algorithm $APICurrenciesRequest.$_.algo} | Select-Object -Unique | Sort-Object)
    $Settings = @(
        [PSCustomObject]@{
            Name        = "Worker"
            Required    = $true
            Default     = $Worker
            ControlType = "string"
            Description = "Worker name to report to pool "
            Tooltip     = ""    
        },
        [PSCustomObject]@{
            Name        = "BTC"
            Required    = $true
            Default     = $Config.Wallet
            ControlType = "string"
            Description = "Enter a valid Bitcoin payout address, otherwise payouts will fail "
            Tooltip     = "Enter Bitcoin wallet address to receive payouts in BTC"    
        },
        [PSCustomObject]@{
            Name        = "IgnorePoolFee"
            Required    = $false
            ControlType = "switch"
            Default     = $false
            Description = "Tick to disable pool fee calculation for this pool"
            Tooltip     = "If ticked MPM will NOT take pool fees into account"
        },
        [PSCustomObject]@{
            Name        = "DisabledCurrency"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of disabled currencies for this miner. "
            Tooltip     = "Case insensitive, leave empty to mine all currencies"    
        },
        [PSCustomObject]@{
            Name        = "DisabledAlgorithm"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of disabled algorithms for this miner. "
            Tooltip     = "Case insensitive, leave empty to mine all algorithms"
        }
    )

    return [PSCustomObject]@{
        Name        = $Name
        WebSite     = $WebSite
        Description = $Description
        Algorithms  = $SupportedAlgorithms
        Note        = $Note
        Settings    = $Settings
    }
}

try {
    $APIRequest           = Invoke-RestMethod $Pool_APIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop # required for fees
    $APICurrenciesRequest = Invoke-RestMethod $Pool_CurrenciesAPIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
}
catch {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

if (($APIRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1 -or ($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

$Regions = "us"

#Pool allows payout in BTC
$Payout_Currencies = @("BTC")

# Some currencies are suffixed with algo name (e.g. AUR-myr-gr), these have the currency in property symbol. Need to add symbol to all the others
$APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Foreach-Object {
    if (-not $APICurrenciesRequest.$_.symbol) {$APICurrenciesRequest.$_ | Add-Member symbol $_}
}

$APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name |  
    # do not mine if there is no one else is mining (undesired quasi-solo-mining)
    # Where-Object {$APICurrenciesRequest.$_.hashrate -gt 0} | #AHashPool does not list hashrate in currencies API

    # a minimum of $MinWorkers is required. Low worker numbers will cause long delays until payout
    # Where-Object {$APICurrenciesRequest.$_.workers -gt $Config.Pools.$Name.MinWorker} | #AHashPool does not list workers in currencies API 

    # allow well defined currencies only
    Where-Object {$Config.Pools.$Name.Currency.Count -eq 0 -or ($Config.Pools.$Name.Currency -icontains $APICurrenciesRequest.$_.symbol)} | 

    # filter disabled currencies
    Where-Object {$Config.Pools.$Name.DisabledCurrency -inotcontains $APICurrenciesRequest.$_.symbol} |

    # filter disabled coins
    Where-Object {$Config.Pools.$Name.DisabledCoin -inotcontains $APICurrenciesRequest.$_.name} |

    # filter disabled algorithms (pool and global definition)
    Where-Object {$Config.Pools.$Name.DisabledAlgorithm -inotcontains (Get-Algorithm $APICurrenciesRequest.$_.algo)} | Foreach-Object {

    $Pool_Host      = "mine.ahashpool.com"
    $Port           = $APICurrenciesRequest.$_.port
    $Algorithm      = $APICurrenciesRequest.$_.algo
    $Algorithm_Norm = Get-Algorithm $Algorithm
    $Coin           = $APICurrenciesRequest.$_.name
    $Currency       = $APICurrenciesRequest.$_.symbol
    $Workers        = $APICurrenciesRequest.$_.workers
    
    # leave fee empty if IgnorePoolFee
    if (-not $Config.IgnorePoolFee -and -not $Config.Pools.$Name.IgnorePoolFee) {$FeeInPercent = $APIRequest.$Algorithm.Fees}
    
    if ($FeeInPercent) {
        $FeeFactor = 1 - $FeeInPercent / 100
    }
    else {
        $FeeFactor = 1
    }

    $Divisor = 1000000000

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
    $Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$APICurrenciesRequest.$_.estimate / $Divisor) -Duration $StatSpan -ChangeDetection $true

    $Regions | ForEach-Object {
        $Region = $_
        $Region_Norm = Get-Region $Region

        $Payout_Currencies | ForEach-Object {
            [PSCustomObject]@{
                Algorithm     = $Algorithm_Norm
                Info          = $Coin
                Price         = $Stat.Live * $FeeFactor
                StablePrice   = $Stat.Week * $FeeFactor
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = "$Algorithm.$Pool_Host"
                Port          = $Port
                User          = $Config.Pools.$Name.$_
                Pass          = "$Worker,c=$_"
                Region        = $Region_Norm
                SSL           = $false
                Updated       = $Stat.Updated
                Fee           = $FeeInPercent
                Workers       = $Workers
                Currency      = $Currency
            }
        }
    }
}