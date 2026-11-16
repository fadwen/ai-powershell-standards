# Pester Test Structure Guide

This guide covers where test files live, how each file loads what it needs, shared setup files, and
tags. It supports rules TST-01 to TST-04 in
[powershell-pester.instructions.md](../powershell-pester.instructions.md). The behaviour described
here was checked on Pester 6.2.0.

## Test Directory Layout

Pester does not require a layout; it runs every `*.Tests.ps1` file under the paths it is given. This
layout suits a module whose tests are split by type:

```text
<repository root>
|-- ModuleName.psd1
|-- ModuleName.psm1
|-- Public/
|-- Private/
|-- build/
|   `-- Invoke-Tests.ps1              CI gate script
|-- Tests/
|   |-- Unit/
|   |   |-- Get-ServerHealth.Tests.ps1
|   |   `-- Set-Configuration.Tests.ps1
|   |-- Integration/
|   |   `-- ModuleName.Tests.ps1
|   |-- TestData/
|   |   `-- server-cases.psd1
|   |-- TestHelpers/
|   |   `-- TestHelpers.ps1
|   `-- Pester.BeforeContainer.ps1    optional: setup for Tests/ and below
`-- Pester.BeforeContainer.ps1        optional: setup for every test file
```

- Write one test file for each source file. Test a private function inside `InModuleScope`
  (TST-21).
- Add a `Performance` or `Security` folder only when a function has such a requirement (TST-43).
- Reports that a run writes (test results, coverage) go to a folder that is not committed.
- The gate script is described in [CI/CD Integration Guide](./cicd-integration.md#the-gate-script).

## File Naming

A test file is named after the file it tests, `<FileName>.Tests.ps1` (TST-01):
`Get-ServerHealth.Tests.ps1` tests `Get-ServerHealth.ps1`, and `ModuleName.Tests.ps1` tests the
module as a whole. The suffix is the `Run.TestExtension` option; leave it at its default.

## Self-Contained Test Files

Pester 6 discovers one file and runs it before it discovers the next. Pester 5 discovered every file
first. In a parallel run each file is discovered and run in its own runspace.

Each file therefore sets up everything it needs, in two places (TST-02):

- `BeforeDiscovery` builds what shapes the test tree: the data for `-ForEach`.
- The top-level `BeforeAll` loads what the tests need when they run: the code under test and helpers.

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    $testsRoot = Split-Path -Path $PSScriptRoot -Parent
    $dataPath = Join-Path -Path $testsRoot -ChildPath 'TestData'
    $data = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $dataPath -ChildPath 'server-cases.psd1')
    $serverCases = $data.Cases
}

BeforeAll {
    $testsRoot = Split-Path -Path $PSScriptRoot -Parent
    $repositoryRoot = Split-Path -Path $testsRoot -Parent
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module -Name (Join-Path -Path $repositoryRoot -ChildPath 'ModuleName.psd1')
    }

    $helperPath = Join-Path -Path $testsRoot -ChildPath 'TestHelpers'
    . (Join-Path -Path $helperPath -ChildPath 'TestHelpers.ps1')
}

Describe 'Get-ServerHealth' -Tag 'Unit' {
    It 'Reports <Expected> for <ComputerName>' -ForEach $serverCases {
        Mock -CommandName Test-Connection -ModuleName ModuleName -MockWith { $Reachable }

        $result = Get-ServerHealth -ComputerName $ComputerName

        $result.Status | Should-Be $Expected
    }
}
```

A variable assigned in `BeforeDiscovery` does not exist when the tests run, which is why
`$testsRoot` is assigned in both blocks. The cases reach the tests only through `-ForEach`.

In a sequential run a module that an earlier file imported is still loaded, so a file with a missing
import can pass by accident. It fails when it runs alone or in a parallel run. To confirm that a file
is self-contained, run it alone:

```powershell
Invoke-Pester -Path ./Tests/Unit/Get-ServerHealth.Tests.ps1
```

## Shared Setup Files

Each test file loads what it needs in its own `BeforeAll` (TST-02). When a project chooses to share
setup between files, the mechanism in Pester 6.2.0 is a file named `Pester.BeforeContainer.ps1`.
Pester's source marks it as experimental, so add one only when the user asks for it or the project
already has one.

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
$supportedRegions = @(
    @{ Region = 'westeurope' }
    @{ Region = 'northeurope' }
)

# Run time: what the tests themselves use.
BeforeAll {
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

- Build every path from `$PSScriptRoot`. The working directory is not reliable.
- The files run once for each test file, so what they do must be safe to repeat.

A setup file holds shared helpers. It does not replace TST-02: each test file still loads the code
under test in its own `BeforeAll`.

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

Tag every `Describe` block (TST-04). A tag on a block applies to every test inside it. Use one tag
for the test type and add others where they help to select tests:

```powershell
Describe 'Get-ServerHealth' -Tag 'Unit' {
}

Describe 'ModuleName' -Tag 'Integration', 'Slow' {
}
```

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

### Finding Untagged Tests

A discovery-only run with the `None` filter lists the tests that have no tag. Count the tests whose
`ShouldRun` property is set; that is the property the filter sets.

```powershell
# In a script in the build folder
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

## Checklist

- The file is named `<FileName>.Tests.ps1` after the file it tests, and starts with the `#Requires`
  line for Pester 6.2.0.
- The file loads the code under test in its own top-level `BeforeAll`.
- Data for `-ForEach` is built in `BeforeDiscovery`, and the list cannot be empty or `$null`.
- Paths are built from `$PSScriptRoot` with `Split-Path` and `Join-Path`.
- Every `Describe` block has a tag, and no tag is named `None`.
- Files that a test creates are in `$TestDrive`.
- The file passes when it is run alone.
