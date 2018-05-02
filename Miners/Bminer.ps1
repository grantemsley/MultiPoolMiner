using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [PSCustomObject]$Stats,
    [PSCustomObject]$Config,
    [PSCustomObject]$Devices
)

# Compatibility check with old MPM builds
if (-not $Config.Miners) {return}

$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\NVIDIA-BMiner\BMiner.exe"
$Type = "NVIDIA"
$API  = "Bminer"
$Port = 1880

$MinerFileVersion = "2018050100" #Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerBinaryInfo = "BMiner 7.0.0 with experimental support for mining Ethereum (x64)"
$MinerBinaryHash = "08b4c8ccbb97305a4eaef472aefae97dd7d1472b6b0d86fed19544dc7c1fde70" # If newer MinerFileVersion and hash does not math MPM will trigger an automatick binary update (if Uri is present)
$Uri = "https://www.bminercontent.com/releases/bminer-lite-v7.0.0-9c7291b-amd64.zip"
$ManualUri = "https://www.bminer.me/releases/"
$WebLink = "https://www.bminer.me/releases/" # See here for more information about the miner
$MinerFeeInPercentEquihash = 2.0 # Fixed at 2%
$MinerFeeInPercentEthash = 0.65 # Fixed at 0.65%
$MinerFeeInPercentEthash2gb = 0.65 # Fixed at 0.65%
$MinerFeeInPercentEthash3gb = 0.65 # Fixed at 0.65%

if ($MinerFileVersion -gt $Config.Miners.$Name.MinerFileVersion) {
    # Create default miner config, required for setup
    $DefaultMinerConfig = [PSCustomObject]@{
        "MinerFileVersion" = $MinerFileVersion
        #"IgnoreHWModel" = @("GPU Model Name", "Another GPU Model Name", e.g "GeforceGTX1070") # Available model names are in $Devices.$Type.Name_Norm, Strings here must match GPU model name reformatted with (Get-Culture).TextInfo.ToTitleCase(($_.Name)) -replace "[^A-Z0-9]"
        "IgnoreHWModel" = @()
        #"IgnoreDeviceID" = @(0, 1) # Available deviceIDs are in $Devices.$Type.DeviceIDs
        "IgnoreDeviceID" = @()
        "Commands" = [PSCustomObject]@{
            "equihash" = "" #Equihash
            "ethash" = "" #Ethash
            "ethash2gb" = "" #Ethash2GB
            "ethash3gb" = "" #Ethash3GB
        }
        "CommonCommands" = " -watchdog=false -no-runtime-info"
        "Stratum" = [PSCustomObject]@{ # Bminer uses different stratum types to select algo
            "equihash" = "stratum" #Stratum for Equihash
            "ethash" = "ethstratum" #Stratum for Ethereum
            "ethash2gb" = "ethstratum" #Stratum for Ethash2GB
            "ethash3gb" = "ethstratum" #Stratum for Ethash3GB
        }
        "DoNotMine" = [PSCustomObject]@{ # Syntax: "Algorithm" = @("Poolname", "Another_Poolname") 
            #e.g. "equihash" = @("Zpool", "ZpoolCoins")
        }
    }
    if (-not $Config.Miners.$Name.MinerFileVersion) { # new miner, create basic config
        $Config = Add-MinerConfig $Name $DefaultMinerConfig
    }
    else { # Update existing miner config
        try {
            # Read existing config file, do not use $Config because variables are expanded (e.g. $Wallet)
            $NewConfig = Get-Content -Path 'Config.txt' | ConvertFrom-Json -InformationAction SilentlyContinue
            
            # Execute action, e.g force re-download of binary
            # Should be the first action. If it fails no further update will take place, update will be retried on next loop
            if ($MinerBinaryHash -and (Test-Path $Path) -and (Get-FileHash $Path).Hash -ne $MinerBinaryHash) {
                if ($Uri) {
                    Remove-Item $Path -Force -Confirm:$false -ErrorAction Stop # Remove miner binary to force re-download
                    # Update log
                    Write-Log -Level Info "Requested automatic miner binary update ($Name [$MinerFileVersion]). "
                    # Remove benchmark files
                    # if (Test-Path ".\Stats\$($Name)_*_hashrate.txt") {Remove-Item ".\Stats\$($Name)_*_hashrate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
                    # if (Test-Path ".\Stats\$($Name)-*_*_hashrate.txt") {Remove-Item ".\Stats\$($Name)-*_*_hashrate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
                }
                else {
                    # Update log
                    Write-Log -Level Info "New miner binary is available - manual download from '$ManualUri' and install to '$(Split-Path $Path)' is required ($Name [$MinerFileVersion]). "
                    #Write-Log -Level Info "For best performance it is recommended to remove the stat files for this miner. "
                }
            }

            # Always update MinerFileVersion -Force to enforce setting
            $NewConfig.Miners.$Name | Add-member MinerFileVersion $MinerFileVersion -Force

            # Save config to file
            Write-Config $NewConfig $Name

            # Apply config, must re-read from file to expand variables
            $Config = Get-ChildItemContent "Config.txt" | Select-Object -ExpandProperty Content
        }
        catch {}
    }
}

