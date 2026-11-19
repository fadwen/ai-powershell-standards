# PowerShell error handling, strict mode, and streams

These rules apply to every `.ps1` and `.psm1` file. They separate two kinds of code: a script that is
run directly, and a function, which a caller invokes and which must leave the caller in control.

## Rules

### Scripts and modules

- **ERR-01** A script that is run directly MUST set `Set-StrictMode -Version Latest` and
  `$ErrorActionPreference = 'Stop'` immediately after its `param()` block.
- **ERR-02** Module code MUST NOT set `$ErrorActionPreference`, at module scope or inside a function.
  A module sets `Set-StrictMode -Version Latest` once, at the top of its `.psm1`.
- **ERR-03** Code MUST run without errors under strict mode: assign a variable before reading it, test
  for an optional property with `$object.PSObject.Properties['Name']`, test for a hashtable key with
  `.ContainsKey()`, and wrap a result in `@()` before reading `.Count` or an index.

### Reporting failure from a function

- **ERR-10** In an advanced function, put the work that can fail inside `try`, and end the function
  on an unrecoverable failure by calling `$PSCmdlet.ThrowTerminatingError()` in `catch`.
- **ERR-11** `throw` and `Write-Error -ErrorAction Stop` MUST NOT be used in an advanced function. Use
  `throw` only where `$PSCmdlet` does not exist: top-level script code, class methods, and plain
  script blocks.
- **ERR-12** Inside `try`, pass `-ErrorAction Stop` to every command whose failure the `catch` must
  see. A non-terminating error does not enter `catch`.
- **ERR-13** When one input item fails and the rest can still be processed, report the failure with
  `$PSCmdlet.WriteError()` and continue with the next item.
- **ERR-14** To add context to a failure, create a new `ErrorRecord` whose exception wraps the
  original as its inner exception. An error MUST NOT be rethrown as a string.
- **ERR-15** Write output to the pipeline after the `try` block, not inside it. An error raised by a
  command further down the pipeline is otherwise caught by this function's `catch`.
- **ERR-16** For an error scenario that callers need to tell apart, define a custom exception class
  that derives from one base exception class of the module. Carry the exception in an `ErrorRecord`
  and raise it as ERR-10 and ERR-13 say.

### Handling failure

- **ERR-20** A `catch` block MUST NOT be empty and MUST NOT hide the error. To tolerate one expected
  failure, catch that exception type and state the reason in a comment.
- **ERR-21** In `catch`, read the error from `$_`. `$Error[0]` MUST NOT be used.
- **ERR-22** Release resources in `finally`, and assign before `try` every variable that `finally`
  reads. Clean up a COM object there as well.
- **ERR-23** After running a native executable, test `$LASTEXITCODE` and fail when it reports an
  error. A non-zero exit code does not raise a PowerShell error by default.
- **ERR-24** In a script, pass `-ErrorAction Stop` to a module command whose non-terminating errors
  must stop the script. The script's own `$ErrorActionPreference` does not reach module functions.
  Set the preference as well (ERR-01): `-ErrorAction Stop` on a call does not make a terminating
  error of that command end the script.

### Streams

- **ERR-30** Send only data to the success stream. Use `Write-Verbose` for progress detail,
  `Write-Debug` for diagnostics, `Write-Warning` for a condition that did not stop the work but that
  the caller should know about, and `Write-Information` for status messages.
- **ERR-31** `Write-Host` MUST NOT be used in a function or module. In a script, use it only when
  coloured console output is explicitly required.
- **ERR-32** In code that runs for every item of a large input, a `Write-Verbose` or `Write-Debug`
  call that builds its message SHOULD sit inside a test of `$VerbosePreference` or
  `$DebugPreference`.

### Measurement and diagnostics

- **ERR-40** Measure the run time of a critical operation with `[System.Diagnostics.Stopwatch]`, and
  the memory it used with `[System.GC]::GetTotalMemory($false)` before and after. Write the figures
  to the verbose stream, so that a baseline can be established.
- **ERR-41** A module SHOULD provide a command that exports diagnostic data to a file for remote
  troubleshooting: system information, `$PSVersionTable`, the loaded modules, and performance
  counters.

## Notes and examples

### A script that is run directly (ERR-01, ERR-23, ERR-24)

