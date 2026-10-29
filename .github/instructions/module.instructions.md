---
applyTo: "**/*.psm1,**/*.psd1,**/Public/*.ps1,**/Private/*.ps1"
description: 'Creates enterprise-grade PowerShell modules with proper structure, security, and functionality'
---

# PowerShell Module Development Assistant

Create comprehensive, enterprise-grade PowerShell modules that follow organizational standards, implement security best
practices, and provide scalable functionality for business operations.

## Module Planning and Design

### Initial Requirements Gathering

Collect essential information for module development:

#### Module Specifications

- **Module Name**: Following PowerShell naming conventions (noun should be singular)
- **Primary Purpose**: Clear business value and functional scope
- **Target Audience**: System administrators, developers, end users, or automation systems
- **Functionality Scope**: Core features and capabilities to implement
- **Dependencies**: Required PowerShell modules and external systems
- **Security Requirements**: Authentication, authorization, and data protection needs
- **Performance Targets**: Expected load, scalability, and response time requirements

#### Technical Requirements

- **PowerShell Versions**: PowerShell 7.6 (LTS, default for new modules), or 5.1 + 7.6 when the module must run on
  Windows estates without pwsh. Do not target 7.4/7.5 alone — both lose support 10-Nov-2026
- **Platform Support**: Windows, Linux, macOS, or cross-platform
- **Integration Points**: External APIs, databases, file systems, or services
- **Deployment Method**: PowerShell Gallery, internal repository, or direct installation

## Module Structure Generation

> **Worked example**:
> [powershell-standards/Examples/Module-Structure-Example](../../powershell-standards/Examples/Module-Structure-Example/)
> is a small working module implementing everything in this section - the folder layout, the load
> order in `ModuleExample.psm1`, an explicit `FunctionsToExport`, a class used as a named output
> type, and a private helper that is never exported. Read it before generating a new module; prefer
> matching its shape over inventing one.

### Standard Module Directory Structure

Create the complete module structure following enterprise standards:

```text
ModuleName/
├── ModuleName.psd1                 # Module manifest
├── ModuleName.psm1                 # Root module file
├── Public/                         # Exported functions
│   ├── Get-ModuleFunction.ps1
│   ├── Set-ModuleConfiguration.ps1
│   └── Invoke-ModuleProcess.ps1
├── Private/                        # Internal functions
│   ├── Test-InternalValidation.ps1
│   └── Connect-InternalService.ps1
├── Classes/                        # PowerShell classes
│   ├── ModuleConfiguration.ps1
│   └── ModuleException.ps1
├── Data/                          # Static data and configuration
│   ├── DefaultConfiguration.psd1
│   └── ErrorCodes.psd1
├── Tests/                         # Comprehensive test suite
│   ├── Unit/
│   ├── Integration/
│   └── Performance/
├── docs/                          # PlatyPS command help - Markdown source, committed
│   └── ModuleName/
│       ├── ModuleName.md          # module page
│       └── Get-ModuleFunction.md  # one file per exported command
├── en-US/                         # Compiled help, packaged with the module
│   ├── ModuleName-Help.xml        # built by Export-MamlCommandHelp - never hand-edited
│   └── about_ModuleName.help.txt  # hand-written conceptual topic
├── Troubleshooting/              # Organized troubleshooting docs
│   ├── Common/
│   ├── Security/
│   ├── Performance/
│   └── Integration/
├── Documentation/                # Project documentation
├── Configuration/               # Environment configurations
├── Scripts/                    # Utility scripts
└── README.md                   # Main documentation
```

`docs/` and `en-US/` are generated and maintained with **Microsoft.PowerShell.PlatyPS** — see
[platyps.instructions.md](./platyps.instructions.md). Every function in `Public/` must carry
`.EXTERNALHELP ModuleName-Help.xml`, or the shipped MAML is silently ignored in favour of the
comment block.

### Module Manifest Creation

