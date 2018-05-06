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
$Path = ".\Bin\NVIDIA-BMiner\BMiner.exe"
$Type = "NVIDIA"
$API  = "Bminer"
$Port = 1880
$DeviceIdBase = 16 # DeviceIDs are in hex
$DeviceIdOffset = 0 # DeviceIDs start at 0

$MinerFileVersion = "2018050400" # Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
#$MinerBinaryInfo = "BMiner 7.0.0 with experimental support for mining Ethereum (x64)"
$MinerBinaryInfo = "BMiner 6.1.0 with experimental support for mining Ethereum (x64)"
#$HashSHA256 = "08b4c8ccbb97305a4eaef472aefae97dd7d1472b6b0d86fed19544dc7c1fde70" # If newer MinerFileVersion and hash does not math MPM will trigger an automatick binary update (if Uri is present)
$HashSHA256 = "1472b6b0d86fed19544dc7c1fde70" # If newer MinerFileVersion and hash does not math MPM will trigger an automatick binary update (if Uri is present)
#$Uri = "https://www.bminercontent.com/releases/bminer-lite-v7.0.0-9c7291b-amd64.zip"
$Uri = "https://www.bminercontent.com/releases/bminer-v6.1.0-7ea8bbe-amd64.zip"
$ManualUri = "https://www.bminer.me/releases/"
$WebLink = "https://www.bminer.me/releases/" # See here for more information about the miner
$MinerFeeInPercentEquihash = 2.0 # Fixed at 2%
$MinerFeeInPercentEthash = 0.65 # Fixed at 0.65%
$MinerFeeInPercentEthash2gb = 0.65 # Fixed at 0.65%
$MinerFeeInPercentEthash3gb = 0.65 # Fixed at 0.65%

if ($Info -or -not $Config.Miners.$Name.MinerFileVersion) {
    # Define default miner config
    $DefaultMinerConfig = [PSCustomObject]@{
        "MinerFileVersion" = $MinerFileVersion
        #"IgnoreHWModel" = @("GPU Model Name", "Another GPU Model Name", e.g "GeforceGTX1070") # Available model names are in $Devices.$Type.Name_Norm, Strings here must match GPU model name reformatted with (Get-Culture).TextInfo.ToTitleCase(($_.Name)) -replace "[^A-Z0-9]"
        "IgnoreHWModel" = @()
        #"IgnoreDeviceID" = @(0, 1) # Available deviceIDs are in $Devices.$Type.DeviceIDs
        "IgnoreDeviceID" = @()
        "Commands" = [PSCustomObject]@{
            "equihash" = "" #Equihash
#            "ethash" = "" #Ethash
#            "ethash2gb" = "" #Ethash2GB
#            "ethash3gb" = "" #Ethash3GB
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

    if ($Info) {
        # Just return info about the miner for use in setup
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
    # Keep miner config up to date
    if (-not $Config.Miners.$Name.MinerFileVersion) { # new miner, add default miner config
        # Add default miner config
        $Config.Miners | Add-Member $Name $DefaultMinerConfig -Force -ErrorAction Stop
        # Save config to file
        Write-Config -Config $Config -MinerName $Name -Action "Added"
    }
    if ($MinerFileVersion -gt $Config.Miners.$Name.MinerFileVersion) { # Update existing miner config
        if ($HashSHA256 -and (Test-Path $Path) -and (Get-FileHash $Path).Hash -ne $HashSHA256) {
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
        $DeviceIDsSet = Get-DeviceIDs -Config $Config -Devices $Devices -Type $Type -DeviceTypeModel $DeviceTypeModel -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset

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
                    $Commands = ConvertTo-CommandPerDeviceSet -Command $Config.Miners.$Name.Commands.$_ -DeviceIDs $DeviceIDs -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset # additional command line options for algorithm
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
                        Arguments        = "-api 127.0.0.1:1880 -uri $($Config.Miners.$Name.Stratum.$Algorithm)$(if ($Pools.$Algorithm_Norm.SSL) {'+ssl'})://$([System.Web.HttpUtility]::UrlEncode($Pools.$Algorithm_Norm.User)):$([System.Web.HttpUtility]::UrlEncode($Pools.$Algorithm_Norm.Pass) -split "," | Select-Object -Index 0)@$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port)$Commmands$($Config.Miners.$Name.CommonCommands)$DisableMinerFee -devices $DeviceIDs"
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
    }
    $Port++ # next higher port for next device
}    
catch {}