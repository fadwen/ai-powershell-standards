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

<!-- include: standards/examples/Get-FolderSize.ps1 -->

## The script that runs the code

- Turn off the provider named `filesystem` first. It is on by default. On PowerShell 7 it writes
  every message, shown or not, to the profile of the account, with the computer name, the path of
  the script, and the target. On PowerShell 7 and on Windows PowerShell 5.1 it writes each error
  there as an XML file, with the computer name and the script stack trace (SEC-06).
- Enable one instance of the `logfile` provider, with these settings:
  - A full path (STY-31). `%Date%` in the file name gives one file for each day.
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
- Call `Wait-PSFMessage` in `finally`, then disable the instance. Without the wait, the last
  message was missing from the file after the process had ended, on a Windows 11 virtual machine.
- A message that the script writes itself has the module name `<Unknown>` and the name of the
  script file as its function name. `-IncludeModules` limits an instance to the named modules, and
  leaves those messages out.
- To follow one run or one request through the log, put its ID in `-Data`, as in
  `-Data @{ CorrelationId = $correlationId }`, and add the header
  `'Data.CorrelationId as CorrelationId'`. `-Data` is not written to the file unless a header
  names it.

<!-- include: standards/examples/Invoke-FolderSizeReport.ps1 -->

## The tests

- A unit test replaces `Write-PSFMessage` with a mock that names the module, and asserts the
  messages that matter with `Should-Invoke -ParameterFilter`, by `$Level`, `$Message`, `$Target`,
  and `$Tag` (TST-21). That mock takes the place of the mocks of `Write-Verbose` and
  `Write-Information` that TST-20 asks for.
- Assert a failure twice: the message with the level `Error`, and the error that the caller gets
  (TST-17).
- An integration test runs the script with a log folder under `$TestDrive` and reads the file back
  line by line with `ConvertFrom-Json`. A test that writes a message without running the script
  disables the `filesystem` provider first.

## Report

Say which mode applied and what step 2 found. List the files changed, the logging that was
replaced or removed, and where the log files go. Give the results of PSScriptAnalyzer and the
tests, and quote one line of the log file that the script wrote. Say plainly when PSFramework could
not be loaded and the code is therefore untested.
