# ModuleExample

A small working module that shows how the PowerShell standards in this repository lay a module out.
It is an example to read and to copy from. There is no real service behind it: the statuses it
returns come from a fixed table that knows the services Billing, Identity, and Reporting.

## Requirements

- PowerShell 7.6 or later, Core edition. The module calls no platform-specific commands.
- No other module is needed to use it.
- Pester 6.2.0 or later, to run the tests.
- Microsoft.PowerShell.PlatyPS 1.0.3 or later, to rebuild the help.

## Installation

The module is not published. Import it from this folder:

```powershell
Import-Module -Name ./ModuleExample.psd1 -Force
```

## Usage

```powershell
Get-ExampleData -ServiceName 'Billing'
```

Gets the status of the Billing service in the Development environment. The result is an
`ExampleServiceResult` object with `ServiceName`, `Environment`, `Status`, and `CheckedAt` properties.

```powershell
'Billing', 'Identity', 'Reporting' | Get-ExampleData -Environment 'Test'
```

Takes the service names from the pipeline and queries the Test environment.

```powershell
Get-ExampleData -ServiceName 'Billing', 'Missing', 'Reporting'
```

Returns the results for Billing and Reporting, and writes a non-terminating error for Missing. Add
`-ErrorAction Stop` to end the command at the first error instead.

Run `Get-Help Get-ExampleData -Full` for every parameter, and `Get-Help about_ModuleExample` for the
behaviour that the examples above rely on.

## Layout

```text
Module-Structure-Example/
    ModuleExample.psd1                  manifest; names the one exported function
    ModuleExample.psm1                  root module; loads Classes, Private, Public in that order
    Classes/
        ExampleClass.ps1                the ExampleServiceResult class
    Private/
        Connect-ExampleService.ps1      not exported
        Get-ExampleServiceStatus.ps1    not exported
    Public/
        Get-ExampleData.ps1             the exported function
    Tests/
        ModuleExample.Tests.ps1
    docs/
        ModuleExample/
            Get-ExampleData.md          source of the help for Get-ExampleData
            ModuleExample.md            module page
    en-US/
        ModuleExample-Help.xml          compiled from docs; this is what Get-Help reads
        about_ModuleExample.help.txt    written by hand
```

## What the example shows

| Rule | File | What to look at |
| --- | --- | --- |
| MOD-02 | `ModuleExample.psd1` | `FunctionsToExport` names the one public function. The two functions in `Private` are loaded but not exported. |
| MOD-05 | `ModuleExample.psm1` | Strict mode, then `Classes`, `Private`, and `Public`. A file that fails to load fails the import. |
| FUN-10 | `Public/Get-ExampleData.ps1` | `[OutputType('ExampleServiceResult')]` names the class as a string. |
| FUN-21 | `Public/Get-ExampleData.ps1` | `ServiceName` is an array that the `process` block loops over, so the pipeline and an array argument behave the same way. |
| ERR-10 | `Private/Get-ExampleServiceStatus.ps1` | An unknown service becomes an `ErrorRecord` with the ID `ServiceNotFound`, passed to `$PSCmdlet.ThrowTerminatingError()`. |
| ERR-13 | `Public/Get-ExampleData.ps1` | The `catch` block passes that error to `$PSCmdlet.WriteError()` and continues with the next name. |
| DOC-09 | `Public/Get-ExampleData.ps1` | The exported function carries `.EXTERNALHELP` and a one-line synopsis. The private functions keep full comment-based help. |
| MOD-07 | `Tests/ModuleExample.Tests.ps1` | The private functions and the class are tested inside `InModuleScope`. |
| TST-17 | `Tests/ModuleExample.Tests.ps1` | The partial-failure tests merge the error stream and count the error records. |
| TST-20 | `Tests/ModuleExample.Tests.ps1` | The only mock is `Get-Date`, the clock. |

The rules are in
[powershell-modules](../../../.github/instructions/powershell-modules.instructions.md),
[powershell-functions](../../../.github/instructions/powershell-functions.instructions.md),
[powershell-error-handling](../../../.github/instructions/powershell-error-handling.instructions.md),
[powershell-help](../../../.github/instructions/powershell-help.instructions.md), and
[powershell-pester](../../../.github/instructions/powershell-pester.instructions.md).

## Tests

Run the tests from this folder:

```powershell
Invoke-Pester -Path ./Tests
```

## Help

The help for `Get-ExampleData` is written in `docs/ModuleExample/Get-ExampleData.md`. After editing
it, compile it again from this folder:

```powershell
Measure-PlatyPSMarkdown -Path ./docs/ModuleExample/*.md |
    Where-Object Filetype -Match 'CommandHelp' |
    Import-MarkdownCommandHelp -Path { $_.FilePath } |
    Export-MamlCommandHelp -OutputFolder ./maml -Force

Copy-Item -LiteralPath ./maml/ModuleExample/ModuleExample-Help.xml -Destination ./en-US -Force
```

The `maml` folder is a build intermediate, and the repository's `.gitignore` excludes it. The rules
for the Markdown are in
[powershell-platyps](../../../.github/instructions/powershell-platyps.instructions.md).

## License

MIT. See [LICENSE](../../../LICENSE).
