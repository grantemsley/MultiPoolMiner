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

$Pool_APIUrl           = "http://blockmasters.co/api/status"
$Pool_CurrenciesAPIUrl = "http://blockmasters.co/api/currencies"

if ($Info) {
    # Just return info about the pool for use in setup
    $Description  = "Pool allows payout in BTC, DOGE, LTC & any currency available in API"
    $WebSite      = "http://www.blockmasters.co"
    $Note         = "To receive payouts specify at least one valid wallet" # Note is shown beside each pool in setup

    try {
        $APICurrenciesRequest = Invoke-RestMethod $Pool_CurrenciesAPIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        Write-Log -Level Warn "Pool API ($Name) has failed. "
        return
    }

    if (($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
        Write-Log -Level Warn "Pool API ($Name) returned nothing. "
        return
    }

    # Define the settings this pool uses.
    $SupportedAlgorithms = @($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Foreach-Object {Get-Algorithm $APICurrenciesRequest.$_.algo} | Select-Object -Unique | Sort-Object)
    $Payout_Currencies = @($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Foreach-Object {
        if ($APICurrenciesRequest.$_.symbol) {$APICurrenciesRequest.$_.symbol} else {$_} # filter ...-algo
    } | Select-Object -Unique | Sort-Object )
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
            Required    = $false
            Default     = $Config.Wallet
            ControlType = "string"
            Description = "Bitcoin payout address "
            Tooltip     = "Enter Bitcoin wallet address to receive payouts in BTC"    
        },
        [PSCustomObject]@{
            Name        = "DOGE"
            Required    = $false
            Default     = $Config.Wallet
            ControlType = "string"
            Description = "DogeCoin payout address "
            Tooltip     = "Enter DogeCoin wallet address to receive payouts in DOGE"    
        },
        [PSCustomObject]@{
            Name        = "LTC"
            Required    = $false
            Default     = $Config.Wallet
            ControlType = "string"
            Description = "LiteCoin payout address "
            Tooltip     = "Enter LiteCoin wallet address to receive payouts in LTC"    
        }
    )
    #add all possible payout currencies
    $Payout_Currencies | Foreach-Object {
        $Settings += [PSCustomObject]@{
            Name        = "$_"
            Required    = $false
            Default     = "$($Config.Pools.$Name.$_)"
            ControlType = "string"
            Description = "$($APICurrenciesRequest.$_.Name) payout address "
            Tooltip     = "Only enter $($APICurrenciesRequest.$_.Name) wallet address receive payouts in $($_)"    
        }
    }
    $Settings += @(
        [PSCustomObject]@{
            Name        = "IgnorePoolFee"
            Required    = $false
            ControlType = "switch"
            Default     = $false
            Description = "Tick to disable pool fee calculation for this pool"
            Tooltip     = "If ticked MPM will NOT take pool fees into account"
        },
        [PSCustomObject]@{
            Name        = "PricePenaltyFactor"
            Required    = $false
            ControlType = "double"
            Decimals    = 2
            Min         = 0.01
            Max         = 1
            Default     = 1
            Description = "This adds a multiplicator on estimations presented by the pool. "
            Tooltip     = "If not set then the default of 1 (no penalty) is used."
        },
        [PSCustomObject]@{
            Name        = "MinWorker"
            Required    = $false
            ControlType = "int"
            Min         = 0
            Max         = 999999
            Default     = $Config.MinWorker
            Description = "Minimum number of workers that must be mining an alogrithm. Low worker numbers will cause long delays until payout. "
            Tooltip     = "You can also set the the value globally in the general parameter section. The smaller value takes precedence"
        },
        [PSCustomObject]@{
            Name        = "ExcludeCurrency"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of excluded currencies for this miner. "
            Tooltip     = "Case insensitive, leave empty to mine all currencies"    
        },
        [PSCustomObject]@{
            Name        = "ExcludeCoin"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of excluded coins for this miner. "
            Tooltip     = "Case insensitive, leave empty to mine all coins"    
        },
        [PSCustomObject]@{
            Name        = "Currency"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of currencies this miner wil mine.  All other currencies will be ignored. "
            Tooltip     = "Case insensitive, leave empty to mine all currencies"    
        },
        [PSCustomObject]@{
            Name        = "Coin"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of coins this miner will mine. All other coins will be ignored. "
            Tooltip     = "Case insensitive, leave empty to mine all coins"    
        },
        [PSCustomObject]@{
            Name        = "ExcludeAlgorithm"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of excluded algorithms for this miner. "
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

# Some currencies are suffixed with algo name (e.g. AUR-myr-gr), these have the currency in property symbol. Need to add symbol to all the others
$APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Foreach-Object {
    if (-not $APICurrenciesRequest.$_.symbol) {$APICurrenciesRequest.$_ | Add-Member symbol $_}
}

#Pool allows payout in BTC, DOGE and LTC any currency available in API
$Payout_Currencies = @("BTC", "DOGE", "LTC") + ($APICurrenciesRequest  | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Foreach-Object {$APICurrenciesRequest.$_.symbol} | Select-Object -Unique) | Where-Object {$Config.Pools.$Name.$_}

$APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name |  
    # do not mine if there is no one else is mining (undesired quasi-solo-mining)
    # Where-Object {$APICurrenciesRequest.$_.hashrate -gt 0} | #AHashPool does not list hashrate in currencies API

    # a minimum of $MinWorkers is required. Low worker numbers will cause long delays until payout
    # Where-Object {$APICurrenciesRequest.$_.workers -gt $Config.Pools.$Name.MinWorker} | #AHashPool does not list workers in currencies API 

    # allow well defined currencies only
    Where-Object {$Config.Pools.$Name.Currency.Count -eq 0 -or ($Config.Pools.$Name.Currency -icontains $APICurrenciesRequest.$_.symbol)} | 

    # filter excluded currencies
    Where-Object {$Config.Pools.$Name.ExcludeCurrency -inotcontains $APICurrenciesRequest.$_.symbol} |

    # allow well defined coins only
    Where-Object {$Config.Pools.$Name.Coin.Count -eq 0 -or ($Config.Pools.$Name.Coin -icontains $APICurrenciesRequest.$_.name)} |

    # filter excluded coins
    Where-Object {$Config.Pools.$Name.ExcludeCoin -inotcontains $APICurrenciesRequest.$_.name} |

    # filter excluded algorithms (pool and global definition)
    Where-Object {$Config.Pools.$Name.ExcludeAlgorithm -inotcontains (Get-Algorithm $APICurrenciesRequest.$_.algo)} | Foreach-Object {

    $Pool_Host      = "blockmasters.co"
    $Port           = $APICurrenciesRequest.$_.port
    $Algorithm      = $APICurrenciesRequest.$_.algo
    $Algorithm_Norm = Get-Algorithm $Algorithm
    $CoinName       = $APICurrenciesRequest.$_.name
    $Currency       = $_
    $Symbol         = $APICurrenciesRequest.$_.symbol
    $Workers        = $APICurrenciesRequest.$_.workers
    
    # leave fee empty if IgnorePoolFee
    if (-not $Config.IgnorePoolFee -and -not $Config.Pools.$Name.IgnorePoolFee) {$FeeInPercent = $APIRequest.$Algorithm.Fees}
    
    if ($FeeInPercent) {
        $FeeFactor = 1 - $FeeInPercent / 100
    }
    else {
        $FeeFactor = 1
    }

    $PricePenaltyFactor = $Config.Pools.$Name.PricePenaltyFactor
    if ($PricePenaltyFactor -le 0 -or $PricePenaltyFactor -gt 1) {
        $PricePenaltyFactor = 1
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

    $Stat = Set-Stat -Name "$($Name)_$($Currency)_Profit" -Value ([Double]$APICurrenciesRequest.$Currency.estimate / $Divisor) -Duration $StatSpan -ChangeDetection $true

    $Regions | ForEach-Object {
        $Region = $_
        $Region_Norm = Get-Region $Region

        $Payout_Currencies | ForEach-Object {
            [PSCustomObject]@{
                Algorithm     = $Algorithm_Norm
                Info          = $CoinName
                Price         = $Stat.Live * $FeeFactor * $PricePenaltyFactor
                StablePrice   = $Stat.Week * $FeeFactor * $PricePenaltyFactor
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = $Pool_Host
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