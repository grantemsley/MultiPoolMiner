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
$Path = ".\Bin\Ethash-Claymore\EthDcrMiner64.exe"
$Type = "NVIDIA"
$API  = "Claymore"
$Port = 23333
$DeviceIdBase = 16 # DeviceIDs are in hex
$DeviceIdOffset = 0 # DeviceIDs start at 0

$MinerFileVersion = "2018050400" # Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerBinaryInfo = "Claymore Dual Ethereum AMD/NVIDIA GPU Miner v11.7"
$HashSHA256 = "11743a7b0f8627ceb088745f950557e303c7350f8e4241814c39904278204580" # If newer MinerFileVersion and hash does not math MPM will trigger an automatick binary update (if Uri is present)
$Uri = ""
$ManualUri = "https://mega.nz/#F!O4YA2JgD!n2b4iSHQDruEsYUvTQP5_w"
$WebLink = "https://bitcointalk.org/index.php?topic=1433925.0" # See here for more information about the miner
$MinerFeeInPercentSingleMode = 1.0 # Fixed
$MinerFeeInPercentDualMode = 1.5 # Fixed

if ($Info -or -not $Config.Miners.$Name.MinerFileVersion) {
    # Create default miner config
    $DefaultMinerConfig = [PSCustomObject]@{
        "MinerFileVersion" = $MinerFileVersion
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
            MinerFeeInPercentSingleMode = $MinerFeeInPercentSingleMode
            MinerFeeInPercentDualMode   = $MinerFeeInPercentDualMode
            Settings         = @(
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
        # Execute action, e.g force re-download of binary
        if ($HashSHA256 -and (Test-Path $Path) -and (Get-FileHash $Path).Hash -ne $HashSHA256) {
            # Should be the first action. If it fails no further update will take place, update will be retried on next loop
            Update-Binaries -Path $Path -Uri $Uri -Name $Name -MinerFileVersion $MinerFileVersion -RemoveBenchmarkFiles $Config.AutoReBenchmark
        }

        # Always update MinerFileVersion -Force to enforce setting
        $Config.Miners.$Name | Add-member MinerFileVersion $MinerFileVersion -Force

#        # Add config item if not in existing config file, -ErrorAction SilentlyContinue to ignore errors if item exists
#        $Config.Miners.$Name.Commands | Add-Member "ethash;pascal:40" "" -ErrorAction SilentlyContinue
#        $Config.Miners.$Name.Commands | Add-Member "ethash;pascal:60" "" -ErrorAction SilentlyContinue
#        $Config.Miners.$Name.Commands | Add-Member "ethash;pascal:80" "" -ErrorAction SilentlyContinue
#        $Config.Miners.$Name.Commands | Add-Member "ethash2gb;pascal:40" "" -ErrorAction SilentlyContinue
#        $Config.Miners.$Name.Commands | Add-Member "ethash2gb;pascal:60" "" -ErrorAction SilentlyContinue
#        $Config.Miners.$Name.Commands | Add-Member "ethash2gb;pascal:80" "" -ErrorAction SilentlyContinue

        # Save config to file
        Write-Config -Config $Config -MinerName $Name -Action "Updated"
    }

    # Generate miner objects
    $Devices.$Type | ForEach-Object {
        
        if ($DeviceTypeModel -and -not $Config.MinerInstancePerCardModel) {return} # after first loop $DeviceTypeModel is present; generate only one miner
        $DeviceTypeModel = $_

        # Get array of IDs of all devices in device set, returned DeviceIDs are of base $DeviceIdBase representation starting from $DeviceIdOffset
        $DeviceSet = Get-DeviceIDsSet -Config $Config -Devices $Devices -Type $Type -DeviceTypeModel $DeviceTypeModel -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset

        $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm ($_.Split(";") | Select-Object -Index 0)) -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm ($_.Split(";") | Select-Object -Index 0)).Name} | ForEach-Object {

            $MainAlgorithm = $_.Split(";") | Select-Object -Index 0
            $MainAlgorithm_Norm = Get-Algorithm $MainAlgorithm
                
            Switch ($Algorithm_Norm) { # default is all devices, ethash has a 4GB minimum memory limit
                "Ethash"    {$DeviceIDs = $DeviceSet."4gb"}
                "Ethash3gb" {$DeviceIDs = $DeviceSet."3gb"}
                default     {$DeviceIDs = $DeviceSet."All"}
            }

            if ($DeviceIDs.Count -gt 0) {

                if ($Config.MinerInstancePerCardModel -and (Get-Command "Get-CommandPerDeviceSet" -ErrorAction SilentlyContinue)) {
                    $Miner_Name = "$Name-$($DeviceTypeModel.Name_Norm)"
                    $MainAlgorithmCommands = Get-CommandPerDeviceSet -Command ($Config.Miners.$Name.Commands.$_.Split(";") | Select-Object -Index 0) -DeviceIDs $DeviceIDs -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset # additional command line options for main algorithm
                    $SecondaryAlgorithmCommands = Get-CommandPerDeviceSet -Command ($Config.Miners.$Name.Commands.$_.Split(";") | Select-Object -Index 1) -DeviceIDs $DeviceIDs -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset # additional command line options for secondary algorithm
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
                        Path             = $Path
                        Arguments        = ("-mode 1 -mport -$Port -epool $($Pools.$MainAlgorithm_Norm.Host):$($Pools.$MainAlgorithm_Norm.Port) -ewal $($Pools.$MainAlgorithm_Norm.User) -epsw $($Pools.$MainAlgorithm_Norm.Pass)$MainAlgorithmCommand$($CommonCommands | Select-Object -Index 0) -esm $EthereumStratumMode -allpools 1 -allcoins 1 -platform 2 -di $($DeviceIDs -join '')" -replace "\s+", " ").trim()
                        HashRates        = [PSCustomObject]@{"$MainAlgorithm_Norm" = $HashRateMainAlgorithm}
                        API              = $Api
                        Port             = $Port
                        URI              = $Uri
                        Fees             = @($Fees)
                        Index            = $DeviceTypeModel.DeviceIDs -join ';' # Always list all devices
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
                            Path             = $Path
                            Arguments        = ("-mode 0 -mport -$Port -epool $($Pools.$MainAlgorithm_Norm.Host):$($Pools.$MainAlgorithm.Port) -ewal $($Pools.$MainAlgorithm_Norm.User) -epsw $($Pools.$MainAlgorithm_Norm.Pass)$MainAlgorithmCommand$($Config.Miners.$Name.CommonCommands | Select-Object -Index 0) -esm $EthereumStratumMode -allpools 1 -allcoins exp -dcoin $SecondaryAlgorithm -dcri $SecondaryAlgorithmIntensity -dpool $($Pools.$SecondaryAlgorithm_Norm.Host):$($Pools.$SecondaryAlgorithm_Norm.Port) -dwal $($Pools.$SecondaryAlgorithm_Norm.User) -dpsw $($Pools.$SecondaryAlgorithm_Norm.Pass)$SecondaryAlgorithmCommand$($Config.Miners.$Name.CommonCommands | Select-Object -Index 0) -platform 2 -di $($DeviceIDs -join '')" -replace "\s+", " ").trim()
                            HashRates        = [PSCustomObject]@{"$MainAlgorithm_Norm" = $HashRateMainAlgorithm; "$SecondaryAlgorithm_Norm" = $HashRateSecondaryAlgorithm}
                            API              = $Api
                            Port             = $Port
                            URI              = $Uri
                            Fees             = @($Fees)
                            Index            = $DeviceTypeModel.DeviceIDs -join ';' # Always list all devices
                            ShowMinerWindow  = $Config.ShowMinerWindow
                        }
                        if ($SecondaryAlgorithm_Norm -eq "Sia" -or $SecondaryAlgorithm_Norm -eq "Decred") {
                            $SecondaryAlgorithm_Norm = "$($SecondaryAlgorithm_Norm)NiceHash"
                            [PSCustomObject]@{
                                Name             = $Miner_Name
                                Type             = $Type
                                Path             = $Path
                                Arguments        = ("-mode 0 -mport -$Port -epool $($Pools.$MainAlgorithm_Norm.Host):$($Pools.$MainAlgorithm.Port) -ewal $($Pools.$MainAlgorithm_Norm.User) -epsw $($Pools.$MainAlgorithm_Norm.Pass)$MainAlgorithmCommand$($Config.Miners.$Name.CommonCommands | Select-Object -Index 0) -esm $EthereumStratumMode -allpools 1 -allcoins exp -dcoin $SecondaryAlgorithm -dcri $SecondaryAlgorithmIntensity -dpool $($Pools.$SecondaryAlgorithm_Norm.Host):$($Pools.$SecondaryAlgorithm_Norm.Port) -dwal $($Pools.$SecondaryAlgorithm_Norm.User) -dpsw $($Pools.$SecondaryAlgorithm_Norm.Pass)$SecondaryAlgorithmCommand$($Config.Miners.$Name.CommonCommandss | Select-Object -Index 1) -platform 2 -di $($DeviceIDs -join '')" -replace "\s+", " ").trim()
                                HashRates        = [PSCustomObject]@{"$MainAlgorithm_Norm" = $HashRateMainAlgorithm; "$SecondaryAlgorithm_Norm" = $HashRateSecondaryAlgorithm}
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
        }
    }
    $Port++ # next higher port for next device
}
catch {}