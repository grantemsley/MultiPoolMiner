[CmdletBinding()]Param()
# GUI Launcher for MultiPoolMiner

# Setup a few synchronized hashtables for sharing data between threads.
# These use the the .NET 1/2 collections described here: https://docs.microsoft.com/en-us/dotnet/standard/collections/thread-safe/
# It's important to note that these lock the entire collection when adding or removing data, which makes any other thread trying to access it have to wait
# That's why it's split into several different collections - to minimize the amount of waiting that has to be done

# Controls holds the WPF control objects
$Controls = [hashtable]::Synchronized(@{})
# State holds information about the configuration and current state of the launcher
$State = [hashtable]::Synchronized(@{})
# Errors holds the $error variable from each thread, so they can be viewed when debugging
$Errors = [hashtable]::Synchronized(@{})

Set-Location -Path (Split-Path -Path $MyInvocation.MyCommand.Path)

# Setup a runspace
$newRunspace = [runspacefactory]::CreateRunspace()
$newRunspace.ApartmentState = 'STA'
$newRunspace.ThreadOptions = 'ReuseThread'
$newRunspace.Open()
$newRunspace.SessionStateProxy.SetVariable('Controls', $Controls)
$newRunspace.SessionStateProxy.SetVariable('State', $State)
$newRunspace.SessionStateProxy.SetVariable('Errors', $Errors)
$newRunspace.SessionStateProxy.Path.SetLocation($pwd)

