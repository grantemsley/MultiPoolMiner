using module .\Include.psm1

Import-Module .\timer.psm1
#$VerbosePreference = 'Continue'
#$DebugPreference = 'Continue'
$InformationPreference = 'Continue'


$Version = "2.7.2.7"
$Strikes = 3
$SyncWindow = 5 #minutes

#Get miner hw info
$Devices = Get-Devices


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

#Set process priority to BelowNormal to avoid hash rate drops on systems with weak CPUs
(Get-Process -Id $PID).PriorityClass = "BelowNormal"


while ($true) {
time1 "start loop"
	$Config = Get-ChildItemContent "Config.txt" | SElect-Object -ExpandProperty Content

time1 "configure pools"
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
time1 "done configuring pools"
    Get-ChildItem "Miners" | Where-Object {-not $Config.Miners.($_.BaseName)} | ForEach-Object {
        $Config.Miners | Add-Member $_.BaseName (
            [PSCustomObject]@{
            }
        )
    }
time1 "load apis"
    Get-ChildItem "APIs" | ForEach-Object {. $_.FullName}
time1 "timer calcs"
    $Timer = (Get-Date).ToUniversalTime()

    $StatStart = $StatEnd
    $StatEnd = $Timer.AddSeconds($Config.Interval)
    $StatSpan = New-TimeSpan $StatStart $StatEnd

    $DecayExponent = [int](($Timer - $DecayStart).TotalSeconds / $DecayPeriod)

    $WatchdogInterval = ($WatchdogInterval / $Strikes * ($Strikes - 1)) + $StatSpan.TotalSeconds
    $WatchdogReset = ($WatchdogReset / ($Strikes * $Strikes * $Strikes) * (($Strikes * $Strikes * $Strikes) - 1)) + $StatSpan.TotalSeconds
time1 "load stats"
    #Load the stats
    Write-Log "Loading saved statistics. "
    $Stats = Get-Stat

    #Load information about the pools
	time1 "load pools"
    $NewPools = @()
    if (Test-Path "Pools") {
        $NewPools = Get-ChildItem "Pools" -File | Where-Object {$Config.Pools.$($_.BaseName) -and $Config.ExcludePoolName -inotcontains $_.BaseName} | ForEach-Object {
            $Pool_Name = $_.BaseName
            $Pool_Parameters = @{StatSpan = $StatSpan}
            $Config.Pools.$Pool_Name | Get-Member -MemberType NoteProperty | ForEach-Object {$Pool_Parameters.($_.Name) = $Config.Pools.$Pool_Name.($_.Name)}
			time2 "before get-childitemcontent" $_.Name
            Get-ChildItemContent "Pools\$($_.Name)" -Parameters $Pool_Parameters
			time2 "after get-childitemcontent" $_.Name
        } | ForEach-Object {$_.Content | Add-Member Name $_.Name -PassThru}
    }
	time1 "add old pools"
    # This finds any pools that were already in $AllPools (from a previous loop) but not in $NewPools. Add them back to the list. Their API likely didn't return in time, but we don't want to cut them off just yet
    # since mining is probably still working.  Then it filters out any algorithms that aren't being used.
    $AllPools = @($NewPools) + @(Compare-Object @($NewPools | Select-Object -ExpandProperty Name -Unique) @($AllPools | Select-Object -ExpandProperty Name -Unique) | Where-Object SideIndicator -EQ "=>" | Select-Object -ExpandProperty InputObject | ForEach-Object {$AllPools | Where-Object Name -EQ $_}) | 
        Where-Object {$Config.Algorithm.Count -eq 0 -or (Compare-Object $Config.Algorithm $_.Algorithm -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0} | 
        Where-Object {$Config.ExcludeAlgorithm.Count -eq 0 -or (Compare-Object $Config.ExcludeAlgorithm $_.Algorithm -IncludeEqual -ExcludeDifferent | Measure-Object).Count -eq 0} | 
        Where-Object {$Config.ExcludePoolName.Count -eq 0 -or (Compare-Object $Config.ExcludePoolName $_.Name -IncludeEqual -ExcludeDifferent | Measure-Object).Count -eq 0}

	time1 "apply watchdog"
    #Apply watchdog to pools
    $AllPools = $AllPools | Where-Object {
        $Pool = $_
        $Pool_WatchdogTimers = $WatchdogTimers | Where-Object PoolName -EQ $Pool.Name | Where-Object Kicked -LT $Timer.AddSeconds( - $WatchdogInterval) | Where-Object Kicked -GT $Timer.AddSeconds( - $WatchdogReset)
        ($Pool_WatchdogTimers | Measure-Object | Select-Object -ExpandProperty Count) -lt <#stage#>3 -and ($Pool_WatchdogTimers | Where-Object {$Pool.Algorithm -contains $_.Algorithm} | Measure-Object | Select-Object -ExpandProperty Count) -lt <#statge#>2
    }

	
    $Pools = [PSCustomObject]@{}
    Write-Log "Selecting best pool for each algorithm. "
	time1 "algorithm filter"
    $AllPools.Algorithm | ForEach-Object {$_.ToLower()} | 
		Select-Object -Unique | 
		ForEach-Object {
			time2 "pool calc for" $_
			$Pools | 
			Add-Member $_ ($AllPools | 
				Sort-Object -Descending `
					{$Config.PoolName.Count -eq 0 -or (Compare-Object $Config.PoolName $_.Name -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0}, 
					{($Timer - $_.Updated).TotalMinutes -le ($SyncWindow * $Strikes)}, 
					{$_.StablePrice * (1 - $_.MarginOfError)}, 
					{$_.Region -EQ $Config.Region}, 
					{$_.SSL -EQ $Config.SSL} | 
				Where-Object Algorithm -EQ $_ | Select-Object -First 1
			)
			time2 "end pool calc for" $_
		}
	$Pools | Export-clixml poolsbefore.xml

    $Pools = [PSCustomObject]@{}

	time1 "algorithm filter enhanced"
    $AllPools.Algorithm | ForEach-Object {$_.ToLower()} | 
		Select-Object -Unique | 
		ForEach-Object {
			time2 "pool calc enhanced for" $_
			$Pools | 
			Add-Member $_ ($AllPools | Where-Object Algorithm -EQ $_ | 
				Sort-Object -Descending `
					{$Config.PoolName.Count -eq 0 -or (Compare-Object $Config.PoolName $_.Name -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0}, 
					{($Timer - $_.Updated).TotalMinutes -le ($SyncWindow * $Strikes)}, 
					{$_.StablePrice * (1 - $_.MarginOfError)}, 
					{$_.Region -EQ $Config.Region}, 
					{$_.SSL -EQ $Config.SSL} | 
				Select-Object -First 1
			)
			time2 "end pool calc enhanced for" $_
		}	
	
	$Pools | Export-clixml poolsafter.xml
	
	time1 "pool calculation"	
    if (($Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_.Name} | Select-Object -Unique | ForEach-Object {$AllPools | Where-Object Name -EQ $_ | Measure-Object Updated -Maximum | Select-Object -ExpandProperty Maximum} | Measure-Object -Minimum -Maximum | ForEach-Object {$_.Maximum - $_.Minimum} | Select-Object -ExpandProperty TotalMinutes) -gt $SyncWindow) {
		time2 "true start"
        Write-Log -Level Warn "Pool prices are out of sync ($([Int]($Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_} | Measure-Object Updated -Minimum -Maximum | ForEach-Object {$_.Maximum - $_.Minimum} | Select-Object -ExpandProperty TotalMinutes)) minutes). "
        $Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_ | Add-Member Price_Bias ($Pools.$_.StablePrice * (1 - ($Pools.$_.MarginOfError * $Config.SwitchingPrevention * [Math]::Pow($DecayBase, $DecayExponent)))) -Force}
        $Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_ | Add-Member Price_Unbias $Pools.$_.StablePrice -Force}
		time2 "true end"
    }
    else {
		time2 "false start"
        $Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_ | Add-Member Price_Bias ($Pools.$_.Price * (1 - ($Pools.$_.MarginOfError * $Config.SwitchingPrevention * [Math]::Pow($DecayBase, $DecayExponent)))) -Force}
        $Pools | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | ForEach-Object {$Pools.$_ | Add-Member Price_Unbias $Pools.$_.Price -Force}
		time2 "false end"
    }

	time1 "finished calculating pools"
}

#Stop the log
Stop-Transcript
