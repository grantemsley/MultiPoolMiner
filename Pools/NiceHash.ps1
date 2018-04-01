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

# Default pool config values, these need to be present for pool logic
$Default_PoolFeeInternalWallet = 1.0
$Config.Pools.$Name | Add-Member PoolFeeInternalWallet $Default_PoolFeeInternalWallet -ErrorAction SilentlyContinue # ignore error if value exists
$Default_PoolFeeExternalWallet = 3.0
$Config.Pools.$Name | Add-Member PoolFeeExternalWallet $Default_PoolFeeExternalWallet -ErrorAction SilentlyContinue # ignore error if value exists
$Default_IsInternalWallet = $false 
$Config.Pools.$Name | Add-Member IsInternalWallet $Default_IsInternalWallet -ErrorAction SilentlyContinue # ignore error if value exists

$Pool_APIUrl = "http://api.nicehash.com/api?method=simplemultialgo.info"

$APIRequest = [PSCustomObject]@{}

if ($Info) {
    # Just return info about the pool for use in setup
    $Description  = "Pool allows payout in BTC only"
    $WebSite      = "http://www.nicehash.com"
    $Note         = "To receive payouts specify a valid BTC wallet" # Note is shown beside each pool in setup

    try {
        $APIRequest = Invoke-RestMethod $Pool_APIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    } 
    Catch {
        Write-Warning "Unable to load supported algorithms and currencies for ($Name) - may not be able to configure all pool settings"
    }

    # Define the settings this pool uses.
    $SupportedAlgorithms = @($APIRequest.result.simplemultialgo | Foreach-Object {Get-Algorithm $_.name} | Select-Object -Unique)
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
        },
        [PSCustomObject]@{
            Name        = "BTC"
            Required    = $false
            Default     = $Config.Wallet
            ControlType = "string"
            Description = "Bitcoin payout address`nTo receive payouts in another currency than BTC clear address and define another address below. "
            Tooltip     = "Enter Bitcoin wallet address if you want to receive payouts in BTC"    
        },
        [PSCustomObject]@{
            Name        = "IsInternalWallet"
            Required    = $false
            ControlType = "switch"
            Default     = $Default_IsInternalWallet
            Description = "Tick to if BTC address is $($Name) internal wallet"
            Tooltip     = "$($Name) applies different pool fees for internal and external wallets"
        },
        [PSCustomObject]@{
            Name        = "PoolFeeInternalWallet"
            Required    = $false
            ControlType = "double"
            Min         = 0
            Max         = 100
            Fractions   = 2
            Default     = $Default_PoolFeeInternalWallet
            Description = "Pool fee (in %) for internal wallet`nSet to 0 to ignore pool fees"
            Tooltip     = "$($Name) applies different pool fees for internal and external wallets"
        },
        [PSCustomObject]@{
            Name        = "PoolFeeExternalWallet"
            Required    = $false
            ControlType = "double"
            Min         = 0
            Max         = 100
            Fractions   = 2
            Default     = $Default_PoolFeeExternalWallet
            Description = "Pool fee (in %) for external wallet`nSet to 0 to ignore pool fees"
            Tooltip     = "$($Name) applies different pool fees for internal and external wallets"
        }
    )

#    #add all possible payout currencies, currently NiceHash allows payout in BTC only
#    $Payout_Currencies | Foreach-Object {
#        $Settings += [PSCustomObject]@{
#            Name        = "$_"
#            Required    = $false
#            Default     = "$($Config.Pools.$Name.$_)"
#            ControlType = "string"
#            Description = "$($APICurrenciesRequest.$_.Name) payout address "
#            Tooltip     = "Only enter $($APICurrenciesRequest.$_.Name) wallet address if you want to receive payouts in $($_)"    
#        }
#    }

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
    $APIRequest = Invoke-RestMethod $Pool_APIUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
}
catch {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

if (($APIRequest.result.simplemultialgo | Measure-Object).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

$Regions = "eu", "usa", "hk", "jp", "in", "br"

$APIRequest.result.simplemultialgo | Where-Object {$DisabledAlgorithms -inotcontains (Get-Algorithm $_.name)} | ForEach-Object {
    $Pool_Host      = "nicehash.com"
    $Port           = $_.port
    $Algorithm      = $_.name
    $Algorithm_Norm = Get-Algorithm $Algorithm
    $Currency       = ""
    
    # leave fee empty if IgnorePoolFee
    if (-not $Config.IgnorePoolFee -and -not $Config.Pools.$Name.IgnorePoolFee) {
        if ($Config.Pools.$Name.IsInternalWallet) {
            $FeeInPercent = $Config.Pools.$Name.PoolFeeInternalWallet
        }
        else {
            $FeeInPercent = $Config.Pools.$Name.PoolFeeExternalWallet
        }
    }
    
    if ($FeeInPercent) {
        $FeeFactor = 1 - $FeeInPercent / 100
    }
    else {
        $FeeFactor = 1
    }

    if ($Algorithm_Norm -eq "Sia") {$Algorithm_Norm = "SiaNiceHash"} #temp fix
    if ($Algorithm_Norm -eq "Decred") {$Algorithm_Norm = "DecredNiceHash"} #temp fix

    $Divisor = 1000000000

    $Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$_.paying / $Divisor) -Duration $StatSpan -ChangeDetection $true

    $Regions | ForEach-Object {
        $Region = $_
        $Region_Norm = Get-Region $Region

        if ($BTC) {
            [PSCustomObject]@{
                Algorithm     = $Algorithm_Norm
                Info          = $Currency
                Price         = $Stat.Live * $FeeFactor
                StablePrice   = $Stat.Week * $FeeFactor
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = "$Algorithm.$Region.$Pool_Host"
                Port          = $Port
                User          = "$BTC.$Worker"
                Pass          = "x"
                Region        = $Region_Norm
                SSL           = $false
                Updated       = $Stat.Updated
                Fee           = $FeeInPercent
            }

            if ($Algorithm_Norm -eq "Cryptonight" -or $Algorithm_Norm -eq "Equihash") {
                [PSCustomObject]@{
                    Algorithm     = $Algorithm_Norm
                    Info          = $Currency
                    Price         = $Stat.Live * $FeeFactor
                    StablePrice   = $Stat.Week * $FeeFactor
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+ssl"
                    Host          = "$Algorithm.$Region.$Pool_Host"
                    Port          = $Port + 30000
                    User          = "$BTC.$Worker"
                    Pass          = "x"
                    Region        = $Region_Norm
                    SSL           = $true
                    Updated       = $Stat.Updated
                    Fee           = $FeeInPercent
                }
            }
        }
    }
}