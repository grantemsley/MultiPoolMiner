using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [PSCustomObject]$Stats,
    [PSCustomObject]$Config,
    [PSCustomObject]$Devices
)

# Compatibility check with old MPM builds
#if (-not $Config.Miners) {return}

$Name = "$(Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName)"
$Path = ".\Bin\Ethash-Claymore\EthDcrMiner64.exe"
$Type = "NVIDIA"
$API  = "Claymore"
$Port = 23333

$MinerFileVersion = "2018040200" #Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerBinaryInfo = "Claymore Dual Ethereum AMD/NVIDIA GPU Miner v11.6"
$MinerFeeInPercentSingleMode = 1.0
$MinerFeeInPercentDualMode = 1.5

if ($MinerFileVersion -gt $Config.Miners.$Name.MinerFileVersion) {
    # Create default miner config, required for setup
    $DefaultMinerConfig = [PSCustomObject]@{
        "MinerFileVersion" = $MinerFileVersion
        "MinerBinaryInfo" = $MinerBinaryInfo
        "Uri" = "" # if new MinerFileVersion and new Uri MPM will download and update new binaries
        "UriManual" = "https://mega.nz/#F!O4YA2JgD!n2b4iSHQDruEsYUvTQP5_w"
        "WebLink" = "https://bitcointalk.org/index.php?topic=1433925.0" # See here for more information about the miner
        #"IgnoreHWModel" = @("GPU Model Name", "Another GPU Model Name", e.g "GeforceGTX1070") # Available model names are in $Devices.$Type.Name_Norm, Strings here must match GPU model name reformatted with (Get-Culture).TextInfo.ToTitleCase(($_.Name)) -replace "[^A-Z0-9]"
        "IgnoreHWModel" = @()
        #"IgnoreDeviceID" = @(0, 1) # Available deviceIDs are in $Devices.$Type.DeviceIDs
        "IgnoreDeviceID" = @()
        "Commands" = [PSCustomObject]@{
            "ethash" = ""
            "ethash2gb" = ""
            "ethash;blake2s:40" = ""
            "ethash;blake2s:60" = ""
            "ethash;blake2s:80" = ""
            "ethash;decred:" = ""
            "ethash;decred:130" = ""
            "ethash;decred:160" = ""
            "ethash;keccak:70" = ""
            "ethash;keccak:90" = ""
            "ethash;keccak:110" = ""
            "ethash;lbry:60" = ""
            "ethash;lbry:75" = ""
            "ethash;lbry:90" = ""
            "ethash;pascal:40" = ""
            "ethash;pascal:60" = ""
            "ethash;pascal:80" = ""
            "ethash;pascal:100" = ""
            "ethash2gb;blake2s:75" = ""
            "ethash2gb;blake2s:100" = ""
            "ethash2gb;blake2s:125" =  ""
            "ethash2gb;decred:100" = ""
            "ethash2gb;decred:130" = ""
            "ethash2gb;decred:160" = ""
            "ethash2gb;keccak:70" = ""
            "ethash2gb;keccak:90" = ""
            "ethash2gb;keccak:110" = ""
            "ethash2gb;lbry:60" = ""
            "ethash2gb;lbry:75" = ""
            "ethash2gb;lbry:90" = ""
            "ethash2gb;pascal:40" = ""
            "ethash2gb;pascal:60" = ""
            "ethash2gb;pascal:80" = ""
        }
        "CommonCommands" = @(" -eres 0 -logsmaxsize 1", "") # array, first value for main algo, sesond value for secondary algo
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

#            # Remove obsolete benchmark files, -ErrorAction SilentlyContinue to ignore errors if item does not exist
#            if ($NewConfig.Miners.$Name -contains "ethash;sia:*") {
#                if (Test-Path ".\Stats\$($Name)Sia*_*_hashrate.txt") {Remove-Item ".\Stats\$($Name)Sia_*_hashrate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
#                if (Test-Path ".\Stats\$($Name)-*Sia*_*_hashrate.txt") {Remove-Item ".\Stats\$($Name)-*Sia_*_hashrate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
#                if (Test-Path ".\Stats\$($Name)2gbSia*_*_hashrate.txt") {Remove-Item ".\Stats\$($Name)2gbSia*_*_hashrate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
#                if (Test-Path ".\Stats\$($Name)-*2gbSia*_*_hashrate.txt") {Remove-Item ".\Stats\$($Name)-*2gbSia*_*_hashrate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
#            }
#            # Remove config item if in existing config file, -ErrorAction SilentlyContinue to ignore errors if item does not exist
#            $NewConfig.Miners.$Name | Foreach-Object {
#                $_.Commands.PSObject.Properties.Remove("ethash;pascal:*")
#            } -ErrorAction SilentlyContinue

            # Add config item if not in existing config file, -ErrorAction SilentlyContinue to ignore errors if item exists
            $NewConfig.Miners.$Name.Commands | Add-Member "ethash;pascal:60" "" -ErrorAction SilentlyContinue
            $NewConfig.Miners.$Name.Commands | Add-Member "ethash;pascal:80" "" -ErrorAction SilentlyContinue
            $NewConfig.Miners.$Name.Commands | Add-Member "ethash2gb;pascal:40" "" -ErrorAction SilentlyContinue
            $NewConfig.Miners.$Name.Commands | Add-Member "ethash2gb;pascal:60" "" -ErrorAction SilentlyContinue
            $NewConfig.Miners.$Name.Commands | Add-Member "ethash2gb;pascal:80" "" -ErrorAction SilentlyContinue

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
        MinerFeeInPercentSingleMode = $MinerFeeInPercentSingleMode
        MinerFeeInPercentDualMode   = $MinerFeeInPercentDualMode
        Settings         = @(
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
                Name        = "IgnoreMinerFee"
                ControlType = "switch"
                Default     = $false
                Description = "Miner contains dev fee: Single mode $($MinerFeeInPercentSingleMode)%, dual mode $($MinerFeeInPercentDualMode)%. Tick to ignore miner fees in internal calculations. "
                Tooltip     = "Miner does not allow to disable miner dev fee"
            },
            [PSCustomObject]@{
                Name        = "IgnoreHWModel"
                Required    = $false
                ControlType = "string[0,$($Devices.$Type.count)]"
                Default     = $DefaultMinerConfig.IgnoreHWModel
                Description = "List of hardware models you do not want to mine with this miner, e.g. 'GeforceGTX1070'. Leave empty to mine with all available hardware. "
                Tooltip     = "Detected $Type miner HW:`n$($Devices.$Type | ForEach-Object {"$($_.Name_Norm): DeviceIDs $($_.DeviceIDs -join ' ,')`n"})"
            }
            [PSCustomObject]@{
                Name        = "IgnoreDeviceID"
                Required    = $false
                ControlType = "int[0,$($Devices.$Type.DeviceIDs)]"
                Min         = 0
                Max         = $Devices.$Type.DeviceIDs
                Default     = $DefaultMinerConfig.IgnoreDeviceID
                Description = "List of device IDs you do not want to mine with this miner, e.g. '0'. Leave empty to mine with all available hardware. "
                Tooltip     = "Detected $Type miner HW:`n$($Devices.$Type | ForEach-Object {"$($_.Name_Norm): DeviceIDs $($_.DeviceIDs -join ' ,')`nDo disable an algorithm prefix it with '#'"})"
            },
            [PSCustomObject]@{
                Name        = "Commands"
                ControlType = "PSCustomObject[1,]"
                Default     = $DefaultMinerConfig.Commands
                Description = "Each line defines an algorithm that can be mined with this miner. For dual mining the two algorithms are separated with ';', intensity parameter for the secondary algorithm is defined after the ':'. Optional miner parameters can be added after the '=' sign. "
                Tooltip     = "Note: Most extra parameters must be prefixed with a space`nTo disable an algorithm prefix it with '#'"
            }
            [PSCustomObject]@{
                Name        = "CommonCommands"
                ControlType = "string[2]" # array, first value for main algo, second value for secondary algo
                Default     = $DefaultMinerConfig.CommonCommands
                Description = "Optional miner parameter that gets appended to the resulting miner command line for all algorithms. The first value applies to the main algorithm, the second value applies to the secondary algorithm. "
                Tooltip     = "Note: Most extra parameters must be prefixed with a space (a notable exception is the payout currency, e.g. ',c=LTC')"
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
$Devices.$Type | Where-Object {$Config.Devices.$Type.IgnoreHWModel -inotcontains $_.Name_Norm -or $Config.Miners.$Name.IgnoreHWModel -inotcontains $_.Name_Norm} | ForEach-Object {
    
    if ($DeviceTypeModel -and -not $Config.MinerInstancePerCardModel) {return} #after first loop $DeviceTypeModel is present; generate only one miner
    $DeviceTypeModel = $_

    # Get list of active devices, returned deviceIDs are in hex format starting from 0
    $DeviceSet = Get-DeviceSet -Config $Config -Devices $Devices -NumberingFormat 16 -StartNumberingFrom 0    

    $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm ($_.Split(";") | Select-Object -Index 0)).Name} |ForEach-Object {

        $MainAlgorithm = $_.Split(";") | Select-Object -Index 0
        $MainAlgorithm_Norm = Get-Algorithm $MainAlgorithm
            
        Switch ($Algorithm_Norm) { # default is all devices, ethash has a 4GB minimum memory limit
            "Ethash"    {$DeviceIDs = $DeviceSet."4gb"}
            "Ethash3gb" {$DeviceIDs = $DeviceSet."3gb"}
            default     {$DeviceIDs = $DeviceSet."All"}
        }

        if ($DeviceIDs.Count -gt 0) {

            if ($Pools.$MainAlgorithm_Norm -and $DeviceIDs) { # must have a valid pool to mine and available devices

                if ($Config.MinerInstancePerCardModel -and (Get-Command "Get-CommandPerDevice" -ErrorAction SilentlyContinue)) {
                    $Miner_Name = "$Name-$($DeviceTypeModel.Name_Norm)"
                    $MainAlgorithmCommands = Get-CommandPerDevice -Command ($Config.Miners.$Name.Commands.$_.Split(";") | Select-Object -Index 0) -Devices $DeviceIDs # additional command line options for main algorithm
                    $SecondaryAlgorithmCommands = Get-CommandPerDevice -Command ($Config.Miners.$Name.Commands.$_.Split(";") | Select-Object -Index 1) -Devices $DeviceIDs # additional command line options for secondary algorithm
                }
                else {
                    $Miner_Name = $Name
                    $MainAlgorithmCommands = $Config.Miners.$Name.Commands.$_.Split(";") | Select-Object -Index 0 # additional command line options for main algorithm
                    $SecondaryAlgorithmCommands = $Config.Miners.$Name.Commands.$_.Split(";") | Select-Object -Index 1 # additional command line options for secondary algorithm
                }    

                if ($Pools.$MainAlgorithm_Norm.Name -eq 'NiceHash') {$EthereumStratumMode = "3"} else {$EthereumStratumMode = "2"} #Optimize stratum compatibility
                
                if ($_ -notmatch ";") { # single algo mining
                    $Miner_Name = "$($Miner_Name)$($MainAlgorithm_Norm -replace '^ethash', '')"
                    $HashRateMainAlgorithm = ($Stats."$($Miner_Name)_$($MainAlgorithm_Norm)_HashRate".Week)

                    if ($Config.IgnoreMinerFee -or $Config.Miners.$Name.IgnoreMinerFee) {
                        $Fees = @($null)
                    }
                    else {
                        $HashRateMainAlgorithm = $HashRateMainAlgorithm * (1 - $MinerFeeInPercentSingleMode / 100)
                        $Fees = @($MinerFeeInPercentSingleMode)
                    }

                    # Single mining mode
                    [PSCustomObject]@{
                        Name             = $Miner_Name
                        Type             = $Type
                        Path             = $Config.Miners.$Name.Path
                        Arguments        = ("-mode 1 -mport -$Port -epool $($Pools.$MainAlgorithm_Norm.Host):$($Pools.$MainAlgorithm_Norm.Port) -ewal $($Pools.$MainAlgorithm_Norm.User) -epsw $($Pools.$MainAlgorithm_Norm.Pass)$MainAlgorithmCommand$($CommonCommands | Select-Object -Index 0) -esm $EthereumStratumMode -allpools 1 -allcoins 1 -platform 2 -di $($DeviceIDs -join '')" -replace "\s+", " ").trim()
                        HashRates        = [PSCustomObject]@{"$MainAlgorithm_Norm" = $HashRateMainAlgorithm}
                        API              = $Api
                        Port             = $Port
                        URI              = $Uri
                        Fees             = $Fees
                        Index            = $DeviceIDs -join ';'
                        ShowMinerWindow  = $Config.ShowMinerWindow
                    }
                }
                elseif ($_ -match "^.+;.+:\d+$") { # valid dual mining parameter set

                    $SecondaryAlgorithm = ($_.Split(";") | Select-Object -Index 1).Split(":") | Select-Object -Index 0
                    $SecondaryAlgorithm_Norm = Get-Algorithm $SecondaryAlgorithm
                    $SecondaryAlgorithmIntensity = ($_.Split(";") | Select-Object -Index 1).Split(":") | Select-Object -Index 1
                
                    $Miner_Name = "$($Miner_Name)$($MainAlgorithm_Norm -replace '^ethash', '')$($SecondaryAlgorithm_Norm)$($SecondaryAlgorithmIntensity)"
                    $HashRateMainAlgorithm = ($Stats."$($Miner_Name)_$($MainAlgorithm_Norm)_HashRate".Week)
                    $HashRateSecondaryAlgorithm = ($Stats."$($Miner_Name)_$($SecondaryAlgorithm_Norm)_HashRate".Week)

                    #Second coin (Decred/Siacoin/Lbry/Pascal/Blake2s/Keccak) is mined without developer fee
                    if ($Config.IgnoreMinerFee -or $Config.Miners.$Name.IgnoreMinerFee) {
                        $Fees = @($null)
                    }
                    else {
                        $HashRateMainAlgorithm = $HashRateMainAlgorithm * (1 - $MinerFeeInPercentDualMode / 100)
                        $Fees = @($MinerFeeInPercentDualMode, 0)
                    }

                    if ($Pools.$SecondaryAlgorithm_Norm -and $SecondaryAlgorithmIntensity -gt 0) { # must have a valid pool to mine and positive intensity
                        # Dual mining mode
                        [PSCustomObject]@{
                            Name             = $Miner_Name
                            Type             = $Type
                            Path             = $Config.Miners.$Name.Path
                            Arguments        = ("-mode 0 -mport -$Port -epool $($Pools.$MainAlgorithm_Norm.Host):$($Pools.$MainAlgorithm.Port) -ewal $($Pools.$MainAlgorithm_Norm.User) -epsw $($Pools.$MainAlgorithm_Norm.Pass)$MainAlgorithmCommand$($Config.Miners.$Name.CommonCommands | Select-Object -Index 0) -esm $EthereumStratumMode -allpools 1 -allcoins exp -dcoin $SecondaryAlgorithm -dcri $SecondaryAlgorithmIntensity -dpool $($Pools.$SecondaryAlgorithm_Norm.Host):$($Pools.$SecondaryAlgorithm_Norm.Port) -dwal $($Pools.$SecondaryAlgorithm_Norm.User) -dpsw $($Pools.$SecondaryAlgorithm_Norm.Pass)$SecondaryAlgorithmCommand$($Config.Miners.$Name.CommonCommands | Select-Object -Index 0) -platform 2 -di $($DeviceIDs -join '')" -replace "\s+", " ").trim()
                            HashRates        = [PSCustomObject]@{"$MainAlgorithm_Norm" = $HashRateMainAlgorithm; "$SecondaryAlgorithm_Norm" = $HashRateSecondaryAlgorithm}
                            API              = $Api
                            Port             = $Port
                            URI              = $Uri
                            Fees             = $Fees
                            Index            = $DeviceIDs -join ';'
                            ShowMinerWindow  = $Config.ShowMinerWindow
                        }
                        if ($SecondaryAlgorithm_Norm -eq "Sia" -or $SecondaryAlgorithm_Norm -eq "Decred") {
                            $SecondaryAlgorithm_Norm = "$($SecondaryAlgorithm_Norm)NiceHash"
                            [PSCustomObject]@{
                                Name             = $Miner_Name
                                Type             = $Type
                                Path             = $Config.Miners.$Name.Path
                                Arguments        = ("-mode 0 -mport -$Port -epool $($Pools.$MainAlgorithm_Norm.Host):$($Pools.$MainAlgorithm.Port) -ewal $($Pools.$MainAlgorithm_Norm.User) -epsw $($Pools.$MainAlgorithm_Norm.Pass)$MainAlgorithmCommand$($Config.Miners.$Name.CommonCommands | Select-Object -Index 0) -esm $EthereumStratumMode -allpools 1 -allcoins exp -dcoin $SecondaryAlgorithm -dcri $SecondaryAlgorithmIntensity -dpool $($Pools.$SecondaryAlgorithm_Norm.Host):$($Pools.$SecondaryAlgorithm_Norm.Port) -dwal $($Pools.$SecondaryAlgorithm_Norm.User) -dpsw $($Pools.$SecondaryAlgorithm_Norm.Pass)$SecondaryAlgorithmCommand$($Config.Miners.$Name.CommonCommandss | Select-Object -Index 1) -platform 2 -di $($DeviceIDs -join '')" -replace "\s+", " ").trim()
                                HashRates        = [PSCustomObject]@{"$MainAlgorithm_Norm" = $HashRateMainAlgorithm; "$SecondaryAlgorithm_Norm" = $HashRateSecondaryAlgorithm}
                                API              = $Api
                                Port             = $Port
                                URI              = $Uri
                                Fees             = $Fees
                                Index            = $DeviceIDs -join ';'
                                ShowMinerWindow  = $Config.ShowMinerWindow
                            }
                        }
                    }
                }
            }
        }
    }
    $Port++ # next higher port for next device
}