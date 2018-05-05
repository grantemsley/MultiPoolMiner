using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [PSCustomObject]$Stats,
    [PSCustomObject]$Config,
    [PSCustomObject]$Devices
)

# Compatibility check with old MPM builds
if (-not $Config.Miners) {$Config | Add-Member Miners @() -ErrorAction SilentlyContinue} 

$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\PhoenixMiner\PhoenixMiner.exe"
$Type = "NVIDIA"
$API  = "Claymore"
$Port = 23334
$DeviceIdBase = 10 # DeviceIDs are in decimal format
$DeviceIdOffset = 1 # DeviceIDs start at 1

$MinerFileVersion = "2018050400" # Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerBinaryInfo = "PhoenixMiner 2.9e: fastest Ethereum/Ethash miner with lowest devfee"
$MinerBinaryHash = "a531b7b0bb925173d3ea2976b72f3d280f64751bdb094d5bb980553dfa85fb07" # If newer MinerFileVersion and hash does not math MPM will trigger an automatick binary update (if Uri is present)
$Uri = ""
$ManualUri = "https://mega.nz/#F!2VskDJrI!lsQsz1CdDe8x5cH3L8QaBw"
$WebLink = "https://bitcointalk.org/index.php?topic=2647654.0" # See here for more information about the miner
$MinerFeeInPercent = 1/90*35/60*100 # Fixed, fee of 0.65% (35 seconds defvee mining per each 90 minutes)

if ($Info -or -not $Config.Miners.$Name.MinerFileVersion) {
    # Create default miner config
    $DefaultMinerConfig = [PSCustomObject]@{
        "MinerFileVersion" = $MinerFileVersion
        #"IgnoreHWModel" = @("GPU Model Name", "Another GPU Model Name", e.g "GeforceGTX1070") # Available model names are in $Devices.$Type.Name_Norm, Strings here must match GPU model name reformatted with (Get-Culture).TextInfo.ToTitleCase(($_.Name)) -replace "[^A-Z0-9]"
        "IgnoreHWModel" = @()
        #"IgnoreDeviceID" = @(0, 1) # Available deviceIDs are in $Devices.$Type.DeviceIDs
        "IgnoreDeviceID" = @()
        "Commands" = [PSCustomObject]@{
            "Ethash"    = "" #Ethash
            "Ethash2gb" = "" #Ethash2gb
            "Ethash3gb" = "" #Ethash3gb
        }
        "CommonCommands" = ""
        "DoNotMine" = [PSCustomObject]@{ # Syntax: "Algorithm" = @("Poolname", "Another_Poolname") 
            #e.g. "equihash" = @("Zpool", "ZpoolCoins")
        }
    }

    if ($Info) {
        # Define default miner config
        # attributes without a corresponding settings entry are read-only by the GUI, to determine variable type use .GetType().FullName
        return [PSCustomObject]@{
            MinerFileVersion  = $MinerFileVersion
            MinerBinaryInfo   = $MinerBinaryInfo
            Uri               = $Uri
            ManualUri         = $ManualUri
            Type              = $Type
            Path              = $Path
            Port              = $Port
            WebLink           = $WebLink
            MinerFeeInPercent = $MinerFeeInPercent
            Settings          = @(
                [PSCustomObject]@{
                    Name        = "IgnoreMinerFee"
                    ControlType = "switch"
                    Default     = $false
                    Description = "Miner contains dev fee $($MinerFeeInPercent)%. Tick to ignore miner fees in internal calculations. "
                    Tooltip     = "Miner does not allow to disable miner dev fee"
                },
                [PSCustomObject]@{
                    Name        = "IgnoreHWModel"
                    Required    = $false
                    ControlType = "string[0,$($Devices.$Type.count)]"
                    Default     = $DefaultMinerConfig.IgnoreHWModel
                    Description = "List of hardware models you do not want to mine with this miner, e.g. 'GeforceGTX1070'. Leave empty to mine with all available hardware. "
                    Tooltip     = "Detected $Type miner HW:`n$($Devices.$Type | ForEach-Object {"$($_.Name_Norm): DeviceIDs $($_.DeviceIDs -join ' ,')"})"
                },
                [PSCustomObject]@{
                    Name        = "IgnoreDeviceID"
                    Required    = $false
                    ControlType = "int[0,$($Devices.$Type.DeviceIDs.count)]"
                    Min         = 0
                    Max         = $Devices.$Type.DeviceIDs.count
                    Default     = $DefaultMinerConfig.IgnoreDeviceID
                    Description = "List of device IDs you do not want to mine with this miner, e.g. '0'. Leave empty to mine with all available hardware. "
                    Tooltip     = "Detected $Type miner HW:`n$($Devices.$Type | ForEach-Object {"$($_.Name_Norm): DeviceIDs $($_.DeviceIDs -join ' ,')"})"
                },
                [PSCustomObject]@{
                    Name        = "Commands"
                    Required    = $false
                    ControlType = "PSCustomObject[1,]"
                    Default     = $DefaultMinerConfig.Commands
                    Description = "Each line defines an algorithm that can be mined with this miner. Optional miner parameters can be added after the '=' sign. "
                    Tooltip     = "Note: Most extra parameters must be prefixed with a space`nTo disable an algorithm prefix it with '#'"
                },
                [PSCustomObject]@{
                    Name        = "CommonCommands"
                    Required    = $false
                    ControlType = "string"
                    Default     = $DefaultMinerConfig.CommonCommands
                    Description = "Optional miner parameter that gets appended to the resulting miner command line (for all algorithms). "
                    Tooltip     = "Note: Most extra parameters must be prefixed with a space"
                },
                [PSCustomObject]@{
                    Name        = "DoNotMine"
                    Required    = $false
                    ControlType = "PSCustomObject[0,]"
                    Default     = $DefaultMinerConfig.DoNotMine
                    Description = "Optional filter parameter per algorithm and pool. MPM will not use the miner for this algorithm at the listed pool. "
                    Tooltip     = "Syntax: 'Algorithm_Norm = @(`"Poolname`", `"PoolnameCoins`")"
                }
            )
        }
    }
}

