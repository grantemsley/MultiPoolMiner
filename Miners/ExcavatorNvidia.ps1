using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [PSCustomObject]$Stats,
    [PSCustomObject]$Config,
    [PSCustomObject]$Devices
)

# Compatibility check with old MPM builds
#if (-not $Config.Miners) {return}

# Hardcoded per miner version, do not allow user to change in config
$MinerFileVersion = "2018040200" #Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerBinaryInfo = "NiceHash Excavator 1.4.4 alpha (x64)"
$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\Excavator\excavator.exe"
$Type = "NVIDIA"
$API = "Excavator"
$Uri = "https://github.com/nicehash/excavator/releases/download/v1.4.4a/excavator_v1.4.4a_NVIDIA_Win64.zip" # if new MinerFileVersion and new Uri MPM will download and update new binaries
$UriManual = "" # Link for manual miner download
$WebLink = "https://github.com/nicehash/excavator" # See here for more information about the miner
$PrerequisitePath = "$env:SystemRoot\System32\msvcr120.dll"
$PrerequisiteURI = "http://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe"

# Create default miner config, required for setup
$DefaultMinerConfig = [PSCustomObject]@{
    "MinerFileVersion" = "$MinerFileVersion"
    "MinerBinaryInfo" = "$MinerBinaryInfo"
    "Uri" = "$Uri"
    "UriManual" = "$UriManual"    
    "Type" = "$Type"
    "Path" = "$Path"
    "Port" = 23456
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
        "nist5:1"           = @() #Nist5
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
        "nist5:2"           = @() #Nist5
        "keccak:2"          = @() #Keccak
        "lbry:2"            = @() #Lbry
        "lyra2rev2:2"       = @() #Lyra2RE2
        "pascal:2"          = @() #Pascal
    }
    "CommonCommands" = ""
    "DoNotMine" = [PSCustomObject]@{ # Syntax: "Algorithm" = "Poolname", e.g. "equihash" = @("Zpool", "ZpoolCoins")
    }
}

