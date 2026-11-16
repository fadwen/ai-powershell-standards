# Examples

Working code that follows the PowerShell standards in this repository, and one file that breaks them
on purpose. The function, the module, and the negative example have Pester tests.

## Requirements

- PowerShell 7.6 or later.
- Windows, for `Basic-Function-Example.ps1`. It calls the CIM commands and queries computers over
  WinRM.
- Pester 6.2.0 or later, to run the tests.
- PSScriptAnalyzer 1.25.0 or later, for `Test-QualityGates.Tests.ps1`.

## Contents

| Example | What it shows |
| --- | --- |
| [Basic-Function-Example.ps1](Basic-Function-Example.ps1) | One advanced function, `Get-BasicServerInfo`, with pipeline input, per-item errors, and a named output type. |
| [Testing-Examples/](Testing-Examples/) | The tests for `Get-BasicServerInfo`, with the CIM commands and the clock mocked. |
| [Module-Structure-Example/](Module-Structure-Example/) | A small working module. Its own [README](Module-Structure-Example/README.md) describes it. |
| [Configuration/DefaultConfiguration.psd1](Configuration/DefaultConfiguration.psd1) | A settings file that holds data only. |
| [Test-QualityGates.ps1](Test-QualityGates.ps1) | A negative example. It breaks the standards on purpose and is not code to copy. |

## Usage

Run the commands in this section from this folder.

### The function example

```powershell
. ./Basic-Function-Example.ps1

Get-BasicServerInfo -ComputerName 'SERVER01'
'SERVER01', 'SERVER02' | Get-BasicServerInfo -IncludeServices
```

Replace the names with computers that accept WinRM connections. The first command returns one
`Example.ServerInfo` object. The second takes the names from the pipeline and fills the
`RunningServices` property of each object. A computer that cannot be queried produces a
non-terminating error, and the remaining computers are still processed.

| Rule | What to look at in the file |
| --- | --- |
| DOC-02 | The help block is the first thing in the function body. |
| FUN-10 | `[OutputType('Example.ServerInfo')]` names the type, and the object carries the same name as `PSTypeName`. |
| FUN-21 | `ComputerName` is an array that the `process` block loops over. |
| FUN-31 | The function only reads, so it does not declare `SupportsShouldProcess`. |
| SEC-03 | `Credential` is a `PSCredential` with the `Credential()` attribute and an empty default. |
| SEC-11 | An anchored `ValidatePattern` rejects a bad computer name when the parameter is bound. |
| ERR-13, ERR-14 | The `catch` block wraps the failure in a new `ErrorRecord`, passes it to `$PSCmdlet.WriteError()`, and continues with the next computer. |
| ERR-22 | The CIM session is closed in `finally`. |

### The settings file

```powershell
$settings = Import-PowerShellDataFile -LiteralPath ./Configuration/DefaultConfiguration.psd1
$settings['Environments']['Production']['TimeoutSeconds']
```

Reads the file into a hashtable and returns `10`, the timeout of the Production environment.

### The negative example

[Test-QualityGates.ps1](Test-QualityGates.ps1) exists so that the quality gates have something to
catch. Its header lists every rule it breaks, in two groups: the violations that PSScriptAnalyzer
reports, and the ones that it does not report.

```powershell
Invoke-ScriptAnalyzer -Path ./Test-QualityGates.ps1 -Settings ../../PSScriptAnalyzerSettings.psd1
```

Shows the first group. An analysis run that has to pass must leave this file out by name.

## Tests

```powershell
Invoke-Pester -Path ./Testing-Examples, ./Test-QualityGates.Tests.ps1
```

Runs the tests for the function example and for the negative example. The tests for the negative
example record what its functions do, and they fail when a violation is added to the file or removed
from it. The module example has its own tests; see its README.

## Related files

- [PSScriptAnalyzerSettings.psd1](../../PSScriptAnalyzerSettings.psd1): the analyzer settings that
  check the layout rules.
- [Templates/Powershell-Module](../../Templates/Powershell-Module/): a module to copy and rename.
- The rules that the examples follow:
  [powershell-functions](../../.github/instructions/powershell-functions.instructions.md),
  [powershell-error-handling](../../.github/instructions/powershell-error-handling.instructions.md),
  [powershell-help](../../.github/instructions/powershell-help.instructions.md), and
  [powershell-pester](../../.github/instructions/powershell-pester.instructions.md).