```powershell
#requires -Version 7.6

<#
.SYNOPSIS
Publishes the build output.

.PARAMETER OutputPath
Folder that contains the build output.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$files = @(Get-ChildItem -LiteralPath $OutputPath -File)
if ($files.Count -eq 0) {
    throw "Nothing to publish: '$OutputPath' contains no files."
}

& git tag --annotate 'release' --message 'Release'
if ($LASTEXITCODE -ne 0) {
    throw "git tag failed with exit code $LASTEXITCODE."
}
```

With `$ErrorActionPreference = 'Stop'`, the script stops on any terminating error, on any error from
a compiled cmdlet, and on any error from a function defined in the script itself.

### A function (ERR-10 to ERR-15)

```powershell
function Get-ReleaseNote {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath
    )

    try {
        $content = Get-Content -LiteralPath $LiteralPath -Raw -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
        $message = "Release notes were not found at '$LiteralPath'. Run the changelog task first."
        $exception = [System.InvalidOperationException]::new($message, $_.Exception)
        $category = [System.Management.Automation.ErrorCategory]::ObjectNotFound
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'ReleaseNoteNotFound', $category, $LiteralPath)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $content.Trim()
}
```

The first `catch` adds context and keeps the original as `InnerException`. The second passes any
other failure on unchanged. The result is written after the `try` block.

Put the entire transaction in the `try` block, not only the risky call, so that the steps that
depend on that call do not run after it fails. Only the output is written after the `try` (ERR-15).

When each input item can fail on its own, report the failure and continue. The object is again
written after the `try` block:

```powershell
process {
    foreach ($item in $Name) {
        try {
            $record = Get-Record -Name $item -ErrorAction Stop
        } catch {
            $PSCmdlet.WriteError($_)
            continue
        }

        $record
    }
}
```

If `$record` were written inside the `try`, an error thrown by a later command in the caller's
pipeline, such as `Get-Thing | ForEach-Object { throw 'stop' }`, would arrive in this `catch`. The
function would report it as its own failure and carry on, and the caller would never see it.

### Custom exception classes (ERR-16)

A base class holds what every error of the module carries, and one derived class describes each
scenario:

```powershell
class BaseModuleException : System.Exception {
    [string]$Component
    [string]$Operation
    [hashtable]$Context

    BaseModuleException([string]$Message, [string]$Component, [string]$Operation) : base($Message) {
        $this.Component = $Component
        $this.Operation = $Operation
        $this.Context = @{}
    }

    [void] AddContext([string]$Key, [object]$Value) {
        $this.Context[$Key] = $Value
    }
}

class ValidationException : BaseModuleException {
    [string]$ParameterName
    [object]$ParameterValue

    ValidationException(
        [string]$Message,
        [string]$ParameterName,
        [object]$ParameterValue
    ) : base($Message, 'Validation', 'ParameterValidation') {
        $this.ParameterName = $ParameterName
        $this.ParameterValue = $ParameterValue
    }
}
```

The function puts the exception in an `ErrorRecord`:

```powershell
$exception = [ValidationException]::new('Limit must not exceed 10.', 'Limit', $Limit)
$category = [System.Management.Automation.ErrorCategory]::InvalidArgument
$errorRecord = [System.Management.Automation.ErrorRecord]::new(
    $exception, 'LimitTooHigh', $category, $Limit)
$PSCmdlet.ThrowTerminatingError($errorRecord)
```

A caller's `catch [ValidationException]` and `catch [BaseModuleException]` both receive this error,
on PowerShell 7.6 and on Windows PowerShell 5.1. SEC-06 also applies to the values that an exception
carries.

### Why the rules are written this way

Each statement below was verified on PowerShell 7.6 and Windows PowerShell 5.1.

- `throw` is suppressed when any caller up the call stack passed `-ErrorAction SilentlyContinue`, or
  `-ErrorAction Ignore` on PowerShell 7. Execution then continues with the statement after the
  `throw`, and the function returns as if it had succeeded. A bare `throw` that passes on an error
  raised with `-ErrorAction Stop` is the exception, described under the table below. On Windows
  PowerShell 5.1, `-ErrorAction Ignore` does not suppress a `throw`: the command that was given the
  parameter ends with another error,
  `The value Ignore is not supported for an ActionPreference variable`.
- `Write-Error -ErrorAction Stop` ignores the caller's `-ErrorAction`, and unless `-ErrorRecord` is
  passed it replaces the original exception with a `WriteErrorException`.
