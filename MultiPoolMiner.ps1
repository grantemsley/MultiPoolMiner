﻿using module .\Include.psm1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [Alias("BTC")]
    [String]$Wallet, 
    [Parameter(Mandatory = $false)]
    [Alias("User")]
    [String]$UserName, 
    [Parameter(Mandatory = $false)]
    [Alias("Worker")]
    [String]$WorkerName = "multipoolminer", 
    [Parameter(Mandatory = $false)]
    [Int]$API_ID = 0, 
    [Parameter(Mandatory = $false)]
    [String]$API_Key = "", 
    [Parameter(Mandatory = $false)]
    [Int]$Interval = 60, #seconds before reading hash rate from miners
    [Parameter(Mandatory = $false)]
    [Alias("Location")]
    [String]$Region = "europe", #europe/us/asia
    [Parameter(Mandatory = $false)]
    [Switch]$SSL = $false, 
    [Parameter(Mandatory = $false)]
    [Array]$Type = @(), #AMD/NVIDIA/CPU
    [Parameter(Mandatory = $false)]
    [Array]$Algorithm = @(), #i.e. Ethash, Equihash, CryptoNightV7 etc.
    [Parameter(Mandatory = $false)]
    [Alias("Miner")]
    [Array]$MinerName = @(), 
    [Parameter(Mandatory = $false)]
    [Alias("Pool")]
    [Array]$PoolName = @(), 
    [Parameter(Mandatory = $false)]
    [Array]$ExcludeAlgorithm = @(), #i.e. Ethash, Equihash, CryptoNightV7 etc.
    [Parameter(Mandatory = $false)]
    [Alias("ExcludeMiner")]
    [Array]$ExcludeMinerName = @(), 
    [Parameter(Mandatory = $false)]
    [Alias("ExcludePool")]
    [Array]$ExcludePoolName = @(), 
    [Parameter(Mandatory = $false)]
    [Array]$Currency = ("BTC", "USD"), #i.e. GBP, EUR, ZEC, ETH etc.
    [Parameter(Mandatory = $false)]
    [Int]$Donate = 24, #Minutes per Day
    [Parameter(Mandatory = $false)]
    [String]$Proxy = "", #i.e http://192.0.0.1:8080
    [Parameter(Mandatory = $false)]
    [Int]$Delay = 0, #seconds before opening each miner
    [Parameter(Mandatory = $false)]
    [Switch]$Watchdog = $false,
    [Parameter(Mandatory = $false)]
    [Array]$ExcludeWatchdogAlgorithm = @("X16R"), #Do not use watchdog for these algorithms, e.g due to its nature X16R will always trigger watchdog
    [Parameter(Mandatory = $false)]
    [Array]$ExcludeWatchdogMinerName = @(), #Do not use watchdog for these miners
    [Parameter(Mandatory = $false)]
    [Alias("Uri", "Url")]
    [String]$MinerStatusUrl = "", #i.e https://multipoolminer.io/monitor/miner.php
    [Parameter(Mandatory = $false)]
    [String]$MinerStatusKey = "",
    [Parameter(Mandatory = $false)]
    [Double]$SwitchingPrevention = 1, #zero does not prevent miners switching
    [Parameter(Mandatory = $false)]
    [Switch]$DisableAutoUpdate = $true,
    [Parameter(Mandatory = $false)]
    [Switch]$ShowMinerWindow = $false #if true all miner windows will be visible (they can steal focus)
)
write-log -level warn "$(Get-Date) Main script A memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
#$VerbosePreference = 'Continue'
#$DebugPreference = 'Continue'
$InformationPreference = 'Continue'

#Limit CPU mining to 1/2 of available processors
$TotalThreads = ((Get-CimInstance win32_processor).NumberOfLogicalProcessors | Measure-Object -Sum).Sum
$MaxThreads = [int]($TotalThreads /2)
If($MaxThreads -lt 1) { $MaxThreads = 1 }
Write-Log -Level Warn "CPU Mining limited to $MaxThreads/$TotalThreads of logical processors"

$Version = "2.7.2.7"
$Strikes = 3
$SyncWindow = 5 #minutes

Set-Location (Split-Path $MyInvocation.MyCommand.Path)
Import-Module NetSecurity -ErrorAction Ignore
Import-Module Defender -ErrorAction Ignore
Import-Module "$env:Windir\System32\WindowsPowerShell\v1.0\Modules\NetSecurity\NetSecurity.psd1" -ErrorAction Ignore
Import-Module "$env:Windir\System32\WindowsPowerShell\v1.0\Modules\Defender\Defender.psd1" -ErrorAction Ignore

$Algorithm = $Algorithm | ForEach-Object {Get-Algorithm $_}
$ExcludeAlgorithm = $ExcludeAlgorithm | ForEach-Object {Get-Algorithm $_}
$Region = $Region | ForEach-Object {Get-Region $_}
$Currency = $Currency | ForEach-Object {$_.ToUpper()}

$Timer = (Get-Date).ToUniversalTime()
$StatEnd = $Timer
$DecayStart = $Timer
$DecayPeriod = 60 #seconds
$DecayBase = 1 - 0.1 #decimal percentage

$WatchdogTimers = @()
$ActiveMiners = @()
$Rates = [PSCustomObject]@{BTC = [Double]1}

# Make sure necessary directories exist
if (-not (Test-Path "Cache")) {New-Item "Cache" -ItemType "directory" | Out-Null}

#Start the log
#Start-Transcript ".\Logs\MultiPoolMiner_$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").txt"
write-log -level warn "$(Get-Date) Main script B memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
#Set process priority to BelowNormal to avoid hash rate drops on systems with weak CPUs
(Get-Process -Id $PID).PriorityClass = "BelowNormal"

if (Get-Command "Unblock-File" -ErrorAction SilentlyContinue -Verbose:$false) {Get-ChildItem . -Recurse | Unblock-File}
if ((Get-Command "Get-MpPreference" -ErrorAction SilentlyContinue -Verbose:$false) -and (Get-MpComputerStatus -ErrorAction SilentlyContinue) -and (Get-MpPreference).ExclusionPath -notcontains (Convert-Path .)) {
    Start-Process (@{desktop = "powershell"; core = "pwsh"}.$PSEdition) "-Command Import-Module '$env:Windir\System32\WindowsPowerShell\v1.0\Modules\Defender\Defender.psd1' -Verbose:`$False; Add-MpPreference -ExclusionPath '$(Convert-Path .)'" -Verb runAs
}

