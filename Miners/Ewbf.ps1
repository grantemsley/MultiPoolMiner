using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [PSCustomObject]$Stats,
    [PSCustomObject]$Config,
    [PSCustomObject]$Devices
)

$Type = "NVIDIA"
if (-not $Devices.$Type) {return} # No NVIDIA device present in system

# Compatibility check with old MPM builds
if (-not $Config.Miners) {$Config | Add-Member Miners @() -ErrorAction SilentlyContinue} 

# Hardcoded per miner version, do not allow user to change in config
$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\Equihash-EWBF\miner.exe"
$API  = "DSTM"
$Port = 42000
$DeviceIdBase = 16 # DeviceIDs are in hex
$DeviceIdOffset = 0 # DeviceIDs start at 0

$MinerFileVersion = "2018050400" # Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerInfo = "EWBF's CUDA Zcash miner Version 0.3.4b (x64)"
$HashSHA256 = "84dd02debbf2b0c5ed7eebf813305543265e34ec98635139787bf8b882e7c7b4" # If newer MinerFileVersion and hash does not math MPM will trigger an automatick binary update (if Uri is present)
$PrerequisitePath = "$env:SystemRoot\System32\msvcr120.dll"
$PrerequisiteURI  = "http://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe"                
$Uri = ""
$ManualUri = "https://mega.nz/#F!usQh2bTa!3qp_PaiO-dw3F0mpvLXynA"
$WebLink = "https://bitcointalk.org/index.php?topic=1707546.0" # See here for more information about the miner
$MinerFeeInPercent = 2.0 # Fixed at 2%

if ($Info -or -not $Config.Miners.$Name.MinerFileVersion) {
    # Define default miner config
    $DefaultMinerConfig = [PSCustomObject]@{
        MinerFileVersion = $MinerFileVersion
        IgnoreHWModel    = @()
        IgnoreDeviceID   = @()
        CommonCommands   = ""
        Commands         = [PSCustomObject]@{
            "equihash" = @() #Equihash
        }
        DoNotMine        = [PSCustomObject]@{
            # Syntax: "Algorithm" = @("Poolname", "Another_Poolname"), e.g. "equihash" = @("Zpool", "ZpoolCoins")
        }
    }

    if ($Info) {
        # Just return info about the miner for use in setup
        # attributes without a corresponding settings entry are read-only by the GUI, to determine variable type use .GetType().FullName
        return [PSCustomObject]@{
            MinerFileVersion  = $MinerFileVersion
            MinerInfo         = $MinerInfo
            Uri               = $Uri
            ManualUri         = $ManualUri
            Type              = $Type
            Path              = $Path
            HashSHA256        = $HashSHA256
            Port              = $Port
            WebLink           = $WebLink
            MinerFeeInPercent = $MinerFeeInPercent
            Settings          = @(
                [PSCustomObject]@{
                    Name        = "IgnoreMinerFee"
                    Required    = $false
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
                    Required    = $true
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
    if (-not $Config.Miners.$Name.MinerFileVersion) { # New miner, add default miner config
        $Config = Add-MinerConfig -ConfigFile $ConfigFile -MinerName $Name -Config $DefaultMinerConfig -Message "Added miner config ($MinerName [$MinerFileVersion]) to $(Split-Path $ConfigFile -leaf). "
    }
    if ($MinerFileVersion -gt $Config.Miners.$Name.MinerFileVersion) { # Update existing miner config
        if ($HashSHA256 -and (Test-Path $Path) -and (Get-FileHash $Path).Hash -ne $HashSHA256) {
            # Should be the first action. If it fails no further update will take place, update will be retried on next loop
            Update-Binaries -Path $Path -Uri $Uri -Name $Name -MinerFileVersion $MinerFileVersion -RemoveBenchmarkFiles $Config.AutoReBenchmark
        }

        # Read config from file to not expand any variables
        $TempConfig = Get-Content "Config.txt" | ConvertFrom-Json

        # Always update MinerFileVersion -Force to enforce setting
        $TempConfig.Miners.$Name | Add-Member MinerFileVersion $MinerFileVersion -Force

        # Save config to file
        $Config = Set-Config -ConfigFile $ConfigFile -Config $TempConfig -MinerName $Name -Message "Updated miner config ($MinerName [$MinerFileVersion]) in $(Split-Path $ConfigFile -leaf). "
    }

    # Create miner objects
    $Devices.$Type | ForEach-Object {

        if ($DeviceTypeModel -and -not $Config.MinerInstancePerCardModel) {return} # after first loop $DeviceTypeModel is present; generate only one miner
        $DeviceTypeModel = $_

        # Get array of IDs of all devices in device set, returned DeviceIDs are of base $DeviceIdBase representation starting from $DeviceIdOffset
        $DeviceIDs = (Get-DeviceIDs -Config $Config -Devices $Devices -Type $Type -DeviceTypeModel $DeviceTypeModel -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset)."All"

        if ($DeviceIDs.Count -gt 0) {

            $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm $_).SSL -eq $false -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm $_).Name} | ForEach-Object {

                $Algorithm_Norm = Get-Algorithm $_

                if ($Config.MinerInstancePerCardModel) {
                    $Miner_Name = "$Name-$($DeviceTypeModel.Name_Norm)"
                    $Commands = ConvertTo-CommandPerDeviceSet -Command $Config.Miners.$Name.Commands.$_ -DeviceIDs $DeviceIDs -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset # additional command line options for algorithm
                }
                else {
                    $Miner_Name = $Name
                    $Commands = $Config.Miners.$Name.Commands.$_ # additional command line options for algorithm
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
                    Arguments        = ("--server $($Pools.$Algorithm_Norm.Host) --port $($Pools.$Algorithm_Norm.Port) --user $($Pools.$Algorithm_Norm.User) --pass $($Pools.$Algorithm_Norm.Pass)$Commands$($Config.Miners.$Name.CommonCommands) --api 0.0.0.0:$($Port) --cuda_devices $($DeviceIDs -join ' ')$($DisableMinerFee)" -replace "\s+", " ").trim()
                    HashRates        = [PSCustomObject]@{$Algorithm_Norm = $HashRate}
                    API              = $Api
                    Port             = $Port
                    URI              = $Uri
                    Fees             = @($Fees)
                    Index            = $DeviceTypeModel.DeviceIDs -join ';' # Always list all devices
                    PrerequisitePath = $PrerequisitePath
                    PrerequisiteURI  = $PrerequisiteURI               
                    ShowMinerWindow  = $Config.ShowMinerWindow
                }
            }
        }
    }
    $Port++ # next higher port for next device
}    
catch {}