- `$PSCmdlet.ThrowTerminatingError()` always ends the function, and the caller's `-ErrorAction` does
  not hide it. It ends only the statement that called the function: the caller continues at its next
  statement unless that call is inside `try` or the caller's `$ErrorActionPreference` is `Stop`.
  Passing `-ErrorAction Stop` on the call does not change this. That is why ERR-10 puts the calls
  inside `try` and ERR-01 sets `Stop` in scripts.
- A module function does not see `$ErrorActionPreference` set by the script that calls it, except when
  the script runs in the global scope, as `pwsh -File` does. That is why ERR-12 and ERR-24 ask for an
  explicit `-ErrorAction Stop`.
- `$ErrorActionPreference = 'Stop'` at module scope turns every non-terminating error from the
  module's functions into a terminating one, so a caller can no longer continue past a per-item
  failure.
- Under `$ErrorActionPreference = 'Stop'`, `Write-Error` terminates. Statements that follow it in the
  same block do not run.

### What a calling script sees (ERR-01, ERR-10, ERR-11, ERR-24)

A module function fails in its `begin` block, in one of three ways, and the script that calls it is
started with `-File`. Measured on PowerShell 7.7.0, PowerShell 7.6.10, and Windows PowerShell 5.1:

| The calling script | `$PSCmdlet.ThrowTerminatingError()` | `throw $_` | `Write-Error -ErrorRecord $_ -ErrorAction Stop` |
| --- | --- | --- | --- |
| Has no `try` and sets no preference | Goes on, exit code 0 | Ends, exit code 1 | Ends, exit code 1 |
| Passes `-ErrorAction Stop` | Goes on, exit code 0 | Ends, exit code 1 | Ends, exit code 1 |
| Passes `-ErrorAction SilentlyContinue` | Goes on, exit code 0 | Goes on, and so does the function | Ends, exit code 1 |
| Sets `$ErrorActionPreference = 'Stop'` | Ends, exit code 1 | Ends, exit code 1 | Ends, exit code 1 |
| Makes the call inside `try` | `catch` runs | `catch` runs | `catch` runs |
| Makes the call twice in a loop | Both calls run | Ends at the first | Ends at the first |

`throw` with text or with an exception object behaves as `throw $_` does, and so does a bare `throw`
in `catch`, with one exception. A bare `throw` that passes on an error raised with
`-ErrorAction Stop` behaves as the last column does, and so does such an error that no `catch`
handles: the script ends under `-ErrorAction SilentlyContinue` as well.

A compiled cmdlet that raises a terminating error, as `ConvertFrom-Json` does for invalid text,
behaves as the first column does.

ERR-10 chooses the first column: the function fails as a cmdlet does, and the caller decides whether
the script stops. The last column ends the calling script whatever the caller asked for. `-ErrorAction`
no longer works for the caller, and a loop ends at its first failure, which is why ERR-11 rules that
form out even with `-ErrorRecord`.

The first two rows are the price of that choice. A script that does not set
`$ErrorActionPreference = 'Stop'` goes on after the failure and ends with exit code 0, and
`-ErrorAction Stop` on the call does not change that. A script therefore needs both: the preference
for a terminating error (ERR-01), and `-ErrorAction Stop` for a non-terminating error of a module
command (ERR-24). Text for callers, such as a README, a runbook, or a help example, says the same.
It does not offer `-ErrorAction Stop` as the way to make a failed command end a script or fail a job
step.

### Strict mode (ERR-02, ERR-03)

`Set-StrictMode` applies to the scope where it runs and to the scopes below it. At the top of a
`.psm1` it therefore covers every function file the module dot-sources. Do not put it in a file that
is dot-sourced into a caller's scope, such as a function file or a test helper, because it would
change that caller's mode.

```powershell
Set-StrictMode -Version Latest

# Each line after the first is an error under strict mode
$settings = @{ Region = 'westeurope' }
$tier = $settings.Tier
$count = (Get-Item -LiteralPath $PSHOME).Count
$first = @()[0]
$total = $neverAssigned + 1

# Compliant equivalents
$tier = if ($settings.ContainsKey('Tier')) { $settings['Tier'] } else { 'standard' }
$count = @(Get-Item -LiteralPath $PSHOME).Count
$items = @(Get-ChildItem -LiteralPath $PSHOME -Filter '*.none')
$first = if ($items.Count -gt 0) { $items[0] } else { $null }
```

### Tolerating one expected failure (ERR-20)

