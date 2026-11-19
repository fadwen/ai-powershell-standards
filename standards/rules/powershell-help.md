# PowerShell help and comments

These rules apply to every `.ps1` and `.psm1` file. They cover comment-based help and ordinary
comments. Help for commands that a module exports is built from Markdown; that process is described
in `.github/instructions/powershell-platyps.instructions.md`.

## Rules

### Comment-based help

- **DOC-01** Every function and every script has comment-based help with `.SYNOPSIS`, `.DESCRIPTION`,
  one `.PARAMETER` for each parameter, at least one `.EXAMPLE`, `.INPUTS`, and `.OUTPUTS`.
- **DOC-02** In a function, the help block is the first thing inside the function body, before
  `[CmdletBinding()]`.
- **DOC-03** In a script, the help block comes before the `param()` block, with a blank line between
  it and any `#requires` line.
- **DOC-04** Write new help as a `<# ... #>` block. Help written as consecutive `#` lines is equally
  valid; do not convert it, and keep a blank line between it and any comment above it.
- **DOC-05** Help MUST describe what the code does. Performance figures, compliance claims, and
  behaviour that the code does not have MUST NOT be invented. If a fact is not known, leave it out.
- **DOC-06** `.OUTPUTS` names the same type as `[OutputType()]`. `.INPUTS` names the type that can be
  piped in, or says `None`.
- **DOC-07** Help MUST NOT contain a version number, a date, or a change history. An author name is
  added only when the user supplies one or `.github/powershell-attribution.md` lists one (DOC-18).
- **DOC-08** Each `.EXAMPLE` starts with a command that runs as written, followed by a blank line and
  a sentence saying what it does. An explanatory line placed before that blank line MUST start with
  `#` and MUST NOT be the first line.
- **DOC-09** A function that a module exports and documents as external help carries only
  `.EXTERNALHELP <ModuleName>-Help.xml` and a one-line `.SYNOPSIS`. Private functions and scripts keep
  full comment-based help.

### Help content

- **DOC-10** `.SYNOPSIS` is one line of at most 80 characters. It uses the command's approved verb,
  states the primary action and its value, and avoids technical jargon unless it is necessary.
- **DOC-11** Structure `.DESCRIPTION` in this order, leaving out a part that does not apply: core
  functionality (primary purpose and key features), why the command exists, common use cases,
  dependencies (required modules, permissions, system requirements), performance considerations,
  and side effects (changes to the system or environment).
- **DOC-12** Each `.PARAMETER` SHOULD state the data type and its constraints, whether the
  parameter is mandatory, its pipeline support (ByValue, ByPropertyName), the validation rules, why
  the parameter exists and when to use it, and sample values.
- **DOC-13** Full help SHOULD have at least three examples of increasing complexity: basic use, an
  advanced scenario with several parameters, and use in a pipeline with other commands.
- **DOC-14** The text after an example's blank line SHOULD state the scenario, the expected output
  or behaviour, and the use case, on the labelled lines `DESCRIPTION:`, `OUTPUT:`, and `USE CASE:`.
  A `DURATION:` line is added only for a time that was measured.
- **DOC-15** `.NOTES` holds security considerations (permissions and data handling), performance
  characteristics, and known limitations with their workarounds. It holds the author's name, blog,
  LinkedIn address, and other profiles only when the user supplies them or the project's
  attribution file lists them (DOC-07, DOC-18).
- **DOC-16** List references with one `.LINK` keyword for each: related commands, the online
  documentation of the command, and Microsoft documentation.
- **DOC-17** Where they have been measured, help documents typical execution time, memory use, and
  scalability. It states no performance figure that was not measured (DOC-05).
- **DOC-18** When the project has `.github/powershell-attribution.md`, take the author details from
  it: the `AUTHOR:` lines of `.NOTES` in new help, and the manifest keys of MOD-03. Use each line
  that has a value, with its label, in the file's order. A line without a value is left out and
  MUST NOT be filled in from anywhere else. Existing help is not changed only to add the details.

### Comments

- **DOC-20** A comment explains why the code is the way it is. A comment MUST NOT restate what the
  code does, and commented-out code MUST NOT be left in a file.
- **DOC-21** A comment MUST stay true when read on its own. References to a conversation, a review, or
  an earlier version of the code MUST NOT be written into a file.
- **DOC-22** A deliberate departure from a rule is recorded where the code is, in a comment directly
  above the statement or at the end of its line: `# Exception to <rule ID>: <reason>`. One comment
  names one rule, and the reason says why the rule does not fit there. The user decides an
  exception. Such a comment MUST NOT be added to make a check pass or to settle a review finding.

## Notes and examples

The function template in the core instructions shows where help goes and the keywords that DOC-01
requires. DOC-10 to DOC-17 describe the content of full help. For a command that a module exports
(DOC-09), the same content goes into its PlatyPS Markdown, where PlatyPS generates each parameter's
type, mandatory, and pipeline entries. The samples below are shortened.

**DOC-02.** `Get-Help` finds a help block only in certain positions. Verified on PowerShell 7.6 and
Windows PowerShell 5.1:

| Position of the help block | Found by `Get-Help` |
| --- | --- |
| First in the function body, before `[CmdletBinding()]` | Yes |
| Last in the function body | Yes |
| Immediately before the `function` keyword, at most one blank line between | Yes |
| Before the `function` keyword with two or more blank lines between | No |
| Between `[CmdletBinding()]` and `param()` | No |
| After `param()`, before the code | No |

A block that is not found produces no error. `Get-Help` shows only the generated syntax.

**DOC-03.** A `#requires` line directly above the help block, with no blank line, stops `Get-Help`
from finding the help:

```powershell
#requires -Version 7.6

<#
.SYNOPSIS
Rotates the application log files.

.DESCRIPTION
Compresses log files older than the retention period and removes the originals.

.PARAMETER LogDirectory
Folder that contains the log files.

.EXAMPLE
./Invoke-LogRotation.ps1 -LogDirectory './logs'

Rotates the log files in the logs folder.

.INPUTS
None.

.OUTPUTS
None.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$LogDirectory
)
```

**DOC-04.** In help written with `#` lines, an ordinary comment directly above the first keyword makes
the whole block an ordinary comment:

```powershell
function Get-Example {
    # Looks up the example record.

    # .SYNOPSIS
    # Gets an example.
    [CmdletBinding()]
    param()
}
```

Without the blank line after the first comment, `Get-Help Get-Example` shows no synopsis.

**DOC-08.** `Get-Help` adds the prompt to the first line of an example, so do not type one. Text after
the blank line is shown as the description. PowerShell 7 shows every line before the blank line as
code; Windows PowerShell 5.1 shows only the first line as code, which is why the command comes first.

```powershell
<#
.EXAMPLE
Get-ConfigValue -Path './settings.json' -Name 'Region'

Gets the Region value from settings.json.

.EXAMPLE
$values = 'Region', 'Tier' | Get-ConfigValue -Path './settings.json'
# $values[0].Name is 'Region'

Takes the names from the pipeline and keeps the results in a variable.
#>
```

**DOC-09.** `.EXTERNALHELP` makes `Get-Help` read the module's compiled help file and ignore the rest
of the comment block, so detail written there is never shown:

```powershell
function Get-Widget {
    <#
    .EXTERNALHELP Contoso.Widgets-Help.xml
    .SYNOPSIS
    Gets widgets from the inventory service.
    #>
    [CmdletBinding()]
    [OutputType('Contoso.Widget')]
    param()
}
```

**DOC-12 to DOC-16.** The labelled layout, shortened to one parameter and one example:

```powershell
<#
.PARAMETER ComputerName
[string[]] (Mandatory: Yes, Pipeline: ByValue, ByPropertyName)

Specifies one or more target computer names for data collection.

VALIDATION RULES:
- Must be valid computer names (NetBIOS or FQDN)
- Maximum 50 computers per execution

BUSINESS CONTEXT:
Used to target specific servers for monitoring. Group servers by function for meaningful reports.

EXAMPLES:
- Single server: 'SERVER01'
- Multiple servers: 'SERVER01', 'SERVER02', 'SERVER03'

.EXAMPLE
Get-ServerHealth -ComputerName 'SERVER01' -IncludePerformance

DESCRIPTION: Basic health check with performance metrics.
OUTPUT: Health status object with CPU, memory, and disk information.
USE CASE: Daily server health verification during morning checks.

.NOTES
SECURITY CONSIDERATIONS:
- Requires local administrator privileges on target servers.

KNOWN LIMITATIONS:
- Computers must be reachable through WinRM.

.LINK
Get-CimInstance

.LINK
Test-Connection
#>
```

Tested on PowerShell 7.6 and Windows PowerShell 5.1: `Get-Help` keeps these lines and the blank
lines between them, and lists each `.LINK` as one related link.

**DOC-18.** The attribution file is a list of labelled lines that the project fills in:

```markdown
- Author: Alex Example
- Company:
- Copyright holder: Alex Example
- Blog: https://blog.example.com
- LinkedIn: https://www.linkedin.com/in/alex-example
```

New help then ends its `.NOTES` with the lines that have a value. `Company` is empty, so it is left
out; `Copyright holder` belongs to the manifest only:

```powershell
<#
.NOTES
KNOWN LIMITATIONS:
- Computers must be reachable through WinRM.

AUTHOR:
- Author: Alex Example
- Blog: https://blog.example.com
- LinkedIn: https://www.linkedin.com/in/alex-example
#>
```

Tested on PowerShell 7.6 and Windows PowerShell 5.1: `Get-Help -Full` shows the `AUTHOR:` block as
written, after the other notes.

The standards installer creates the file when it is missing and never changes it afterwards. It
starts from the profile of the project's GitHub owner when the standards repository has one, and
from an empty template otherwise.

**DOC-20.**

```powershell
# Compliant: says why
# The service rejects requests for more than 100 items, so page through the results.
$pageSize = 100

# Non-compliant: restates the code
# Set page size to 100
$pageSize = 100
```

**DOC-22.** The comment keeps the decision with the code, where every agent and every reviewer reads
it. A note in a project file that only one tool loads does not do that.

```powershell
function Get-StaleRecord {
    [CmdletBinding()]
    [OutputType('Contoso.StaleRecord')]
    param()

    try {
        $session = Connect-RecordStore -ErrorAction Stop
    } catch {
        # Exception to ERR-11: the scheduled cleanup that calls this command sets no error
        # preference, and it must end when the store cannot be reached.
        Write-Error -ErrorRecord $_ -ErrorAction Stop
    }

    Get-RecordStoreItem -Session $session -Stale
}
```

The reason can run over several comment lines. A blank line between the comment and the statement
separates the two, and the comment then excuses nothing.

A review lists a recorded exception with its reason, apart from the findings, and reports one whose
reason is missing or is no longer true (DOC-21). The compliance check of the standards repository,
`Test-StandardsCompliance.ps1`, reports the excused finding with the severity Information and does
not fail on it. It reports the comment itself when the reason is missing, and when the comment names
a rule that the check covers and excuses nothing.

The comment does not silence PSScriptAnalyzer. Suppress one of its findings with its own attribute
on the function, and give the attribute a justification:

```powershell
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost', '', Justification = 'The menu needs colour.')]
[CmdletBinding()]
param()
```