#Initialize the API
Import-Module .\API.psm1
Start-APIServer
$API.Version = $Version

write-log -level warn "$(Get-Date) Main script C memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB" 

# Create config.txt if it is missing
if (!(Test-Path "Config.txt")) {
    if(Test-Path "Config.default.txt") {
        Copy-Item -Path "Config.default.txt" -Destination "Config.txt"
    } else {
        Write-Log -Level Error "Config.txt and Config.default.txt are missing. Cannot continue. "
        Start-Sleep 10
        Exit
    }
}

while ($true) {
    write-log -level warn "$(Get-Date) Main script D memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    #Load the config
    $ConfigBackup = $Config
    if (Test-Path "Config.txt") {
        $Config = Get-ChildItemContent "Config.txt" -Parameters @{
            Wallet                   = $Wallet
            UserName                 = $UserName
            WorkerName               = $WorkerName
            API_ID                   = $API_ID
            API_Key                  = $API_Key
            Interval                 = $Interval
            Region                   = $Region
            SSL                      = $SSL
            Type                     = $Type
            Algorithm                = $Algorithm
            MinerName                = $MinerName
            PoolName                 = $PoolName
            ExcludeAlgorithm         = $ExcludeAlgorithm
            ExcludeMinerName         = $ExcludeMinerName
            ExcludePoolName          = $ExcludePoolName
            Currency                 = $Currency
            Donate                   = $Donate
            Proxy                    = $Proxy
            Delay                    = $Delay
            Watchdog                 = $Watchdog
            WatchdogExcludeAlgorithm = $WatchdogExcludeAlgorithm
            WatchdogExcludeMinerName = $WatchdogExcludeMinerName
            MinerStatusURL           = $MinerStatusURL
            MinerStatusKey           = $MinerStatusKey
            SwitchingPrevention      = $SwitchingPrevention
            ShowMinerWindow          = $ShowMinerWindow
        } | Select-Object -ExpandProperty Content
    }

    #Error in Config.txt
    if ($Config -isnot [PSCustomObject]) {
        Write-Log -Level Error "Config.txt is invalid. Cannot continue. "
        Start-Sleep 10
        Exit
    }

    #For backwards compatibility, set the MinerStatusKey to $Wallet if it's not specified
    if ($Wallet -and -not $Config.MinerStatusKey) {$Config.MinerStatusKey = $Wallet}

    Get-ChildItem "Pools" -File | Where-Object {-not $Config.Pools.($_.BaseName)} | ForEach-Object {
        $Config.Pools | Add-Member $_.BaseName (
            [PSCustomObject]@{
                BTC     = $Wallet
                User    = $UserName
                Worker  = $WorkerName
                API_ID  = $API_ID
                API_Key = $API_Key
            }
        )
    }

    Get-ChildItem "Miners" | Where-Object {-not $Config.Miners.($_.BaseName)} | ForEach-Object {
        $Config.Miners | Add-Member $_.BaseName (
            [PSCustomObject]@{
            }
        )
    }
    write-log -level warn "$(Get-Date) Main script E memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"

    # Add MaxThreads to $Config
    $Config | Add-Member MaxThreads $MaxThreads -Force

    #Give API access to the current running configuration
    $API.Config = $Config

    #Clear pool cache if the pool configuration has changed
    if (($ConfigBackup.Pools | ConvertTo-Json -Compress) -ne ($Config.Pools | ConvertTo-Json -Compress)) {$AllPools = $null}

    if ($Config.Proxy) {$PSDefaultParameterValues["*:Proxy"] = $Config.Proxy}
    else {$PSDefaultParameterValues.Remove("*:Proxy")}
    write-log -level warn "$(Get-Date) Main script F memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    # Disable verbose while importing APIs
    $OldVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    Get-ChildItem "APIs" | ForEach-Object {. $_.FullName}
    $VerbosePreference = $OldVerbosePreference

    $Timer = (Get-Date).ToUniversalTime()

    $StatStart = $StatEnd
    $StatEnd = $Timer.AddSeconds($Config.Interval)
    $StatSpan = New-TimeSpan $StatStart $StatEnd

    $DecayExponent = [int](($Timer - $DecayStart).TotalSeconds / $DecayPeriod)

    $WatchdogInterval = ($WatchdogInterval / $Strikes * ($Strikes - 1)) + $StatSpan.TotalSeconds
    $WatchdogReset = ($WatchdogReset / ($Strikes * $Strikes * $Strikes) * (($Strikes * $Strikes * $Strikes) - 1)) + $StatSpan.TotalSeconds

    write-log -level warn "$(Get-Date) Main script G memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    #Load the stats
    Write-Log "Loading saved statistics. "
    $Stats = Get-Stat
    #Give API access to the current stats
    $API.Stats = $Stats

    #Load information about the pools
    Write-Log "Loading pool information. "
    $NewPools = @()
    if (Test-Path "Pools") {
        $NewPools = Get-ChildItem "Pools" -File | Where-Object {$Config.Pools.$($_.BaseName) -and $Config.ExcludePoolName -inotcontains $_.BaseName} | ForEach-Object {
            $Pool_Name = $_.BaseName
            $Pool_Parameters = @{StatSpan = $StatSpan}
            $Config.Pools.$Pool_Name | Get-Member -MemberType NoteProperty | ForEach-Object {$Pool_Parameters.($_.Name) = $Config.Pools.$Pool_Name.($_.Name)}
            Get-ChildItemContent "Pools\$($_.Name)" -Parameters $Pool_Parameters
        } | ForEach-Object {$_.Content | Add-Member Name $_.Name -PassThru}
    }
    write-log -level warn "$(Get-Date) Main script I memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"

    #Give API access to the current running configuration
    $API.NewPools = $NewPools

    # This finds any pools that were already in $AllPools (from a previous loop) but not in $NewPools. Add them back to the list. Their API likely didn't return in time, but we don't want to cut them off just yet
    # since mining is probably still working.  Then it filters out any algorithms that aren't being used.
    $AllPools = @($NewPools) + @(Compare-Object @($NewPools | Select-Object -ExpandProperty Name -Unique) @($AllPools | Select-Object -ExpandProperty Name -Unique) | Where-Object SideIndicator -EQ "=>" | Select-Object -ExpandProperty InputObject | ForEach-Object {$AllPools | Where-Object Name -EQ $_}) | 
        Where-Object {$Config.Algorithm.Count -eq 0 -or (Compare-Object $Config.Algorithm $_.Algorithm -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0} | 
        Where-Object {$Config.ExcludeAlgorithm.Count -eq 0 -or (Compare-Object $Config.ExcludeAlgorithm $_.Algorithm -IncludeEqual -ExcludeDifferent | Measure-Object).Count -eq 0} | 
        Where-Object {$Config.ExcludePoolName.Count -eq 0 -or (Compare-Object $Config.ExcludePoolName $_.Name -IncludeEqual -ExcludeDifferent | Measure-Object).Count -eq 0}

    write-log -level warn "$(Get-Date) Main script J memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    
    #Give API access to the current running configuration
    $API.AllPools = $AllPools

    #Apply watchdog to pools
    $AllPools = $AllPools | Where-Object {
        $Pool = $_
        $Pool_WatchdogTimers = $WatchdogTimers | Where-Object PoolName -EQ $Pool.Name | Where-Object Kicked -LT $Timer.AddSeconds( - $WatchdogInterval) | Where-Object Kicked -GT $Timer.AddSeconds( - $WatchdogReset)
        ($Pool_WatchdogTimers | Measure-Object | Select-Object -ExpandProperty Count) -lt <#stage#>3 -and ($Pool_WatchdogTimers | Where-Object {$Pool.Algorithm -contains $_.Algorithm} | Measure-Object | Select-Object -ExpandProperty Count) -lt <#statge#>2
    }
    write-log -level warn "$(Get-Date) Main script K memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    #Update the active pools
    if ($AllPools.Count -eq 0) {
        Write-Log -Level Warn "No pools available. "
        Start-Sleep $Config.Interval
        continue
    }
    $Pools = [PSCustomObject]@{}
    write-log -level warn "$(Get-Date) Main script L memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    Write-Log "Selecting best pool for each algorithm. "
    $AllPools.Algorithm | ForEach-Object {$_.ToLower()} | Select-Object -Unique | ForEach-Object {$Pools | Add-Member $_ ($AllPools | Sort-Object -Descending {$Config.PoolName.Count -eq 0 -or (Compare-Object $Config.PoolName $_.Name -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0}, {($Timer - $_.Updated).TotalMinutes -le ($SyncWindow * $Strikes)}, {$_.StablePrice * (1 - $_.MarginOfError)}, {$_.Region -EQ $Config.Region}, {$_.SSL -EQ $Config.SSL} | Where-Object Algorithm -EQ $_ | Select-Object -First 1)}
    if (($Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_.Name} | Select-Object -Unique | ForEach-Object {$AllPools | Where-Object Name -EQ $_ | Measure-Object Updated -Maximum | Select-Object -ExpandProperty Maximum} | Measure-Object -Minimum -Maximum | ForEach-Object {$_.Maximum - $_.Minimum} | Select-Object -ExpandProperty TotalMinutes) -gt $SyncWindow) {
        Write-Log -Level Warn "Pool prices are out of sync ($([Int]($Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_} | Measure-Object Updated -Minimum -Maximum | ForEach-Object {$_.Maximum - $_.Minimum} | Select-Object -ExpandProperty TotalMinutes)) minutes). "
        $Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_ | Add-Member Price_Bias ($Pools.$_.StablePrice * (1 - ($Pools.$_.MarginOfError * $Config.SwitchingPrevention * [Math]::Pow($DecayBase, $DecayExponent)))) -Force}
        $Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_ | Add-Member Price_Unbias $Pools.$_.StablePrice -Force}
    }
    else {
        $Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_ | Add-Member Price_Bias ($Pools.$_.Price * (1 - ($Pools.$_.MarginOfError * $Config.SwitchingPrevention * [Math]::Pow($DecayBase, $DecayExponent)))) -Force}
        $Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_ | Add-Member Price_Unbias $Pools.$_.Price -Force}
    }

    write-log -level warn "$(Get-Date) Main script M memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"

    #Give API access to the pools information
    $API.Pools = $Pools

    #Load information about the miners
    #Messy...?
    Write-Log "Getting miner information. "
    # Get all the miners, get just the .Content property and add the name, select only the ones that match our $Config.Type (CPU, AMD, NVIDIA) or all of them if type is unset,
    # select only the ones that have a HashRate matching our algorithms, and that only include algorithms we have pools for
    # select only the miners that match $Config.MinerName, if specified, and don't match $Config.ExcludeMinerName
    $AllMiners = if (Test-Path "Miners") {
        Get-ChildItemContentParallel "Miners" -Parameters @{Pools = $Pools; Stats = $Stats; Config = $Config} | ForEach-Object {$_.Content | Add-Member Name $_.Name -PassThru -Force} | 
            Where-Object {$Config.Type.Count -eq 0 -or (Compare-Object $Config.Type $_.Type -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0} | 
            Where-Object {($Config.Algorithm.Count -eq 0 -or (Compare-Object $Config.Algorithm $_.HashRates.PSObject.Properties.Name | Where-Object SideIndicator -EQ "=>" | Measure-Object).Count -eq 0) -and ((Compare-Object $Pools.PSObject.Properties.Name $_.HashRates.PSObject.Properties.Name | Where-Object SideIndicator -EQ "=>" | Measure-Object).Count -eq 0)} | 
            Where-Object {$Config.ExcludeAlgorithm.Count -eq 0 -or (Compare-Object $Config.ExcludeAlgorithm $_.HashRates.PSObject.Properties.Name -IncludeEqual -ExcludeDifferent | Measure-Object).Count -eq 0} | 
            Where-Object {$Config.MinerName.Count -eq 0 -or (Compare-Object $Config.MinerName $_.Name -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0} | 
            Where-Object {$Config.ExcludeMinerName.Count -eq 0 -or (Compare-Object $Config.ExcludeMinerName $_.Name -IncludeEqual -ExcludeDifferent | Measure-Object).Count -eq 0}
    }
    write-log -level warn "$(Get-Date) Main script N memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    Write-Log "Calculating profit for each miner. "
    $AllMiners | ForEach-Object {
        $Miner = $_

        $Miner_HashRates = [PSCustomObject]@{}
        $Miner_Pools = [PSCustomObject]@{}
        $Miner_Pools_Comparison = [PSCustomObject]@{}
        $Miner_Profits = [PSCustomObject]@{}
        $Miner_Profits_Comparison = [PSCustomObject]@{}
        $Miner_Profits_MarginOfError = [PSCustomObject]@{}
        $Miner_Profits_Bias = [PSCustomObject]@{}
        $Miner_Profits_Unbias = [PSCustomObject]@{}

        $Miner_Types = $Miner.Type | Select-Object -Unique
        $Miner_Indexes = $Miner.Index | Select-Object -Unique
        $Miner_Devices = $Miner.Device | Select-Object -Unique

        $Miner.HashRates.PSObject.Properties.Name | ForEach-Object { #temp fix, must use 'PSObject.Properties' to preserve order
            $Miner_HashRates | Add-Member $_ ([Double]$Miner.HashRates.$_)
            $Miner_Pools | Add-Member $_ ([PSCustomObject]$Pools.$_)
            $Miner_Pools_Comparison | Add-Member $_ ([PSCustomObject]$Pools.$_)
            $Miner_Profits | Add-Member $_ ([Double]$Miner.HashRates.$_ * $Pools.$_.Price)
            $Miner_Profits_Comparison | Add-Member $_ ([Double]$Miner.HashRates.$_ * $Pools.$_.StablePrice)
            $Miner_Profits_Bias | Add-Member $_ ([Double]$Miner.HashRates.$_ * $Pools.$_.Price_Bias)
            $Miner_Profits_Unbias | Add-Member $_ ([Double]$Miner.HashRates.$_ * $Pools.$_.Price_Unbias)
        }

        $Miner_Profit = [Double]($Miner_Profits.PSObject.Properties.Value | Measure-Object -Sum).Sum
        $Miner_Profit_Comparison = [Double]($Miner_Profits_Comparison.PSObject.Properties.Value | Measure-Object -Sum).Sum
        $Miner_Profit_Bias = [Double]($Miner_Profits_Bias.PSObject.Properties.Value | Measure-Object -Sum).Sum
        $Miner_Profit_Unbias = [Double]($Miner_Profits_Unbias.PSObject.Properties.Value | Measure-Object -Sum).Sum

        $Miner.HashRates | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {
            $Miner_Profits_MarginOfError | Add-Member $_ ([Double]$Pools.$_.MarginOfError * (& {if ($Miner_Profit) {([Double]$Miner.HashRates.$_ * $Pools.$_.StablePrice) / $Miner_Profit}else {1}}))
        }

        $Miner_Profit_MarginOfError = [Double]($Miner_Profits_MarginOfError.PSObject.Properties.Value | Measure-Object -Sum).Sum

        $Miner.HashRates | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {
            if (-not [String]$Miner.HashRates.$_) {
                $Miner_HashRates.$_ = $null
                $Miner_Profits.$_ = $null
                $Miner_Profits_Comparison.$_ = $null
                $Miner_Profits_Bias.$_ = $null
                $Miner_Profits_Unbias.$_ = $null
                $Miner_Profit = $null
                $Miner_Profit_Comparison = $null
                $Miner_Profits_MarginOfError = $null
                $Miner_Profit_Bias = $null
                $Miner_Profit_Unbias = $null
            }
        }

        if ($Miner_Types -eq $null) {$Miner_Types = $AllMiners.Type | Select-Object -Unique}
        if ($Miner_Indexes -eq $null) {$Miner_Indexes = $AllMiners.Index | Select-Object -Unique}

        if ($Miner_Types -eq $null) {$Miner_Types = ""}
        if ($Miner_Indexes -eq $null) {$Miner_Indexes = 0}

        $Miner.HashRates = $Miner_HashRates

        $Miner | Add-Member Pools $Miner_Pools
        $Miner | Add-Member Profits $Miner_Profits
        $Miner | Add-Member Profits_Comparison $Miner_Profits_Comparison
        $Miner | Add-Member Profits_Bias $Miner_Profits_Bias
        $Miner | Add-Member Profits_Unbias $Miner_Profits_Unbias
        $Miner | Add-Member Profit $Miner_Profit
        $Miner | Add-Member Profit_Comparison $Miner_Profit_Comparison
        $Miner | Add-Member Profit_MarginOfError $Miner_Profit_MarginOfError
        $Miner | Add-Member Profit_Bias $Miner_Profit_Bias
        $Miner | Add-Member Profit_Unbias $Miner_Profit_Unbias

        $Miner | Add-Member Type ($Miner_Types | Sort-Object) -Force
        $Miner | Add-Member Index ($Miner_Indexes | Sort-Object) -Force

        $Miner | Add-Member Device ($Miner_Devices | Sort-Object) -Force
        $Miner | Add-Member Device_Auto (($Miner_Devices -eq $null) | Sort-Object) -Force

        $Miner.Path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Miner.Path)
        if ($Miner.PrerequisitePath) {$Miner.PrerequisitePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Miner.PrerequisitePath)}

        if ($Miner.Arguments -isnot [String]) {$Miner.Arguments = $Miner.Arguments | ConvertTo-Json -Compress}

        if (-not $Miner.API) {$Miner | Add-Member API "Miner" -Force}
    }
    $Miners = $AllMiners | Where-Object {(Test-Path $_.Path) -and ((-not $_.PrerequisitePath) -or (Test-Path $_.PrerequisitePath))}
    write-log -level warn "$(Get-Date) Main script O memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    # Open firewall ports for all miners
    if (Get-Command "Get-MpPreference" -ErrorAction SilentlyContinue -Verbose:$false) {
        if ((Get-Command "Get-MpComputerStatus" -ErrorAction SilentlyContinue -Verbose:$false) -and (Get-MpComputerStatus -ErrorAction SilentlyContinue -Verbose:$false)) {
            if (Get-Command "Get-NetFirewallRule" -ErrorAction SilentlyContinue -Verbose:$false) {
                if ($MinerFirewalls -eq $null) {$MinerFirewalls = Get-NetFirewallApplicationFilter | Select-Object -ExpandProperty Program}
                if (@($AllMiners | Select-Object -ExpandProperty Path -Unique) | Compare-Object @($MinerFirewalls) | Where-Object SideIndicator -EQ "=>") {
                    Start-Process (@{desktop = "powershell"; core = "pwsh"}.$PSEdition) ("-Command Import-Module '$env:Windir\System32\WindowsPowerShell\v1.0\Modules\NetSecurity\NetSecurity.psd1' -Verbose:`$False; ('$(@($AllMiners | Select-Object -ExpandProperty Path -Unique) | Compare-Object @($MinerFirewalls) | Where-Object SideIndicator -EQ '=>' | Select-Object -ExpandProperty InputObject | ConvertTo-Json -Compress)' | ConvertFrom-Json) | ForEach {New-NetFirewallRule -DisplayName 'MultiPoolMiner' -Program `$_}" -replace '"', '\"') -Verb runAs
                    $MinerFirewalls = $null
                }
            }
        }
    }

    #Apply watchdog to miners
    $Miners = $Miners | Where-Object {
        $Miner = $_
        $Miner_WatchdogTimers = $WatchdogTimers | Where-Object MinerName -EQ $Miner.Name | Where-Object Kicked -LT $Timer.AddSeconds( - $WatchdogInterval) | Where-Object Kicked -GT $Timer.AddSeconds( - $WatchdogReset)
        ($Miner_WatchdogTimers | Measure-Object | Select-Object -ExpandProperty Count) -lt <#stage#>2 -and ($Miner_WatchdogTimers | Where-Object {$Miner.HashRates.PSObject.Properties.Name -contains $_.Algorithm} | Measure-Object | Select-Object -ExpandProperty Count) -lt <#stage#>1
    }

    #Update the active miners
    if ($Miners.Count -eq 0) {
        Write-Log -Level Warn "No miners available. "
        Start-Sleep $Config.Interval
        continue
    }

    write-log -level warn "$(Get-Date) Main script P memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"

    #Give API access to the miners information
    $API.Miners = $Miners

    $ActiveMiners | ForEach-Object {
        $_.Profit = 0
        $_.Profit_Comparison = 0
        $_.Profit_MarginOfError = 0
        $_.Profit_Bias = 0
        $_.Profit_Unbias = 0
        $_.Best = $false
        $_.Best_Comparison = $false
    }
    $Miners | ForEach-Object {
        $Miner = $_
        $ActiveMiner = $ActiveMiners | Where-Object {
            $_.Name -eq $Miner.Name -and 
            $_.Path -eq $Miner.Path -and 
            $_.Arguments -eq $Miner.Arguments -and 
            $_.Wrap -eq $Miner.Wrap -and 
            $_.API -eq $Miner.API -and 
            $_.Port -eq $Miner.Port -and 
            (Compare-Object $_.Algorithm ($Miner.HashRates | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) | Measure-Object).Count -eq 0
        }
        if ($ActiveMiner) {
            $ActiveMiner.Type = $Miner.Type
            $ActiveMiner.Index = $Miner.Index
            $ActiveMiner.Device = $Miner.Device
            $ActiveMiner.Device_Auto = $Miner.Device_Auto
            $ActiveMiner.Profit = $Miner.Profit
            $ActiveMiner.Profit_Comparison = $Miner.Profit_Comparison
            $ActiveMiner.Profit_MarginOfError = $Miner.Profit_MarginOfError
            $ActiveMiner.Profit_Bias = $Miner.Profit_Bias
            $ActiveMiner.Profit_Unbias = $Miner.Profit_Unbias
            $ActiveMiner.Speed = $Miner.HashRates.PSObject.Properties.Value #temp fix, must use 'PSObject.Properties' to preserve order
        }
        else {
            $ActiveMiners += New-Object $Miner.API -Property @{
                Name                 = $Miner.Name
                Path                 = $Miner.Path
                Arguments            = $Miner.Arguments
                Wrap                 = $Miner.Wrap
                API                  = $Miner.API
                Port                 = $Miner.Port
                Algorithm            = $Miner.HashRates.PSObject.Properties.Name #temp fix, must use 'PSObject.Properties' to preserve order
                Type                 = $Miner.Type
                Index                = $Miner.Index
                Device               = $Miner.Device
                Device_Auto          = $Miner.Device_Auto
                Profit               = $Miner.Profit
                Profit_Comparison    = $Miner.Profit_Comparison
                Profit_MarginOfError = $Miner.Profit_MarginOfError
                Profit_Bias          = $Miner.Profit_Bias
                Profit_Unbias        = $Miner.Profit_Unbias
                Speed                = $Miner.HashRates.PSObject.Properties.Value #temp fix, must use 'PSObject.Properties' to preserve order
                Speed_Live           = 0
                Best                 = $false
                Best_Comparison      = $false
                New                  = $false
                Benchmarked          = 0
                Pool                 = $Miner.Pools.PSObject.Properties.Value.Name
                ShowMinerWindow      = $Config.ShowMinerWindow
            }
        }
    }
    write-log -level warn "$(Get-Date) Main script Q memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    $ActiveMiners | Where-Object Device_Auto | ForEach-Object {
        $Miner = $_
        $Miner.Device = ($Miners | Where-Object {(Compare-Object $Miner.Type $_.Type -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0}).Device | Select-Object -Unique | Sort-Object
        if ($Miner.Device -eq $null) {$Miner.Device = ($Miners | Where-Object {(Compare-Object $Miner.Type $_.Type -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0}).Type | Select-Object -Unique | Sort-Object}
    }

    #Don't penalize active miners
    $ActiveMiners | Where-Object {$_.GetStatus() -EQ "Running"} | ForEach-Object {$_.Profit_Bias = $_.Profit_Unbias}
    write-log -level warn "$(Get-Date) Main script R memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    #Get most profitable miner combination i.e. AMD+NVIDIA+CPU
    $BestMiners = $ActiveMiners | Select-Object Type, Index -Unique | ForEach-Object {$Miner_GPU = $_; ($ActiveMiners | Where-Object {(Compare-Object $Miner_GPU.Type $_.Type | Measure-Object).Count -eq 0 -and (Compare-Object $Miner_GPU.Index $_.Index | Measure-Object).Count -eq 0} | Sort-Object -Descending {($_ | Where-Object Profit -EQ $null | Measure-Object).Count}, {($_ | Measure-Object Profit_Bias -Sum).Sum}, {($_ | Where-Object Profit -NE 0 | Measure-Object).Count} | Select-Object -First 1)}
    $BestDeviceMiners = $ActiveMiners | Select-Object Device -Unique | ForEach-Object {$Miner_GPU = $_; ($ActiveMiners | Where-Object {(Compare-Object $Miner_GPU.Device $_.Device | Measure-Object).Count -eq 0} | Sort-Object -Descending {($_ | Where-Object Profit -EQ $null | Measure-Object).Count}, {($_ | Measure-Object Profit_Bias -Sum).Sum}, {($_ | Where-Object Profit -NE 0 | Measure-Object).Count} | Select-Object -First 1)}
    $BestMiners_Comparison = $ActiveMiners | Select-Object Type, Index -Unique | ForEach-Object {$Miner_GPU = $_; ($ActiveMiners | Where-Object {(Compare-Object $Miner_GPU.Type $_.Type | Measure-Object).Count -eq 0 -and (Compare-Object $Miner_GPU.Index $_.Index | Measure-Object).Count -eq 0} | Sort-Object -Descending {($_ | Where-Object Profit -EQ $null | Measure-Object).Count}, {($_ | Measure-Object Profit_Comparison -Sum).Sum}, {($_ | Where-Object Profit -NE 0 | Measure-Object).Count} | Select-Object -First 1)}
    $BestDeviceMiners_Comparison = $ActiveMiners | Select-Object Device -Unique | ForEach-Object {$Miner_GPU = $_; ($ActiveMiners | Where-Object {(Compare-Object $Miner_GPU.Device $_.Device | Measure-Object).Count -eq 0} | Sort-Object -Descending {($_ | Where-Object Profit -EQ $null | Measure-Object).Count}, {($_ | Measure-Object Profit_Comparison -Sum).Sum}, {($_ | Where-Object Profit -NE 0 | Measure-Object).Count} | Select-Object -First 1)}
    $Miners_Type_Combos = @([PSCustomObject]@{Combination = @()}) + (Get-Combination ($ActiveMiners | Select-Object Type -Unique) | Where-Object {(Compare-Object ($_.Combination | Select-Object -ExpandProperty Type -Unique) ($_.Combination | Select-Object -ExpandProperty Type) | Measure-Object).Count -eq 0})
    $Miners_Index_Combos = @([PSCustomObject]@{Combination = @()}) + (Get-Combination ($ActiveMiners | Select-Object Index -Unique) | Where-Object {(Compare-Object ($_.Combination | Select-Object -ExpandProperty Index -Unique) ($_.Combination | Select-Object -ExpandProperty Index) | Measure-Object).Count -eq 0})
    $Miners_Device_Combos = (Get-Combination ($ActiveMiners | Select-Object Device -Unique) | Where-Object {(Compare-Object ($_.Combination | Select-Object -ExpandProperty Device -Unique) ($_.Combination | Select-Object -ExpandProperty Device) | Measure-Object).Count -eq 0})
    $BestMiners_Combos = $Miners_Type_Combos | ForEach-Object {
        $Miner_Type_Combo = $_.Combination
        $Miners_Index_Combos | ForEach-Object {
            $Miner_Index_Combo = $_.Combination
            [PSCustomObject]@{
                Combination = $Miner_Type_Combo | ForEach-Object {
                    $Miner_Type_Count = $_.Type.Count
                    [Regex]$Miner_Type_Regex = "^(" + (($_.Type | ForEach-Object {[Regex]::Escape($_)}) -join "|") + ")$"
                    $Miner_Index_Combo | ForEach-Object {
                        $Miner_Index_Count = $_.Index.Count
                        [Regex]$Miner_Index_Regex = "^(" + (($_.Index | ForEach-Object {[Regex]::Escape($_)}) -join "|") + ")$"
                        $BestMiners | Where-Object {([Array]$_.Type -notmatch $Miner_Type_Regex).Count -eq 0 -and ([Array]$_.Index -notmatch $Miner_Index_Regex).Count -eq 0 -and ([Array]$_.Type -match $Miner_Type_Regex).Count -eq $Miner_Type_Count -and ([Array]$_.Index -match $Miner_Index_Regex).Count -eq $Miner_Index_Count}
                    }
                }
            }
        }
    }
    write-log -level warn "$(Get-Date) Main script S memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    $BestMiners_Combos += $Miners_Device_Combos | ForEach-Object {
        $Miner_Device_Combo = $_.Combination
        [PSCustomObject]@{
            Combination = $Miner_Device_Combo | ForEach-Object {
                $Miner_Device_Count = $_.Device.Count
                [Regex]$Miner_Device_Regex = "^(" + (($_.Device | ForEach-Object {[Regex]::Escape($_)}) -join "|") + ")$"
                $BestDeviceMiners | Where-Object {([Array]$_.Device -notmatch $Miner_Device_Regex).Count -eq 0 -and ([Array]$_.Device -match $Miner_Device_Regex).Count -eq $Miner_Device_Count}
            }
        }
    }
    write-log -level warn "$(Get-Date) Main script T memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    $BestMiners_Combos_Comparison = $Miners_Type_Combos | ForEach-Object {
        $Miner_Type_Combo = $_.Combination
        $Miners_Index_Combos | ForEach-Object {
            $Miner_Index_Combo = $_.Combination
            [PSCustomObject]@{
                Combination = $Miner_Type_Combo | ForEach-Object {
                    $Miner_Type_Count = $_.Type.Count
                    [Regex]$Miner_Type_Regex = "^(" + (($_.Type | ForEach-Object {[Regex]::Escape($_)}) -join "|") + ")$"
                    $Miner_Index_Combo | ForEach-Object {
                        $Miner_Index_Count = $_.Index.Count
                        [Regex]$Miner_Index_Regex = "^(" + (($_.Index | ForEach-Object {[Regex]::Escape($_)}) -join "|") + ")$"
                        $BestMiners_Comparison | Where-Object {([Array]$_.Type -notmatch $Miner_Type_Regex).Count -eq 0 -and ([Array]$_.Index -notmatch $Miner_Index_Regex).Count -eq 0 -and ([Array]$_.Type -match $Miner_Type_Regex).Count -eq $Miner_Type_Count -and ([Array]$_.Index -match $Miner_Index_Regex).Count -eq $Miner_Index_Count}
                    }
                }
            }
        }
    }
    write-log -level warn "$(Get-Date) Main script U memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    $BestMiners_Combos_Comparison += $Miners_Device_Combos | ForEach-Object {
        $Miner_Device_Combo = $_.Combination
        [PSCustomObject]@{
            Combination = $Miner_Device_Combo | ForEach-Object {
                $Miner_Device_Count = $_.Device.Count
                [Regex]$Miner_Device_Regex = "^(" + (($_.Device | ForEach-Object {[Regex]::Escape($_)}) -join "|") + ")$"
                $BestDeviceMiners_Comparison | Where-Object {([Array]$_.Device -notmatch $Miner_Device_Regex).Count -eq 0 -and ([Array]$_.Device -match $Miner_Device_Regex).Count -eq $Miner_Device_Count}
            }
        }
    }
    write-log -level warn "$(Get-Date) Main script V memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    $BestMiners_Combo = $BestMiners_Combos | Sort-Object -Descending {($_.Combination | Where-Object Profit -EQ $null | Measure-Object).Count}, {($_.Combination | Measure-Object Profit_Bias -Sum).Sum}, {($_.Combination | Where-Object Profit -NE 0 | Measure-Object).Count} | Select-Object -First 1 | Select-Object -ExpandProperty Combination
    $BestMiners_Combo_Comparison = $BestMiners_Combos_Comparison | Sort-Object -Descending {($_.Combination | Where-Object Profit -EQ $null | Measure-Object).Count}, {($_.Combination | Measure-Object Profit_Comparison -Sum).Sum}, {($_.Combination | Where-Object Profit -NE 0 | Measure-Object).Count} | Select-Object -First 1 | Select-Object -ExpandProperty Combination
    $BestMiners_Combo | ForEach-Object {$_.Best = $true}
    $BestMiners_Combo_Comparison | ForEach-Object {$_.Best_Comparison = $true}

    #Stop or start miners in the active list depending on if they are the most profitable
    $ActiveMiners | Where-Object {$_.GetActivateCount() -GT 0} | Where-Object Best -EQ $false | ForEach-Object {
        $Miner = $_

        if ($Miner.GetStatus() -eq "Running") {
            Write-Log "Stopping miner ($($Miner.Name)). "
            $Miner.SetStatus("Idle")

            #Remove watchdog timer
            $Miner_Name = $Miner.Name
            $Miner.Algorithm | ForEach-Object {
                $Miner_Algorithm = $_
                $WatchdogTimer = $WatchdogTimers | Where-Object {$_.MinerName -eq $Miner_Name -and $_.PoolName -eq $Pools.$Miner_Algorithm.Name -and $_.Algorithm -eq $Miner_Algorithm}
                if ($WatchdogTimer) {
                    if ($WatchdogTimer.Kicked -lt $Timer.AddSeconds( - $WatchdogInterval)) {
                        $Miner.SetStatus("Failed")
                    }
                    else {
                        $WatchdogTimers = $WatchdogTimers -notmatch $WatchdogTimer
                    }
                }
            }
        }
    }
    write-log -level warn "$(Get-Date) Main script W memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    Get-Process -Name @($ActiveMiners | ForEach-Object {$_.GetProcessNames()}) -ErrorAction Ignore | Select-Object -ExpandProperty ProcessName | Compare-Object @($ActiveMiners | Where-Object Best -EQ $true | Where-Object {$_.GetStatus() -eq "Running"} | ForEach-Object {$_.GetProcessNames()}) | Where-Object SideIndicator -EQ "=>" | Select-Object -ExpandProperty InputObject | Select-Object -Unique | ForEach-Object {Stop-Process -Name $_ -Force -ErrorAction Ignore}
    Start-Sleep $Config.Delay #Wait to prevent BSOD
    write-log -level warn "$(Get-Date) Main script X memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    $ActiveMiners | Where-Object Best -EQ $true | ForEach-Object {
        if ($_.GetStatus() -ne "Running") {
            Write-Log "Starting miner ($($_.Name)): '$($_.Path) $($_.Arguments)'"
            $DecayStart = $Timer
            $_.SetStatus("Running")

            #Add watchdog timer
            if ($Config.Watchdog -and $_.Profit -ne $null) {
                $Miner_Name = $_.Name
                $_.Algorithm | ForEach-Object {
                    $Miner_Algorithm = $_
                    if ($Config.ExcludeWatchdogAlgorithm -inotcontains $Miner_Algorithm -and $Config.ExcludeWatchdogMinerName -inotcontains $Miner_Name) {
                        $WatchdogTimer = $WatchdogTimers | Where-Object {$_.MinerName -eq $Miner_Name -and $_.PoolName -eq $Pools.$Miner_Algorithm.Name -and $_.Algorithm -eq $Miner_Algorithm}
                        if (-not $WatchdogTimer) {
                            $WatchdogTimers += [PSCustomObject]@{
                                MinerName = $Miner_Name
                                PoolName  = $Pools.$Miner_Algorithm.Name
                                Algorithm = $Miner_Algorithm
                                Kicked    = $Timer
                            }
                        }
                        elseif (-not ($WatchdogTimer.Kicked -GT $Timer.AddSeconds( - $WatchdogReset))) {
                            $WatchdogTimer.Kicked = $Timer
                        }
                    }
                }
            }
        }
    }
    write-log -level warn "$(Get-Date) Main script Y memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    if ($Config.MinerStatusURL -and $Config.MinerStatusKey) {& .\ReportStatus.ps1 -Key $Config.MinerStatusKey -WorkerName $Config.WorkerName -ActiveMiners $ActiveMiners -MinerStatusURL $Config.MinerStatusURL}

    #Clear-Host

    #Display mining information
    $Miners | Where-Object {$_.Profit -ge 1E-5 -or $_.Profit -eq $null} | Sort-Object -Descending Type, Profit_Bias | Format-Table -GroupBy Type (
        @{Label = "Miner"; Expression = {$_.Name}}, 
        @{Label = "Algorithm"; Expression = {$_.HashRates.PSObject.Properties.Name}}, 
        @{Label = "Speed"; Expression = {$_.HashRates.PSObject.Properties.Value | ForEach-Object {if ($_ -ne $null) {"$($_ | ConvertTo-Hash)/s"}else {"Benchmarking"}}}; Align = 'right'}, 
        @{Label = "$($Config.Currency | Select-Object -Index 0)/Day"; Expression = {if ($_.Profit) {ConvertTo-LocalCurrency $($_.Profit) $($Rates.$($Config.Currency | Select-Object -Index 0)) -Offset 2} else {"Unknown"}}; Align = "right"},
        @{Label = "Accuracy"; Expression = {$_.Pools.PSObject.Properties.Value.MarginOfError | ForEach-Object {(1 - $_).ToString("P0")}}; Align = 'right'}, 
        @{Label = "$($Config.Currency | Select-Object -Index 0)/GH/Day"; Expression = {$_.Pools.PSObject.Properties.Value.Price | ForEach-Object {ConvertTo-LocalCurrency $($_ * 1000000000) $($Rates.$($Config.Currency | Select-Object -Index 0)) -Offset 2}}; Align = "right"}, 
        @{Label = "Pool"; Expression = {$_.Pools.PSObject.Properties.Value | ForEach-Object {if ($_.Info) {"$($_.Name)-$($_.Info)"}else {"$($_.Name)"}}}}
    ) | Out-Host

    #Display active miners list
    $ActiveMiners | Where-Object {$_.GetActivateCount() -GT 0} | Sort-Object -Property {$_.GetStatus()}, @{Expression = {$_.GetActiveLast()}; Ascending = $false} | Select-Object -First (1 + 6 + 6) | Format-Table -Wrap -GroupBy @{Label = "Status"; Expression = {$_.GetStatus()}} (
        @{Label = "Speed"; Expression = {$_.Speed_Live | ForEach-Object {"$($_ | ConvertTo-Hash)/s"}}; Align = 'right'}, 
        @{Label = "Active"; Expression = {"{0:dd} Days {0:hh} Hours {0:mm} Minutes" -f $_.GetActiveTime()}}, 
        @{Label = "Launched"; Expression = {Switch ($_.GetActivateCount()) {0 {"Never"} 1 {"Once"} Default {"$_ Times"}}}}, 
        @{Label = "Command"; Expression = {"$($_.Path.TrimStart((Convert-Path ".\"))) $($_.Arguments)"}}
    ) | Out-Host

    #Display watchdog timers
    $WatchdogTimers | Where-Object Kicked -GT $Timer.AddSeconds( - $WatchdogReset) | Format-Table -Wrap (
        @{Label = "Miner"; Expression = {$_.MinerName}}, 
        @{Label = "Pool"; Expression = {$_.PoolName}}, 
        @{Label = "Algorithm"; Expression = {$_.Algorithm}}, 
        @{Label = "Watchdog Timer"; Expression = {"{0:n0} Seconds" -f ($Timer - $_.Kicked | Select-Object -ExpandProperty TotalSeconds)}; Align = 'right'}
    ) | Out-Host
    write-log -level warn "$(Get-Date) Main script Z memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"

    $BenchmarksNeeded = ($miners | Where {$_.HashRates.PSObject.Properties.Value -eq $null}).Count
    if($BenchmarksNeeded -gt 0) {
        Write-Host -BackgroundColor Red "Benchmarking: $($BenchmarksNeeded) miners left to benchmark."
    }

    write-log -level warn "$(Get-Date) Main script ZA memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    #Give API access to WatchdogTimers information
    $API.WatchdogTimers = $WatchdogTimers

    #Update API miner information
    $API.ActiveMiners = $ActiveMiners
    $API.RunningMiners = $ActiveMiners | Where-Object {$_.GetStatus() -eq [MinerStatus]::Running}
    $API.FailedMiners = $ActiveMiners | Where-Object {$_.GetStatus() -eq [MinerStatus]::Failed}

    #Reduce Memory
    Get-Job -State Completed | Remove-Job
    [GC]::Collect()
    write-log -level warn "$(Get-Date) Main script ZD memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    #Do nothing for a few seconds as to not overload the APIs and display miner download status
    Write-Log "Start waiting before next run. "
    for ($i = $Strikes; $i -gt 0 -or $Timer -lt $StatEnd; $i--) {
        if ($API.Stop) {Exit}
        Start-Sleep 10
        $Timer = (Get-Date).ToUniversalTime()
    }
    Write-Log "Finish waiting before next run. "
    write-log -level warn "$(Get-Date) Main script ZE memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    #Save current hash rates
    Write-Log "Saving hash rates. "
    $ActiveMiners | ForEach-Object {
        $Miner = $_
        $Miner.Speed_Live = 0
        $Miner_Data = [PSCustomObject]@{}

        if ($Miner.New) {$Miner.Benchmarked++}

        $Miner_Data = $Miner.GetMinerData(($Miner.New -and $Miner.Benchmarked -lt $Strikes))
        $Miner_Data.Lines | ForEach-Object {Write-Log -Level Debug "$($Miner.Name): $_"}

        if ($Miner.GetStatus() -eq "Running") {
            $Miner.Speed_Live = $Miner_Data.HashRate.PSObject.Properties.Value

            $Miner.Algorithm | Where-Object {$Miner_Data.HashRate.$_} | ForEach-Object {
                $Stat = Set-Stat -Name "$($Miner.Name)_$($_)_HashRate" -Value $Miner_Data.HashRate.$_ -Duration $StatSpan -FaultDetection $true

                #Update watchdog timer
                $Miner_Name = $Miner.Name
                $Miner_Algorithm = $_
                $WatchdogTimer = $WatchdogTimers | Where-Object {$_.MinerName -eq $Miner_Name -and $_.PoolName -eq $Pools.$Miner_Algorithm.Name -and $_.Algorithm -eq $Miner_Algorithm}
                if ($Stat -and $WatchdogTimer -and $Stat.Updated -gt $WatchdogTimer.Kicked) {
                    $WatchdogTimer.Kicked = $Stat.Updated
                }

                $Miner.New = $false
            }
        }

        #Benchmark timeout
        if ($Miner.Benchmarked -ge ($Strikes * $Strikes) -or ($Miner.Benchmarked -ge $Strikes -and $Miner.GetActivateCount() -ge $Strikes)) {
            $Miner.Algorithm | Where-Object {-not $Miner_HashRate.$_} | ForEach-Object {
                if ((Get-Stat -Name "$($Miner.Name)_$($_)_HashRate") -eq $null) {
                    $Stat = Set-Stat -Name "$($Miner.Name)_$($_)_HashRate" -Value 0 -Duration $StatSpan
                }
            }
        }
    }
    write-log -level warn "$(Get-Date) Main script ZF memory usage: $((Get-Process -ID $PID | Select-Object -ExpandProperty WorkingSet)/1MB) MB"
    Write-Log "Starting next run. "
}

#Stop the log
Stop-Transcript
