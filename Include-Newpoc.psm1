Set-Location (Split-Path $MyInvocation.MyCommand.Path)

function Get-Devices {
    [CmdletBinding()]

    # returns a list of all OpenGL devices found.

    $Devices = [PSCustomObject]@{}

    [OpenCl.Platform]::GetPlatformIDs() | ForEach-Object { # Hardware platform

        if ($_.Type -eq "Cpu") {
            $Type = "CPU"
        }
        else {
            Switch ($_.Vendor) {
                "Advanced Micro Devices, Inc." {$Type = "AMD"}
                "Intel(R) Corporation"         {$Type = "INTEL"}
                "NVIDIA Corporation"           {$Type = "NVIDIA"}
            }
        }
        $Devices | Add-Member $Type @()
        $DeviceID = 0 # For each platform start counting DeviceIDs from 0

        [OpenCl.Device]::GetDeviceIDs($_, [OpenCl.DeviceType]::All) | ForEach-Object {

            $Name_Norm = (Get-Culture).TextInfo.ToTitleCase(($_.Name)) -replace "[^A-Z0-9]"

            if ($Devices.$Type.Name_Norm -inotcontains $Name_Norm) { # New card model
                $Device = @([PSCustomObject]$_)
                $Device | Add-Member Name_Norm $Name_Norm
                $Device | Add-Member DeviceIDs @()
                $Devices.$Type += $Device
            }
            $Devices.$Type | Where-Object {$_.Name_Norm -eq $Name_Norm} | ForEach-Object {$_.DeviceIDs += $DeviceID++} # Add DeviceID
        }
    ################################# Begin fake hardware ########################################
    #    [OpenCl.Device]::GetDeviceIDs($_, [OpenCl.DeviceType]::All) | ForEach-Object {
    #
    #        $Name_Norm = (Get-Culture).TextInfo.ToTitleCase(($_.Name)) -replace "[^A-Z0-9]"
    #
    #        if ($Devices.$Type.Name_Norm -inotcontains $Name_Norm) { # New card model
    #            $Device = @([PSCustomObject]$_)
    #            $Device | Add-Member Name_Norm $Name_Norm
    #            $Device | Add-Member DeviceIDs @()
    #            $Devices.$Type += $Device
    #        }
    #        $Devices.$Type | Where-Object {$_.Name_Norm -eq $Name_Norm} | ForEach-Object {$_.DeviceIDs += $DeviceID++}
    #    }
    ################################# End fake hardware #############################################

    }
    $Devices
}

function Get-DeviceIDs {
    # Filters the DeviceIDs and returns only DeviceIDs for active miners
    # $DeviceIdBase: Returened  DeviceID numbers are of base $DeviceIdBase, e.g. HEX (16)
    # $DeviceIdOffset: Change default numbering start from 0 -> $DeviceIdOffset

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Devices,
        [Parameter(Mandatory = $true)]
        [String]$Type,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DeviceTypeModel,
        [Parameter(Mandatory = $true)]
        [Int]$DeviceIdBase,
        [Parameter(Mandatory = $true)]
        [Int]$DeviceIdOffset
    )

    $DeviceIDs  = [PSCustomObject]@{}
    $DeviceIDs | Add-Member "All" @() # array of all devices, ids will be in hex format
    $DeviceIDs | Add-Member "3gb" @() # array of all devices with more than 3MiB VRAM, ids will be in hex format
    $DeviceIDs | Add-Member "4gb" @() # array of all devices with more than 4MiB VRAM, ids will be in hex format

    # Get DeviceIDs, filter out all disabled hw models and IDs
    if ($Config.MinerInstancePerCardModel) { # separate miner instance per hardware model
        if ($Config.Devices.$Type.IgnoreHWModel -inotcontains $DeviceTypeModel.Name_Norm -and $Config.Miners.$Name.IgnoreHWModel -inotcontains $DeviceTypeModel.Name_Norm) {
            $DeviceTypeModel.DeviceIDs | Where-Object {$Config.Devices.$Type.IgnoreDeviceID -notcontains $_ -and $Config.Miners.$Name.IgnoreDeviceID -notcontains $_} | ForEach-Object {
                $DeviceIDs."All" += [Convert]::ToString(($_ + $DeviceIdOffset), $DeviceIdBase)
                if ($DeviceTypeModel.GlobalMemsize -ge 3000000000) {$DeviceIDs."3gb" += [Convert]::ToString(($_ + $DeviceIdOffset), $DeviceIdBase)}
                if ($DeviceTypeModel.GlobalMemsize -ge 4000000000) {$DeviceIDs."4gb" += [Convert]::ToString(($_ + $DeviceIdOffset), $DeviceIdBase)}
            }
        }
    }
    else { # one miner instance per hw type
        $DeviceIDs."All" = @($Devices.$Type | Where-Object {$Config.Devices.$Type.IgnoreHWModel -inotcontains $_.Name_Norm -and $Config.Miners.$Name.IgnoreHWModel -inotcontains $_.Name_Norm}).DeviceIDs | Where-Object {$Config.Devices.$Type.IgnoreDeviceID -notcontains $_ -and $Config.Miners.$Name.IgnoreDeviceID -notcontains $_} | ForEach-Object {[Convert]::ToString(($_ + $DeviceIdOffset), $DeviceIdBase)}
        $DeviceIDs."3gb" = @($Devices.$Type | Where-Object {$Config.Devices.$Type.IgnoreHWModel -inotcontains $_.Name_Norm -and $Config.Miners.$Name.IgnoreHWModel -inotcontains $_.Name_Norm} | Where-Object {$_.GlobalMemsize -gt 3000000000}).DeviceIDs | Where-Object {$Config.Devices.$Type.IgnoreDeviceID -notcontains $_ -and $Config.Miners.$Name.IgnoreDeviceID -notcontains $_} | Foreach-Object {[Convert]::ToString(($_ + $DeviceIdOffset), $DeviceIdBase)}
        $DeviceIDs."4gb" = @($Devices.$Type | Where-Object {$Config.Devices.$Type.IgnoreHWModel -inotcontains $_.Name_Norm -and $Config.Miners.$Name.IgnoreHWModel -inotcontains $_.Name_Norm} | Where-Object {$_.GlobalMemsize -gt 4000000000}).DeviceIDs | Where-Object {$Config.Devices.$Type.IgnoreDeviceID -notcontains $_ -and $Config.Miners.$Name.IgnoreDeviceID -notcontains $_} | Foreach-Object {[Convert]::ToString(($_ + $DeviceIdOffset), $DeviceIdBase)}
    }
    $DeviceIDs
}

