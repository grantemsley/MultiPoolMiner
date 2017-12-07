using module .\Include.psm1

Set-Location (Split-Path $MyInvocation.MyCommand.Path)

#Load information about the miners
$AllMiners = if (Test-Path "Miners") {
	Get-ChildItemContent "Miners" -Parameters @{Pools = $Pools; Stats = $Stats} | ForEach-Object {$_.Content | Add-Member Name $_.Name -PassThru}
}

$Miners = $AllMiners | Select-Object URI, Path, @{name = "Searchable"; expression = {$Miner = $_; ($AllMiners | Where-Object {(Split-Path $_.Path -Leaf) -eq (Split-Path $Miner.Path -Leaf) -and $_.URI -ne $Miner.URI}).Count -eq 0}} -Unique 

ForEach($m in $Miners) {
	if(Test-Path $m.Path) {
		Write-Host $m.Path "already exists"
	} else {
		Write-Host "Downloading $($m.Path) from $($m.URI) "
		.\Downloader.ps1 $m
	}
}
	
    