Generate comprehensive module manifest (ModuleName.psd1). For a complete, valid manifest see
[ModuleExample.psd1](../../powershell-standards/Examples/Module-Structure-Example/ModuleExample.psd1) -
note that `FunctionsToExport` names each public function explicitly, which is what keeps private
helpers internal:

```powershell
@{
    # Basic Module Information
    RootModule = 'ModuleName.psm1'
    ModuleVersion = '1.0.0'
    GUID = '$(New-Guid)'
    Author = 'Jeffrey Stuhr'
    CompanyName = 'Organization Name'
    Copyright = '(c) $(Get-Date -Format yyyy) Organization Name. All rights reserved.'
    Description = 'Comprehensive description of module functionality and business value'

    # PowerShell Version Requirements
    # Default to 7.6 (LTS). Switch to '5.1' + @('Desktop','Core') only when Windows PowerShell
    # support is an explicit requirement — see instructions/powershell-version.instructions.md
    PowerShellVersion = '7.6'
    CompatiblePSEditions = @('Core')

    # Dependencies
    RequiredModules = @(
        @{ ModuleName = 'PSFramework'; ModuleVersion = '1.7.270' }
    )

    # Module Components
    FunctionsToExport = @('Get-ModuleFunction', 'Set-ModuleConfiguration')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    # PowerShell Gallery Metadata
    PrivateData = @{
        PSData = @{
            Tags = @('PowerShell', 'Enterprise', 'Automation', 'Management')
            LicenseUri = 'https://github.com/organization/modulename/blob/main/LICENSE'
            ProjectUri = 'https://github.com/organization/modulename'
            # Omit IconUri when there is no icon. An empty string is not "no icon": NuGet
            # aborts the pack with "IconUrl cannot be empty" and names neither file nor key.
            IconUri = 'https://github.com/organization/modulename/raw/main/Assets/icon.png'
            # The current release only, ending with a pointer to CHANGELOG.md. The Gallery
            # refuses more than 10,600 characters, and only at upload.
            ReleaseNotes = 'Initial release with core functionality'
            RequireLicenseAcceptance = $false
        }
    }

    # Help Information
    # Only set this if you actually publish an Updatable Help package to that location.
    # Update-Help reports an error against a HelpInfoURI with no HelpInfo.xml behind it.
    # Shipping MAML in en-US/ does not require this key. Omit it rather than setting it
    # to '' - an empty value fails the pack the same way an empty IconUri does.
    HelpInfoURI = 'https://docs.organization.com/powershell/modulename'
}
```

### Root Module Implementation

Create optimized root module file (ModuleName.psm1). Load order matters: classes first, then private
functions, then public ones - see
[ModuleExample.psm1](../../powershell-standards/Examples/Module-Structure-Example/ModuleExample.psm1) for a
working loader.

```powershell
# Match the manifest's PowerShellVersion. This template targets 7.6; use 5.1 only
# when the module is built for Windows PowerShell compatibility.
#Requires -Version 7.6

# Module initialization
$ModuleRoot = $PSScriptRoot
Write-Verbose "Initializing module: $($MyInvocation.MyCommand.Module.Name)"

# Import module components in order
try {
    # Load Classes first (dependencies for functions)
    $classFiles = Get-ChildItem -Path "$ModuleRoot\Classes\*.ps1" -ErrorAction SilentlyContinue
    foreach ($class in $classFiles) {
        Write-Verbose "Loading class: $($class.Name)"
        . $class.FullName
    }

    # Load Private functions
    $privateFunctions = Get-ChildItem -Path "$ModuleRoot\Private\*.ps1" -ErrorAction SilentlyContinue
    foreach ($function in $privateFunctions) {
        Write-Verbose "Loading private function: $($function.Name)"
        . $function.FullName
    }

    # Load Public functions
    $publicFunctions = Get-ChildItem -Path "$ModuleRoot\Public\*.ps1" -ErrorAction SilentlyContinue
    foreach ($function in $publicFunctions) {
        Write-Verbose "Loading public function: $($function.Name)"
        . $function.FullName
    }

    # Load Data files
    $script:ModuleConfiguration = Import-PowerShellDataFile -Path "$ModuleRoot\Data\DefaultConfiguration.psd1" -ErrorAction SilentlyContinue

    Write-Verbose "Module loaded successfully. Public functions: $($publicFunctions.Count), Private functions: $($privateFunctions.Count)"
}
catch {
    Write-Error "Failed to load module components: $($_.Exception.Message)"
    throw
}

# Module cleanup on removal
$ExecutionContext.SessionState.Module.OnRemove = {
    Write-Verbose "Cleaning up module: $($MyInvocation.MyCommand.Module.Name)"
    # Clean up module variables and resources
    Remove-Variable -Name ModuleConfiguration -Scope Script -ErrorAction SilentlyContinue
}
```