if (-not $Config.Miners.$Name.MinerFileVersion) {
    # Read existing config file, do not use $Config because variables are expanded (e.g. $Wallet)
    $NewConfig = Get-Content -Path 'Config.txt' -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    # Apply default
    $NewConfig.Miners | Add-Member $Name $DefaultMinerConfig -Force -ErrorAction Stop
    # Save config to file
    $NewConfig | ConvertTo-Json -Depth 10 | Set-Content "Config.txt" -Force -ErrorAction Stop
    # Update log
    Write-Log -Level Info "Added miner config ($Name [$MinerFileVersion]) to Config.txt. "
    # Apply config, must re-read from file to expand variables
    $Config = Get-ChildItemContent "Config.txt" -ErrorAction Stop | Select-Object -ExpandProperty Content
}
else {
    if ($MinerFileVersion -gt $Config.Miners.$Name.MinerFileVersion) {
        try {
            # Read existing config file, do not use $Config because variables are expanded (e.g. $Wallet)
            $NewConfig = Get-Content -Path 'Config.txt' | ConvertFrom-Json -InformationAction SilentlyContinue
            
            # Execute action, e.g force re-download of binary
            # Should be the first action. If it fails no further update will take place, update will be retried on next loop
            if ($Uri -and $Uri -ne $Config.Miners.$Name.Uri) {
                if (Test-Path $Path) {Remove-Item $Path -Force -Confirm:$false -ErrorAction Stop} # Remove miner binary to force re-download
                # Update log
                Write-Log -Level Info "Requested automatic miner binary update ($Name [$MinerFileVersion]). "
                # Remove benchmark files
                # if (Test-Path ".\Stats\$($Name)_*_hashrate.txt") {Remove-Item ".\Stats\$($Name)_*_hashrate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
                # if (Test-Path ".\Stats\$($Name)-*_*_hashrate.txt") {Remove-Item ".\Stats\$($Name)-*_*_hashrate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
            }

            # Always update MinerFileVersion, MinerBinaryInfo and download link, -Force to enforce setting
            $NewConfig.Miners.$Name | Add-member MinerFileVersion "$MinerFileVersion" -Force
            $NewConfig.Miners.$Name | Add-member MinerBinaryInfo "$MinerBinaryInfo" -Force
            $NewConfig.Miners.$Name | Add-member Uri "$Uri" -Force

            # Remove config item if in existing config file, -ErrorAction SilentlyContinue to ignore errors if item does not exist
            $NewConfig.Miners.$Name | Foreach-Object {
                # e.g. $_.Commands.PSObject.Properties.Remove("ethash;pascal:-dcoin pasc -dcri 20")
            } -ErrorAction SilentlyContinue

            # Add config item if not in existing config file, -ErrorAction SilentlyContinue to ignore errors if item exists
            # e.g. $NewConfig.Miners.$Name.Commands | Add-Member "ethash;pascal:60" "" -ErrorAction SilentlyContinue

            # Save config to file
            $NewConfig | ConvertTo-Json -Depth 10 | Set-Content "Config.txt" -Force -ErrorAction Stop
            # Update log
            Write-Log -Level Info "Updated miner config ($Name [$MinerFileVersion]) in Config.txt. "
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
        MinerFileVersion = $MinerFileVersion
        MinerBinaryInfo  = $MinerBinaryInfo
        Uri              = $Uri
        UriDescription   = $UriManual
        Type             = $Type
        Path             = $Path
        Port             = $Port
        WebLink          = $WebLink
        Settings         = @(
            [PSCustomObject]@{
                Name        = "Uri"
                Required    = $false
                ControlType = "string"
                Default     = $DefaultMinerConfig.Uri
                Description = "MPM automatically downloads the miner binaries from this link and unpacks them.`nFiles stored on Google Drive or Mega links cannot be downloaded automatically.`n"
                Tooltip     = "If Uri is blank or is not a direct download link the miner binaries must be downloaded and unpacked manually (see README). "
            },
            [PSCustomObject]@{
                Name        = "UriManual"
                Required    = $false
                ControlType = "string"
                Default     = $DefaultMinerConfig.UriManual
                Description = "Due to the NiceHash special EULA excavator must be downloaded and extracted manually.`nUnpack downloaded files to '$Path'."
                Tooltip     = "See README for manual download and unpack instructions."
            },
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

# Starting port for first miner
$Port = $Config.Miners.$Name.Port

# Get device list
$Devices.$Type | Where-Object {$Config.Devices.$Type.IgnoreHWModel -inotcontains $_.Name_Norm -or $Config.Miners.$Name.IgnoreHWModel -inotcontains $_.Name_Norm} | ForEach-Object {
    
    if ($DeviceTypeModel -and -not $Config.MinerInstancePerCardModel) {return} #after first loop $DeviceTypeModel is present; generate only one miner
    $DeviceTypeModel = $_
    $DeviceIDsAll = @() # array of all devices, ids will be in hex format
    $DeviceIDs3gb = @() # array of all devices with more than 3MiB VRAM, ids will be in hex format
    $DeviceIDs4gb = @() # array of all devices with more than 4MiB VRAM, ids will be in hex format

    # Get DeviceIDs, filter out all disabled hw models and IDs
    if ($Config.MinerInstancePerCardModel -and (Get-Command "Get-CommandPerDevice" -ErrorAction SilentlyContinue)) { # separate miner instance per hardware model
        if ($Config.Devices.$Type.IgnoreHWModel -inotcontains $DeviceTypeModel.Name_Norm -and $Config.Miners.$Name.IgnoreHWModel -inotcontains $DeviceTypeModel.Name_Norm) {
            $DeviceTypeModel.DeviceIDs | Where-Object {$Config.Devices.$Type.IgnoreDeviceID -notcontains $_ -and $Config.Miners.$Name.IgnoreDeviceID -notcontains $_} | ForEach-Object {
                $DeviceIDsAll += [Convert]::ToString($_, 16) # convert id to hex
                if ($DeviceTypeModel.GlobalMemsize -ge 3000000000) {$DeviceIDs3gb += [Convert]::ToString($_, 16)} # convert id to hex
                if ($DeviceTypeModel.GlobalMemsize -ge 4000000000) {$DeviceIDs4gb += [Convert]::ToString($_, 16)} # convert id to hex
            }
        }
    }
    else { # one miner instance per hw type
        $DeviceIDsAll = @($Devices.$Type | Where-Object {$Config.Devices.$Type.IgnoreHWModel -inotcontains $_.Name_Norm -and $Config.Miners.$Name.IgnoreHWModel -inotcontains $_.Name_Norm}).DeviceIDs | Where-Object {$Config.Devices.$Type.IgnoreDeviceID -notcontains $_ -and $Config.Miners.$Name.IgnoreDeviceID -notcontains $_} | ForEach-Object {[Convert]::ToString($_, 16)} # convert id to hex
        $DeviceIDs3gb = @($Devices.$Type | Where-Object {$Config.Devices.$Type.IgnoreHWModel -inotcontains $_.Name_Norm -and $Config.Miners.$Name.IgnoreHWModel -inotcontains $_.Name_Norm} | Where-Object {$_.GlobalMemsize -gt 3000000000}).DeviceIDs | Where-Object {$Config.Devices.$Type.IgnoreDeviceID -notcontains $_ -and $Config.Miners.$Name.IgnoreDeviceID -notcontains $_} | Foreach-Object {[Convert]::ToString($_, 16)} # convert id to hex
        $DeviceIDs4gb = @($Devices.$Type | Where-Object {$Config.Devices.$Type.IgnoreHWModel -inotcontains $_.Name_Norm -and $Config.Miners.$Name.IgnoreHWModel -inotcontains $_.Name_Norm} | Where-Object {$_.GlobalMemsize -gt 4000000000}).DeviceIDs | Where-Object {$Config.Devices.$Type.IgnoreDeviceID -notcontains $_ -and $Config.Miners.$Name.IgnoreDeviceID -notcontains $_} | Foreach-Object {[Convert]::ToString($_, 16)} # convert id to hex
    }

    $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$_ -match ".+:[1-9]" -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm ($_.Split(":") | Select -Index 0)).Name} | ForEach-Object {

        $Algorithm = $_.Split(":") | Select -Index 0
        $Algorithm_Norm = Get-Algorithm $Algorithm
        
        $Threads = $_.Split(":") | Select -Index 1

        [Array]$Commands = $Config.Miners.$Name.Commands.$_ # additional command line options for algorithm

        Switch ($Algorithm_Norm) { # default is all devices, ethash has a 4GB minimum memory limit
            "Ethash"    {$DeviceIDs = $DeviceIDs4gb}
            "Ethash3gb" {$DeviceIDs = $DeviceIDs3gb}
            default     {$DeviceIDs = $DeviceIDsAll}
        }
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
                    Arguments        = @([PSCustomObject]@{id = 1; method = "algorithm.add"; params = @("$Algorithm", "$([Net.DNS]::Resolve($Pools.$Algorithm_Norm.Host).AddressList.IPAddressToString | Select-Object -First 1):$($Pools.$Algorithm_Norm.Port)", "$($Pools.$Algorithm_Norm.User):$($Pools.$Algorithm_Norm.Pass)")}) + @([PSCustomObject]@{id = 1; method = "workers.add"; params = @(@($DeviceIDs | ForEach-Object {@("alg-0", "$_",$(($Commands | Select -Index $_) -Join ", "))} | Select-Object) * $Threads)})
                    HashRates        = [PSCustomObject]@{$Algorithm_Norm = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week}
                    API              = $Api
                    Port             = $Port
                    URI              = $Uri
                    PrerequisitePath = $PrerequisitePath
                    PrerequisiteURI  = $PrerequisiteURI
                    Fees             = @($null)
                    Index            = $DeviceIDs -join ';'
                    ShowMinerWindow  = $Config.ShowMinerWindow 
                }
            }
            else {
                if ($Pools."$($Algorithm_Norm)NiceHash".Host) {
                    [PSCustomObject]@{
                        Name             = $Miner_Name
                        Type             = $Type
                        Path             = $Path
                        Arguments        = @([PSCustomObject]@{id = 1; method = "algorithm.add"; params = @("$Algorithm", "$([Net.DNS]::Resolve($Pools."$($Algorithm_Norm)NiceHash".Host).AddressList.IPAddressToString | Select-Object -First 1):$($Pools."$($Algorithm_Norm)NiceHash".Port)", "$($Pools."$($Algorithm_Norm)NiceHash".User):$($Pools."$($Algorithm_Norm)NiceHash".Pass)")}) + @([PSCustomObject]@{id = 1; method = "workers.add"; params = @(@($DeviceIDs | ForEach-Object {@("alg-0", "$_",$(($Commands | Select -Index $_) -Join ", "))} | Select-Object) * $Threads)})
                        HashRates        = [PSCustomObject]@{"$($Algorithm_Norm)Nicehash" = $Stats."$($Miner_Name)_$($Algorithm_Norm)NiceHash_HashRate".Week}
                        API              = $Api
                        Port             = $Port
                        URI              = $Uri
                        PrerequisitePath = $PrerequisitePath
                        PrerequisiteURI  = $PrerequisiteURI
                        Fees             = @($null)
                        Index            = $DeviceIDs -join ';'
                        ShowMinerWindow  = $Config.ShowMinerWindow 
                    }
                }
            }
        }
        catch {
        }
    }
    $Port++ # next higher port for next device
}