try {
    # Keep miner config up to date
    if (-not $Config.Miners.$Name.MinerFileVersion) { # new miner, add default miner config
        # Add default miner config
        $Config.Miners | Add-Member $Name $DefaultMinerConfig -Force -ErrorAction Stop
        # Save config to file
        Write-Config -Config $Config -MinerName $Name -Action "Added"
    }
    if ($MinerFileVersion -gt $Config.Miners.$Name.MinerFileVersion) { # Update existing miner config
        if ($MinerBinaryHash -and (Test-Path $Path) -and (Get-FileHash $Path).Hash -ne $MinerBinaryHash) {
            # Should be the first action. If it fails no further update will take place, update will be retried on next loop
            Update-Binaries -Path $Path -Uri $Uri -Name $Name -MinerFileVersion $MinerFileVersion -RemoveBenchmarkFiles $Config.AutoReBenchmark
        }

        # Always update MinerFileVersion -Force to enforce setting
        $Config.Miners.$Name | Add-member MinerFileVersion $MinerFileVersion -Force

        # Save config to file
        Write-Config -Config $Config -MinerName $Name -Action "Updated"
    }

    # Create miner objects
    $Devices.$Type | ForEach-Object {
        if ($DeviceTypeModel -and -not $Config.MinerInstancePerCardModel) {return} # after first loop $DeviceTypeModel is present; generate only one miner
        $DeviceTypeModel = $_

        # Get array of IDs of all devices in device set, returned DeviceIDs are of base $DeviceIdBase representation starting from $DeviceIdOffset
        $DeviceIDsSet = Get-DeviceIDsSet -Config $Config -Devices $Devices -Type $Type -DeviceTypeModel $DeviceTypeModel -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset

        $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm $_) -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm $_).Name} | ForEach-Object {

            $Algorithm = $_
            $Algorithm_Norm = Get-Algorithm $Algorithm

            Switch ($Algorithm_Norm) { # default is all devices, ethash has a 4GB minimum memory limit
                "Ethash"    {$DeviceIDs = $DeviceIDsSet."4gb"; break}
                "Ethash3gb" {$DeviceIDs = $DeviceIDsSet."3gb"; break}
                default     {$DeviceIDs = $DeviceIDsSet."All"}
            }

            if ($DeviceIDs.Count -gt 0) {

                if ($Config.MinerInstancePerCardModel) {
                    $Miner_Name = "$Name-$($DeviceTypeModel.Name_Norm)"
                    $Commands = Get-CommandPerDeviceSet -Command $Config.Miners.$Name.Commands.$_ -DeviceIDs $DeviceIDs -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset # additional command line options for algorithm
                }
                else {
                    $Miner_Name = $Name
                    $Commands = $Config.Miners.$Name.Commands.$_.Split(";") | Select-Object -Index 0 # additional command line options for algorithm
                }
                
                $HashRate = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week
                if ($Config.IgnoreMinerFee -or $Config.Miners.$Name.IgnoreMinerFee) {
                    $DisableMinerFee = " --no-devfee"
                }
                else {
                    $HashRate = $HashRate * (1 - $MinerFeeInPercent / 100)
                    $Fees = @($MinerFeeInPercent)
                }
                
                # Use only the specified GPUs (if more than 10, separate the indexes with comma)
                if ($DeviceIDs -gt 9) {$GPUs = $DeviceIDs -join ','} else {$GPUs = $DeviceIDs -join ''}
                
                [PSCustomObject]@{
                    Name             = $Miner_Name
                    Type             = $Type
                    Path             = $Path
                    Arguments        = ("-rmode 0 -cdmport 23334 -cdm 1 -pool $($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) -wal $($Pools.$Algorithm_Norm.User) -pass $($Pools.$Algorithm_Norm.Pass)$Commands$($Config.Miners.$Name.CommonCommands) -proto 4 -coin auto -nvidia -gpus $($GPUs)" -replace "\s+", " ").trim()
                    HashRates        = [PSCustomObject]@{$Algorithm_Norm = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week}
                    API              = $Api
                    Port             = $Port
                    URI              = $Uri
                    Fees             = @($Fees)
                    Index            = $DeviceTypeModel.DeviceIDs -join ';' # Always list all devices
                    ShowMinerWindow  = $Config.ShowMinerWindow
                }
            }
        }
    }
    $Port++ # next higher port for next device
}
catch{}