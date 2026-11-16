# Script collection layout

A reference layout for a repository of standalone PowerShell scripts. This folder contains no files
to copy: it describes where the files of such a project go and which rules of the standards apply to
them. For a template with working code, use [Templates/Powershell-Module](../Powershell-Module/).

## Layout

```text
ScriptCollection/
    README.md
    PSScriptAnalyzerSettings.psd1       the analyzer settings that check the layout rules
    Scripts/
        Invoke-LogRotation.ps1          one script for each task
    Tests/
        Invoke-LogRotation.Tests.ps1    one test file for each script, named after it
```

`Invoke-LogRotation.ps1` stands for any script. Add other folders only when the project has something
to put in them.

## What the standards ask of each script

- A `#requires -Version` line that declares the PowerShell version the script targets (VER-03).
- Comment-based help before the `param()` block, with a blank line between it and the `#requires`
  line (DOC-01, DOC-03).
- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` immediately after the
  `param()` block (ERR-01).
- A test of `$LASTEXITCODE` after every native executable the script runs (ERR-23).
- No secrets in the file. A script that runs unattended fails with an error when a credential is
  missing, and does not prompt for it (SEC-01, SEC-05).
- A test file named `<Script>.Tests.ps1` that starts with the Pester `#Requires` line (TST-01).

The rules are in
[powershell-error-handling](../../.github/instructions/powershell-error-handling.instructions.md),
[powershell-help](../../.github/instructions/powershell-help.instructions.md),
[powershell-security](../../.github/instructions/powershell-security.instructions.md),
[powershell-version](../../.github/instructions/powershell-version.instructions.md), and
[powershell-pester](../../.github/instructions/powershell-pester.instructions.md).
`powershell-error-handling` and `powershell-help` each show a complete script.

## Adding the standards to the project

Run this from the root of the standards repository, with the path of an existing project folder:

```powershell
./Tools/Install-CopilotStandards.ps1 -ProjectPath 'C:\Projects\ScriptCollection' -IncludeAnalyzerSettings
```

Installs the instruction files for the coding agents, together with `PSScriptAnalyzerSettings.psd1`.
The script creates none of the folders in the layout above.

## Tests

Run the tests from the root of the project:

```powershell
Invoke-Pester -Path ./Tests
```
