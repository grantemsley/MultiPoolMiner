﻿Function Start-APIServer {
    Param(
        [Parameter(Mandatory = $false)]
        [Switch]$RemoteAPI = $false
    )

    # If using API remotely, an ACL must be set to allow listening on a port. If not using the API remotely, an ACL also has to be set for localhost if one for the + host has already been set.
    # This requires administrator priviledges and will trigger a UAC prompt
    # Check if the ACL is already set first to avoid triggering the prompt if it isn't necessary
    $urlACLs = & netsh http show urlacl | Out-String
    if ($RemoteAPI -and (!$urlACLs.Contains('http://+:3999/'))) {
        # S-1-5-32-545 is the well known SID for the Users group. Use the SID because the name Users is localized for different languages
        Start-Process netsh -Verb runas -Wait -ArgumentList 'http add urlacl url=http://+:3999/ sddl=D:(A;;GX;;;S-1-5-32-545)'
    }
    if (!$RemoteAPI -and ($urlACLs.Contains('http://+:3999/')) -and (!$urlACLs.Contains('http://localhost:3999/'))) {
        Start-Process netsh -Verb runas -Wait -ArgumentList 'http add urlacl url=http://localhost:3999/ sddl=D:(A;;GX;;;S-1-5-32-545)'
    }

    # Create a global synchronized hashtable that all threads can access to pass data between the main script and API
    $Global:API = [hashtable]::Synchronized(@{})
  
    # Setup flags for controlling script execution
    $API.Stop = $false
    $API.Pause = $false

    # Setup runspace to launch the API webserver in a separate thread
    $newRunspace = [runspacefactory]::CreateRunspace()
    $newRunspace.Open()
    $newRunspace.SessionStateProxy.SetVariable("API", $API)
    $newRunspace.SessionStateProxy.Path.SetLocation($(pwd)) | Out-Null

    $apiserver = [PowerShell]::Create().AddScript({

        # Set the starting directory
        Set-Location (Split-Path $MyInvocation.MyCommand.Path)
        $BasePath = "$PWD\web"

        # List of possible mime types for files
        $MIMETypes = @{
            ".js" = "application/x-javascript"
            ".html" = "text/html"
            ".htm" = "text/html"
            ".json" = "application/json"
            ".css" = "text/css"
            ".txt" = "text/plain"
            ".ico" = "image/x-icon"
            ".ps1" = "text/html" # ps1 files get executed, assume their response is html
        }

        # Setup the listener
        $Server = New-Object System.Net.HttpListener
        if ($RemoteAPI) {
            $Server.Prefixes.Add("http://+:3999/")
            # Requires authentication when listening remotely
            $Server.AuthenticationSchemes = [System.Net.AuthenticationSchemes]::IntegratedWindowsAuthentication
        } else {
            $Server.Prefixes.Add("http://localhost:3999/")
        }
        $Server.Start()

        While ($Server.IsListening) {
            $Context = $Server.GetContext()
            $Request = $Context.Request
            $URL = $Request.Url.OriginalString

            # Determine the requested resource and parse query strings
            $Path = $Request.Url.LocalPath

            # Parse any parameters in the URL - $Request.Url.Query looks like "+ ?a=b&c=d&message=Hello%20world"
            $Parameters = [PSCustomObject]@{}
            $Request.Url.Query -Replace "\?", "" -Split '&' | Foreach-Object {
                $key, $value = $_ -Split '='
                # Decode any url escaped characters in the key and value
                $key = [URI]::UnescapeDataString($key)
                $value = [URI]::UnescapeDataString($value)
                if ($key -and $value) {
                    $Parameters | Add-Member $key $value
                }
            }

            # Create a new response and the defaults for associated settings
            $Response = $Context.Response
            $ContentType = "application/json"
            $StatusCode = 200
            $Data = ""

            if($RemoteAPI -and (!$Request.IsAuthenticated)) {
                $Data = "Unauthorized"
                $StatusCode = 403
                $ContentType = "text/html"
            } else {
                # Set the proper content type, status code and data for each resource
                Switch($Path) {
                    "/version" {
                        $Data = $API.Version | ConvertTo-Json
                        break
                    }
                    "/activeminers" {
                        $Data = ConvertTo-Json @($API.ActiveMiners)
                        break
                    }
                    "/runningminers" {
                        $Data = ConvertTo-Json @($API.RunningMiners)
                        Break
                    }
                    "/failedminers" {
                        $Data = ConvertTo-Json @($API.FailedMiners)
                        Break
                    }
                    "/minersneedingbenchmark" {
                        $Data = ConvertTo-Json @($API.MinersNeedingBenchmark)
                        Break
                    }
                    "/pools" {
                        $Data = ConvertTo-Json @($API.Pools)
                        Break
                    }
                    "/newpools" {
                        $Data = ConvertTo-Json @($API.NewPools)
                        Break
                    }
                    "/allpools" {
                        $Data = ConvertTo-Json @($API.AllPools)
                        Break
                    }
                    "/algorithms" {
                        $Data = ConvertTo-Json @($API.AllPools.Algorithm | Sort-Object -Unique)
                        Break
                    }
                    "/miners" {
                        $Data = ConvertTo-Json @($API.Miners)
                        Break
                    }
                    "/fastestminers" {
                        $Data = ConvertTo-Json @($API.FastestMiners)
                        Break
                    }
                    "/config" {
                        $Data = $API.Config | ConvertTo-Json
                        Break
                    }
                    "/debug" {
                        $Data = $API | ConvertTo-Json
                        Break
                    }
                    "/devices" {
                        $Data = ConvertTo-Json @($API.Devices)
                        Break
                    }
                    "/stats" {
                        $Data = ConvertTo-Json @($API.Stats)
                        Break
                    }
                    "/watchdogtimers" {
                        $Data = ConvertTo-Json @($API.WatchdogTimers)
                        Break
                    }
                    "/balances" {
                        $Data = ConvertTo-Json @($API.Balances)
                        Break
                    }
                    "/currentprofit" {
                        $Data = ($API.RunningMiners | Measure-Object -Sum -Property Profit).Sum | ConvertTo-Json
                        Break
                    }
                    "/stop" {
                        $API.Stop = $true
                        $Data = "Stopping"
                        break
                    }
                    default {
                        # Set index page
                        if ($Path -eq "/") {
                            $Path = "/index.html"
                        }

                        # Check if there is a file with the requested path
                        $Filename = $BasePath + $Path
                        if (Test-Path $Filename -PathType Leaf) {
                            # If the file is a powershell script, execute it and return the output. A $Parameters parameter is sent built from the query string
                            # Otherwise, just return the contents of the file
                            $File = Get-ChildItem $Filename

                            If ($File.Extension -eq ".ps1") {
                                $Data = & $File.FullName -Parameters $Parameters
                            } else {
                                $Data = Get-Content $Filename -Raw

                                # Process server side includes for html files
                                # Includes are in the traditional '<!-- #include file="/path/filename.html" -->' format used by many web servers
                                if($File.Extension -eq ".html") {
                                    $IncludeRegex = [regex]'<!-- *#include *file="(.*)" *-->'
                                    $IncludeRegex.Matches($Data) | Foreach-Object {
                                        $IncludeFile = $BasePath + '/' + $_.Groups[1].Value
                                        If (Test-Path $IncludeFile -PathType Leaf) {
                                            $IncludeData = Get-Content $IncludeFile -Raw
                                            $Data = $Data -Replace $_.Value, $IncludeData
                                        }
                                    }
                                }
                            }

                            # Set content type based on file extension
                            If ($MIMETypes.ContainsKey($File.Extension)) {
                                $ContentType = $MIMETypes[$File.Extension]
                            } else {
                                # If it's an unrecognized file type, prompt for download
                                $ContentType = "application/octet-stream"
                            }
                        } else {
                            $StatusCode = 404
                            $ContentType = "text/html"
                            $Data = "URI '$Path' is not a valid resource."
                        }
                    }
                }
            }

            # If $Data is null, the API will just return whatever data was in the previous request.  Instead, show an error
            # This happens if the script just started and hasn't filled all the properties in yet.
            If($Data -eq $Null) { 
                $Data = @{'Error' = "API data not available"} | ConvertTo-Json
            }

            # Send the response
            $Response.Headers.Add("Content-Type", $ContentType)
            $Response.StatusCode = $StatusCode
            $ResponseBuffer = [System.Text.Encoding]::UTF8.GetBytes($Data)
            $Response.ContentLength64 = $ResponseBuffer.Length
            $Response.OutputStream.Write($ResponseBuffer,0,$ResponseBuffer.Length)
            $Response.Close()

        }
        # Only gets here if something is wrong and the server couldn't start or stops listening
        $Server.Stop()
        $Server.Close()
    }) #end of $apiserver

    $apiserver.Runspace = $newRunspace
    $apihandle = $apiserver.BeginInvoke()
}