# Pester Test Structure Guide

This guide covers where test files live, how each file loads what it needs, shared setup files, and
tags. It supports rules TST-01 to TST-04 in
[powershell-pester.instructions.md](../powershell-pester.instructions.md). The behaviour described
here was checked on Pester 6.2.0.

Do not use emoji in generated code, documentation, or test output. Use plain text and standard
ASCII characters only (STY-06, TST-07).

## Test Directory Layout

Organize the tests of a project in this layout:

```text
<repository root>
|-- ModuleName.psd1
|-- ModuleName.psm1
|-- Public/
|-- Private/
|-- Classes/
|-- Tests/
|   |-- Unit/
|   |   |-- Public/
|   |   |   |-- Get-ServerHealth.Tests.ps1
|   |   |   `-- Set-Configuration.Tests.ps1
|   |   |-- Private/
|   |   |   |-- Test-Connection.Tests.ps1
|   |   |   `-- Format-Output.Tests.ps1
|   |   `-- Classes/
|   |       `-- ServerManager.Tests.ps1
|   |-- Integration/
|   |   |-- EndToEnd/
|   |   |   `-- CompleteWorkflow.Tests.ps1
|   |   `-- SystemIntegration/
|   |       `-- ExternalServices.Tests.ps1
|   |-- Performance/
|   |   |-- Benchmarks/
|   |   |   `-- ExecutionTime.Tests.ps1
|   |   `-- LoadTests/
|   |       `-- MemoryUsage.Tests.ps1
|   |-- Security/
|   |   |-- InputValidation/
|   |   |   `-- ParameterSanitization.Tests.ps1
|   |   `-- CredentialHandling/
|   |       `-- SecureCredentials.Tests.ps1
|   |-- TestData/
|   |   |-- server-cases.psd1
|   |   |-- sample-data.json
|   |   |-- test-config.psd1
|   |   `-- mock-responses.json
|   |-- TestHelpers/
|   |   |-- TestHelpers.ps1
|   |   |-- MockFactory.ps1
|   |   `-- TestDataGenerator.ps1
|   |-- Results/
|   |   |-- Coverage.xml
|   |   `-- TestResults.xml
|   |-- Pester.BeforeContainer.ps1    optional: setup for Tests/ and below
|   |-- PesterConfiguration.psd1      standard configuration
|   |-- PesterConfiguration.Development.psd1  settings that differ for one environment
|   |-- PesterConfiguration.CI.psd1
|   |-- TestRunnerHelpers.ps1         functions that the runner dot-sources
|   `-- Invoke-Tests.ps1              test runner, applies the CI gate
`-- Pester.BeforeContainer.ps1        optional: setup for every test file
```

- The first level under `Tests` is the test type, and the second level is the category within it.
  The `Performance` and `Security` folders hold the tests that TST-43 requires: performance tests
  for a function that processes more than 100 items, and security tests for credential handling
  and input validation.