if ($Info) {
    # Just return info about the miner for use in setup
    # attributes without a curresponding settings entry are read-only by the GUI, to determine variable type use .GetType().FullName
    return [PSCustomObject]@{
        MinerFileVersion  = $MinerFileVersion
        MinerBinaryInfo   = $MinerBinaryInfo
        Uri               = $Uri
        ManualUri         = $ManualUri
        Type              = $Type
        Path              = $Path
        Port              = $Port
        WebLink           = $WebLink
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
                Tooltip     = "Detected $Type miner HW:`n$($Devices.$Type | ForEach-Object {"$($_.Name_Norm): DeviceIDs $($_.DeviceIDs -join ' ,')`n"})"
            },
            [PSCustomObject]@{
                Name        = "IgnoreDeviceID"
                Required    = $false
                ControlType = "int[0,$($Devices.$Type.DeviceIDs)]"
                Min         = 0
                Max         = $Devices.$Type.DeviceIDs
                Default     = $DefaultMinerConfig.IgnoreDeviceID
                Description = "List of device IDs you do not want to mine with this miner, e.g. '0'. Leave empty to mine with all available hardware. "
                Tooltip     = "Detected $Type miner HW:`n$($Devices.$Type | ForEach-Object {"$($_.Name_Norm): DeviceIDs $($_.DeviceIDs -join ' ,')`n"})"
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

# Get device list
$Devices.$Type | ForEach-Object {

    if ($DeviceTypeModel -and -not $Config.MinerInstancePerCardModel) {return} #after first loop $DeviceTypeModel is present; generate only one miner
    $DeviceTypeModel = $_
    $DeviceIDs = @() # array of all devices

    # Get list of active devices, returned deviceIDs are in hex format starting from 0
    $DeviceSet = Get-DeviceSet -Config $Config -Devices $Devices -NumberingFormat 16 -StartNumberingFrom 0

    $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm $_).Protocol -eq "stratum+tcp" -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm $_).Name} | ForEach-Object {

        $Algorithm = $_
        $Algorithm_Norm = Get-Algorithm $Algorithm

        Switch ($Algorithm_Norm) { # default is all devices, ethash has a 4GB minimum memory limit
            "Ethash"    {$DeviceIDs = $DeviceSet."4gb"; break}
            "Ethash3gb" {$DeviceIDs = $DeviceSet."3gb"; break}
            default     {$DeviceIDs = $DeviceSet."All"}
        }

        if ($DeviceIDs.Count -gt 0) {

            if ($Config.MinerInstancePerCardModel -and (Get-Command "Get-CommandPerDevice" -ErrorAction SilentlyContinue)) {
                $Miner_Name = "$Name-$($DeviceTypeModel.Name_Norm)"
                $Commands = Get-CommandPerDevice -Command $Config.Miners.$Name.Commands.$_ -Devices $DeviceIDs # additional command line options for algorithm
            }
            else {
                $Miner_Name = $Name
                $Commands = $Config.Miners.$Name.Commands.$_.Split(";") | Select-Object -Index 0 # additional command line options for algorithm
            }

            # Bminer uses different fees per algorithm
            $MinerFeeInPercent = Get-Variable $("MinerFeeInPercent$($Algorithm)") -ValueOnly
            if ($Config.Miners.$Name.DisableMinerFee) {
                $MinerFeeInPercent = $null
                $DisableMinerFee = " -nofee"
                $Fees = @($null)
            }

            $HashRate = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week
            if ($Config.IgnoreMinerFee -or $Config.Miners.$Name.IgnoreMinerFee) {
                $Fees = @($null)
            }
            else {
                $HashRate = $HashRate * (1 - $MinerFeeInPercent / 100)
                $Fees = @($MinerFeeInPercent)
            }
            
            if (-not ($Pools.$Algorithm_Norm.SSL -and $Config.Miners.$Name.Stratum.$Algorithm -eq 'ethstratum')) { # temp fix: Bminer cannot do ethstratum over SSL
                [PSCustomObject]@{
                    Name             = $Miner_Name
                    Type             = $Type
                    Path             = $Path
                    Arguments        = "-api 127.0.0.1:1880 -uri $($Config.Miners.$Name.Stratum.$Algorithm)$(if ($Pools.$Algorithm_Norm.SSL) {'+ssl'})://$($Pools.$Algorithm_Norm.User):$(($Pools.$Algorithm_Norm.Pass) -split "," | Select-Object -Index 0)@$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port)$Commmands$CommonCommands$DisableMinerFee -devices $DeviceIDs"
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