Set-Location (Split-Path $MyInvocation.MyCommand.Path)

function Update-Binaries {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [String]$URI,
        [Parameter(Mandatory = $true)]
        [String]$Name,
        [Parameter(Mandatory = $true)]
        [String]$MinerFileVersion,
        [Parameter(Mandatory = $false)]
        $RemoveBenchmarkFiles = $false
    )

    if ($URI) {
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

function Get-Config {
    # Read configuration data from file, expand vaiable names, e.g. $Wallet
    Param(
        [Parameter(Mandatory = $true)]
        [String]$ConfigFile,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [HashTable]$Parameters
    )

    $NewConfig = Get-ChildItemContent -Path $ConfigFile -Parameters $Parameters | Select-Object -ExpandProperty Content

    #Error in Config.txt
    if ($NewConfig -isnot [PSCustomObject]) {
        Write-Log -Level Error "*********************************************************** "
        Write-Log -Level Error "Critical error: Config.txt is invalid. MPM cannot continue. "
        Write-Log -Level Error "*********************************************************** "
        Start-Sleep 10
        Exit
    }
    $NewConfig
}

function Set-Config {

# The variables in $Config are expanded, so
# Set-Config always reads current config from file
# to retrieve the unresolved variables

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String]$ConfigFile,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [String]$Message
    )

    Begin { }
    Process {
        # Get mutex named MPMSetConfig. Mutexes are shared across all threads and processes.
        # This lets us ensure only one thread is trying to write to the file at a time.
        $Mutex = New-Object System.Threading.Mutex($false, "MPMWriteConfig")

        # Attempt to aquire mutex, waiting up to 1 second if necessary. If aquired, write to the config file and release mutex. Otherwise, display an error.
        if ($Mutex.WaitOne(1000)) {
            $Config | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigFile -Encoding ASCII -ErrorAction Stop
            $Mutex.ReleaseMutex()
            # Activate config
            Get-Config -ConfigFile $ConfigFile
            # Update log file
            Write-Log -Level Info -Message $Message
        }
        else {
            Write-Error -Message "Config file is locked, unable to write message to $ConfigFile."
            return $null
        }
    }
    End {}
}

function Add-MinerConfig {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [String]$ConfigFile,
        [Parameter(Mandatory = $true)]
        [String]$MinerName,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [String]$Message
        
    )

    # Read config from file to not expand any variables
    $TempConfig = Get-Content $ConfigFile | ConvertFrom-Json

    # Add default miner config
    $TempConfig.Miners | Add-Member $MinerName $Config -Force -ErrorAction Stop

    # Save config to file and apply
    Set-Config -ConfigFile $ConfigFile -Config $TempConfig -Message $Message
}