﻿using module .\Include.psm1

$VerbosePreference = 'continue'

If(!(Test-Path -Path '.\Config.ps1')) {
    Throw "Configuration missing!  You must copy Config.sample.ps1 as Config.ps1 and edit the settings."  
} else {
    . .\Config.ps1
}

Set-Location (Split-Path $MyInvocation.MyCommand.Path)


if ($Proxy -eq "") {$PSDefaultParameterValues.Remove("*:Proxy")}
else {$PSDefaultParameterValues["*:Proxy"] = $Proxy}

$Algorithm = $Algorithm | ForEach-Object {Get-Algorithm $_}
If($Algorithm.Count -eq 0) {
    Write-Verbose "Using algorithms:  Any available"
} else {
    Write-Verbose "Using algorithms: $Algorithm"
}

$Region = $Region | ForEach-Object {Get-Region $_}
Write-Verbose "Using region: $Region"

$Strikes = 3

$Timer = (Get-Date).ToUniversalTime()

$StatEnd = $Timer

$DecayStart = $Timer
$DecayPeriod = 60 #seconds
$DecayBase = 1 - 0.1 #decimal percentage

$WatchdogInterval = $Interval * $Strikes
$WatchdogReset = $Interval * $Strikes * $Strikes * $Strikes
$WatchdogTimers = @()

$ActiveMiners = @()

$Rates = [PSCustomObject]@{BTC = [Double]1}

# Make sure the cache directory exists
if (-not (Test-Path "Cache")) {New-Item "Cache" -ItemType "directory" | Out-Null}