## Function Development

### Public Function Template

Generate public functions following enterprise standards:

```powershell
function Verb-Noun {
    <#
    .SYNOPSIS
        Brief description using approved PowerShell verb-noun pattern

    .DESCRIPTION
        Comprehensive description including business value, functionality,
        dependencies, and performance characteristics

    .PARAMETER ParameterName
        [Type] (Mandatory: Yes/No, Pipeline: ByValue/ByPropertyName)
        Detailed parameter description with validation rules and business context

    .EXAMPLE
        PS> Verb-Noun -ParameterName "Value"

        DESCRIPTION: What this example demonstrates
        OUTPUT: Expected output description
        USE CASE: Business scenario

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: $(Get-Date -Format 'yyyy-MM-dd')

        TROUBLESHOOTING:
        - Common issues: .\Troubleshooting\Common\Function-Issues.md
        - Performance: .\Troubleshooting\Performance\Optimization.md
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([ExpectedOutputType])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ParameterName
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting $($MyInvocation.MyCommand.Name) - CorrelationId: $correlationId"

        # Initialize collections and validation
    }

    process {
        try {
            if ($PSCmdlet.ShouldProcess($ParameterName, "Action Description")) {
                # Core function logic with proper error handling
                # Include correlation ID in all operations
            }
        }
        catch {
            Write-Error "Failed to process $ParameterName : $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed $($MyInvocation.MyCommand.Name) - CorrelationId: $correlationId"
    }
}
```

### Functions That Reduce Their Input to One Result

`ValueFromPipeline` changes what `process` receives. Passed by parameter, a collection arrives in
`process` once, as one argument. Piped, PowerShell unrolls it and `process` runs once per element. A
function that reduces its input to a single result, such as folding a set of policy evaluations into
one outcome, gives a different answer on each path unless it handles both: by parameter it folds the
whole collection, piped it folds each element on its own and emits one wrong result per element. No
error is raised, and every result has the declared output type.

For such a function:

- Collect in `process` and fold in `end`. Elements arriving one at a time go into a `List[object]`
  and the set is folded once the pipeline closes.
- Decide what a single element arriving alone means, and write that decision into the function. A
  whole input that is itself one object (an envelope with a `value` property, a JSON string) is
  folded as it arrives, so piping several whole inputs still yields one result each.
- Exclude `[string]` before any `IEnumerable` check. A string enumerates as characters.
- A hashtable is `IEnumerable` too, and is one object rather than a collection.

