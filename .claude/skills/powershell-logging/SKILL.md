---
name: powershell-logging
description: Add logging to a PowerShell module, script, or project with PSFramework, or bring the logging that it already has into one standard form. Use when asked to add, set up, standardize, unify, or clean up logging or log files.
---

# Add or standardize logging with PSFramework

These standards write messages to the output streams and add no logging module (ERR-30). Use this
skill when a project also wants log files. The streams keep working: a message written with
`Write-PSFMessage` still reaches the caller's verbose or warning stream.

Read these first, unless they are already loaded:

- `.github/copilot-instructions.md`, or `AGENTS.md` if the repository has no such file
- `.github/instructions/powershell-error-handling.instructions.md`
- `.github/instructions/powershell-security.instructions.md`

Every statement about PSFramework below was measured with PSFramework 1.15.479 on PowerShell 7.7.0,
PowerShell 7.6.10, and Windows PowerShell 5.1.

## Steps

1. Confirm that PSFramework loads, with `Import-Module -Name PSFramework`. Its assembly is not
   signed. Windows Smart App Control refuses the import with "An Application Control policy has
   blocked this file", and another application control policy can do the same. When the import
   fails, stop and report it. Do not look for a way around the policy. When the code runs on
   other computers, ask whether they have such a policy.
2. Find the logging that the files in scope already have. Search for `Write-Host`, `Write-Verbose`,
   `Write-Warning`, `Write-Debug`, `Write-Information`, `Write-PSFMessage`, `Stop-PSFFunction`,
   `Set-PSFLoggingProvider`, `Start-Transcript`, `Write-EventLog`, text appended to a file with
   `Add-Content` or `Out-File`, and functions of the project whose name contains `Log`.
3. Choose the mode from what was found, and say which one applies:
   - **Add.** Nothing writes a log file. Add the standard form below.
   - **Standardize.** The code logs in one or more other ways. List each way with the number of
     places, then replace them with the standard form. Keep the meaning of every message and move
     it to the level in the table. Change the callers of a logging function of the project first,
     and remove the function only when nothing calls it any more. Code that already uses
     PSFramework is brought to the same form: other levels, `Stop-PSFFunction`, and a provider
     that a module sets up are replaced. Ask before removing `Start-Transcript`, because a
     transcript records console output that a log file does not.
4. Ask where the log files go and how long they are kept, unless the project already says so. Do
   not invent a path or a retention time.
5. Change the code that does the work, then the script that runs it, then the tests, as the three
   sections below say.
6. Run PSScriptAnalyzer and the tests, then run the script once and read the log file it wrote.

## The code that does the work

A module or a function only writes messages. It MUST NOT enable, change, or disable a logging
provider, and a module MUST NOT do so when it is imported (MOD-06). The script that runs the code
decides where the messages go.

| The code has, or means | Write |
| --- | --- |
| `Write-Verbose`, progress detail | `Write-PSFMessage -Level Verbose` |
| `Write-Debug`, diagnostics | `Write-PSFMessage -Level Debug` |
| `Write-Warning`, a condition the caller should know about | `Write-PSFMessage -Level Warning` |
| `Write-Host` or `Write-Information` with status text | `Write-PSFMessage -Level Verbose` |
| A failure, in `catch` | `Write-PSFMessage -Level Error -ErrorRecord $_` with `3>$null`, then the error as ERR-10 or ERR-13 says |

- These four levels are the only ones for a function or a module. PSFramework writes `Critical`,
  `Important`, `Host`, `Output`, and `Significant` straight to the console, where the caller can
  neither capture nor silence them (ERR-31). It has no level named `Information`.
- A `Verbose` message is shown when the caller passes `-Verbose`, and a `Warning` message follows
  `-WarningAction`. Every message goes to the log whether it is shown or not, `Debug` included.
- Logging does not replace error handling. `-Level Error` writes a warning, not an error, and
  `-ErrorRecord` does not end the function. Log the failure, then call `$PSCmdlet.WriteError()` or
  `$PSCmdlet.ThrowTerminatingError()`. `Stop-PSFFunction` and `-EnableException` MUST NOT be used.
