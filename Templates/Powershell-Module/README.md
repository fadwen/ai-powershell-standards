# ModuleName

A module to copy and rename, laid out as the PowerShell standards in this repository ask. As shipped,
it exports one function, `Get-TemplateFunction`, which returns the settings that
`Configuration/DefaultConfiguration.psd1` defines for an environment. The function is there to show
the shape of a module; replace it with your own.

## Requirements

- PowerShell 7.6 or later, Core edition. The module calls no platform-specific commands.
- No other module is needed to use it.
- Pester 6.2.0 or later, to run the tests.

## Installation

The template is not published. To try it as it is, import it from this folder:

```powershell
Import-Module -Name ./ModuleName.psd1 -Force
```

To start a module from it:

1. Copy this folder and give the copy the name of your module.
2. Rename `ModuleName.psd1` and `ModuleName.psm1` to that name, and set `RootModule` in the manifest
   to the new name of the `.psm1` file.
3. In the manifest, replace `GUID` with the output of `New-Guid`, and set `Author` and `Description`.
4. Replace `ModuleName` wherever it stands for the name of the module: in the test files, in the
   file name of `Tests/ModuleName.Tests.ps1`, and in the type name `ModuleName.EnvironmentSetting`.
   Leave the parameter `-ModuleName` of `Mock` and `Should-Invoke` and the key `ModuleName` of the
   `#Requires` lines as they are. They belong to Pester and PowerShell.
5. Run the tests. They pass before any function has changed.
6. Replace `Get-TemplateFunction` and `Import-TemplateSetting` with your own functions, one file for
   each function, and name every public function in `FunctionsToExport`.

## Usage

```powershell
Get-TemplateFunction -Name 'Production'
```

Gets the settings of the Production environment. The result is a `ModuleName.EnvironmentSetting`
object with `Name`, `LogLevel`, `TimeoutSeconds`, and `RetryCount` properties.

```powershell
'Development', 'Staging', 'Production' | Get-TemplateFunction
```

Takes the names from the pipeline. The settings file does not define Staging, so the command returns
the settings of Development and Production and writes a non-terminating error for Staging.

Run `Get-Help Get-TemplateFunction -Full` for the parameter and the examples.

## Layout

```text
Powershell-Module/
    ModuleName.psd1                         manifest; names the one exported function
    ModuleName.psm1                         root module; loads Classes, Private, Public in that order
    Configuration/
        DefaultConfiguration.psd1           the settings that Get-TemplateFunction returns
    Private/
        Import-TemplateSetting.ps1          not exported; reads the settings file
    Public/
        Get-TemplateFunction.ps1            the exported function
    Tests/
        Get-TemplateFunction.Tests.ps1
        Import-TemplateSetting.Tests.ps1
        ModuleName.Tests.ps1                the manifest and the list of exported commands
```

The template has no `Classes` folder. The root module skips a folder that does not exist, so add
`Classes` when the module defines a class.

## What the template shows

| Rule | File | What to look at |
| --- | --- | --- |
| MOD-02 | `ModuleName.psd1` | `FunctionsToExport` names the one public function, and the other export lists are empty. |
| MOD-05 | `ModuleName.psm1` | Strict mode, then `Classes`, `Private`, and `Public`. A file that fails to load fails the import. |
| ERR-10 | `Public/Get-TemplateFunction.ps1` | The `begin` block ends the function with `$PSCmdlet.ThrowTerminatingError()` when the settings cannot be used. |
| ERR-13 | `Public/Get-TemplateFunction.ps1` | An environment that is not defined goes to `$PSCmdlet.WriteError()`, and the loop continues with the next name. |
| FUN-10 | `Public/Get-TemplateFunction.ps1` | `[OutputType('ModuleName.EnvironmentSetting')]` names the type, and the object carries the same name as `PSTypeName`. |
| STY-31 | `Private/Import-TemplateSetting.ps1` | The settings file is located from `$PSScriptRoot`. |
| TST-21 | `Tests/Get-TemplateFunction.Tests.ps1` | The mock of `Import-PowerShellDataFile` names the module, because the call is made inside the module. |
| MOD-07 | `Tests/Import-TemplateSetting.Tests.ps1` | The private function is tested inside `InModuleScope`. |

The rules are in
[powershell-modules](../../.github/instructions/powershell-modules.instructions.md),
[powershell-functions](../../.github/instructions/powershell-functions.instructions.md),
[powershell-error-handling](../../.github/instructions/powershell-error-handling.instructions.md),
[powershell-style](../../.github/instructions/powershell-style.instructions.md), and
[powershell-pester](../../.github/instructions/powershell-pester.instructions.md).

## Tests

Run the tests from this folder:

```powershell
Invoke-Pester -Path ./Tests
```

## Help

`Get-TemplateFunction` carries full comment-based help. To ship the help of the exported commands as
compiled external help, follow
[powershell-platyps](../../.github/instructions/powershell-platyps.instructions.md). Add
`.EXTERNALHELP` to a function only after its Markdown has been generated, because the keyword hides
the comment block that the Markdown is generated from.

## License

MIT. See [LICENSE](../../LICENSE). A module started from the template states its own license here.
