# Development update script

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$False)]
    [String]$Commit
)

Set-Location (Split-Path $MyInvocation.MyCommand.Path)

Write-Host -NoNewLine "Verifying git is installed..."
If (Get-Command "git.exe") {
    Write-Host -Foregroundcolor Green "Yes"
}
else {
    Write-Host "No"
    Write-Warning "You must install git from https://git-scm.com/download/win first"
    Exit
}

Write-Host -NoNewLine "Verifying this is a git repository..."
& git rev-parse --is-inside-work-tree *>$null
If ($LastExitCode -eq 0) {
    Write-Host -Foregroundcolor Green "Yes"
}
else {
    Write-Host "No"
    Write-Warning "Cannot update release installs. You must checkout master branch using git."
    Exit
}

Write-Host -NoNewLine "Checking for local changes..."
& git diff-index --quiet HEAD --
If ($LastExitCode -eq 0) {
    Write-Host -Foregroundcolor Green "Yes"
}
else {
    Write-Host "No"
    Write-Warning "There are local changes. Commit or discard your changes before updating."
    & git status
    Exit
}

If($Commit) {
    Write-Host -NoNewLine "Verifying specified commit exists..."
    & git cat-file -e $commit *>$null
    If($LastExitCode -eq 0) {
        Write-Host -Foregroundcolor Green "Ok"
    }
    else {
        Write-Host "Unable to find commit $Commit"
        Write-Warning "Specify a valid commit to update from, or leave out to update from current commit automatically."
        Exit
    }
}
else {
    Write-Host -NoNewLine "Finding current commit to update from..."
    $Commit = & git rev-parse --verify HEAD
    If ($LastExitCode -eq 0 -and $Commit) {
        Write-Host -Foregroundcolor Green "updating from $Commit"
    } 
    else {
        Write-Host "Error"
        Write-Warning "Unable to get current commit from git."
        Exit
    }
}

Write-Host -NoNewLine "Checking remote repositories..."
& git remote update *>$Null
If ($LastExitCode -eq 0) {
    Write-Host -Foregroundcolor Green "remotes updated"
}
else {
    Write-Host "Error updating remote repositories.  Check network connection and try 'git update remotes'"
    Exit
}

Write-Host -NoNewLine "Checking if updates are available..."
$remotecommit = & git rev-parse '@{u}'
If ($LastExitCode -eq 0) {
    If($remotecommit -eq $commit) {
        Write-Host -Foregroundcolor Green "No updates needed. Already up to date!"
        Write-Host "Checking for updates to binaries..."
        .\Get-Binaries.ps1
        Exit
    } else {
        Write-Host "Updates available"
    }
}
else {
    Write-Host "Error"
    Write-Warning "Unable to get latest remote commit."
    Exit
}

Write-Host -NoNewLine "Attempting to merge latest changes..."
& git merge --ff-only '@{u}' *>$Null
If ($LastExitCode -eq 0) {
    Write-Host -Foregroundcolor Green "merge successful"
} 
else {
    Write-Host "Error merging. Run 'git merge --ff-only @{u}' from command line to see error"
    Exit
}

Write-Host -NoNewLine "Detecting changed miners..."
$files = & git diff --name-only $Commit HEAD
If ($LastExitCode -eq 0) {
    # Get just the basename of verything that start with Miners/ - can't use Get-ChildItem, since the file may have been deleted
    $miners = $files | Where-Object {$_.StartsWith('Miners/')} | Foreach-Object {$_.Split('/')[1].Split('.')[0]}
    $miners += $files | Where-Object {$_.StartsWith('MinersLegacy/')} | Foreach-Object {$_.Split('/')[1].Split('.')[0]}
    If($miners.count -gt 0) {
        Write-Host -Foregroundcolor Green "changes detected for: $miners"
    } else {
        Write-Host -Foregroundcolor Green "no miner changes detected"
    }
} 
else {
    Write-Host "error"
    Write-Warning "Unable to detect changed files between $Commit and HEAD"
    Exit
}

If($miners.count -gt 0) {
    Write-Host "Clearing stats for changed miners..."
    $miners | Foreach-Object {
        Remove-Item ".\Stats\$_*.txt"
    }

    Write-Host "Updating binaries..."
    .\Get-Binaries.ps1
}

Write-Host -Foregroundcolor Green "Update complete!"