- Reports that a run writes go to `Tests/Results`. The folder is not committed.
- `PesterConfiguration.psd1`, the settings files of the environments, and the runner script
  `Invoke-Tests.ps1` with its helper file are in `Tests`, as in
  [Test Execution Guide](./test-execution.md#the-test-runner-script) and
  [Pester Configuration Guide](./pester-configuration.md#settings-for-each-environment).
- The subfolders of `TestData` are in
  [Test Data Management Guide](./test-data-guide.md#data-files).

Pester does not require a layout; it runs every `*.Tests.ps1` file under the paths it is given. Two
alternatives can each replace their counterpart above:

- A small module keeps `Tests/Unit` and `Tests/Integration` flat, without the second level.
- The runner script, its helper file, and the settings files are in a `build` folder beside
  `Tests`. Both folders are one level below the repository root, so a script that builds its paths
  from `$PSScriptRoot` works in either.

```text
|-- build/
|   |-- Invoke-Tests.ps1                      test runner, applies the CI gate
|   |-- TestRunnerHelpers.ps1                 functions that the runner dot-sources
|   |-- PesterConfiguration.psd1              standard configuration
|   |-- PesterConfiguration.Development.psd1  settings that differ for one environment
|   `-- PesterConfiguration.CI.psd1
|-- Tests/
|   `-- Results/                              reports of a run; not committed
```

### What Goes in One File

- Public functions: one test file for each public function.
- Private functions: group related private functions in a single test file, and test them inside
  `InModuleScope` (TST-21).
- Classes: one test file for each class.
- Integration tests: group them by business workflow or by the system that is integrated.

TST-01 states the same thing by source file: one test file for each source file. Where each
function has its own source file, the two forms give the same files.

### Contract Tests

A contract test asserts something about the module as a whole, in a file of its own. FUN-05 asks
for one that refuses a `$script:` read inside a job or a parallel block, because such a block does
not see the state of the module. The test parses each source file, so it needs no mock and does not
load the module:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    # The file is in Tests/Unit, so the repository root is two levels up.
    $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $fileCases = foreach ($folder in 'Public', 'Private') {
        $sourceFolder = Join-Path -Path $repositoryRoot -ChildPath $folder
        foreach ($file in Get-ChildItem -LiteralPath $sourceFolder -Filter '*.ps1' -File) {
            @{ FileName = $file.Name; FullPath = $file.FullName }
        }
    }
}

Describe 'Background scope contract' -Tag 'Unit', 'Contract' {
    It 'Reads no $script: variable inside a job or parallel block in <FileName>' -ForEach $fileCases {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($FullPath, [ref]$null, [ref]$null)
        $workerCalls = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and (
                    $node.GetCommandName() -in 'Start-Job', 'Start-ThreadJob' -or
                    $node.Extent.Text -match '\s-Parallel\b')
            }, $true)
        $scriptReads = foreach ($call in $workerCalls) {
            $call.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $node.VariablePath.UserPath -like 'script:*'
                }, $true)
        }

        @($scriptReads | ForEach-Object { $_.Extent.Text }) -join ', ' | Should-BeString ''
    }
}
```

Run on Pester 6.2.0 under PowerShell 7.6 and Windows PowerShell 5.1: the test fails for a file
that reads `$script:prefix` inside `ForEach-Object -Parallel` or `Start-Job`, and passes for a file
whose block uses `$using:` or `-ArgumentList`.

## File Naming

- Unit tests: `FunctionName.Tests.ps1`
- Integration tests: `ComponentName.Tests.ps1`
- Performance tests: `PerformanceArea.Tests.ps1`
- Security tests: `SecurityArea.Tests.ps1`

TST-01 names a test file after the file it tests, `<FileName>.Tests.ps1`:
`Get-ServerHealth.Tests.ps1` tests `Get-ServerHealth.ps1`, and `ModuleName.Tests.ps1` tests the
module as a whole. For a function in its own source file both forms give the same name. A name
taken from the function, the component, or the area is the allowed form where no single source file
matches, which is the usual case for integration, performance, and security tests.

The suffix is the `Run.TestExtension` option. It can be changed, but leave it at its default.

### Test Names

Name each test after the behaviour that it proves. The templates begin every name with `Should`,
as in `'Should retry on transient failures'`. A name that states the behaviour directly, such as
`'Retries on a transient failure'`, is the alternative that the samples of this guide use; keep one
form within a file. Write the name in single quotes unless it needs expansion (STY-21).

## Self-Contained Test Files

Pester 6 discovers one file and runs it before it discovers the next. Pester 5 discovered every file
first. In a parallel run each file is discovered and run in its own runspace.

Each file therefore sets up everything it needs, in two places (TST-02):

- `BeforeDiscovery` builds what shapes the test tree: the data for `-ForEach`.
- The top-level `BeforeAll` loads what the tests need when they run: the code under test and helpers.

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    # The file is in Tests/Unit/Public, so the Tests folder is two levels up.
    $testsRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $dataPath = Join-Path -Path $testsRoot -ChildPath 'TestData'
    $data = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $dataPath -ChildPath 'server-cases.psd1')
    $serverCases = $data.Cases
}

BeforeAll {
    $testsRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $repositoryRoot = Split-Path -Path $testsRoot -Parent
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module -Name (Join-Path -Path $repositoryRoot -ChildPath 'ModuleName.psd1')
    }

    $helperPath = Join-Path -Path $testsRoot -ChildPath 'TestHelpers'
    . (Join-Path -Path $helperPath -ChildPath 'TestHelpers.ps1')
}

Describe 'Get-ServerHealth' -Tag 'Unit', 'Public' {
    It 'Reports <Expected> for <ComputerName>' -ForEach $serverCases {
        Mock -CommandName Test-Connection -ModuleName ModuleName -MockWith { $Reachable }

        $result = Get-ServerHealth -ComputerName $ComputerName

        $result.Status | Should-Be $Expected
    }
}
```

