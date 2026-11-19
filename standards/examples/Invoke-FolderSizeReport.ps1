#requires -Version 7.6
#requires -Modules @{ ModuleName = 'PSFramework'; ModuleVersion = '1.15.479' }

<#
.SYNOPSIS
Measures folders and writes what happened to a log file.

.DESCRIPTION
Turns on a PSFramework log file, measures each folder with Get-FolderSize, and writes the results
to the pipeline. The log is a file of JSON lines in the log folder, one file for each day, with
timestamps in UTC. Log files of this script that are older than 30 days are removed.

The script stops at the first folder that cannot be measured. The failure is in the log file.

.PARAMETER LiteralPath
One or more folders to measure. Wildcard characters are not expanded.

.PARAMETER LogDirectory
Folder for the log files. It is created when it does not exist.

.EXAMPLE
./Invoke-FolderSizeReport.ps1 -LiteralPath './reports', './archive' -LogDirectory './logs'

Measures two folders and writes the log to the logs folder.

.INPUTS
None.

.OUTPUTS
Example.FolderSize. One object for each folder, with Path, FileCount, and TotalBytes properties.
#>
[CmdletBinding()]
[OutputType('Example.FolderSize')]
param(
    [Parameter(Mandatory)]
    [string[]]$LiteralPath,

    [Parameter(Mandatory)]
    [string]$LogDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'Get-FolderSize.ps1')

$logFolder = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($LogDirectory)
$null = New-Item -Path $logFolder -ItemType Directory -Force

# PSFramework's own log is on by default. It records every message, shown or not, in the profile
# of the account, with the computer name and the path of the script.
Set-PSFLoggingProvider -Name filesystem -Enabled $false -Wait

$logFile = @{
    Name = 'logfile'
    InstanceName = 'FolderSizeReport'
    FilePath = Join-Path -Path $logFolder -ChildPath 'FolderSizeReport-%Date%.jsonl'
    FileType = 'Json'
    # With these two, every line of the file is one JSON object.
    JsonCompress = $true
    JsonNoComma = $true
    # Writes the level as a word. Without it the level is a number.
    JsonString = $true
    # The default headers add the computer name and the user name to every line.
    Headers = 'Timestamp', 'Level', 'ModuleName', 'FunctionName', 'Message', 'Tags', 'TargetObject'
    TimeFormat = 'yyyy-MM-ddTHH:mm:ss.fffZ'
    UTC = $true
    LogRotatePath = $logFolder
    # Without a filter, every file in the folder that is older than the retention time is removed.
    LogRotateFilter = 'FolderSizeReport-*.jsonl'
    LogRetentionTime = '30d'
    Enabled = $true
    Wait = $true
}
Set-PSFLoggingProvider @logFile

try {
    Write-PSFMessage -Level Verbose -Message "Measuring $($LiteralPath.Count) folder(s)." -Tag 'start'
    Get-FolderSize -LiteralPath $LiteralPath
} finally {
    # The last message can be missing from the file when the process ends without this call.
    Wait-PSFMessage
    Set-PSFLoggingProvider -Name logfile -InstanceName 'FolderSizeReport' -Enabled $false -Wait
}
