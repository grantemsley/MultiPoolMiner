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
$Path = ".\Bin\NVIDIA-Alexis78hsr\ccminer-alexis.exe"
$Type = "NVIDIA"
$API  = "Ccminer"
$Port = 4068

$MinerFileVersion = "2018040300" #Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerBinaryInfo = "CcminerHSR compiled by Nemosminer"

if ($MinerFileVersion -gt $Config.Miners.$Name.MinerFileVersion) {
    # Create default miner config, required for setup
    $DefaultMinerConfig = [PSCustomObject]@{
        "MinerFileVersion" = $MinerFileVersion
        "MinerBinaryInfo" = $MinerBinaryInfo
        "Uri" = "https://github.com/nemosminer/ccminer-hcash/releases/download/alexishsr/ccminer-hsr-alexis-x86-cuda8.7z" # if new MinerFileVersion and new Uri MPM will download and update new binaries
        "UriManual" = ""    
        "WebLink" = "https://github.com/nemosminer/ccminer-hcash" # See here for more information about the miner
        #"IgnoreHWModel" = @("GPU Model Name", "Another GPU Model Name", e.g "GeforceGTX1070") # Available model names are in $Devices.$Type.Name_Norm, Strings here must match GPU model name reformatted with (Get-Culture).TextInfo.ToTitleCase(($_.Name)) -replace "[^A-Z0-9]"
        "IgnoreHWModel" = @()
        #"IgnoreDeviceID" = @(0, 1) # Available deviceIDs are in $Devices.$Type.DeviceIDs
        "IgnoreDeviceID" = @()
        "Commands" = [PSCustomObject]@{
            "hsr" = "" #HSR
        }
        "CommonCommands" = ""
        "DoNotMine" = [PSCustomObject]@{ # Syntax: "Algorithm" = "Poolname", e.g. "equihash" = @("Zpool", "ZpoolCoins")
        }
    }
    if (-not $Config.Miners.$Name.MinerFileVersion) { # new miner, create basic config
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
    else { # Update existing miner config
        try {
            # Read existing config file, do not use $Config because variables are expanded (e.g. $Wallet)
            $NewConfig = Get-Content -Path 'Config.txt' | ConvertFrom-Json -InformationAction SilentlyContinue
            
            # Execute action, e.g force re-download of binary
            # Should be the first action. If it fails no further update will take place, update will be retried on next loop
            if ($DefaultMinerConfig.Uri -and $DefaultMinerConfig.Uri -ne $Config.Miners.$Name.Uri) {
                if (Test-Path $Path) {Remove-Item $Path -Force -Confirm:$false -ErrorAction Stop} # Remove miner binary to force re-download
                # Update log
                Write-Log -Level Info "Requested automatic miner binary update ($Name [$MinerFileVersion]). "
                # Remove benchmark files
                # if (Test-Path ".\Stats\$($Name)_*_hashrate.txt") {Remove-Item ".\Stats\$($Name)_*_hashrate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
                # if (Test-Path ".\Stats\$($Name)-*_*_hashrate.txt") {Remove-Item ".\Stats\$($Name)-*_*_hashrate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
            }

            # Always update MinerFileVersion, MinerBinaryInfo and download link, -Force to enforce setting
            $NewConfig.Miners.$Name | Add-member MinerFileVersion $MinerFileVersion -Force
            $NewConfig.Miners.$Name | Add-member MinerBinaryInfo $MinerBinaryInfo -Force
            $NewConfig.Miners.$Name | Add-member Uri $DefaultMinerConfig.Uri -Force

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
        MinerFileVersion  = $MinerFileVersion
        MinerBinaryInfo   = $MinerBinaryInfo
        Uri               = $Uri
        UriManual         = $UriManual
        Type              = $Type
        Path              = $Path
        Port              = $Port
        WebLink           = $WebLink
        Settings          = @(
            [PSCustomObject]@{
                Name        = "Uri"
                Required    = $false
                ControlType = "string"
                Default     = $DefaultMinerConfig.Uri
                Description = "MPM automatically downloads the miner binaries from this link and unpacks them. Files stored on Google Drive or Mega links cannot be downloaded automatically. "
                Tooltip     = "If Uri is blank or is not a direct download link the miner binaries must be downloaded and unpacked manually (see README)"
            },
            [PSCustomObject]@{
                Name        = "UriManual"
                Required    = $false
                ControlType = "string"
                Default     = $DefaultMinerConfig.UriManual
                Description = "Download link for manual miner binaries download. Unpack downloaded files to '$Path'. "
                Tooltip     = "See README for manual download and unpack instruction"
            },
            [PSCustomObject]@{
                Name        = "WebLink"
                Required    = $false
                ControlType = "string"
                Default     = $DefaultMinerConfig.WebLink
                Description = "See here for more information about the miner. "
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

# Starting port for first miner
$Port = $Config.Miners.$Name.Port

# Get device list
$Devices.$Type | ForEach-Object {

    if ($DeviceTypeModel -and -not $Config.MinerInstancePerCardModel) {return} #after first loop $DeviceTypeModel is present; generate only one miner
    $DeviceTypeModel = $_
    $DeviceIDs = @() # array of all devices, ids will be in hex format

    # Get DeviceIDs, filter out all disabled hw models and IDs
    if ($Config.MinerInstancePerCardModel -and (Get-Command "Get-CommandPerDevice" -ErrorAction SilentlyContinue)) { # separate miner instance per hardware model
        if ($Config.Devices.$Type.IgnoreHWModel -inotcontains $DeviceTypeModel.Name_Norm -and $Config.Miners.$Name.IgnoreHWModel -inotcontains $DeviceTypeModel.Name_Norm) {
            $DeviceTypeModel.DeviceIDs | Where-Object {$Config.Devices.$Type.IgnoreDeviceID -notcontains $_ -and $Config.Miners.$Name.IgnoreDeviceID -notcontains $_} | ForEach-Object {
                $DeviceIDs += [Convert]::ToString($_, 16) # convert id to hex
            }
        }
    }
    else { # one miner instance per hw type
        $DeviceIDs = @($Devices.$Type | Where-Object {$Config.Devices.$Type.IgnoreHWModel -inotcontains $_.Name_Norm -and $Config.Miners.$Name.IgnoreHWModel -inotcontains $_.Name_Norm}).DeviceIDs | Where-Object {$Config.Devices.$Type.IgnoreDeviceID -notcontains $_ -and $Config.Miners.$Name.IgnoreDeviceID -notcontains $_} | ForEach-Object {[Convert]::ToString($_, 16)} # convert id to hex
    }

    $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm $_).Protocol -eq "stratum+tcp"  -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm $_).Name -and $DeviceIDs} | ForEach-Object {

        $Algorithm_Norm = Get-Algorithm $_

        if ($Config.MinerInstancePerCardModel -and (Get-Command "Get-CommandPerDevice" -ErrorAction SilentlyContinue)) {
            $Miner_Name = "$Name-$($DeviceTypeModel.Name_Norm)"
            $Commands = Get-CommandPerDevice -Command $Config.Miners.$Name.Commands.$_ -Devices $DeviceIDs # additional command line options for algorithm
        }
        else {
            $Miner_Name = $Name
            $Commands = $Config.Miners.$Name.Commands.$_.Split(";") | Select -Index 0 # additional command line options for algorithm
        }

        [PSCustomObject]@{
            Name             = $Miner_Name
            Type             = $Type
            Path             = $Path
            Arguments        = ("-a $_ -o $($Pools.$Algorithm_Norm.Protocol)://$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) -u $($Pools.$Algorithm_Norm.User) -p $($Pools.$Algorithm_Norm.Pass)$Commands$($Config.Miners.$Name.CommonCommands) -b 127.0.0.1:$($Port) -d $($DeviceIDs -join ',')" -replace "\s+", " ").trim()
            HashRates        = [PSCustomObject]@{$Algorithm_Norm = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week}
            API              = $Api
            Port             = $Port
            URI              = $Uri
            Fees             = @($null)
            Index            = $DeviceIDs -join ';'
            ShowMinerWindow  = $Config.ShowMinerWindow
        }
    }
    $Port++ # next higher port for next device
}