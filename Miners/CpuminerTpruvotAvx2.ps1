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
$Path = ".\Bin\CPU-TPruvot\cpuminer-gw64-avx2.exe"
$Type = "CPU"
$API  = "Ccminer"
$Port = 4048
$MinerFileVersion = "2018050600" # Format: YYYYMMDD[TwoDigitCounter], higher value will trigger config file update
$MinerInfo = "cpuminer-multi v1.3.1 windows by Tpruvot (x64)"
$HashSHA256 = "1F7ACE389009B0CB13D048BEDBBECCCDD3DDD723892FD2E2F6F3032D999224DC"
$Uri = "https://github.com/tpruvot/cpuminer-multi/releases/download/v1.3.1-multi/cpuminer-multi-rel1.3.1-x64.zip" # if new MinerFileVersion and new Uri MPM will download and update new binaries
$ManalUri = ""
$WebLink = "https://github.com/tpruvot/cpuminer-multi" # See here for more information about the miner

if ($Info -or -not $Config.Miners.$Name.MinerFileVersion) {
    $DefaultMinerConfig = [PSCustomObject]@{
        MinerFileVersion = $MinerFileVersion
        CPUThread        = ($Devices.$Type.MaxComputeUnits | Measure-Object -sum).sum * 2
        CommonCommands   = ""
        Commands         = [PSCustomObject]@{
            "blake2s" = "" #Blake2s
            "blakecoin" = "" #Blakecoin
            "vanilla" = "" #BlakeVanilla
            "c11" = "" #C11
            #"cryptonight" = "" #CryptoNight is ASIC territory
            "decred" = "" #Decred
            "groestl" = "" #Groestl
            "keccak" = "" #Keccak
            "lyra2rev2" = "" #Lyra2RE2
            #"myr-gr" = "" #MyriadGroestl is ASIC territory
            "neoscrypt" = "" #NeoScrypt
            #"nist5" = "" #Nist5 is ASIC territory
            "sib" = "" #Sib
            "skein" = "" #Skein
            "timetravel" = "" #Timetravel
            "x11evo" = "" #X11evo
            "x17" = "" #X17
            "xevan" = "" #Xevan
            "yescrypt" = "" #Yescrypt
        }
        DoNotMine        = [PSCustomObject]@{
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
            Settings          = @(
                [PSCustomObject]@{
                    Name        = "CPUThread"
                    Required    = $false
                    ControlType = "int"
                    Min         = 1
                    Max         = ($Devices.$Type.MaxComputeUnits | Measure-Object -sum).sum
                    Default     = ($Devices.$Type.MaxComputeUnits | Measure-Object -sum).sum * 4
                    Description = "Number of parallel CPU threads the miner wil execute. "
                    Tooltip     = "MPM has found $($Devices.$Type.count) with a total of $($Devices.$Type.MaxComputeUnits.sum) compute units"
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

        # Save config to file
        $Config = Set-Config -ConfigFile "Config.txt" -Config $TempConfig -MinerName $Name -Action "Updated"
    }

    # Threads, miner setting will take precedence over global setting
    $Threads = ""
    if ($Config.Devices.$Type.CPUThread -gt 0) {$Threads = " -t $($Config.Devices.$Type.CPUThread)"}
    if ($Config.Miners.$Name.CPUThread -gt 0) {$Threads = " -t $($Config.Miners.$Name.CPUThread)"}

    $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm $_).Protocol -eq "stratum+tcp" -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm $_).Name} | ForEach-Object {

        $Algorithm_Norm = Get-Algorithm $_

        [PSCustomObject]@{
            Name             = $Name
            Type             = $Type
            Path             = $Path
            Arguments        = ("-a $_ -o $($Pools.$Algorithm_Norm.Protocol)://$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) -u $($Pools.$Algorithm_Norm.User) -p $($Pools.$Algorithm_Norm.Pass)$Commands$($Config.Miners.$Name.CommonCommands) -b 127.0.0.1:$($Port)$Threads" -replace "\s+", " ").trim()
            HashRates        = [PSCustomObject]@{$Algorithm_Norm = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week}
            API              = $Api
            Port             = $Port
            URI              = $Uri
            Fees             = @($null)
            Index            = $Devices.$Type.DeviceIDs -join ';'
            ShowMinerWindow  = $Config.ShowMinerWindow
        }
    }
}
catch {}
