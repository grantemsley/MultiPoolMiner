$global:Timer1 = [Diagnostics.StopWatch]::StartNew()
$global:Timer2 = [Diagnostics.StopWatch]::StartNew()
$global:Timer1Name = "Start"
$global:Timer2Name = "Start"

Function Time1 {
    Param($Name, $Data)
    Write-Host ("{0,10}ms - {1} {2} to {3} {4}" -f [int]($Timer1.Elapsed).TotalMilliseconds, $Timer1Name, $Timer1Data, $Name, $Data)
    "{0,10}ms - {1} {2} to {3} {4}" -f [int]($Timer1.Elapsed).TotalMilliseconds, $Timer1Name, $Timer1Data, $Name, $Data | Out-File -FilePath "profiledata.txt" -Append -Encoding ascii
    $global:Timer1.Restart()
    $global:Timer1Name = $Name
    $global:Timer1Data = $Data
    # Also reset Timer2
    $global:Timer2.Restart()
    $global:Timer2Name = "Start"
    $global:Timer2Data = ""
}
Function Time2 {
    Param($Name, $Data)
    Write-Host ("{0,20}ms - {1} {2} to {3} {4}" -f [int]($Timer2.Elapsed).TotalMilliseconds, $Timer2Name, $Timer2Data, $Name, $Data)
    "{0,20}ms - {1} {2} to {3} {4}" -f [int]($Timer2.Elapsed).TotalMilliseconds, $Timer2Name, $Timer2Data, $Name, $Data | Out-File -FilePath "profiledata.txt" -Append -Encoding ascii
    $global:Timer2.Restart()
    $global:Timer2Name = $Name
    $global:Timer2Data = $Data
}