function ConvertTo-CommandPerDeviceSet {

    # converts the command parameters
    # if a parameter has multiple values, only the values for the valid devices are returned
    # parameters without values are valid for all devices and are left untouched

    # supported parameter syntax:
    #$Command = ",c=BTC -9 1  -y  2 -a 00,11,22,33,44,55  -b=00,11,22,33,44,55 --c==00,11,22,33,44,55 --d --e=00,11,22,33,44,55 -f -g 00 11 22 33 44 55 ,c=LTC  -h 00 11 22 33 44 55 -i=,11,,33,,55 --j=00,11,,,44,55 --k==00,,,33,44,55 -l -zzz=0123,1234,2345,3456,4567,5678,6789 -u 0  --p all ,something=withcomma blah *blah *blah"
    #$DeviceIDs = @(0;1;4)
    # Result: ",c=BTC -9 1  -y  2 -a 00,11,44  -b=00,11,44 --c==00,11,44 --d --e=00,11,44 -f -g 00 11 44 ,c=LTC  -h 00 11 44 -i=,11 --j=00,11,44 --k==00,,44 -l -zzz=0123,1234,4567 -u 0  --p all ,something=withcomma blah *blah *blah"
    #$DeviceIDs = @(1)
    # Result: ",c=BTC -9 1  -y  2 -a 11  -b=11 --c==11 --d --e=11 -f -g 11 ,c=LTC  -h 11 -i=11 --j=11 --k== -l -zzz=1234 -u 0  --p all ,something=withcomma blah *blah *blah"
    #$DeviceIDs = @(0;2;9)
    # Result: ",c=BTC -9 1  -y  2 -a 00,22  -b=00,22 --c==00,22 --d --e=00,22 -f -g 00 22 ,c=LTC  -h 00 22 -i= --j=00 --k==00 -l -zzz=0123,2345 -u 0  --p all ,something=withcomma blah *blah *blah"
    # $Command = ",c=BTC -a 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16"
    # $DeviceIDs = @("0";"A";"B"); $DeviceIdBase = 16
    # Result: ",c=BTC -a 0,10,11"
    # $DeviceIDs = @("1";"A";"B"); $DeviceIdBase = 16; $DeviceIdOffset = 1
    # Result: ",c=BTC -a 0,9,10"

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [String]$Command,
        [Parameter(Mandatory = $true)]
        [Array]$DeviceIDs,
        [Parameter(Mandatory = $true)]
        [Int]$DeviceIdBase,
        [Parameter(Mandatory = $false)]
        [Int]$DeviceIdOffset
    )

    $CommandPerDeviceSet = ""

    $Command -split "(?=\s{1,}--|\s{1,}-| ,|^,)" | ForEach-Object {
        $Token = $_
        $Prefix = $null
        $ParameterValueSeparator = $null
        $ValueSeparator = $null
        $Values = $null

        if ($Token.TrimStart() -match "(?:^[-=]{1,})") { # supported prefix characters are listed in brackets: [-=]{1,}

            $Prefix = "$($Token -split $Matches[0] | Select-Object -Index 0)$($Matches[0])"
            $Token = $Token -split $Matches[0] | Select-Object -Last 1

            if ($Token -match "(?:[ =]{1,})") { # supported separators are listed in brackets: [ =]{1,}
                $ParameterValueSeparator = $Matches[0]
                $Parameter = $Token -split $ParameterValueSeparator | Select-Object -Index 0
                $Values = $Token.Substring(("$($Parameter)$($ParameterValueSeparator)").length)

                if ($Values -match "(?:[,; ]{1})") { # supported separators are listed in brackets: [,; ]{1}
                    $ValueSeparator = $Matches[0]
                    $RelevantValues = @()
                    $DeviceIDs | Foreach-Object {
                        $DeviceID = [Convert]::ToInt32($_, $DeviceIdBase) - $DeviceIdOffset
                        if ($Values.Split($ValueSeparator) | Select-Object -Index $DeviceId) {$RelevantValues += ($Values.Split($ValueSeparator) | Select-Object -Index $DeviceId)}
                        else {$RelevantValues += ""}
                    }                    
                    $CommandPerDeviceSet += "$($Prefix)$($Parameter)$($ParameterValueSeparator)$(($RelevantValues -join $ValueSeparator).TrimEnd($ValueSeparator))"
                }
                else {$CommandPerDeviceSet += "$($Prefix)$($Parameter)$($ParameterValueSeparator)$($Values)"}
            }
            else {$CommandPerDeviceSet += "$($Prefix)$($Token)"}
        }
        else {$CommandPerDeviceSet += $Token}
    }
    $CommandPerDeviceSet
}

