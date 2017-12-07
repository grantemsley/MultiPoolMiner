using module .\Include.psm1

Import-Module "$env:Windir\System32\WindowsPowerShell\v1.0\Modules\NetSecurity\NetSecurity.psd1" -ErrorAction Ignore
Import-Module "$env:Windir\System32\WindowsPowerShell\v1.0\Modules\Defender\Defender.psd1" -ErrorAction Ignore

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
	
Write-Verbose 'Unblocking files...'
if (Get-Command "Unblock-File" -ErrorAction SilentlyContinue) {Get-ChildItem . -Recurse | Unblock-File}

Write-Verbose 'Adding exclusions to Windows Defender...'
if ((Get-Command "Get-MpPreference" -ErrorAction SilentlyContinue) -and (Get-MpComputerStatus -ErrorAction SilentlyContinue) -and (Get-MpPreference).ExclusionPath -notcontains (Convert-Path .)) {
    Start-Process (@{desktop = "powershell"; core = "pwsh"}.$PSEdition) "-Command Import-Module '$env:Windir\System32\WindowsPowerShell\v1.0\Modules\Defender\Defender.psd1'; Add-MpPreference -ExclusionPath '$(Convert-Path .)'" -Verb runAs
}
    