- Discard the warning of the `Error` level with `3>$null` on that call. The caller then gets the
  failure once, as an error. Without it the caller also gets a warning, which
  `-ErrorAction SilentlyContinue` does not silence.
- Put the item being processed in `-Target`, as its name or ID and not as a whole object, and a
  category in `-Tag`. Secrets and personal data MUST NOT go into the message, the target, the
  tags, or `-Data` (SEC-06). With `-ErrorRecord`, PSFramework adds the exception's message to the
  logged message.
- Do not write a message for every item of a large input. One call took between 16 microseconds
  and 1.5 milliseconds on the computers measured, whether the message was shown or not. Write one
  for each step or batch.
- Declare the dependency. A module lists
  `@{ ModuleName = 'PSFramework'; ModuleVersion = '1.15.479' }` in `RequiredModules`, with the
  version that the project tested (MOD-04). Importing the module then loads PSFramework. Name it
  in the README's requirements (RDM-02) and install it at a fixed version in CI (CIC-02).

This function follows the form. It and the script below are files with tests in the standards
repository:

```powershell
function Get-FolderSize {
    <#
    .SYNOPSIS
    Gets the number of files in a folder and their total size.

    .DESCRIPTION
    Emits one object for each folder, with the count and the total length of the files directly
    in it. A folder that cannot be read is reported as a non-terminating error and the remaining
    folders are still processed.

    The function writes its progress, its warnings, and its failures with Write-PSFMessage. A
    script that has enabled a PSFramework logging provider gets them in its log, and a caller
    still sees them on the verbose, warning, and error streams. The PSFramework module is
    required.

    .PARAMETER LiteralPath
    One or more folders to measure. Wildcard characters are not expanded.

    .EXAMPLE
    Get-FolderSize -LiteralPath './reports'

    Gets the file count and the total size of the reports folder.

    .EXAMPLE
    './reports', './archive' | Get-FolderSize

    Measures two folders, taking the paths from the pipeline.

    .INPUTS
    System.String. You can pipe folder paths to this function.

    .OUTPUTS
    Example.FolderSize. An object with Path, FileCount, and TotalBytes properties.
    #>
    [CmdletBinding()]
    [OutputType('Example.FolderSize')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$LiteralPath
    )

    process {
        foreach ($item in $LiteralPath) {
            Write-PSFMessage -Level Verbose -Message "Measuring '$item'." -Target $item -Tag 'measure'

            try {
                $fullPath = Convert-Path -LiteralPath $item -ErrorAction Stop
                $files = @(Get-ChildItem -LiteralPath $fullPath -File -ErrorAction Stop)
            } catch {
                $failure = @{
                    Level = 'Error'
                    Message = "Could not measure '$item'."
                    ErrorRecord = $_
                    Target = $item
                    Tag = 'measure', 'failure'
                }
                # PSFramework writes this level to the warning stream as well. That warning is
                # discarded: the caller gets the failure once, as an error that -ErrorAction controls.
                Write-PSFMessage @failure 3>$null
                $PSCmdlet.WriteError($_)
                continue
            }

            $totalBytes = [long]0
            foreach ($file in $files) {
                $totalBytes += $file.Length
            }

            if ($files.Count -eq 0) {
                # The path as the caller gave it. The resolved path can hold the user name.
                $message = "'$item' contains no files."
                Write-PSFMessage -Level Warning -Message $message -Target $item -Tag 'measure'
            }

            [PSCustomObject]@{
                PSTypeName = 'Example.FolderSize'
                Path = $fullPath
                FileCount = $files.Count
                TotalBytes = $totalBytes
            }
        }
    }
}
```

## The script that runs the code

- Turn off the provider named `filesystem` for the run. It is on by default. On PowerShell 7 it
  writes every message, shown or not, to the profile of the account, with the computer name, the
  path of the script, and the target. On PowerShell 7 and on Windows PowerShell 5.1 it writes each
  error there as an XML file, with the computer name and the script stack trace (SEC-06).
- Put it back. The provider belongs to the whole process, and other code in the same session may
  use it. Read `(Get-PSFLoggingProvider -Name filesystem).Enabled` before turning it off, and in
  `finally` enable it again when it was enabled. The messages of the run did not reach it
  afterwards. PowerShell 7 creates an empty file in the profile when the provider is enabled again.