#Start the log
Start-Transcript ".\Logs\$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").txt"
#Set donation parameters
if ($Donate -lt 10) {$Donate = 10}
$LastDonated = $Timer.AddDays(-1).AddHours(1)
$WalletDonate = @("1BLXARB3GbKyEg8NTY56me5VXFsX2cixFB", "1Q24z7gHPDbedkaWDTFqhMF8g7iHMehsCb", "1Fonyo1sgJQjEzqp1AxgbHhGkCuNrFt6v9")[[Math]::Floor((Get-Random -Minimum 1 -Maximum 11) / 10)]
$UserNameDonate = @("grantemsley","aaronsace", "fonyo")[[Math]::Floor((Get-Random -Minimum 1 -Maximum 11) / 10)]
$WorkerNameDonate = "multipoolminer"
$WalletBackup = $Wallet
$UserNameBackup = $UserName
$WorkerNameBackup = $WorkerName
while ($true) {

    # Suppress the verbose output this line causes, when it loads the module.
    $oldVerbosePreference = $VerbosePreference
    $VerbosePreference = 'SilentlyContinue'
    Get-ChildItem "APIs" | ForEach-Object {. $_.FullName}
    $VerbosePreference = $oldVerbosePreference


    $Timer = (Get-Date).ToUniversalTime()
    $StatStart = $StatEnd
    $StatEnd = $Timer.AddSeconds($Interval)
    $StatSpan = New-TimeSpan $StatStart $StatEnd

    $DecayExponent = [int](($Timer - $DecayStart).TotalSeconds / $DecayPeriod)

    $WatchdogInterval = ($WatchdogInterval / $Strikes * ($Strikes - 1)) + $StatSpan.TotalSeconds
    $WatchdogReset = ($WatchdogReset / ($Strikes * $Strikes * $Strikes) * (($Strikes * $Strikes * $Strikes) - 1)) + $StatSpan.TotalSeconds
    #Activate or deactivate donation
    if ($Timer.AddDays(-1).AddMinutes($Donate) -ge $LastDonated) {
        $Wallet = $WalletDonate
        $UserName = $UserNameDonate
        $WorkerName = $WorkerNameDonate
    }
    if ($Timer.AddDays(-1) -ge $LastDonated) {
        $Wallet = $WalletBackup
        $UserName = $UserNameBackup
        $WorkerName = $WorkerNameBackup
        $LastDonated = $Timer
    }
    #Update the exchange rates
    Write-Verbose "Updating exchange rates..."
    $NewRates = Invoke-RestMethod "https://api.coinbase.com/v2/exchange-rates?currency=BTC" -UseBasicParsing | Select-Object -ExpandProperty data | Select-Object -ExpandProperty rates
    $Currency | Where-Object {$NewRates.$_} | ForEach-Object {$Rates | Add-Member $_ ([Double]$NewRates.$_) -Force}

    #Load the stats
    Write-Verbose "Loading mining statistics..."
    $Stats = [PSCustomObject]@{}
    if (Test-Path "Stats") {Get-ChildItemContent "Stats" | ForEach-Object {$Stats | Add-Member $_.Name $_.Content}}

    #Load information about the pools
    Write-Verbose "Loading pool information..."
    $NewPools = @()
    if (Test-Path "Pools") {
        # Get all the pool info (algorithm, profitability, host, etc)
        $NewPools = Get-ChildItemContent "Pools" -Parameters @{Wallet = $Wallet; UserName = $UserName; WorkerName = $WorkerName; StatSpan = $StatSpan} | ForEach-Object {$_.Content | Add-Member Name $_.Name -PassThru}
    }

    # Find any pools that were already in $AllPools (from a previous loop) but not in $NewPools. Add them back into the list.  Their API likely didn't return in time, but we don't want to cut them off just yet since mining is likely still working.
    # Then filter out any pools that are for algorithms we aren't using.
    $AllPools = @($NewPools) + @(Compare-Object @($NewPools | Select-Object -ExpandProperty Name -Unique) @($AllPools | Select-Object -ExpandProperty Name -Unique) | Where-Object SideIndicator -EQ "=>" | Select-Object -ExpandProperty InputObject | ForEach-Object {$AllPools | Where-Object Name -EQ $_}) | 
    Where-Object {$Algorithm.Count -eq 0 -or (Compare-Object $Algorithm $_.Algorithm -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0}

    #Apply watchdog to pools
    $AllPools = $AllPools | Where-Object {
        $Pool = $_
        $Pool_WatchdogTimers = $WatchdogTimers | Where-Object PoolName -EQ $Pool.Name | Where-Object Kicked -LT $Timer.AddSeconds( - $WatchdogInterval) | Where-Object Kicked -GT $Timer.AddSeconds( - $WatchdogReset)
        ($Pool_WatchdogTimers | Measure-Object | Select-Object -ExpandProperty Count) -lt <#stage#>3 -and ($Pool_WatchdogTimers | Where-Object {$Pool.Algorithm -contains $_.Algorithm} | Measure-Object | Select-Object -ExpandProperty Count) -lt <#statge#>2
    }

    #Update the active pools
    if ($AllPools.Count -eq 0) {
        Write-Warning "No pools available. "
        Start-Sleep $Interval
        continue
    }
    $Pools = [PSCustomObject]@{}
    # Set $Pools to have the best pool for each algorithm, sorting by pool preference, best price, region, and ssl options then picking the first one.
    Write-Verbose "Selecting best pool for each algorithm..."
    $AllPools.Algorithm | ForEach-Object {$_.ToLower()} | Select-Object -Unique | ForEach-Object {$Pools | Add-Member $_ ($AllPools | Sort-Object -Descending {$PoolName.Count -eq 0 -or (Compare-Object $PoolName $_.Name -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0}, StablePrice, {$_.Region -EQ $Region}, {$_.SSL -EQ $SSL} | Where-Object Algorithm -EQ $_ | Select-Object -First 1)}
    #Set Price_Bias based on either Price, or StablePrice if the prices are out of sync.
    if (($Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_} | Measure-Object Updated -Minimum -Maximum | ForEach-Object {$_.Maximum - $_.Minimum} | Select-Object -ExpandProperty TotalSeconds) -gt $Interval * $Strikes) {
        Write-Warning "Pool prices are out of sync. "
        $Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_ | Add-Member Price_Bias ($Pools.$_.StablePrice * (1 - ($Pools.$_.MarginOfError * [Math]::Pow($DecayBase, $DecayExponent)))) -Force}
    }
    else {
        $Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_ | Add-Member Price_Bias ($Pools.$_.Price * (1 - ($Pools.$_.MarginOfError * [Math]::Pow($DecayBase, $DecayExponent)))) -Force}
    }
    
    #Load information about the miners
    Write-Verbose "Getting miner information..."

    # Get all the miners, get just the .Content property and add the name, select only the ones that match our $Type (CPU, AMD, NVIDIA) or all of them if type is unset,
    # select only the ones that have a HashRate matching our algorithms, and that only include algorithms we have pools for
    # select only the miners that match $MinerName, if specified
    $AllMiners = if (Test-Path "Miners") {
        Get-ChildItemContent "Miners" -Parameters @{Pools = $Pools; Stats = $Stats} | ForEach-Object {$_.Content | Add-Member Name $_.Name -PassThru} | 
        Where-Object {$Type.Count -eq 0 -or (Compare-Object $Type $_.Type -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0} | 
        Where-Object {($Algorithm.Count -eq 0 -or (Compare-Object $Algorithm $_.HashRates.PSObject.Properties.Name | Where-Object SideIndicator -EQ "=>" | Measure-Object).Count -eq 0) -and ((Compare-Object $Pools.PSObject.Properties.Name $_.HashRates.PSObject.Properties.Name | Where-Object SideIndicator -EQ "=>" | Measure-Object).Count -eq 0)} | 
        Where-Object {$MinerName.Count -eq 0 -or (Compare-Object $MinerName $_.Name -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0}
    }
    Write-Verbose "Calculating profit for each miner..."
    $AllMiners | ForEach-Object {
        $Miner = $_

        $Miner_HashRates = [PSCustomObject]@{}
        $Miner_Pools = [PSCustomObject]@{}
        $Miner_Pools_Comparison = [PSCustomObject]@{}
        $Miner_Profits = [PSCustomObject]@{}
        $Miner_Profits_Comparison = [PSCustomObject]@{}
        $Miner_Profits_MarginOfError = [PSCustomObject]@{}
        $Miner_Profits_Bias = [PSCustomObject]@{}

        $Miner_Types = $Miner.Type | Select-Object -Unique
        $Miner_Indexes = $Miner.Index | Select-Object -Unique
        $Miner_Devices = $Miner.Device | Select-Object -Unique

        # Calculate the profit for each algorithm this miner does
        $Miner.HashRates.PSObject.Properties.Name | ForEach-Object { #temp fix, must use 'PSObject.Properties' to preserve order
            $Miner_HashRates | Add-Member $_ ([Double]$Miner.HashRates.$_)
            $Miner_Pools | Add-Member $_ ([PSCustomObject]$Pools.$_)
            $Miner_Pools_Comparison | Add-Member $_ ([PSCustomObject]$Pools.$_)
            $Miner_Profits | Add-Member $_ ([Double]$Miner.HashRates.$_ * $Pools.$_.Price)
            $Miner_Profits_Comparison | Add-Member $_ ([Double]$Miner.HashRates.$_ * $Pools.$_.StablePrice)
            $Miner_Profits_Bias | Add-Member $_ ([Double]$Miner.HashRates.$_ * $Pools.$_.Price_Bias)
        }

        # Calculate the overall profit for the miner
        $Miner_Profit = [Double]($Miner_Profits.PSObject.Properties.Value | Measure-Object -Sum).Sum
        $Miner_Profit_Comparison = [Double]($Miner_Profits_Comparison.PSObject.Properties.Value | Measure-Object -Sum).Sum
        $Miner_Profit_Bias = [Double]($Miner_Profits_Bias.PSObject.Properties.Value | Measure-Object -Sum).Sum

        # Calculate margin of error
        $Miner.HashRates | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {
            $Miner_Profits_MarginOfError | Add-Member $_ ([Double]$Pools.$_.MarginOfError * (& {if ($Miner_Profit) {([Double]$Miner.HashRates.$_ * $Pools.$_.StablePrice) / $Miner_Profit}else {1}}))
        }

        $Miner_Profit_MarginOfError = [Double]($Miner_Profits_MarginOfError.PSObject.Properties.Value | Measure-Object -Sum).Sum

        # If any of the algorithms don't have a hashrate set, set all the profit calculations to $null
        $Miner.HashRates | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {
            if (-not [String]$Miner.HashRates.$_) {
                $Miner_HashRates.$_ = $null
                $Miner_Profits.$_ = $null
                $Miner_Profits_Comparison.$_ = $null
                $Miner_Profits_Bias.$_ = $null
                $Miner_Profit = $null
                $Miner_Profit_Comparison = $null
                $Miner_Profits_MarginOfError = $null
                $Miner_Profit_Bias = $null
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
        $Miner | Add-Member Profit $Miner_Profit
        $Miner | Add-Member Profit_Comparison $Miner_Profit_Comparison
        $Miner | Add-Member Profit_MarginOfError $Miner_Profit_MarginOfError
        $Miner | Add-Member Profit_Bias $Miner_Profit_Bias

        $Miner | Add-Member Type ($Miner_Types | Sort-Object) -Force
        $Miner | Add-Member Index ($Miner_Indexes | Sort-Object) -Force

        $Miner | Add-Member Device ($Miner_Devices | Sort-Object) -Force
        $Miner | Add-Member Device_Auto (($Miner_Devices -eq $null) | Sort-Object) -Force

        $Miner.Path = (Resolve-Path($Miner.Path)).Path

        if (-not $Miner.API) {$Miner | Add-Member API "Miner" -Force}
    }
    # Remove any miners where the file is missing.
    $Miners = $AllMiners | Where-Object {Test-Path $_.Path}

    if(($AllMiners | Where-Object {!(Test-Path $_.Path)}).Count -gt 0) {
        Write-Warning "Some miners disabled because not installed (run GetMiners.ps1 to install):"
        $AllMiners | Where-Object {!(Test-Path $_.Path)} | Sort Path -Unique | ft Path, URI
    }


    #Apply watchdog to miners
    $Miners = $Miners | Where-Object {
        $Miner = $_
        $Miner_WatchdogTimers = $WatchdogTimers | Where-Object MinerName -EQ $Miner.Name | Where-Object Kicked -LT $Timer.AddSeconds( - $WatchdogInterval) | Where-Object Kicked -GT $Timer.AddSeconds( - $WatchdogReset)
        ($Miner_WatchdogTimers | Measure-Object | Select-Object -ExpandProperty Count) -lt <#stage#>2 -and ($Miner_WatchdogTimers | Where-Object {$Miner.HashRates.PSObject.Properties.Name -contains $_.Algorithm} | Measure-Object | Select-Object -ExpandProperty Count) -lt <#stage#>1
    }

    #Update the active miners
    if ($Miners.Count -eq 0) {
        Write-Warning "No miners available. "
        Start-Sleep $Interval
        continue
    }
    $ActiveMiners | ForEach-Object {
        $_.Profit = 0
        $_.Profit_Comparison = 0
        $_.Profit_MarginOfError = 0
        $_.Profit_Bias = 0
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
                Speed                = $Miner.HashRates.PSObject.Properties.Value #temp fix, must use 'PSObject.Properties' to preserve order
                Speed_Live           = 0
                Best                 = $false
                Best_Comparison      = $false
                Process              = $null
                New                  = $false
                Active               = [TimeSpan]0
                Activated            = 0
                Status               = ""
                Benchmarked          = 0
            }
        }
    }
    $ActiveMiners | Where-Object Device_Auto | ForEach-Object {
        $Miner = $_
        $Miner.Device = ($Miners | Where-Object {(Compare-Object $Miner.Type $_.Type -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0}).Device | Select-Object -Unique | Sort-Object
        if ($Miner.Device -eq $null) {$Miner.Device = ($Miners | Where-Object {(Compare-Object $Miner.Type $_.Type -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0}).Type | Select-Object -Unique | Sort-Object}
    }

    #Don't penalize active miners
    $ActiveMiners | Where-Object Status -EQ "Running" | ForEach-Object {$_.Profit_Bias = $_.Profit}

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
    $BestMiners_Combo = $BestMiners_Combos | Sort-Object -Descending {($_.Combination | Where-Object Profit -EQ $null | Measure-Object).Count}, {($_.Combination | Measure-Object Profit_Bias -Sum).Sum}, {($_.Combination | Where-Object Profit -NE 0 | Measure-Object).Count} | Select-Object -First 1 | Select-Object -ExpandProperty Combination
    $BestMiners_Combo_Comparison = $BestMiners_Combos_Comparison | Sort-Object -Descending {($_.Combination | Where-Object Profit -EQ $null | Measure-Object).Count}, {($_.Combination | Measure-Object Profit_Comparison -Sum).Sum}, {($_.Combination | Where-Object Profit -NE 0 | Measure-Object).Count} | Select-Object -First 1 | Select-Object -ExpandProperty Combination
    $BestMiners_Combo | ForEach-Object {$_.Best = $true}
    $BestMiners_Combo_Comparison | ForEach-Object {$_.Best_Comparison = $true}
    
    #Stop or start miners in the active list depending on if they are the most profitable
    $ActiveMiners | Where-Object Activated -GT 0 | Where-Object Best -EQ $false | ForEach-Object {
        $Miner = $_

        if ($Miner.Process -eq $null -or $Miner.Process.HasExited) {
            if ($Miner.Status -eq "Running") {$Miner.Status = "Failed"}
        }
        else {
            $Miner.Process.CloseMainWindow() | Out-Null
            $Miner.Status = "Idle"

            #Remove watchdog timer
            $Miner_Name = $Miner.Name
            $Miner.Algorithm | ForEach-Object {
                $Miner_Algorithm = $_
                $WatchdogTimer = $WatchdogTimers | Where-Object {$_.MinerName -eq $Miner_Name -and $_.PoolName -eq $Pools.$Miner_Algorithm.Name -and $_.Algorithm -eq $Miner_Algorithm}
                if ($WatchdogTimer) {
                    if ($WatchdogTimer.Kicked -lt $Timer.AddSeconds( - $WatchdogInterval)) {
                        $Miner.Status = "Failed"
                    }
                    else {
                        $WatchdogTimers = $WatchdogTimers -notmatch $WatchdogTimer
                    }
                }
            }
        }
    }
	
    Start-Sleep $Delay #Wait to prevent BSOD
    $ActiveMiners | Where-Object Best -EQ $true | ForEach-Object {
        if ($_.Process -eq $null -or $_.Process.HasExited -ne $false) {
            $DecayStart = $Timer
            $_.New = $true
            $_.Activated++
            if ($_.Process -ne $null) {$_.Active += $_.Process.ExitTime - $_.Process.StartTime}
            if ($_.Wrap) {$_.Process = Start-Process -FilePath (@{desktop = "powershell"; core = "pwsh"}.$PSEdition) -ArgumentList "-executionpolicy bypass -command . '$(Convert-Path ".\Wrapper.ps1")' -ControllerProcessID $PID -Id '$($_.Port)' -FilePath '$($_.Path)' -ArgumentList '$($_.Arguments)' -WorkingDirectory '$(Split-Path $_.Path)'" -PassThru
            }
            else {$_.Process = Start-SubProcess -FilePath $_.Path -ArgumentList $_.Arguments -WorkingDirectory (Split-Path $_.Path) -Priority ($_.Type | ForEach-Object {if ($_ -eq "CPU") {-2}else {-1}} | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum)}
            if ($_.Process -eq $null) {$_.Status = "Failed"}
            else {$_.Status = "Running"}

            #Add watchdog timer
            if ($Watchdog -and $_.Profit -ne $null) {
                $Miner_Name = $_.Name
                $_.Algorithm | ForEach-Object {
                    $Miner_Algorithm = $_
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
  
    #Display mining information
    #Clear-Host
    $Miners | Where-Object {$_.Profit -ge 1E-5 -or $_.Profit -eq $null} | Sort-Object -Descending Type, Profit | Format-Table -GroupBy Type (
        @{Label = "Miner"; Expression = {$_.Name}}, 
        @{Label = "Algorithm"; Expression = {$_.HashRates.PSObject.Properties.Name}}, 
        @{Label = "Speed"; Expression = {$_.HashRates.PSObject.Properties.Value | ForEach-Object {if ($_ -ne $null) {"$($_ | ConvertTo-Hash)/s"}else {"Benchmarking"}}}; Align = 'right'}, 
        @{Label = "BTC/Day"; Expression = {$_.Profits.PSObject.Properties.Value | ForEach-Object {if ($_ -ne $null) {$_.ToString("N5")}else {"Benchmarking"}}}; Align = 'right'}, 
        @{Label = "BTC/GH/Day"; Expression = {$_.Pools.PSObject.Properties.Value.Price | ForEach-Object {($_ * 1000000000).ToString("N5")}}; Align = 'right'}, 
        @{Label = "Pool"; Expression = {$_.Pools.PSObject.Properties.Value | ForEach-Object {if ($_.Info) {"$($_.Name)-$($_.Info)"}else {"$($_.Name)"}}}}
    ) | Out-Host

    #Display active miners list
    $ActiveMiners | Where-Object Activated -GT 0 | Sort-Object -Descending Status, {if ($_.Process -eq $null) {[DateTime]0}else {$_.Process.StartTime}} | Select-Object -First (1 + 6 + 6) | Format-Table -Wrap -GroupBy Status (
        @{Label = "Speed"; Expression = {$_.Speed_Live | ForEach-Object {"$($_ | ConvertTo-Hash)/s"}}; Align = 'right'}, 
        @{Label = "Active"; Expression = {"{0:dd} Days {0:hh} Hours {0:mm} Minutes" -f $(if ($_.Process -eq $null) {$_.Active}else {if ($_.Process.ExitTime -gt $_.Process.StartTime) {($_.Active + ($_.Process.ExitTime - $_.Process.StartTime))}else {($_.Active + ((Get-Date) - $_.Process.StartTime))}})}}, 
        @{Label = "Launched"; Expression = {Switch ($_.Activated) {0 {"Never"} 1 {"Once"} Default {"$_ Times"}}}}, 
        @{Label = "Command"; Expression = {"$($_.Path.TrimStart((Convert-Path ".\"))) $($_.Arguments)"}}
    ) | Out-Host

    # Display miner current profit
    $ActiveMiners | Where-Object {$_.Activated -GT 0 -and $_.Status -eq "Running"} | Format-Table -Wrap (
        @{Label = "Name"; Expression = {$_.Name}},
        @{Label = "Current Speed"; Expression = {$_.Speed_Live | Foreach-Object {"$($_ | ConvertTo-Hash)/s"}}; Align = 'right'},
        @{Label = "Estimated Speed"; Expression = {$_.Speed | Foreach-Object {"$($_ | ConvertTo-Hash)/s"}}; Align = 'right'},
        @{Label = "Estimated BTC/day"; Expression = {"{0:N8}" -f $_.Profit}; Align='right'},
        @{Label = "Estimated CAD/day"; Expression = {"{0:N4}" -f ($_.Profit*$Rates.CAD)}; Align='right'}

    ) | Out-Host



    # Print Balances
    $Balances = Get-Balances -Wallet $Wallet -API_Key $API_Key -Rates $Rates
    $Balances | ft *
    $Rates.PsObject.Properties.Name | Foreach-Object {
        Write-Host -ForegroundColor Green "Total $_ :" ($Balances | Measure-Object -sum "Total_$_").sum
    }


    #Display watchdog timers
    $WatchdogTimers | Where-Object Kicked -GT $Timer.AddSeconds( - $WatchdogReset) | Format-Table -Wrap (
        @{Label = "Miner"; Expression = {$_.MinerName}}, 
        @{Label = "Pool"; Expression = {$_.PoolName}}, 
        @{Label = "Algorithm"; Expression = {$_.Algorithm}}, 
        @{Label = "Watchdog Timer"; Expression = {"{0:n0} Seconds" -f ($Timer - $_.Kicked | Select-Object -ExpandProperty TotalSeconds)}; Align = 'right'}
    ) | Out-Host

    #Display profit comparison
    if (($BestMiners_Combo | Where-Object Profit -EQ $null | Measure-Object).Count -eq 0) {
        $MinerComparisons = 
        [PSCustomObject]@{"Miner" = "MultiPoolMiner"}, 
        [PSCustomObject]@{"Miner" = $BestMiners_Combo_Comparison | ForEach-Object {"$($_.Name)-$($_.Algorithm -join "/")"}}

        $BestMiners_Combo_Stat = Set-Stat -Name "Profit" -Value ($BestMiners_Combo | Measure-Object Profit -Sum).Sum -Duration $StatSpan

        $MinerComparisons_Profit = $BestMiners_Combo_Stat.Week, ($BestMiners_Combo_Comparison | Measure-Object Profit_Comparison -Sum).Sum

        $MinerComparisons_MarginOfError = $BestMiners_Combo_Stat.Week_Fluctuation, ($BestMiners_Combo_Comparison | ForEach-Object {$_.Profit_MarginOfError * (& {if ($MinerComparisons_Profit[1]) {$_.Profit_Comparison / $MinerComparisons_Profit[1]}else {1}})} | Measure-Object -Sum).Sum

        $Currency | ForEach-Object {
            $MinerComparisons[0] | Add-Member $_.ToUpper() ("{0:N5} $([Char]0x00B1){1:P0} ({2:N5}-{3:N5})" -f ($MinerComparisons_Profit[0] * $Rates.$_), $MinerComparisons_MarginOfError[0], (($MinerComparisons_Profit[0] * $Rates.$_) / (1 + $MinerComparisons_MarginOfError[0])), (($MinerComparisons_Profit[0] * $Rates.$_) * (1 + $MinerComparisons_MarginOfError[0])))
            $MinerComparisons[1] | Add-Member $_.ToUpper() ("{0:N5} $([Char]0x00B1){1:P0} ({2:N5}-{3:N5})" -f ($MinerComparisons_Profit[1] * $Rates.$_), $MinerComparisons_MarginOfError[1], (($MinerComparisons_Profit[1] * $Rates.$_) / (1 + $MinerComparisons_MarginOfError[1])), (($MinerComparisons_Profit[1] * $Rates.$_) * (1 + $MinerComparisons_MarginOfError[1])))
        }

        if ($MinerComparisons_Profit[0] -gt $MinerComparisons_Profit[1]) {
            $MinerComparisons_Range = ($MinerComparisons_MarginOfError | Measure-Object -Average | Select-Object -ExpandProperty Average), (($MinerComparisons_Profit[0] - $MinerComparisons_Profit[1]) / $MinerComparisons_Profit[1]) | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum
            Write-Host -BackgroundColor Yellow -ForegroundColor Black "MultiPoolMiner is between $([Math]::Round((((($MinerComparisons_Profit[0]-$MinerComparisons_Profit[1])/$MinerComparisons_Profit[1])-$MinerComparisons_Range)*100)))% and $([Math]::Round((((($MinerComparisons_Profit[0]-$MinerComparisons_Profit[1])/$MinerComparisons_Profit[1])+$MinerComparisons_Range)*100)))% more profitable than the fastest miner: "
        }

        $MinerComparisons | Out-Host
    }


    #Reduce Memory
    Get-Job -State Completed | Remove-Job
    [GC]::Collect()

    #Do nothing for a few seconds as to not overload the APIs and display miner download status
    for ($i = $Strikes; $i -gt 0 -or $Timer -lt $StatEnd; $i--) {
        Start-Sleep 10
        $Timer = (Get-Date).ToUniversalTime()
    }

    #Save current hash rates
    $ActiveMiners | ForEach-Object {
        $Miner = $_
        $Miner.Speed_Live = 0
        $Miner_HashRate = [PSCustomObject]@{}

        if ($Miner.New) {$Miner.Benchmarked++}

        if ($Miner.Process -and -not $Miner.Process.HasExited) {
            $Miner_HashRate = $Miner.GetHashRate($Miner.Algorithm, ($Miner.New -and $Miner.Benchmarked -lt $Strikes))
            $Miner.Speed_Live = $Miner_HashRate.PSObject.Properties.Value

            $Miner.Algorithm | Where-Object {$Miner_HashRate.$_} | ForEach-Object {
                $Stat = Set-Stat -Name "$($Miner.Name)_$($_)_HashRate" -Value $Miner_HashRate.$_ -Duration $StatSpan -FaultDetection $true

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
        if ($Miner.Benchmarked -ge ($Strikes * $Strikes) -or ($Miner.Benchmarked -ge $Strikes -and $Miner.Activated -ge $Strikes)) {
            $Miner.Algorithm | Where-Object {-not $Miner_HashRate.$_} | ForEach-Object {
                if ((Get-Stat "$($Miner.Name)_$($_)_HashRate") -eq $null) {
                    $Stat = Set-Stat -Name "$($Miner.Name)_$($_)_HashRate" -Value 0 -Duration $StatSpan
                }
            }
        }
    }
}

#Stop the log
Stop-Transcript
