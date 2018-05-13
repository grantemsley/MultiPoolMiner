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
$Path = ".\Bin\Excavator\excavator.exe"
$API  = "Excavator"
$Port = 23456
$DeviceIdBase = 16 # DeviceIDs are in hex
$DeviceIdOffset = 0 # DeviceIDs start at 0

$MinerFileVersion = "2018050404" # Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerInfo = "NiceHash Excavator 1.4.4 alpha (x64)"
$HashSHA256 = "4cc2ff8c07f17e940a1965b8d0f7dd8508096a4e4928704912fa96c442346642" # If newer MinerFileVersion and hash does not math MPM will trigger an automatick binary update (if URI is present)
$PrerequisitePath = "$env:SystemRoot\System32\msvcr120.dll"
$PrerequisiteURI = "http://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe"
$URI = "https://github.com/nicehash/excavator/releases/download/v1.4.4a/excavator_v1.4.4a_NVIDIA_Win64.zip"
$ManualURI = "" # Link for manual miner download
$WebLink = "https://github.com/nicehash/excavator" # See here for more information about the miner

if ($Config.InfoOnly -or -not $Config.Miners.$Name.MinerFileVersion) {
    # Define default miner config
    $DefaultMinerConfig = [PSCustomObject]@{
        MinerFileVersion = $MinerFileVersion
        IgnoreHWModel    = @()
        IgnoreDeviceID   = @()
        CommonCommands   = ""
        Commands         = [PSCustomObject]@{
            "blake2s:1"         = @() #Blake2s 
            #"cryptonight:1"     = @() #Cryptonight; ASIC territory
            "decred:1"          = @() #Decred
            "daggerhashimoto:1" = @() #Ethash
            "equihash:1"        = @() #Equihash
            "neoscrypt:1"       = @() #NeoScrypt
            "keccak:1"          = @() #Keccak
            "lbry:1"            = @() #Lbry
            "lyra2rev2:1"       = @() #Lyra2RE2
            "pascal:1"          = @() #Pascal
            "blake2s:2"         = @() #Blake2s 
            #"cryptonight:2"     = @() #Cryptonight; out of memory; ASIC territory
            "decred:2"          = @() #Decred
            "daggerhashimoto:2" = @() #Ethash
            "equihash:2"        = @() #Equihash
            #"neoscrypt:2"       = @() #NeoScrypt; out of memory
            "keccak:2"          = @() #Keccak
            "lbry:2"            = @() #Lbry
            "lyra2rev2:2"       = @() #Lyra2RE2
            "pascal:2"          = @() #Pascal
        }
        DoNotMine        = [PSCustomObject]@{
            # Syntax: "Algorithm" = @("Poolname", "Another_Poolname"), e.g. "equihash" = @("Zpool", "ZpoolCoins")
        }
    }

    if ($Config.InfoOnly) {
        # Just return info about the miner for use in setup
        # attributes without a corresponding settings entry are read-only by the GUI, to determine variable type use .GetType().FullName
        return [PSCustomObject]@{
            MinerFileVersion = $MinerFileVersion
            MinerInfo        = $MinerInfo
            URI              = $URI
            ManualURI        = $ManualUri
            Type             = $Type
            Path             = $Path
            HashSHA256       = $HashSHA256
            Port             = $Port
            WebLink          = $WebLink
            Settings         = @(
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
            Update-Binaries -Path $Path -URI $URI -Name $Name -MinerFileVersion $MinerFileVersion -RemoveBenchmarkFiles $Config.AutoReBenchmark
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
        $DeviceSet = Get-DeviceIDs -Config $Config -Devices $Devices -Type $Type -DeviceTypeModel $DeviceTypeModel -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset

        $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$_ -match ".+:[1-9]" -and  $Pools.(Get-Algorithm ($_.Split(":") | Select-Object -Index 0)) -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm ($_.Split(":") | Select-Object -Index 0)).Name} | ForEach-Object {

            $Algorithm = $_.Split(":") | Select-Object -Index 0
            $Algorithm_Norm = Get-Algorithm $Algorithm
            
            $Threads = $_.Split(":") | Select-Object -Index 1

            [Array]$Commands = $Config.Miners.$Name.Commands.$_ # additional command line options for algorithm

            Switch ($Algorithm_Norm) { # default is all devices, ethash has a 4GB minimum memory limit
                "Ethash"    {$DeviceIDs = $DeviceSet."4gb"}
                "Ethash3gb" {$DeviceIDs = $DeviceSet."3gb"}
                default     {$DeviceIDs = $DeviceSet."All"}
            }

            if ($DeviceIDs.Count -gt 0) {

                if ($Config.MinerInstancePerCardModel) {
                    $Miner_Name = "$Name$($Threads)-$($DeviceTypeModel.Name_Norm)"
                }
                else {
                    $Miner_Name = "$($Name)$($Threads)"
                }    

                try {
                    if ($Algorithm_Norm -ne "Decred" -and $Algorithm_Norm -ne "Sia") {
                        [PSCustomObject]@{
                            Name             = $Miner_Name
                            Type             = $Type
                            Path             = $Path
                            HashSHA256       = $HashSHA256
                            Arguments        = @([PSCustomObject]@{id = 1; method = "algorithm.add"; params = @("$Algorithm", "$([Net.DNS]::Resolve($Pools.$Algorithm_Norm.Host).AddressList.IPAddressToString | Select-Object -First 1):$($Pools.$Algorithm_Norm.Port)", "$($Pools.$Algorithm_Norm.User):$($Pools.$Algorithm_Norm.Pass)")}) + @([PSCustomObject]@{id = 1; method = "workers.add"; params = @(@($DeviceIDs | ForEach-Object {@("alg-0", "$_", $(if ($Commands) {($Commands | Select-Object -Index $_) -Join ", "}))} | Select-Object) * $Threads)})
                            HashRates        = [PSCustomObject]@{$Algorithm_Norm = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week}
                            API              = $API
                            Port             = $Port
                            URI              = $URI
                            PrerequisitePath = $PrerequisitePath
                            PrerequisiteURI  = $PrerequisiteURI
                            Fees             = @($null)
                            Index            = $DeviceTypeModel.DeviceIDs -join ';' # Always list all devices
                            ShowMinerWindow  = $Config.ShowMinerWindow 
                        }
                    }
                    else {
                        if ($Pools."$($Algorithm_Norm)NiceHash".Host) {
                            [PSCustomObject]@{
                                Name             = $Miner_Name
                                Type             = $Type
                                Path             = $Path
                                HashSHA256       = $HashSHA256
                                Arguments        = @([PSCustomObject]@{id = 1; method = "algorithm.add"; params = @("$Algorithm", "$([Net.DNS]::Resolve($Pools."$($Algorithm_Norm)NiceHash".Host).AddressList.IPAddressToString | Select-Object -First 1):$($Pools."$($Algorithm_Norm)NiceHash".Port)", "$($Pools."$($Algorithm_Norm)NiceHash".User):$($Pools."$($Algorithm_Norm)NiceHash".Pass)")}) + @([PSCustomObject]@{id = 1; method = "workers.add"; params = @(@($DeviceIDs | ForEach-Object {@("alg-0", "$_", $(if ($Commands) {($Commands | Select-Object -Index $_) -Join ", "}))} | Select-Object) * $Threads)})
                                HashRates        = [PSCustomObject]@{"$($Algorithm_Norm)Nicehash" = $Stats."$($Miner_Name)_$($Algorithm_Norm)NiceHash_HashRate".Week}
                                API              = $API
                                Port             = $Port
                                URI              = $URI
                                PrerequisitePath = $PrerequisitePath
                                PrerequisiteURI  = $PrerequisiteURI
                                Fees             = @($null)
                                Index            = $DeviceTypeModel.DeviceIDs -join ';' # Always list all devices
                                ShowMinerWindow  = $Config.ShowMinerWindow 
                            }
                        }
                    }
                }
                catch {
                }
            }
        }
    }
    $Port++ # next higher port for next device
}
catch {}