```powershell
function ConvertTo-Outcome {
    [CmdletBinding()]
    [OutputType('Module.Outcome')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject
    )

    begin {
        # Elements piped in one at a time are held here and folded together in end
        $loose = [System.Collections.Generic.List[object]]::new()
    }

    process {
        # A lone element is a single object without the envelope's value property. A string is
        # IEnumerable (of characters) and a hashtable is IEnumerable (of entries), so both are
        # settled before the enumerable check.
        $isLoneElement = $null -ne $InputObject -and $InputObject -isnot [string] -and
            ($InputObject -is [hashtable] -or $InputObject -isnot [System.Collections.IEnumerable])
        if ($isLoneElement) {
            if ($InputObject -is [hashtable]) {
                $isLoneElement = -not $InputObject.ContainsKey('value')
            } else {
                $isLoneElement = -not $InputObject.PSObject.Properties['value']
            }
        }

        if ($isLoneElement) {
            $loose.Add($InputObject)
        } else {
            # A whole input arrived at once: a collection by parameter, an envelope, a JSON string
            Get-FoldedOutcome -Response $InputObject
        }
    }

    end {
        if ($loose.Count -gt 0) {
            Get-FoldedOutcome -Response $loose.ToArray()
        }
    }
}
```

Test both paths. `-InputObject $collection` and `$collection | ConvertTo-Outcome` run different code
once the input is enumerable, and the piped test must pipe the shape the real upstream command
produces. A usage example in the README or in help is a test case until one exists that runs it as
written. See the [Unit Test Template](./pester-supporting-docs/unit-test-template.md).

### Responses That Arrive as Hashtables or PSObjects

The same JSON reaches a function in two shapes. `Invoke-MgGraphRequest` returns hashtables unless
`-OutputType PSObject` is passed; `ConvertFrom-Json` returns PSObjects unless `-AsHashtable` is
passed (PowerShell 7); a baseline or fixture read back from disk comes through `ConvertFrom-Json`. A
function that reads response data with one syntax is correct for one shape and silently wrong for
the other. Measured on PowerShell 7.6 and Windows PowerShell 5.1 alike:

| Read | Hashtable | PSObject |
|---|---|---|
| `$response['value']` | the value | `$null` with no error; an error only under `Set-StrictMode` |
| `$response.value` | the value | the value |
| `$response.Count` | the key `Count` when one exists, otherwise the number of entries | the property when one exists, otherwise `1` |
| `$response.missing` | `$null` | `$null` |

Index syntax reads only the hashtable. Member syntax reads both, but a key named like a hashtable
member (`Count`, `Keys`, `Values`) comes back as the hashtable's own property when the key is absent,
and a scalar's `Count` is `1`, so neither is `$null` when the data is missing. CaOutcome computed
Conditional Access outcomes from nulls, with no error, until every read of response data went
through one accessor:

```powershell
function Get-ResponseProperty {
    <#
    .SYNOPSIS
        Reads one property from response data in either shape it can arrive in.

    .DESCRIPTION
        Private helper. Graph SDK responses are hashtables by default and PSObjects with
        -OutputType PSObject; ConvertFrom-Json is the reverse. Indexing a PSObject with a key
        returns $null with no error, so every read of anything that came from an API or a file
        goes through this function.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }
    return $null
}
```

Use it for every read of anything that came from an API or a file. Like any function, it unrolls a
one-element collection on the way out, so wrap a read of a collection such as `value` in `@(...)`
before indexing or counting it. Test the public function with both shapes: the fixture parsed with
`ConvertFrom-Json`, and again with `ConvertFrom-Json -AsHashtable` or through the SDK's hashtable
form. Keep fixtures real: a recorded response with identifiers rewritten, because every shape defect
found this way came from a shape the API returned rather than one anybody imagined.

### Class Development

Create PowerShell classes with proper validation and methods. One constraint comes with the dot-source
loader above: **a class or enum defined in `Classes/` must not appear as a type constraint in any
`param()` block.** A type literal in a parameter attribute is resolved when the file is parsed, and a
dot-sourced file cannot see a class defined by a sibling file at that moment. Casts and `::new()` calls
in a function body are fine, because they resolve at run time. One `[ModuleConfiguration]$Config`
parameter breaks the import for every command in the module, not only the one that declares it. Take
`[object]` or `[PSCustomObject]` at the boundary and validate the type in the body, or build the module
into a single file whose classes precede the functions.

