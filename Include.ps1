using module .\Include-Newpoc.psm1

function Get-PoolConfigTemplate {
    
    if ($APICurrenciesRequest) {
        if (($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
            Write-Warning  "Unable to load supported algorithms and currencies for ($Name) - may not be able to configure all pool settings"
        }

        # Define the settings this pool uses.
        $SupportedAlgorithms = @($APICurrenciesRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Foreach-Object {Get-Algorithm $APICurrenciesRequest.$_.algo} | Select-Object -Unique | Sort-Object)
    }
    else {
        if (($APIRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
            Write-Warning  "Unable to load supported algorithms for ($Name) - may not be able to configure all pool settings"
        }

        # Define the settings this pool uses.
        $SupportedAlgorithms = @($APIRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Foreach-Object {Get-Algorithm $_} | Select-Object -Unique | Sort-Object)
    }

    #get all possible payout currencies
    $Currencies = @()
    $Payout_Currencies | Foreach-Object {
        $Currencies += [PSCustomObject]@{
            Name        = "$_"
            Required    = ($Payout_Currencies.Count -eq 0)
            Default     = $($Config.Wallets.$_)
            ControlType = "String"
            Description = "$(if ($($APICurrenciesRequest.$_.Name)) {$($APICurrenciesRequest.$_.Name)} else {$_}) payout address "
            Tooltip     = "Enter $($APICurrenciesRequest.$_.Name) wallet address to receive payouts in $($_)"    
        }
    }
    $Settings = @(
        [PSCustomObject]@{
            Name        = "Worker"
            Required    = $true
            Default     = $Config.Worker
            ControlType = "String"
            Description = "Worker name to report to pool "
            Tooltip     = ""    
        },
        [PSCustomObject]@{
            Name        = "IgnorePoolFee"
            Required    = $false
            ControlType = "Bool"
            Default     = $Config.IgnorePoolFee
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
            Name        = "ExcludeAlgorithm"
            Required    = $false
            Default     = @()
            ControlType = "string[,]"
            Description = "List of excluded algorithms for this miner. "
            Tooltip     = "Case insensitive, leave empty to mine all algorithms"
        }
    )

    [PSCustomObject]@{
        Name             = $Name
        WebSite          = $WebSite
        Description      = $Description
        Algorithms       = $SupportedAlgorithms
        Note             = $Note
        Settings         = ($Settings += $Currencies)
        PayoutCurrencies = $Currencies
    }
}

function New-CcMinerObjects {

    $Miners = @()
    
    # Get device list
    $Devices.$Type | ForEach-Object {

        if ($DeviceTypeModel -and -not $Config.MinerInstancePerCardModel) {return} # after first loop $DeviceTypeModel is present; generate only one miner
        $DeviceTypeModel = $_

        # Get array of IDs of all devices in device set, returned DeviceIDs are of base $DeviceIdBase representation starting from $DeviceIdOffset
        $DeviceIDs = (Get-DeviceIDs -Config $Config -Devices $Devices -Type $Type -DeviceTypeModel $DeviceTypeModel -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset)."All"

        if ($DeviceIDs.Count -gt 0) {

            $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm $_).Protocol -eq "stratum+tcp" -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm $_).Name} | ForEach-Object {

                $Algorithm_Norm = Get-Algorithm $_

                if ($Config.MinerInstancePerCardModel) {
                    $Miner_Name = "$Name-$($DeviceTypeModel.Name_Norm)"
                    $Commands = ConvertTo-CommandPerDeviceSet -Command $Config.Miners.$Name.Commands.$_ -DeviceIDs $DeviceIDs -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset # additional command line options for algorithm
                }
                else {
                    $Miner_Name = $Name
                    $Commands = $Config.Miners.$Name.Commands.$_.Split(";") | Select-Object -Index 0 # additional command line options for algorithm
                }

                $HashRate = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week
                if ($Config.IgnoreMinerFee -or $Config.Miners.$Name.IgnoreMinerFee) {
                    $Fees = @($null)
                }
                else {
                    $HashRate = $HashRate * (1 - $MinerFeeInPercent / 100)
                    $Fees = @($MinerFeeInPercent)
                }

                [PSCustomObject]@{
                    Name             = $Miner_Name
                    Type             = $Type
                    Path             = $Path
                    HashSHA256       = $HashSHA256
                    Arguments        = ("-a $_ -o $($Pools.$Algorithm_Norm.Protocol)://$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) -u $($Pools.$Algorithm_Norm.User) -p $($Pools.$Algorithm_Norm.Pass)$Commands$($Config.Miners.$Name.CommonCommands) -b 127.0.0.1:$($Port) -d $($DeviceIDs -join ',')" -replace "\s+", " ").trim()
                    HashRates        = [PSCustomObject]@{$Algorithm_Norm = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week}
                    API              = $Api
                    Port             = $Port
                    URI              = $URI
                    Fees             = @($Fees)
                    Index            = $DeviceTypeModel.DeviceIDs -join ';' # Always list all devices
                    ShowMinerWindow  = $Config.ShowMinerWindow
                }
            }
        }
        $Port++ # next higher port for next device
    }
}