```powershell
try {
    Remove-Item -LiteralPath $lockFilePath -ErrorAction Stop
} catch [System.Management.Automation.ItemNotFoundException] {
    # The lock file is already gone, which is the state this code wants.
    Write-Debug "No lock file at '$lockFilePath'."
}
```

A typed `catch` matches the exception that a failing .NET method call raised, and its base types,
even though PowerShell wraps that exception in a `MethodInvocationException`.

### Reading the error in `catch` (ERR-21)

`$_` carries what a report of the failure needs: `$_.Exception.Message` is the message and
`$_.ScriptStackTrace` is the script stack trace. `$MyInvocation.MyCommand.Name` is the name of the
function that caught the error. `$PSBoundParameters` MUST NOT be added to these details (SEC-06).

### Releasing resources (ERR-22)

```powershell
$reader = $null
try {
    $reader = [System.IO.StreamReader]::new($fullPath)
    $firstLine = $reader.ReadLine()
} finally {
    if ($null -ne $reader) {
        $reader.Dispose()
    }
}
```

A COM object has no `Dispose()` method. Release it with `ReleaseComObject()`:

```powershell
$fileSystem = $null
try {
    $fileSystem = New-Object -ComObject 'Scripting.FileSystemObject'
    $folderExists = $fileSystem.FolderExists($folderPath)
} finally {
    if ($null -ne $fileSystem) {
        $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($fileSystem)
    }
}
```

### Native executables (ERR-23)

Setting `$PSNativeCommandUseErrorActionPreference = $true` (PowerShell 7.4 and later) makes a
non-zero exit code raise an error that follows `$ErrorActionPreference`. It does not exist in Windows
PowerShell 5.1, and some tools use non-zero exit codes for success (`robocopy` returns values up to 7
for normal outcomes), so an explicit `$LASTEXITCODE` test is the portable form.

### Messages in a loop (ERR-32)

PowerShell builds the message before `Write-Verbose` decides whether to show it. Measured with
200,000 messages that were not shown: 2.7 seconds without the test and 0.5 seconds with it on
PowerShell 7.6, and 13.6 seconds against 0.5 seconds on Windows PowerShell 5.1.

```powershell
foreach ($record in $records) {
    if ($VerbosePreference -ne 'SilentlyContinue') {
        Write-Verbose ('Processing record {0} of {1}.' -f $record.Index, $records.Count)
    }

    Convert-Record -InputObject $record
}
```

Inside an advanced function, `-Verbose` and `-Debug` set these preferences, so the test follows the
caller's switch. A message that is written a few times needs no test.

### Measuring an operation (ERR-40)

```powershell
function Measure-OperationPerformance {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Operation,

        [Parameter(Mandatory)]
        [string]$OperationName
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $memoryBefore = [System.GC]::GetTotalMemory($false)
    try {
        $result = & $Operation
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    } finally {
        $stopwatch.Stop()
    }

    $memoryUsedMB = [math]::Round(([System.GC]::GetTotalMemory($false) - $memoryBefore) / 1MB, 2)
    Write-Verbose ('{0} took {1} ms and used {2} MB.' -f
        $OperationName, $stopwatch.Elapsed.TotalMilliseconds, $memoryUsedMB)
    $result
}
```

The wrapper passes on the output of the operation, and its failure, unchanged.

### Diagnostic data (ERR-41)

```powershell
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$diagnosticPath = Join-Path -Path $OutputPath -ChildPath "Diagnostic-$timestamp"
$null = New-Item -Path $diagnosticPath -ItemType Directory -Force
$dataFilePath = Join-Path -Path $diagnosticPath -ChildPath 'diagnostic-data.json'

$processName = (Get-Process -Id $PID).ProcessName
$diagnosticData = @{
    SystemInfo = Get-ComputerInfo | Select-Object -Property WindowsVersion, CsTotalPhysicalMemory
    PowerShellInfo = $PSVersionTable
    ModuleInfo = Get-Module | Select-Object -Property Name, Version
    PerformanceCounters = Get-Counter -Counter "\Process($processName)\Working Set"
}
$diagnosticData | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $dataFilePath -Encoding utf8
```

This ran on PowerShell 7.6 and Windows PowerShell 5.1. `Get-ComputerInfo` has no
`TotalPhysicalMemory` property; the figure is in `CsTotalPhysicalMemory`. The counter instance has
the name of the process, `pwsh` or `powershell`, so the sample reads it from the running process.
Export selected properties only: a whole `Get-ComputerInfo` object also names the user and the
computer (SEC-06).