- Enable one instance of the `logfile` provider, with these settings:
  - A full path (STY-31). `%Date%` in the file name gives one file for each day. It is the local
    date, with `-UTC` as well, so a file can hold timestamps of two UTC dates.
  - `-FileType Json` with `-JsonCompress` and `-JsonNoComma`, so that every line is one JSON
    object, and `-JsonString`, so that the level is a word. Without them the file starts with a
    comma and the level is a number.
  - `-Headers` with the columns the project wants. The default headers add the computer name and
    the user name to every line (SEC-06).
  - `-TimeFormat` and `-UTC`. The default timestamp is written in the format of the session's
    culture.
  - `-LogRotatePath`, `-LogRetentionTime`, and `-LogRotateFilter`, to remove old log files. Set
    the filter to the names of the project's log files. With the default filter, every file in
    that folder that is older than the retention time is removed.
- Call `Wait-PSFMessage` in `finally`, then disable the instance, then put `filesystem` back.
  Without the wait, the last message was missing from the file after the process had ended, on a
  Windows 11 virtual machine.
- A message that the script writes itself has the module name `<Unknown>` and the name of the
  script file as its function name. `-IncludeModules` limits an instance to the named modules, and
  leaves those messages out.
- To follow one run or one request through the log, put its ID in `-Data`, as in
  `-Data @{ CorrelationId = $correlationId }`, and add the header
  `'Data.CorrelationId as CorrelationId'`. `-Data` is not written to the file unless a header
  names it.

```powershell
#requires -Version 7.6
#requires -Modules @{ ModuleName = 'PSFramework'; ModuleVersion = '1.15.479' }

<#
.SYNOPSIS
Measures folders and writes what happened to a log file.

.DESCRIPTION
Turns on a PSFramework log file, measures each folder with Get-FolderSize, and writes the results
to the pipeline. The log is a file of JSON lines in the log folder, one file for each day, with
timestamps in UTC. Log files of this script that are older than 30 days are removed. PSFramework's
own log is off while the script runs and has its earlier state again when the script ends.

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
# of the account, with the computer name and the path of the script. It is off while this script
# runs. The setting belongs to the whole process, so it gets its state back at the end.
$ownLogWasEnabled = (Get-PSFLoggingProvider -Name filesystem).Enabled

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

try {
    Set-PSFLoggingProvider -Name filesystem -Enabled $false -Wait
    Set-PSFLoggingProvider @logFile
    Write-PSFMessage -Level Verbose -Message "Measuring $($LiteralPath.Count) folder(s)." -Tag 'start'
    Get-FolderSize -LiteralPath $LiteralPath
} finally {
    # The last message can be missing from the file when the process ends without this call.
    Wait-PSFMessage
    Set-PSFLoggingProvider -Name logfile -InstanceName 'FolderSizeReport' -Enabled $false -Wait
    if ($ownLogWasEnabled) {
        Set-PSFLoggingProvider -Name filesystem -Enabled $true -Wait
    }
}
```

## The tests

- A unit test replaces `Write-PSFMessage` with a mock, and asserts the messages that matter with
  `Should-Invoke -ParameterFilter`, by `$Level`, `$Message`, `$Target`, and `$Tag`. The mock names
  the module when the function is in a module (TST-21), and not when the test dot-sources the
  function file. It takes the place of the mocks of `Write-Verbose` and `Write-Information` that
  TST-20 asks for.
- Assert a failure twice: the message with the level `Error`, and the error that the caller gets
  (TST-17).
- An integration test runs the script with a log folder under `$TestDrive` and reads the file back
  line by line with `ConvertFrom-Json`. It also asserts that the `filesystem` provider has the
  state after the script that it had before. A test that writes a message without running the
  script disables that provider first, and puts its state back in `AfterAll`.

## Report

Say which mode applied and what step 2 found. List the files changed, the logging that was
replaced or removed, and where the log files go. Give the results of PSScriptAnalyzer and the
tests, and quote one line of the log file that the script wrote. Say that the project now depends
on PSFramework and that its assembly is not signed, because some organizations approve such a
dependency before it is used. Say plainly when PSFramework could not be loaded and the code is
therefore untested.
