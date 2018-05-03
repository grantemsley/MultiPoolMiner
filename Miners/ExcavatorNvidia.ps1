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
$Path = ".\Bin\Excavator\excavator.exe"
$Type = "NVIDIA"
$API  = "Excavator"
$Port = 23456

$MinerFileVersion = "2018050300" #Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerBinaryInfo = "NiceHash Excavator 1.4.4 alpha (x64)"
$MinerBinaryHash = "4cc2ff8c07f17e940a1965b8d0f7dd8508096a4e4928704912fa96c442346642" # If newer MinerFileVersion and hash does not math MPM will trigger an automatick binary update (if Uri is present)
$PrerequisitePath = "$env:SystemRoot\System32\msvcr120.dll"
$PrerequisiteURI = "http://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe"
$Uri = "https://github.com/nicehash/excavator/releases/download/v1.4.4a/excavator_v1.4.4a_NVIDIA_Win64.zip"
$ManualUri = "" # Link for manual miner download
$WebLink = "https://github.com/nicehash/excavator" # See here for more information about the miner

if ($MinerFileVersion -gt $Config.Miners.$Name.MinerFileVersion) {
    # Create default miner config, required for setup
    $DefaultMinerConfig = [PSCustomObject]@{
        "MinerFileVersion" = $MinerFileVersion
        #"IgnoreHWModel" = @("GPU Model Name", "Another GPU Model Name", e.g "GeforceGTX1070") # Available model names are in $Devices.$Type.Name_Norm, Strings here must match GPU model name reformatted with (Get-Culture).TextInfo.ToTitleCase(($_.Name)) -replace "[^A-Z0-9]"
        "IgnoreHWModel" = @()
        #"IgnoreDeviceID" = @(0, 1) # Available deviceIDs are in $Devices.$Type.DeviceIDs
        "IgnoreDeviceID" = @()
        "Commands" = [PSCustomObject]@{
            "blake2s:1"         = @() #Blake2s 
            "cryptonight:1"     = @() #Cryptonight
            "decred:1"          = @() #Decred
            "daggerhashimoto:1" = @() #Ethash
            "equihash:1"        = @() #Equihash
            "neoscrypt:1"       = @() #NeoScrypt
            "keccak:1"          = @() #Keccak
            "lbry:1"            = @() #Lbry
            "lyra2rev2:1"       = @() #Lyra2RE2
            "pascal:1"          = @() #Pascal
            "blake2s:2"         = @() #Blake2s 
            "cryptonight:2"     = @() #Cryptonight
            "decred:2"          = @() #Decred
            "daggerhashimoto:2" = @() #Ethash
            "equihash:2"        = @() #Equihash
            #"neoscrypt:2"       = @() #NeoScrypt; out of memory
            "keccak:2"          = @() #Keccak
            "lbry:2"            = @() #Lbry
            "lyra2rev2:2"       = @() #Lyra2RE2
            "pascal:2"          = @() #Pascal
        }
        "CommonCommands" = ""
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

            # Remove config item if in existing config file, -ErrorAction SilentlyContinue to ignore errors if item does not exist
            $NewConfig.Miners.$Name | Foreach-Object {
                $_.Commands.PSObject.Properties.Remove("nist5:1")
                $_.Commands.PSObject.Properties.Remove("nist5:2")
            } -ErrorAction SilentlyContinue
            # Cleanup stat files
            if (Test-Path ".\Stats\$($Name)1_$(Get-Algorithm 'nist5')_HashRate.txt") {Remove-Item ".\Stats\$($Name)1_$(Get-Algorithm 'nist5')_HashRate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
            if (Test-Path ".\Stats\$($Name)1-*_$(Get-Algorithm 'nist5')_HashRate.txt") {Remove-Item ".\Stats\$($Name)1-*_$(Get-Algorithm 'nist5')_HashRate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
            if (Test-Path ".\Stats\$($Name)2_$(Get-Algorithm 'nist5')_HashRate.txt") {Remove-Item ".\Stats\$($Name)2_$(Get-Algorithm 'nist5')_HashRate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
            if (Test-Path ".\Stats\$($Name)2-*_$(Get-Algorithm 'nist5')_HashRate.txt") {Remove-Item ".\Stats\$($Name)2-*_$(Get-Algorithm 'nist5')_HashRate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
            if (Test-Path ".\Stats\*_$(Get-Algorithm 'nist5')_Profit.txt") {Remove-Item ".\Stats\*_$(Get-Algorithm 'nist5')_Profit.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}

            # Add config item if not in existing config file, -ErrorAction SilentlyContinue to ignore errors if item exists
            # e.g. $NewConfig.Miners.$Name.Commands | Add-Member "ethash;pascal:60" "" -ErrorAction SilentlyContinue

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
                Name        = "IgnoreHWModel"
                Required    = $false
                ControlType = "string[0,$($Devices.$Type.count)]"
                Default     = $DefaultMinerConfig.IgnoreHWModel
                Description = "List of hardware models you do not want to mine with this miner, e.g. 'GeforceGTX1070'.`nLeave empty to mine with all available hardware. "
                Tooltip     = "Detected $Type miner HW:`n$($Devices.$Type | ForEach-Object {"$($_.Name_Norm): DeviceIDs $($_.DeviceIDs -join ' ,')`n"})"
            },
            [PSCustomObject]@{
                Name        = "IgnoreDeviceID"
                Required    = $false
                ControlType = "int[0,$($Devices.$Type.DeviceIDs)]"
                Min         = 0
                Max         = $Devices.$Type.DeviceIDs
                Default     = $DefaultMinerConfig.IgnoreDeviceID
                Description = "List of device IDs you do not want to mine with this miner, e.g. '0'.`nLeave empty to mine with all available hardware. "
                Tooltip     = "Detected $Type miner HW:`n$($Devices.$Type | ForEach-Object {"$($_.Name_Norm): DeviceIDs $($_.DeviceIDs -join ' ,')`n"})"
            },
            [PSCustomObject]@{
                Name        = "Commands"
                Required    = $true
                ControlType = "PSCustomObject"
                Default     = $DefaultMinerConfig.Commands
                Description = "Each line defines an algorithm that can be mined with this miner.`nThe number of threads (default:1) are defined after the ':'.`nOptional miner parameters can be added after the '=' sign. "
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

# Make sure miner binpath exists
if (-not (Test-Path (Split-Path $Path))) {New-Item (Split-Path $Path) -ItemType "directory" -ErrorAction Stop | Out-Null}

# Get device list
$Devices.$Type | Where-Object {$Config.Devices.$Type.IgnoreHWModel -inotcontains $_.Name_Norm -or $Config.Miners.$Name.IgnoreHWModel -inotcontains $_.Name_Norm} | ForEach-Object {

    if ($DeviceTypeModel -and -not $Config.MinerInstancePerCardModel) {return} #after first loop $DeviceTypeModel is present; generate only one miner
    $DeviceTypeModel = $_

    # Get list of active devices, returned deviceIDs are in hex format starting from 0
    $DeviceSet = Get-DeviceSet -Config $Config -Devices $Devices -NumberingFormat 16 -StartNumberingFrom 0    

    $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$_ -match ".+:[1-9]" -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm ($_.Split(":") | Select-Object -Index 0)).Name} | ForEach-Object {

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

            if ($Config.MinerInstancePerCardModel -and (Get-Command "Get-CommandPerDevice" -ErrorAction SilentlyContinue)) {
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
                        Arguments        = @([PSCustomObject]@{id = 1; method = "algorithm.add"; params = @("$Algorithm", "$([Net.DNS]::Resolve($Pools.$Algorithm_Norm.Host).AddressList.IPAddressToString | Select-Object -First 1):$($Pools.$Algorithm_Norm.Port)", "$($Pools.$Algorithm_Norm.User):$($Pools.$Algorithm_Norm.Pass)")}) + @([PSCustomObject]@{id = 1; method = "workers.add"; params = @(@($DeviceIDs | ForEach-Object {@("alg-0", "$_", $(if ($Commands) {($Commands | Select-Object -Index $_) -Join ", "}))} | Select-Object) * $Threads)})
    #                    Arguments        = @([PSCustomObject]@{id = 1; method = "algorithm.add"; params = @("$Algorithm", "$([Net.DNS]::Resolve($Pools.$Algorithm_Norm.Host).AddressList.IPAddressToString | Select-Object -First 1):$($Pools.$Algorithm_Norm.Port)", "$($Pools.$Algorithm_Norm.User):$($Pools.$Algorithm_Norm.Pass)")}) + @([PSCustomObject]@{id = 1; method = "worker.free"; params = @(@($DeviceIDs | ForEach-Object {@("$_")} | Select-Object) * $Threads)}) + @([PSCustomObject]@{id = 1; method = "workers.add"; params = @(@($DeviceIDs | ForEach-Object {@("alg-0", "$_", $(if ($Commands) {($Commands | Select-Object -Index $_) -Join ", "}))} | Select-Object) * $Threads)})
                        HashRates        = [PSCustomObject]@{$Algorithm_Norm = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week}
                        API              = $Api
                        Port             = $Port
                        URI              = $Uri
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
                            Arguments        = @([PSCustomObject]@{id = 1; method = "algorithm.add"; params = @("$Algorithm", "$([Net.DNS]::Resolve($Pools."$($Algorithm_Norm)NiceHash".Host).AddressList.IPAddressToString | Select-Object -First 1):$($Pools."$($Algorithm_Norm)NiceHash".Port)", "$($Pools."$($Algorithm_Norm)NiceHash".User):$($Pools."$($Algorithm_Norm)NiceHash".Pass)")}) + @([PSCustomObject]@{id = 1; method = "workers.add"; params = @(@($DeviceIDs | ForEach-Object {@("alg-0", "$_", $(if ($Commands) {($Commands | Select-Object -Index $_) -Join ", "}))} | Select-Object) * $Threads)})
    #                        Arguments        = @([PSCustomObject]@{id = 1; method = "algorithm.add"; params = @("$Algorithm", "$([Net.DNS]::Resolve($Pools."$($Algorithm_Norm)NiceHash".Host).AddressList.IPAddressToString | Select-Object -First 1):$($Pools."$($Algorithm_Norm)NiceHash".Port)", "$($Pools."$($Algorithm_Norm)NiceHash".User):$($Pools."$($Algorithm_Norm)NiceHash".Pass)")}) + @([PSCustomObject]@{id = 1; method = "worker.free"; params = @(@($DeviceIDs | ForEach-Object {@("$_")} | Select-Object) * $Threads)}) + @([PSCustomObject]@{id = 1; method = "workers.add"; params = @(@($DeviceIDs | ForEach-Object {@("alg-0", "$_", $(if ($Commands) {($Commands | Select-Object -Index $_) -Join ", "}))} | Select-Object) * $Threads)})
                            HashRates        = [PSCustomObject]@{"$($Algorithm_Norm)Nicehash" = $Stats."$($Miner_Name)_$($Algorithm_Norm)NiceHash_HashRate".Week}
                            API              = $Api
                            Port             = $Port
                            URI              = $Uri
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
    $Port++ # next higher port for next device
}