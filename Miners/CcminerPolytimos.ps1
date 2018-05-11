using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [PSCustomObject]$Stats,
    [PSCustomObject]$Config,
    [PSCustomObject]$Devices
)

$Type = "NVIDIA"
if (-not $Devices.$Type) {return} # No NVIDIA mining device present in system

# Compatibility check with old MPM builds
if (-not $Config.Miners) {$Config | Add-Member Miners @() -ErrorAction SilentlyContinue} 

$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\Polytimos-NVIDIA\ccminer.exe"
$API  = "Ccminer"
$Port = 4068
$DeviceIdBase = 16 # DeviceIDs are in hex
$DeviceIdOffset = 0 # DeviceIDs start at 0

$MinerFileVersion = "2018050400" # Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerInfo = "Ccminer Polytimos by punxsutawneyphil"
$HashSHA256 = "3b9f6a607f0e66974ffb1880b1e89062ac7d0794be6cc596493cc475ee36da6f" # If newer MinerFileVersion and hash does not math MPM will trigger an automatick binary update (if Uri is present)
$Uri = "https://github.com/punxsutawneyphil/ccminer/releases/download/polytimosv2/ccminer-polytimos_v2.zip"
$ManualUri = ""    
$WebLink = "https://github.com/punxsutawneyphil/ccminer/releases" # See here for more information about the miner

if ($Info -or -not $Config.Miners.$Name.MinerFileVersion) {
    # Define default miner config
    $DefaultMinerConfig = [PSCustomObject]@{
        MinerFileVersion = $MinerFileVersion
        IgnoreHWModel  = @()
        IgnoreDeviceID = @()
        CommonCommands = ""
        Commands       = [PSCustomObject]@{
            "poly" = "" #Polytimos
        }
        DoNotMine      = [PSCustomObject]@{
			# Syntax: "Algorithm" = @("Poolname", "Another_Poolname"), e.g. "equihash" = @("Zpool", "ZpoolCoins")
        }
    }

    if ($Info) {
        # Just return info about the miner for use in setup
        # attributes without a corresponding settings entry are read-only by the GUI, to determine variable type use .GetType().FullName
        return [PSCustomObject]@{
            MinerFileVersion = $MinerFileVersion
            MinerInfo        = $MinerInfo
            Uri              = $Uri
            ManualUri        = $ManualUri
            Type             = $Type
            Path             = $Path
            HashSHA256       = $HashSHA256
            Port             = $Port
            WebLink          = $WebLink
            Settings         = @(
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

        # Always update MinerFileVersion -Force to enforce setting
        $TempConfig.Miners.$Name | Add-Member MinerFileVersion $MinerFileVersion -Force

        # Save config to file
        $Config = Set-Config -ConfigFile $ConfigFile -Config $TempConfig -MinerName $Name -Message "Updated miner config ($MinerName [$MinerFileVersion]) in $(Split-Path $ConfigFile -leaf). "
    }

    # Create miner objects
    . .\Create-MinerObjects.ps1
    Create-CcMinerObjects
}    
catch {}