```powershell
# Classes/ModuleConfiguration.ps1
class ModuleConfiguration {
    [ValidateNotNullOrEmpty()]
    [string]$Environment

    [ValidateRange(1, 5)]
    [int]$LogLevel = 3

    [hashtable]$CustomSettings = @{}

    # Constructor with validation
    ModuleConfiguration([string]$Environment) {
        if ([string]::IsNullOrWhiteSpace($Environment)) {
            throw [ArgumentNullException]::new('Environment')
        }
        $this.Environment = $Environment
    }

    # Business logic methods
    [bool] Validate() {
        # Implement validation logic
        return $true
    }

    [hashtable] ToHashtable() {
        return @{
            Environment = $this.Environment
            LogLevel = $this.LogLevel
            CustomSettings = $this.CustomSettings
        }
    }
}
```

## Security Implementation

### Input Validation and Sanitization

Implement comprehensive input validation:

```powershell
function Protect-UserInput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputString,
        [ValidateSet('ComputerName', 'FileName', 'UserName', 'General')]
        [string]$InputType = 'General'
    )

    # Length validation
    if ($InputString.Length -gt 1000) {
        throw [ValidationException]::new("Input exceeds maximum length", "InputString", $InputString)
    }

    # Type-specific validation
    switch ($InputType) {
        'ComputerName' {
            if ($InputString -notmatch '^[a-zA-Z0-9\-\.]+$') {
                throw [ValidationException]::new("Invalid computer name format", "InputString", $InputString)
            }
        }
        'FileName' {
            $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
            foreach ($char in $invalidChars) {
                if ($InputString.Contains($char)) {
                    throw [ValidationException]::new("Invalid file name character: $char", "InputString", $InputString)
                }
            }
        }
    }

    return $InputString.Trim()
}
```

### Credential Management Integration

Implement secure credential handling:

```powershell
function Get-ModuleCredential {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$VaultName = 'DefaultVault'
    )

    try {
        # Use SecretManagement for secure credential storage
        $credential = Get-Secret -Name $Name -Vault $VaultName -AsPlainText:$false -ErrorAction Stop
        return $credential
    }
    catch {
        Write-Warning "Credential not found in vault, prompting user"
        return Get-Credential -Message "Enter credentials for: $Name"
    }
}
```

## Testing Framework Integration

### Pester Test Structure

Generate comprehensive test suites targeting **Pester 6.2+**:

```powershell
# Tests/Unit/Public/Verb-Noun.Tests.ps1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    # Pester 6 discovers and runs one file at a time - each file must be self-contained
    $ModulePath = Join-Path $PSScriptRoot '..\..\..\..\ModuleName.psd1'
    Import-Module $ModulePath -Force
}

Describe "Verb-Noun" -Tag "Unit", "Public" {
    Context "Parameter Validation" {
        # -ForEach data is injected as variables - no param() block needed.
        # Never name a key 'Input' - it collides with the automatic variable.
        It "Should accept valid input: <TestValue>" -ForEach @(
            @{ TestValue = 'ValidValue1' }
            @{ TestValue = 'ValidValue2' }
        ) {
            # There is no Should-NotThrow - just call it; a throw fails the test
            Verb-Noun -ParameterName $TestValue
        }

        It "Should reject invalid input" {
            { Verb-Noun -ParameterName $null } | Should-Throw
        }
    }

    Context "Functionality" {
        BeforeEach {
            Mock External-Dependency { "MockedResult" }
        }

        It "Should return expected result" {
            Verb-Noun -ParameterName "TestValue" | Should-NotBeNull
        }

        It "Should call the dependency once" {
            Verb-Noun -ParameterName "TestValue"
            Should-Invoke External-Dependency -Times 1 -Exactly
        }
    }

    Context "Error Handling" {
        It "Should handle errors gracefully" {
            Mock External-Dependency { throw "Test Error" }
            { Verb-Noun -ParameterName "TestValue" } |
                Should-Throw -ExceptionMessage "*Test Error*"
        }
    }
}
```

