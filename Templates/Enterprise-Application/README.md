# Multi-module application layout

A reference layout for a repository that holds several PowerShell modules and the scripts that use
them. This folder contains no files to copy: it describes where the files of such a project go and
which rules of the standards apply to them. For a template with working code, use
[Templates/Powershell-Module](../Powershell-Module/).

## Layout

```text
Application/
    README.md
    PSScriptAnalyzerSettings.psd1       the analyzer settings that check the layout rules
    Modules/
        Contoso.Core/
            Contoso.Core.psd1
            Contoso.Core.psm1
            Private/
            Public/
            Tests/
        Contoso.Reporting/
            Contoso.Reporting.psd1
            Contoso.Reporting.psm1
            Private/
            Public/
            Tests/
    Scripts/
        Publish-Report.ps1              a script that calls the modules
    Tests/
        Publish-Report.Tests.ps1        the tests for the scripts
```

The module and script names are placeholders. Add other folders only when the project has something
to put in them.

## What the standards ask of the project

- Each folder under `Modules` is a complete module: a manifest, a root module, a `Public` folder, a
  `Private` folder, and its own tests (MOD-01).
- A module that calls another module names it in `RequiredModules`, and names nothing that its code
  does not call (MOD-04).
- Every manifest names its exported functions without wildcards and has its own GUID (MOD-02,
  MOD-03).
- A script under `Scripts` declares its PowerShell version, sets strict mode and
  `$ErrorActionPreference = 'Stop'`, and passes `-ErrorAction Stop` to a module command whose errors
  must stop the script (VER-03, ERR-01, ERR-24).
- A pull request pipeline runs PSScriptAnalyzer and Pester for the whole repository and fails when
  either reports a problem (CIC-01).

The rules are in
[powershell-modules](../../.github/instructions/powershell-modules.instructions.md),
[powershell-error-handling](../../.github/instructions/powershell-error-handling.instructions.md),
[powershell-version](../../.github/instructions/powershell-version.instructions.md), and
[powershell-cicd](../../.github/instructions/powershell-cicd.instructions.md).

## Adding the standards to the project

Run this from the root of the standards repository, with the path of an existing project folder:

```powershell
./Tools/Install-CopilotStandards.ps1 -ProjectPath 'C:\Projects\Application' -IncludeAnalyzerSettings
```

Installs the instruction files for the coding agents, together with `PSScriptAnalyzerSettings.psd1`.
The script creates none of the folders in the layout above.

## Tests

Run every test in the project from its root:

```powershell
Invoke-Pester -Path ./Modules, ./Tests
```