function Update-Binaries {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [String]$Uri,
        [Parameter(Mandatory = $true)]
        [String]$Name,
        [Parameter(Mandatory = $true)]
        [String]$MinerFileVersion,
        [Parameter(Mandatory = $false)]
        $RemoveBenchmarkFiles = $false
    )

    if ($Uri) {
        Remove-Item $Path -Force -Confirm:$false -ErrorAction Stop # Remove miner binary to force re-download
        # Update log
        Write-Log -Level Info "Requested automatic miner binary update ($Name [$MinerFileVersion]). "
        if ($RemoveBenchmarkFiles) {Remove-BenchmarkFiles -MinerName $Name}
    }
    else {
        # Update log
        Write-Log -Level Info "New miner binary is available - manual download from '$ManualUri' and install to '$(Split-Path $Path)' is required ($Name [$MinerFileVersion]). "
        Write-Log -Level Info "For optimal profitability it is recommended to remove the stat files for this miner. "
    }
}

function Remove-BenchmarkFiles {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String]$MinerName,
        [Parameter(Mandatory = $false)]
        [String]$Algorithm = "*" # If no algorithm then remove ALL benchmark files
    )

    if (Test-Path ".\Stats\$($MinerName)_$($Algorithm)_HashRate.txt") {Remove-Item ".\Stats\$($MinerName)_$($Algorithm)_HashRate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
    if (Test-Path ".\Stats\$($MinerName)-*_$($Algorithm)_HashRate.txt") {Remove-Item ".\Stats\$($MinerName)-*_$($Algorithm)_HashRate.txt" -Force -Confirm:$false -ErrorAction SilentlyContinue}
}

function Write-Config {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        [Parameter(Mandatory = $true)]
        [String]$MinerName,
        [Parameter(Mandatory = $true)]
        [String]$Action
    )

    Begin { }
    Process {
        # Get mutex named MPMWriteConfig. Mutexes are shared across all threads and processes.
        # This lets us ensure only one thread is trying to write to the file at a time.
        $Mutex = New-Object System.Threading.Mutex($false, "MPMWriteConfig")

        $FileName = ".\Config.txt"

        # Attempt to aquire mutex, waiting up to 1 second if necessary. If aquired, write to the config file and release mutex. Otherwise, display an error.
        if ($Mutex.WaitOne(1000)) {
            $Config | ConvertTo-Json -Depth 10 | Out-File -FilePath $FileName -Encoding ASCII -ErrorAction Stop
            $Mutex.ReleaseMutex()
            # Update log
            Write-Log -Level Info "$Action miner config ($MinerName [$($Config.Miners.$MinerName.MinerFileVersion)]) "
        }
        else {
            Write-Error -Message "Config file is locked, unable to write message to $FileName."
        }
    }
    End {}
}