Key Pester 6 points: `Should-*` assertions replace `Should -Be` for new tests,
`Assert-MockCalled` was removed in favour of `Should-Invoke`, and every file must import its own
dependencies. See
[Pester instructions](./pester.instructions.md) and the
[migration guide](./pester-supporting-docs/v6-migration.md).

## Performance Optimization

### Efficient Resource Management

Implement performance best practices:

```powershell
# Memory-efficient processing
function Process-LargeDataSet {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object[]]$InputObject
    )

    begin {
        # Initialize StringBuilder for efficient string operations
        $sb = [System.Text.StringBuilder]::new()
        $results = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in $InputObject) {
            # Process items in pipeline for memory efficiency
            $processedItem = Process-Item $item
            $results.Add($processedItem)
        }
    }

    end {
        # Return results and cleanup
        return $results.ToArray()
    }
}
```

### Caching Implementation

Add intelligent caching for improved performance:

```powershell
# Module-level caching
$script:ModuleCache = @{}

function Get-CachedResult {
    param([string]$Key, [ScriptBlock]$Operation, [int]$ExpirationMinutes = 15)

    $cacheEntry = $script:ModuleCache[$Key]
    if ($cacheEntry -and $cacheEntry.ExpirationTime -gt (Get-Date)) {
        return $cacheEntry.Value
    }

    # Execute operation and cache result
    $result = & $Operation
    $script:ModuleCache[$Key] = @{
        Value = $result
        ExpirationTime = (Get-Date).AddMinutes($ExpirationMinutes)
    }

    return $result
}
```

## Documentation and Troubleshooting

### README Generation

Create comprehensive README following enterprise standards:

```markdown
# ModuleName

## 📖 Overview
Clear business value and technical summary

## 🚀 Quick Start
Copy-paste ready examples for immediate use

## 📋 Prerequisites
System requirements, dependencies, and permissions

## 🔧 Installation
Step-by-step installation instructions

## 💡 Usage
Basic and advanced usage examples

## 🔍 Troubleshooting
Reference to ./Troubleshooting/ folder organization

## 📚 References
Links to additional documentation and resources
```

### Troubleshooting Documentation Structure

Organize troubleshooting documentation in standardized folders:

```text
Troubleshooting/
├── Common/
│   ├── Installation-Issues.md
│   ├── Function-Errors.md
│   └── Configuration-Problems.md
├── Security/
│   ├── Credential-Management.md
│   └── Permission-Issues.md
├── Performance/
│   ├── Memory-Usage.md
│   └── Slow-Execution.md
└── Integration/
    ├── API-Connection-Issues.md
    └── External-Dependencies.md
```

## Releasing to the PowerShell Gallery

A Gallery version is consumed the moment it uploads. It can be unlisted but never deleted, and the
`.nupkg` stays downloadable at its direct URL afterwards. Each rule below comes from a release of a
module built to these standards that passed every local gate and then shipped the wrong thing or
failed at the upload.

### Stage an allowlist, never publish the repository root

When the repository is the module root, `Publish-PSResource -Path .` packages the working tree:
`.git`, the tests and their fixtures, the build scripts, and anything else on disk. Measured on one
module: 313 files and 975 KB, all 213 files of `.git` among them, against 46 files and 507 KB for
the module itself.

Publish from a staging folder that an allowlist fills. A new folder does not ship until it is named,
and the staged copy is imported in a fresh process and checked before anything uploads:

