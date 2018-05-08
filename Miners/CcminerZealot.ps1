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
$Path = ".\Bin\NVIDIA-Zealot\z-enemy.exe"
$Type = "NVIDIA"
$API  = "Ccminer"
$Port = 4068
$DeviceIdBase = 16 # DeviceIDs are in hex
$DeviceIdOffset = 0 # DeviceIDs start at 0

$MinerFileVersion = "2018050400" # Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerInfo = "zealot/enemy-1.08, 1% devfee"
$HashSHA256 = "59e413741711e2984a1911db003fee807941f9a9f838cb96ff050194bc74bfce" # If newer MinerFileVersion and hash does not math MPM will trigger an automatick binary update (if Uri is present)
$Uri = ""
$ManualUri = "https://mega.nz/#!5WACFRTT!tV1vUsFdBIDqCzBrcMoXVR2G9YHD6xqct5QB2nBiuzM"
$WebLink = "https://bitcointalk.org/index.php?topic=3378390.0;all"
$MinerFeeInPercent = 1 # Fixed at 1%. Dev fee will start randomly when miner is first started. After 1% of time mined then automatically switches back to user pool 

if ($Info -or -not $Config.Miners.$Name.MinerFileVersion) {
    # Define default miner config
    $DefaultMinerConfig = [PSCustomObject]@{
        MinerFileVersion = $MinerFileVersion
        IgnoreHWModel  = @()
        IgnoreDeviceID = @()
        CommonCommands = ""
        Commands       = [PSCustomObject]@{
            "bitcore" = "" #Bitcore
            #"blake2s" = "" #Blake2s - Not Supported
            #"blakecoin" = "" #Blakecoin - Not Supported
            #"c11" = "" #C11 - Not Supported
            #"cryptonight" = "" #CryptoNight - Not Supported; ASIC territory
            "decred" = "" #Decred - NOT TESTED
            #"equihash" = "" #Equihash - Not Supported
            #"ethash" = "" #Ethash - Not Supported
            #"groestl" = "" #Groestl - Not Supported
            #"hmq1725" = "" #HMQ1725 - Not Supported
            #"hsr" = "" #HSR - Not Supported
            "jha" = "" #JHA - NOT TESTED
            #"keccak" = "" #Keccak - Not Supported
            #"keccakc" = "" #Keccakc - Not Supported
            #"lbry" = "" #Lbry - Not Supported
            #"lyra2v2" = "" #Lyra2RE2 - Not Supported
            #"lyra2z" = "" #Lyra2z - Not Supported
            #"myr-gr" = "" #MyriadGroestl - Not Supported
            #"neoscrypt" = "" #NeoScrypt - Not Supported
            #"nist5" = "" #Nist5 is ASIC territory
            #"pascal" = "" #Pascal - Not Supported
            "phi" = "" #PHI
            "poly" = "" #Polytmos - NOT TESTED
            #"qubit" = "" #qubit - Not Supported
            #"quark" = "" #Quark - Not Supported
            #"sib" = "" #Sib - Not Supported
            #"skein" = "" #Skein - Not Supported
            #"skunk" = "" #Skunk - Not Supported
            #"timetravel" = "" #Timetravel - Not Supported
            #"tribus" = "" #Tribus - Not Supported
            "vanilla" = "" #BlakeVanilla - NOT TESTED
            "veltor" = "" #Veltor - NOT TESTED
            #"x11" = "" #X11 - Not Supported
            #"x11evo" = "" #X11evo - Not Supported
            "x12" = "" #X12 - NOT TESTED
            #"x13" = "" #X13 - Not Supported
            "x14" = "" #X14 - NOT TESTED
            "x16r" = "" #Rave
            "x16s" = "" #Pigeon
            #"x17" = "" #X17 - Not Supported
            #"xevan" = "" #Xevan - Not Supported
            #"yescrypt" = "" #Yescrypt - Not Supported
        }
        DoNotMine      = [PSCustomObject]@{
            # Syntax: "Algorithm" = "Poolname", e.g. "equihash" = @("Zpool", "ZpoolCoins")
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
    if (-not $Config.Miners.$Name.MinerFileVersion) { 
        # New miner, add default miner config
        $Config = Add-MinerConfig -ConfigFile "Config.txt" -MinerName $Name -Config $DefaultMinerConfig
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

        # Remove config item if in existing config file
        $TempConfig.Miners.$Name.Commands.PSObject.Properties.Remove("myr-gr")
        $TempConfig.Miners.$Name.Commands.PSObject.Properties.Remove("nist5")
        $TempConfig.Miners.$Name.Commands.PSObject.Properties.Remove("cryptonight")
                    
        # Remove miner benchmark files, these are no longer needed
        Remove-BenchmarkFiles -MinerName $Name -Algorithm (Get-Algorithm "cryptonight")
        Remove-BenchmarkFiles -MinerName $Name -Algorithm (Get-Algorithm "nist5")
        Remove-BenchmarkFiles -MinerName $Name -Algorithm (Get-Algorithm "myr-gr")

        # Save config to file and apply
        $Config = Set-Config -ConfigFile "Config.txt" -Config $TempConfig -MinerName $Name -Action "Updated"
    }

    # Create miner objects
    . .\Create-MinerObjects.ps1
    Create-CcMinerObjects
}    
catch {}