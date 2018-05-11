Set-Location (Split-Path $MyInvocation.MyCommand.Path)

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