```powershell
# Build/Publish-Module.ps1 - [CmdletBinding(SupportsShouldProcess)] with -WhatIf as the rehearsal
$shipFiles = 'ModuleName.psd1', 'ModuleName.psm1', 'README.md', 'CHANGELOG.md', 'LICENSE'
$shipFolders = 'Classes', 'Private', 'Public', 'en-US', 'Troubleshooting'

# out/ is git-ignored. Every step but the publish is pinned -WhatIf:$false; see below for why.
$stage = Join-Path (Join-Path $PSScriptRoot '..\out') 'ModuleName'
if (Test-Path $stage) {
    Remove-Item -Path $stage -Recurse -Force -WhatIf:$false
}
New-Item -Path $stage -ItemType Directory -Force -WhatIf:$false | Out-Null
foreach ($item in $shipFiles + $shipFolders) {
    Copy-Item -Path (Join-Path $PSScriptRoot "..\$item") -Destination $stage -Recurse -WhatIf:$false
}

# A fresh process proves the staged copy imports on its own and exports what the manifest says
$exported = pwsh -NoProfile -Command "Import-Module '$stage' -Force; (Get-Module ModuleName).ExportedFunctions.Keys"

if ($PSCmdlet.ShouldProcess("ModuleName $($manifest.ModuleVersion)", 'Publish to PSGallery')) {
    Publish-PSResource -Path $stage -Repository PSGallery -ApiKey $env:PSGALLERY_API_KEY
}
```

Pass the API key through an environment variable or a SecretManagement secret, never on the command
line of a workflow step, where it lands in the run log.

### Metadata the Gallery refuses at upload

Three fields carry a limit that is enforced only on upload, so every local gate passes until the
publish step returns 400:

| Field | Limit | Whose limit |
|---|---|---|
| `ReleaseNotes` | 10,600 characters | The Gallery's, stated in its error response |
| `Description` | 4,000 characters | NuGet's |
| Package tags | 4,000 characters | NuGet's, applied to the full tag list, not to the manifest's `Tags` key alone |

The tag list the Gallery stores is the manifest's `Tags` plus what the publish adds: `PSModule`, a
`PSEdition_` tag per compatible edition, `PSIncludes_Function`, and `PSFunction_` and `PSCommand_`
for every exported function. A module with 27 commands carries 61 tags and about 1,900 characters,
so each new command costs about twice its name and a module that keeps adding commands reaches the
limit without its `Tags` key changing.

`ReleaseNotes` grows the same way when every release prepends its paragraph and none removes one.
Two modules built to these standards were refused at 11,319 and 12,699 characters, each after every
other gate had passed and the tag had been pushed. Keep the current release's notes in the manifest
and end them with a pointer to `CHANGELOG.md`, which ships in the package and already holds the
history.

Measure all three in the release rehearsal and in a contract test, so a pull request fails rather
than the tag-driven release:

```powershell
$manifest = Import-PowerShellDataFile -Path ./ModuleName.psd1
$module = Get-Module -Name ModuleName   # the staged copy
$tags = @($manifest.PrivateData.PSData.Tags) + 'PSModule' + 'PSIncludes_Function' +
    @($manifest.CompatiblePSEditions | ForEach-Object { "PSEdition_$_" }) +
    @($module.ExportedFunctions.Keys | ForEach-Object { "PSFunction_$_"; "PSCommand_$_" })

$limits = @{
    Description  = @{ Length = $manifest.Description.Length; Limit = 4000 }
    Tags         = @{ Length = ($tags -join ' ').Length; Limit = 4000 }
    ReleaseNotes = @{ Length = $manifest.PrivateData.PSData.ReleaseNotes.Length; Limit = 10600 }
}
foreach ($field in $limits.Keys) {
    $measured = $limits[$field]
    if ($measured.Length -gt $measured.Limit) {
        $message = "The manifest's $field is $($measured.Length) characters; " +
            "the Gallery accepts at most $($measured.Limit)"
        Write-Error $message -ErrorAction Stop
    }
}
```

A module that exports cmdlets or DSC resources gains further automatic tags (`PSCmdlet_`,
`PSDscResource_`); build the list the way the publish does for what the module ships.

### Omit a URI key rather than leaving it empty

`IconUri = ''` is not "no icon". The nuspec writer emits an empty `<iconUrl>` and NuGet aborts the
pack with `IconUrl cannot be empty`, naming neither the manifest nor the key. `HelpInfoURI = ''`
fails the same way. Leave the key out until there is a value, and have the rehearsal check for an
empty one. Setting `IconUri` has no visible effect on the Gallery in any case: the package page
renders the default PowerShell logo and does not fetch the icon.