# Script for the main GUI thread, which also spawns a few threads of its own
$guiCmd = [PowerShell]::Create().AddScript{
    Import-Module .\Include.psm1
    Add-Type -AssemblyName PresentationFramework, System.Drawing, System.Windows.Forms, WindowsFormsIntegration
    # Load settings
    If (Test-Path -Path '.\launchersettings.json') {
        $State.Settings = Get-Content -Path '.\launchersettings.json' | ConvertFrom-Json
    } else {
        $State.Settings = [pscustomobject]@{
            'IdleDelay' = 120
            'StartWhenIdle' = $False
        }
    }

    #region Load window
    # Get XAML and create a window
    Add-Type -AssemblyName PresentationFramework
    [xml]$xaml = [xml](Get-Content -Path 'Launcher.xaml')
    $reader = (New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $xaml)
    $Controls.Window = [Windows.Markup.XamlReader]::Load($reader)
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object{
        #Find all of the form types and add them as members to the Window
        $Controls.Add($_.Name,$Controls.Window.FindName($_.Name) )
    }
    #endregion Load window

    # Set control values
    $Controls.IdleDelay.Text = $State.Settings.IdleDelay
    $Controls.StartWhenIdle.IsChecked = $State.Settings.StartWhenIdle

    # Set variables
    $State.Running = $false
    $State.ManualStart = $false
    $State.MultiPoolMinerProcess = $null
    $State.Config = Get-ChildItemContent 'Config.txt' | Select-Object -ExpandProperty Content

    # Setup functions for buttons
    $Controls.Window.Add_Closing{
        [Windows.Forms.Application]::Exit()
    }

    $Controls.StartStop.add_Click{
        if($State.Running) {
            $State.Running = $false
            $State.ManualStart = $false
            $Controls.StatusText.Dispatcher.Invoke([action]{$Controls.StatusText.Text = 'Stopped'})
            $Controls.StartStop.Dispatcher.Invoke([action]{$Controls.StartStop.Content = 'Start Mining'})
        } else {
            $State.Running = $true
            $State.ManualStart = $true
            $Controls.StatusText.Dispatcher.Invoke([action]{$Controls.StatusText.Text = 'Running'})
            $Controls.StartStop.Dispatcher.Invoke([action]{$Controls.StartStop.Content = 'Stop Mining'})
        }
    }

    $Controls.IdleDelay.add_TextChanged{
        $State.Settings.IdleDelay = $Controls.IdleDelay.Text
        $State.Settings | ConvertTo-Json | Out-File -FilePath '.\Launchersettings.json'
    }

    $Controls.StartWhenIdle.add_Checked{
        $State.Settings.StartWhenIdle = $Controls.StartWhenIdle.IsChecked
        $State.Settings | ConvertTo-Json | Out-File -FilePath '.\Launchersettings.json'
    }

    $Controls.StartWhenIdle.add_Unchecked{
        $State.Settings.StartWhenIdle = $Controls.StartWhenIdle.IsChecked
        $State.Settings | ConvertTo-Json | Out-File -FilePath '.\Launchersettings.json'
    }

    $Controls.ShowWebInterface.add_Click{
        if($State.Running -eq $false) {
            [System.Windows.MessageBox]::Show('Web interface only runs when mining. Start mining first.')
        } else {
            Start-Process -FilePath 'http://localhost:3999'
        }
    }

    $Controls.ShowMonitoringSite.add_Click{
        $url = $State.Config.MinerStatusURL.Substring(0, $State.Config.MinerStatusURL.lastIndexOf('/')) + "/?address=$($State.Config.MinerStatusKey)"
        Start-Process -FilePath $url
    }

    $Controls.EditConfig.add_Click{
        Start-Process -FilePath .\config.txt
    }

    # Stop mining if the window is closed
    $Controls.Window.Add_Closed({
        $State.Running = $false
        $State.GUIRunning = $false
        if($State.MultiPoolMinerProcess -and $State.MultiPoolMinerProcess.HasExited -eq $false) {
            $State.MultiPoolMinerProcess.CloseMainWindow()
        }
    })


    #region Create multipoolminer script runner thread...
    # This thread is responsible for starting the script when $State.Running = $true, and stopping it when it's $false.
    # The Running flag is set by both the StartStop button and the idle monitoring thread.
    # It also monitors the script and restarts it if closed unexpectedly, and stopping any rogue miners that keep going after the script is closed.
    $newRunspace = [runspacefactory]::CreateRunspace()
    $newRunspace.ApartmentState = 'STA'
    $newRunspace.ThreadOptions = 'ReuseThread'
    $newRunspace.Open()
    $newRunspace.SessionStateProxy.SetVariable('State', $State)
    $newRunspace.SessionStateProxy.SetVariable('Errors', $Errors)
    $newRunspace.SessionStateProxy.Path.SetLocation($pwd)

    $scriptRunner = [PowerShell]::Create().AddScript{
        While ($State.GUIRunning) {
            If($State.Running) {
                # Start script if it is not running
                If($State.MultiPoolMinerProcess -and $State.MultiPoolMinerProcess.HasExited -eq $false) {
                    # Script is already running, do nothing
                } else {
                    # Start the script
                    $FilePath = 'pwsh.exe'
                    $ArgumentList = "-executionpolicy bypass `"$(Convert-Path -Path '.\MultiPoolMiner.ps1')`""

                    $Job = Start-Job -ArgumentList $PID, $FilePath, $ArgumentList, $PWD -ScriptBlock {
                        param($ControllerProcessID, $FilePath, $ArgumentList, $WorkingDirectory)
                        $ControllerProcess = Get-Process -Id $ControllerProcessID
                        if ($ControllerProcess -eq $null) {return}

                        $ProcessParam = @{}
                        $ProcessParam.Add('FilePath', $FilePath)
                        $ProcessParam.Add('WindowStyle', 'Minimized')
                        if ($ArgumentList -ne '') {$ProcessParam.Add('ArgumentList', $ArgumentList)}
                        if ($WorkingDirectory -ne '') {$ProcessParam.Add('WorkingDirectory', $WorkingDirectory)}
                        $Process = Start-Process @ProcessParam -PassThru
                        if ($Process -eq $null) {
                            [PSCustomObject]@{ProcessId = $null}
                            return
                        }

                        [PSCustomObject]@{
                            ProcessId = $Process.Id
                            ProcessHandle = $Process.Handle
                        }

                        $ControllerProcess.Handle | Out-Null
                        $Process.Handle | Out-Null

                        do {if ($ControllerProcess.WaitForExit(1000)) {$Process.CloseMainWindow() | Out-Null}}
                        while ($Process.HasExited -eq $false)
                    }
                    do {Start-Sleep -Seconds 1; $JobOutput = Receive-Job -Job $Job} while ($JobOutput -eq $null)

                    $State.MultiPoolMinerProcess = Get-Process -Id $JobOutput.ProcessId
                    $State.MultiPoolMinerHandle = $JobOutput.Handle
                }
            } else {
                # Close script if it is running
                if($State.MultiPoolMinerProcess -and $State.MultiPoolMinerProcess.HasExited -eq $false) {
                    $State.MultiPoolMinerProcess.CloseMainWindow()
                    Start-Sleep -Seconds 5
                    # Kill any miners that are didn't exit properly
                    Get-Process | Where-Object {$_.Path -like "$($PWD)\Bin\*"} | Stop-Process
                }
            }

            $Errors.ScriptRunner = $Error
            Start-Sleep 1
        }
        # GUI no longer running, kill any miners that still are
        Get-Process | Where-Object {$_.Path -like "$($PWD)Bin\*"} | Stop-Process

    }
    $scriptrunner.Runspace = $newRunspace
    $ScriptRunnerThread = $scriptrunner.BeginInvoke()
    #endregion Create multipoolminer script runner thread...

    #region Create idle monitoring
    $newRunspace = [runspacefactory]::CreateRunspace()
    $newRunspace.ApartmentState = 'STA'
    $newRunspace.ThreadOptions = 'ReuseThread'
    $newRunspace.Open()
    $newRunspace.SessionStateProxy.SetVariable('Controls', $Controls)
    $newRunspace.SessionStateProxy.SetVariable('State', $State)
    $idlemonitor = [PowerShell]::Create().AddScript{
        # There is no powershell native way to check how long the system has been idle.  Have to use .NET code to do it.
        Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
namespace PInvoke.Win32 {
    public static class UserInput {
        [DllImport("user32.dll", SetLastError=false)]
        private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

        [StructLayout(LayoutKind.Sequential)]
        private struct LASTINPUTINFO {
            public uint cbSize;
            public int dwTime;
        }

        public static DateTime LastInput {
            get {
                DateTime bootTime = DateTime.UtcNow.AddMilliseconds(-Environment.TickCount);
                DateTime lastInput = bootTime.AddMilliseconds(LastInputTicks);
                return lastInput;
            }
        }
        public static TimeSpan IdleTime {
            get {
                return DateTime.UtcNow.Subtract(LastInput);
            }
        }
        public static int LastInputTicks {
            get {
                LASTINPUTINFO lii = new LASTINPUTINFO();
                lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
                GetLastInputInfo(ref lii);
                return lii.dwTime;
            }
        }
    }
}
'@
        While ($State.GUIRunning) {
            $IdleSeconds = [math]::Round(([PInvoke.Win32.UserInput]::IdleTime).TotalSeconds)
            $Controls.IdleTime.Dispatcher.Invoke([action]{$Controls.IdleTime.Text = "$($IdleSeconds)s"}, "Background")

            # Start mining if idle long enough
            if($State.Settings.StartWhenIdle -and !$State.Running -and $IdleSeconds -gt $State.Settings.IdleDelay) {
                $State.ManualStart = $false
                $State.Running = $true
                $Controls.StatusText.Dispatcher.Invoke([action]{$Controls.StatusText.Text = 'Running (Idle)'})
            }

            # Stop mining if no longer idle, and mining was not manually started
            if($State.Running -and !$State.ManualStart -and $IdleSeconds -lt $State.Settings.IdleDelay) {
                $State.Running = $false
                $Controls.StatusText.Dispatcher.Invoke([action]{$Controls.StatusText.Text = 'Stopped'})
            }

            Start-Sleep -Seconds 1
        }
    }
    $idlemonitor.Runspace = $newRunspace
    $IdleMonitorThread = $IdleMonitor.BeginInvoke()
    #endregion Create idle monitoring

    #region Create remote worker thread
    $newRunspace = [runspacefactory]::CreateRunspace()
    $newRunspace.ApartmentState = 'STA'
    $newRunspace.ThreadOptions = 'ReuseThread'
    $newRunspace.Open()
    $newRunspace.SessionStateProxy.SetVariable('State', $State)
    $newRunspace.SessionStateProxy.SetVariable('Controls', $Controls)
    $newRunspace.SessionStateProxy.SetVariable('Errors', $Errors)
    $newRunspace.SessionStateProxy.Path.SetLocation($pwd)
    $remoteworker = [PowerShell]::Create().AddScript{
        While ($State.GUIRunning) {
            If($State.Config.MinerStatusURL -and $State.Config.MinerStatusKey) {
                Try {
                    $apiurl = $State.Config.MinerStatusURL.Substring(0, $State.Config.MinerStatusURL.lastIndexOf('/')) + "/stats.php?address=$($State.Config.MinerStatusKey)"
                    $Remoteminers = Invoke-RestMethod -Uri $apiurl -ErrorAction Stop -TimeoutSec 30

                    If($RemoteMiners -eq $null) {
                        Throw 'Monitoring API returned nothing.'
                    }

                    If($Remoteminers.PSObject.Properties.Name -Match 'error') {
                        Throw $Remoteminers.error
                    }

                    $Remoteminers | Foreach-Object {
                        # Convert last seen to a datetime, accounting for timezone differences (timestamp is always in UTC)
                        $lastseen = [TimeZone]::CurrentTimeZone.ToLocalTime(([datetime]'1/1/1970').AddSeconds($_.lastseen))
                        $now = Get-Date
                        $timebetween = New-TimeSpan -Start $lastseen -End $now
                        # Set online/offline status
                        if ($timebetween.TotalSeconds -gt 300) {
                            $_ | Add-Member Status 'Offline'
                        } else {
                            $_ | Add-Member Status 'Online'
                        }
                        # Set time since last seen
                        if ($timebetween.Days -gt 1) {
                            $_ | Add-Member TimeSinceLastSeen ('{0:N0} days ago' -f $timebetween.TotalDays)
                        } elseif ($timebetween.Hours -gt 1) {
                            $_ | Add-Member TimeSinceLastSeen ('{0:N0} hours ago' -f $timebetween.TotalHours)
                        } elseif ($timebetween.Minutes -gt 1) {
                            $_ | Add-Member TimeSinceLastSeen ('{0:N0} minutes ago' -f $timebetween.TotalMinutes)
                        } else {
                            $_ | Add-Member TimeSinceLastSeen ('{0:N0} seconds ago' -f $timebetween.TotalSeconds)
                        }
                        # Format profit to 8 digits
                        $_.Profit = '{0:N8}' -f $_.Profit
                    }

                    # Calculate totals for status bar
                    $RemoteMinerProfit = "BTC: $(($Remoteminers | Where-Object {$_.Status -eq 'Online'} | Measure-Object -Sum -Property Profit).Sum)"

                    $OnlineWorkers = ($RemoteMiners | Where-Object {$_.Status -eq 'Online'} | Measure-Object).Count
                    $TotalWorkers = ($RemoteMiners | Measure-Object).Count
                    $RemoteMinerStatus = "$OnlineWorkers/$TotalWorkers online"

                    # Add the total lines
                    $Remoteminers += [pscustomobject]@{WorkerName = '-----'; Status='-----'}

                    $Remoteminers += [pscustomobject]@{
                        WorkerName='Total (Online only)'
                        Status = '-----'
                        Profit= '{0:N8}' -f ($Remoteminers | Where-Object {$_.Status -eq 'Online'} | Measure-Object -Property Profit -Sum).sum
                        Profit1= '{0:N2}' -f ($Remoteminers | Where-Object {$_.Status -eq 'Online'} | Measure-Object -Property Profit1 -Sum).sum
                        Profit2= '{0:N2}' -f ($Remoteminers | Where-Object {$_.Status -eq 'Online'} | Measure-Object -Property Profit2 -Sum).sum
                        Profit3= '{0:N2}' -f ($Remoteminers | Where-Object {$_.Status -eq 'Online'} | Measure-Object -Property Profit3 -Sum).sum
                    }

                    $Remoteminers += [pscustomobject]@{
                        WorkerName='Total (All)'
                        Status = '-----'
                        Profit= '{0:N8}' -f ($Remoteminers | Where-Object {$_.Status -eq 'Online' -or $_.Status -eq 'Offline'} | Measure-Object -Property Profit -Sum).sum
                        Profit1= '{0:N2}' -f ($Remoteminers | Where-Object {$_.Status -eq 'Online' -or $_.Status -eq 'Offline'} | Measure-Object -Property Profit1 -Sum).sum
                        Profit2= '{0:N2}' -f ($Remoteminers | Where-Object {$_.Status -eq 'Online' -or $_.Status -eq 'Offline'} | Measure-Object -Property Profit2 -Sum).sum
                        Profit3= '{0:N2}' -f ($Remoteminers | Where-Object {$_.Status -eq 'Online' -or $_.Status -eq 'Offline'} | Measure-Object -Property Profit3 -Sum).sum
                    }
                } Catch {
                    $Remoteminers = @()
                    $RemoteMinerStatus = "Unknown"
                    $RemoteMinerProfit = "Unknown"
                }
                $Controls.WorkersList.Dispatcher.Invoke([action]{$Controls.WorkersList.ItemsSource = $Remoteminers}, "Background")
                $Controls.RemoteMinerStatus.Dispatcher.Invoke([action]{$Controls.RemoteMinerStatus.Text = $RemoteMinerStatus}, "Background")
                $Controls.RemoteMinerProfit.Dispatcher.Invoke([action]{$Controls.RemoteMinerProfit.Text = $RemoteMinerProfit}, "Background")

                $Errors.RemoteMiner = $error
            }
            Start-Sleep -Seconds 120
        }
    }
    $remoteworker.Runspace = $newRunspace
    $remoteWorkerThread = $remoteworker.BeginInvoke()
    #endregion Create remote worker thread

    #region Open window
    # See https://blog.netnerds.net/2016/01/showdialog-sucks-use-applicationcontexts-instead/ for an explaination of why not just use .ShowDialog()
    [Windows.Forms.Integration.ElementHost]::EnableModelessKeyboardInterop($Controls.Window)
    $Controls.Window.Show()
    $Controls.Window.Activate()
    $appContext = New-Object -TypeName System.Windows.Forms.ApplicationContext
    $Errors.main = $Error
    [void][Windows.Forms.Application]::Run($appContext)
    #endregion Open window
    $Errors.main = $Error
}

# GUIRunning flag makes sure all threads exit after GUI closes
$State.GUIRunning = $true

$guiCmd.Runspace = $newRunspace
$guiThread = $guiCmd.BeginInvoke()

# If running from the ISE or -debug is set, give a prompt that can access $synchash for debugging.
# Otherwise, hide the console window and wait for the GUI to exit.
If($DebugPreference -ne 'SilentlyContinue' -or $host.name -match 'ISE') {
    Write-Warning -Message 'MultiPoolMiner GUI Debug Console.  If you close this, the GUI will exit as well.'
    $host.EnterNestedPrompt()
} else {
    $windowcode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
    $asyncwindow = Add-Type -MemberDefinition $windowcode -name Win32ShowWindowAsync -namespace Win32Functions -PassThru
    $null = $asyncwindow::ShowWindowAsync((Get-Process -Id $pid).MainWindowHandle, 0)
    While(!$guiThread.IsCompleted) {
        Start-Sleep -Seconds 1
    }
}

$State.GUIRunning = $false