A variable assigned in `BeforeDiscovery` does not exist when the tests run, which is why
`$testsRoot` is assigned in both blocks. The cases reach the tests only through `-ForEach`. In the
flat layout the file is one level higher, and one `Split-Path` is enough.

The same path can be written in one string with forward slashes:
`"$PSScriptRoot/../../../ModuleName.psd1"`. Run on Windows under PowerShell 7.6 and Windows
PowerShell 5.1, that form imported the module and dot-sourced a helper. Do not write it with
backslashes, which separate folders on Windows only, and do not pass more than one child path to
`Join-Path` in code that runs on 5.1. The samples in these guides use `Split-Path` and `Join-Path`.

In a sequential run a module that an earlier file imported is still loaded, so a file with a missing
import can pass by accident. It fails when it runs alone or in a parallel run. To confirm that a file
is self-contained, run it alone:

```powershell
Invoke-Pester -Path ./Tests/Unit/Public/Get-ServerHealth.Tests.ps1
```

## Shared Setup Files

When many files need identical setup, put it in one place instead of repeating it in every file.
In Pester 6.2.0 that place is a file named `Pester.BeforeContainer.ps1`.

Pester's source marks the mechanism as experimental, so the Pester rules ask that the first such
file is added to a project only when the user asks for it. Propose one when the same setup is
repeated in many files, and use it when the user agrees or the project already has one. The file
supplements the setup of each test file and does not replace it: each test file still loads what
it needs in its own `BeforeAll` and can be discovered and run alone (TST-02).

Before each test file is discovered and run, Pester dot-sources every `Pester.BeforeContainer.ps1`
that lies between the repository root (`Run.RepoRoot`) and the test file's own folder, outermost
first. It does this in sequential runs, in parallel runs, and in a discovery-only run
(`Run.SkipRun`).

### Discovery Time and Run Time

A setup file follows the same rule as a test file. Its top-level code runs during discovery only.
What the tests need when they run goes in a `BeforeAll` in the setup file.

```powershell
# Pester.BeforeContainer.ps1 at the repository root

# Discovery: keep only what a -ForEach or a BeforeDiscovery block needs.
if (-not (Get-Module -Name ModuleName)) {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'ModuleName.psd1')
}
$supportedRegions = @(
    @{ Region = 'westeurope' }
    @{ Region = 'northeurope' }
)

# Run time: what the tests themselves use. This file runs before every test file, so a forced
# import here costs the same as one in every test file.
BeforeAll {
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'ModuleName.psd1')
    }

    $helperRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Tests'
    $helperRoot = Join-Path -Path $helperRoot -ChildPath 'TestHelpers'
    . (Join-Path -Path $helperRoot -ChildPath 'TestHelpers.ps1')
}
```

What a statement in a setup file can reach, measured on Pester 6.2.0 in sequential and parallel
runs:

| Statement in the setup file | Visible during discovery | Visible to the tests |
| --- | --- | --- |
| Top-level variable assignment | Yes | No, it reads as `$null` |
| Top-level function definition or dot-sourced file | Yes | No, `CommandNotFoundException` |
| Top-level `Import-Module` | Yes | Yes, because a loaded module stays in the session |
| Variable or function defined inside `BeforeAll` | No | Yes |