### The rehearsal under `-WhatIf`

`-WhatIf` sets `$WhatIfPreference`, and preference variables are inherited by every child scope:
the cmdlets a script calls and the scripts it calls. In a release script that declares
`SupportsShouldProcess`, `-WhatIf` therefore reaches the staging `Copy-Item`, the help build's
`Export-MamlCommandHelp`, and everything else downstream, not only the publish. The rehearsal then
copies nothing and compiles nothing, and either fails on the empty folder or passes while having
verified nothing. One module's release broke this way twice.

- Only the publish is gated by `ShouldProcess`. Every other step is pinned `-WhatIf:$false` or runs
  with the preference cleared. When adding a step, decide whether it is destructive; if not, pin it.
- A called script that declares `[CmdletBinding()]` without `SupportsShouldProcess` has no `-WhatIf`
  parameter to pin. Save and clear the preference around the call:

  ```powershell
  $savedWhatIf = $WhatIfPreference
  $WhatIfPreference = $false
  try {
      & (Join-Path $PSScriptRoot 'Build-Help.ps1')
  } finally {
      $WhatIfPreference = $savedWhatIf
  }
  ```

- Test `-WhatIf` in combination with the script's other switches, not each alone. Both failures
  above survived testing because `-WhatIf` and `-SkipHelpBuild` had only ever been exercised
  separately.
- A stale local intermediate (a `maml/` left by an earlier run) hides a step that now produces
  nothing. Rehearse from a clean checkout, or delete the intermediate first.

### Tag-driven release

The release workflow runs on `git tag v<ModuleVersion> && git push origin v<ModuleVersion>`,
re-runs every gate, refuses a tag that disagrees with the manifest's `ModuleVersion`, stages,
verifies, and publishes. When the upload fails for a reason the rehearsal did not measure, nothing
has been consumed: fix the manifest, move the tag to the new merge commit, and release under the same
number.

## Quality Assurance Requirements

### Pre-Release Checklist

Ensure module meets all quality standards:

- [ ] All public functions have a PlatyPS Markdown file under `docs/` with no `{{ Fill in`
      placeholders remaining; all private functions have comprehensive comment-based help
- [ ] All public functions carry `.EXTERNALHELP ModuleName-Help.xml`
- [ ] MAML built to `en-US/ModuleName-Help.xml` and `Get-Help` verified against the packaged module
- [ ] Pester tests achieve minimum 80% code coverage
- [ ] PSScriptAnalyzer validation passes with no errors
- [ ] Security validation completed (no credential leaks)
- [ ] Performance benchmarks established
- [ ] Cross-platform compatibility tested (if applicable)
- [ ] Documentation complete and accurate
- [ ] Troubleshooting guides organized in proper folder structure

### PowerShell Gallery Preparation

Prepare module for publication:

- [ ] Module manifest includes all required metadata, and no URI key is set to an empty string
- [ ] License file included and referenced
- [ ] README provides clear installation and usage instructions
- [ ] `ReleaseNotes` covers the current release and points to `CHANGELOG.md` for the rest
- [ ] `Description`, the full tag list and `ReleaseNotes` are measured against the Gallery's limits
      in the rehearsal and in a contract test
- [ ] The publish stages an allowlist into a git-ignored folder; `Publish-PSResource` is never
      pointed at the repository root
- [ ] `Publish-Module.ps1 -WhatIf` stages, imports and verifies the package with every
      non-destructive step pinned against the inherited preference, and has been run together with
      the script's other switches
- [ ] Version follows semantic versioning principles
- [ ] Dependencies clearly documented and available

Generate comprehensive PowerShell modules that follow all enterprise standards, implement proper security controls,
include comprehensive testing, and provide excellent documentation with organized troubleshooting resources in the
`./Troubleshooting/` folder structure.
