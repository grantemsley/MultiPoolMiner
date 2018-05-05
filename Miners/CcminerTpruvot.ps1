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
$Path = ".\Bin\NVIDIA-TPruvot\ccminer-x64.exe"
$Type = "NVIDIA"
$API  = "Ccminer"
$Port = 4068
$DeviceIdBase = 16 # DeviceIDs are in hex
$DeviceIdOffset = 0 # DeviceIDs start at 0

$MinerFileVersion = "2018050500" # Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerBinaryInfo = "Ccminer (x64) 2.2.5 by Tpruvot"
$MinerBinaryHash = "9156d5fc42daa9c8739d04c3456da8fbf3e9dc91d4894d351334f69a7cee58c5" # If newer MinerFileVersion and hash does not math MPM will trigger an automatick binary update (if Uri is present)
$Uri = "https://github.com/tpruvot/ccminer/releases/download/2.2.5-tpruvot/ccminer-x64-2.2.5-cuda9.7z"
$ManualUri = ""
$WebLink = "https://bitcointalk.org/?topic=770064" # See here for more information about the miner

if ($Info -or -not $Config.Miners.$Name.MinerFileVersion) {
    # Define default miner config
    $DefaultMinerConfig = [PSCustomObject]@{
        "MinerFileVersion" = $MinerFileVersion
        #"IgnoreHWModel" = @("GPU Model Name", "Another GPU Model Name", e.g "GeforceGTX1070") # Available model names are in $Devices.$Type.Name_Norm, Strings here must match GPU model name reformatted with (Get-Culture).TextInfo.ToTitleCase(($_.Name)) -replace "[^A-Z0-9]"
        "IgnoreHWModel" = @()
        #"IgnoreDeviceID" = @(0, 1) # Available deviceIDs are in $Devices.$Type.DeviceIDs
        "IgnoreDeviceID" = @()
        "Commands" = [PSCustomObject]@{
            "bitcore" = "" #Bitcore
            "blake2s" = "" #Blake2s
            "blakecoin" = "" #Blakecoin
            "vanilla" = "" #BlakeVanilla
            "c11" = "" #C11
            #"cryptonight" = "" #CryptoNight is ASIC territory
			"cryptolight" = "" #CryptoLight
            "decred" = "" #Decred
            "equihash" = "" #Equihash
            "groestl" = "" #Groestl
            "hmq1725" = "" #HMQ1725
            "jha" = "" #JHA
            "keccak" = "" #Keccak
            "lbry" = "" #Lbry
            "lyra2v2" = "" #Lyra2RE2
            "lyra2z" = "" #Lyra2z
            #"myr-gr" = "" #MyriadGroestl is ASIC territory
            "neoscrypt" = "" #NeoScrypt
            "phi" = "" #PHI
            "sib" = "" #Sib
            "skein" = "" #Skein
            "skunk" = "" #Skunk
            "timetravel" = "" #Timetravel
            "tribus" = "" #Tribus
            "veltor" = "" #Veltor
            "x11evo" = "" #X11evo
            "x16r" = "" #Raven
            "x17" = "" #X17
        }
        "CommonCommands" = " --submit-stale"
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
        if ($MinerBinaryHash -and (Test-Path $Path) -and (Get-FileHash $Path).Hash -ne $MinerBinaryHash) {
            # Should be the first action. If it fails no further update will take place, update will be retried on next loop
            Update-Binaries -Path $Path -Uri $Uri -Name $Name -MinerFileVersion $MinerFileVersion -RemoveBenchmarkFiles $Config.AutoReBenchmark
        }

        # Always update MinerFileVersion -Force to enforce setting
        $Config.Miners.$Name | Add-member MinerFileVersion $MinerFileVersion -Force

        # Remove config item if in existing config file
        $Config.Miners.$Name.Commands.PSObject.Properties.Remove("myr-gr")
        $Config.Miners.$Name.Commands.PSObject.Properties.Remove("cryptonight")
                    
        # Remove miner benchmark files, these are no longer needed
        Remove-BenchmarkFiles -MinerName $Name -Algorithm (Get-Algorithm "cryptonight")
        Remove-BenchmarkFiles -MinerName $Name -Algorithm (Get-Algorithm "myr-gr")

		# 2.5.5 Add cryptolight algo
		$Config.Miners.$Name.Commands | Add-member cryptolight "" -ErrorAction SilentlyContinue
		
        # Save config to file
        Write-Config -Config $Config -MinerName $Name -Action "Updated"
    }

    # Create miner objects
    . .\Create-MinerObjects.ps1
    Create-CcMinerObjects
}    
catch {}