Nothing warns when top-level setup fails to reach the tests. A setup file written for Pester 6.1 has
no `BeforeAll` and needs this change; see
[Pester 6 Migration Guide](./v6-migration.md#the-setup-file-needs-a-beforeall).

Two more requirements:

- Build every path from `$PSScriptRoot`. The file runs before each test file in sequential and in
  parallel runs, and a relative path would resolve against whatever the working directory happens
  to be. That is why the `Run.BeforeContainer` script block option of 6.0, which had no file to
  anchor a path to, was removed in 6.1.
- The files run once for each test file, so what they do must be safe to repeat.

A setup file imports the module and loads shared helpers for the files that rely on it. It does not
replace TST-02: each test file still loads the code under test in its own `BeforeAll`.

### Setup for One Folder

A setup file in a subfolder applies to that folder and below, after the files above it:

```powershell
# Tests/Unit/Pester.BeforeContainer.ps1
BeforeAll {
    $script:storageKind = 'memory'
}
```

```powershell
# Tests/Integration/Pester.BeforeContainer.ps1
BeforeAll {
    $script:storageKind = 'database'
}
```

Each file is dot-sourced for one test file at a time, so a test under `Tests/Integration` never sees
the value that `Tests/Unit` set, whichever runs first.

A folder that wants none of the setup above it starts its file with the `#pester:no-inherit`
directive. That file still applies; the files above it do not:

```powershell
# Tests/Docs/Pester.BeforeContainer.ps1
#pester:no-inherit
BeforeAll {
    $script:storageKind = 'none'
}
```

The result object records which setup files applied to each test file, outermost first:

```powershell
$result = Invoke-Pester -Path ./Tests -PassThru
foreach ($container in $result.Containers) {
    $container.Item.Name
    foreach ($setupFile in $container.BeforeContainerFile) {
        "    $setupFile"
    }
}
```

### When a Setup File Does Not Run

The search starts at `Run.RepoRoot` and nothing above it is considered. When the option is not set,
Pester finds the root from the current location, so a run started outside the repository, or in a
checkout that has no `.git` folder, can miss the setup files without any message. Set the option in
scripts and CI jobs; see [Pester Configuration Guide](./pester-configuration.md#runreporoot).

## Hidden Folders and Excluded Paths

Pester 6 finds test files in folders that have the hidden attribute, and in dot-prefixed folders
such as `.build`. Pester 5 skipped hidden folders. Folders named `.git`, `.svn`, and `.hg` are never
searched.

To keep a folder out of a run, set `Run.ExcludePath`. Pester compares each entry with the full path
of every test file, so an entry is either a full folder or file path, or a wildcard pattern that
matches the full path. A relative entry such as `./.build` matches nothing. In this example
`$testRoot` holds the full path of the `Tests` folder:

```powershell
$fixturePath = Join-Path -Path $testRoot -ChildPath 'Fixtures'

$configuration.Run.ExcludePath = @(
    $fixturePath
    '*/.build/*'
)
```

## Tags

Tag every `Describe` block (TST-04). A tag on a block applies to every test inside it. Use
consistent tags: one for the test type and one for the category within it, which match the two
folder levels of the layout:

```powershell
Describe 'Get-ServerHealth' -Tag 'Unit', 'Public' {
    # Unit tests for a public function
}

Describe 'Complete workflow' -Tag 'Integration', 'EndToEnd' {
    # Integration tests
}

Describe 'Execution time' -Tag 'Performance', 'Benchmark' {
    # Performance tests
}

Describe 'Parameter validation' -Tag 'Security', 'InputValidation' {
    # Security tests
}
```

A further tag such as `Slow` can be added where it helps to select tests.

A tag filter with several tags selects a test that has any one of them. `Filter.Tag = 'Unit', 'Slow'`
runs every test tagged `Unit` and every test tagged `Slow`. To narrow a selection, combine
`Filter.Tag` with `Filter.ExcludeTag`.

### The Reserved Tag None

Pester 6 reserves `None` (in any letter case) as a filter value. It selects tests that have no tag
on themselves or on any parent block. Do not use it as a tag name (TST-04): a `Describe` block
tagged `None` is selected together with every untagged test.

```powershell
Invoke-Pester -Path ./Tests -TagFilter 'None'                 # only untagged tests
Invoke-Pester -Path ./Tests -ExcludeTagFilter 'None'          # only tagged tests
Invoke-Pester -Path ./Tests -TagFilter 'None', 'Integration'  # untagged tests and Integration tests
```

A well-tagged suite runs zero tests with `-TagFilter 'None'`. Reading that run interactively, look
at the `Passed` and `Failed` counts in the summary, not at the counts of discovered tests, which
stay at the full size of the suite. Measured on 6.2.0 with three tagged tests and one untagged
test: the summary reads `Tests Passed: 1, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 3`,
while the count after a file, `(2 tests)`, and the `Discovery found 4 tests` line of a
discovery-only run include the tagged tests.

### Finding Untagged Tests

A discovery-only run with the `None` filter lists the tests that have no tag. Count the tests whose
`ShouldRun` property is set; that is the property the filter sets.

```powershell
# In a script in the Tests folder or in the build folder
$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$testRoot = Join-Path -Path $repositoryRoot -ChildPath 'Tests'

$configuration = New-PesterConfiguration
$configuration.Run.Path = $testRoot
$configuration.Run.RepoRoot = $repositoryRoot
$configuration.Run.SkipRun = $true
$configuration.Run.PassThru = $true
$configuration.Filter.Tag = 'None'
$configuration.Output.Verbosity = 'None'

$result = Invoke-Pester -Configuration $configuration

$untagged = @($result.Tests | Where-Object -Property ShouldRun)
if ($untagged.Count -gt 0) {
    $names = $untagged.ExpandedPath -join [Environment]::NewLine
    throw "$($untagged.Count) test(s) have no tag:$([Environment]::NewLine)$names"
}
```

Do not use `TotalCount` or `PassedCount` for this check:

| Property | Behaviour with `Filter.Tag = 'None'` |
| --- | --- |
| `TotalCount` | Counts every discovered test and ignores the filter, so it is never zero for a suite that has tests. |
| `PassedCount` | Counts untagged tests that ran and passed. It misses an untagged test that fails, and it is 0 with `Run.SkipRun`. |
| `ShouldRun` | Set on exactly the tests that the filter selected, with or without `Run.SkipRun`. |

Measured on Pester 6.2.0 with three tagged and two untagged tests, one of which fails: `TotalCount`
is 5, `PassedCount` is 1, and two tests have `ShouldRun` set.

## Directives in a Test File

A directive is a comment that Pester reads from the file before it runs it. Pester matches it only
in a comment, never in a string.

| Directive | Where | Effect |
| --- | --- | --- |
| `#pester:no-parallel` | Test file | The file runs in the calling session after the parallel batch. See [Test Execution Guide](./test-execution.md#which-files-to-opt-out). |
| `#pester:no-shuffle` | Test file | The file keeps its declared order when `Run.Shuffle` is on. See [Test Execution Guide](./test-execution.md#shuffled-test-order). |
| `#pester:no-inherit` | Setup file | Setup files in the folders above do not apply. See [Setup for One Folder](#setup-for-one-folder). |

## Checking the Structure

A discovery-only run checks every file without running a test. It fails for a `-ForEach` value that
is empty or `$null`, for a file that throws during discovery, and for a file that uses a removed
parameter such as `-Focus`. The script uses `$repositoryRoot` and `$testRoot` as set in the previous
script.

```powershell
$configuration = New-PesterConfiguration
$configuration.Run.Path = $testRoot
$configuration.Run.RepoRoot = $repositoryRoot
$configuration.Run.SkipRun = $true
$configuration.Run.PassThru = $true

$result = Invoke-Pester -Configuration $configuration

if ($null -eq $result) {
    throw 'Pester found no test files.'
}

if ($result.Result -ne 'Passed') {
    $failedFiles = foreach ($container in $result.FailedContainers) {
        "$($container.Item)"
    }
    throw "Discovery failed in $($result.FailedContainersCount) file(s): $($failedFiles -join ', ')"
}
```

Run this check in CI before the real test job. It is fast and catches structural breakage early.

## Documentation

- Include the performance baselines and the expected figures with the performance tests.
- Document what test data the tests require and how it is set up.
- Keep the guidance on how to run the tests in the main test runner, `Invoke-Tests.ps1`.

## Checklist

- The file is named after the function, class, component, or source file that it tests, ends in
  `.Tests.ps1`, and starts with the `#Requires` line for Pester 6.2.0.
- The file loads the code under test in its own top-level `BeforeAll`, and in `BeforeDiscovery`
  when discovery needs it.
- Data for `-ForEach` is built in `BeforeDiscovery`, and the list cannot be empty or `$null`.
- Paths are built from `$PSScriptRoot`.
- Every external dependency of a unit test is mocked: what crosses a boundary such as the network,
  the file system, the clock, or another module, and nothing else (TST-20).
- Tests are isolated from each other and from other files, and what a test changes is cleaned up in
  `AfterAll` or `AfterEach`.
- Every `Describe` block has a tag, and no tag is named `None`.
- Files that a test creates are in `$TestDrive`.
- The file passes when it is run alone.
