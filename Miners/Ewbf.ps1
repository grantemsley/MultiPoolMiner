using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [PSCustomObject]$Stats,
    [PSCustomObject]$Config,
    [PSCustomObject]$Devices
)

# Compatibility check with old MPM builds
if (-not $Config.Miners) {return}

# Hardcoded per miner version, do not allow user to change in config
$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\Equihash-EWBF\miner.exe"
$Type = "NVIDIA"
$API  = "DSTM"
$Port = 42000

$MinerFileVersion = "2018040200" #Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerBinaryInfo = "EWBF's CUDA Zcash miner Version 0.3.4b (x64)"
$PrerequisitePath = "$env:SystemRoot\System32\msvcr120.dll"
$PrerequisiteURI  = "http://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe"                
$MinerFeeInPercent = 2.0

if ($MinerFileVersion -gt $Config.Miners.$Name.MinerFileVersion) {
    # Create default miner config, required for setup
    $DefaultMinerConfig = [PSCustomObject]@{
        "MinerFileVersion" = $MinerFileVersion
        "MinerBinaryInfo" = $MinerBinaryInfo
        "Uri" = "" # if new MinerFileVersion and new Uri MPM will download and update new binaries
        "UriManual" = "https://mega.nz/#F!usQh2bTa!3qp_PaiO-dw3F0mpvLXynA"
        "WebLink" = "https://bitcointalk.org/index.php?topic=1707546.0" # See here for more information about the miner
        #"IgnoreHWModel" = @("GPU Model Name", "Another GPU Model Name", e.g "GeforceGTX1070") # Available model names are in $Devices.$Type.Name_Norm, Strings here must match GPU model name reformatted with (Get-Culture).TextInfo.ToTitleCase(($_.Name)) -replace "[^A-Z0-9]"
        "IgnoreHWModel" = @()
        #"IgnoreDeviceID" = @(0, 1) # Available deviceIDs are in $Devices.$Type.DeviceIDs
        "IgnoreDeviceID" = @()
        "Commands" = [PSCustomObject]@{
            "equihash" = @() #Equihash
        }
        "CommonCommands" = " --eexit --intensity 64"
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
        MinerFeeInPercent = $MinerFeeInPercent
        Settings          = @(
            [PSCustomObject]@{
                Name        = "Uri"
                Required    = $false
                ControlType = "string"
                Default     = $DefaultMinerConfig.Uri
                Description = "MPM automatically downloads the miner binaries from this link and unpacks them. Files stored on Google Drive or Mega links cannot be downloaded automatically. "
                Tooltip     = "If Uri is blank or is not a direct download link the miner binaries must be downloaded and unpacked manually (see README). "
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

# Get device list
$Devices.$Type | ForEach-Object {

    if ($DeviceTypeModel -and -not $Config.MinerInstancePerCardModel) {return} #after first loop $DeviceTypeModel is present; generate only one miner
    $DeviceTypeModel = $_

    # Get list of active devices, returned deviceIDs are in hex format starting from 0
    $DeviceIDs = (Get-DeviceSet -Config $Config -Devices $Devices -NumberingFormat 16 -StartNumberingFrom 0)."All"

    if ($DeviceIDs.Count -gt 0) {

        $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm $_) -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm $_).Name} | ForEach-Object {

            $Algorithm_Norm = Get-Algorithm $_

            if ($Config.MinerInstancePerCardModel -and (Get-Command "Get-CommandPerDevice" -ErrorAction SilentlyContinue)) {
                $Miner_Name = "$Name-$($DeviceTypeModel.Name_Norm)"
                $Commands = Get-CommandPerDevice -Command $Config.Miners.$Name.Commands.$_ -Devices $DeviceIDs # additional command line options for algorithm
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
                Arguments        = ("--server $($Pools.$Algorithm_Norm.Host) --port $($Pools.$Algorithm_Norm.Port) --user $($Pools.$Algorithm_Norm.User) --pass $($Pools.$Algorithm_Norm.Pass)$Commands$($Config.Miners.$Name.CommonCommands) --api 0.0.0.0:$($Port) --cuda_devices $($DeviceIDs -join ' ')$($DisableMinerFee)" -replace "\s+", " ").trim()
                HashRates        = [PSCustomObject]@{$Algorithm_Norm = $HashRate}
                API              = $Api
                Port             = $Port
                URI              = $Uri
                Fees             = $Fees
                Index            = $DeviceIDs -join ';'
                PrerequisitePath = $PrerequisitePath
                PrerequisiteURI  = $PrerequisiteURI               
                ShowMinerWindow  = $Config.ShowMinerWindow
            }
        }
    }
    $Port++ # next higher port for next device
}