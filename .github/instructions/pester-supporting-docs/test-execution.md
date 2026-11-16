# Test Execution Guide

This guide covers how to run tests, how to read the result, and the two experimental run modes,
parallel and shuffled. It supports rules TST-40 to TST-42 in
[powershell-pester.instructions.md](../powershell-pester.instructions.md). The behaviour described
here was checked on Pester 6.2.0 under PowerShell 7.6 and Windows PowerShell 5.1.

## Loading the Right Pester Version

A test file declares the minimum version with `#Requires` (TST-01). That line does not choose
between installed versions, and Windows PowerShell 5.1 ships with Pester 3.4.0. Install the version
the standard targets and import exactly that version before a run:

```powershell
Install-PSResource -Name Pester -Version 6.2.0 -TrustRepository
Import-Module -Name Pester -RequiredVersion 6.2.0
```

## Running Tests

```powershell
# Every test file under a folder
Invoke-Pester -Path ./Tests

# One file, listing every test
Invoke-Pester -Path ./Tests/Unit/Get-ServerHealth.Tests.ps1 -Output Detailed

# By tag
Invoke-Pester -Path ./Tests -TagFilter 'Unit'
Invoke-Pester -Path ./Tests -ExcludeTagFilter 'Integration', 'Slow'

# By name, with wildcards
Invoke-Pester -Path ./Tests -FullNameFilter '*Get-ServerHealth*'
```

`-Output` takes `None`, `Normal`, `Detailed`, or `Diagnostic`. It also accepts `Minimal`, which
Pester 6 treats as `Normal`.

For coverage, reports, or any other option, pass a configuration object; see
[Pester Configuration Guide](./pester-configuration.md). To run exactly what CI runs, call the gate
script that CI calls; see [CI/CD Integration Guide](./cicd-integration.md#the-gate-script).

### Console Output

A run prints one banner, one line for each test file, and one summary:

```text
Running tests from 4 files.
[+] C:\repo\Tests\Unit\Get-ServerHealth.Tests.ps1 638ms (5 tests)
Tests completed in 1.2s
Tests Passed: 20, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
```

A discovery-only run (`Run.SkipRun`) prints `Starting discovery in 4 files.`,
`Discovery found 20 tests in 39ms.`, and `Test run was skipped.` instead.

Do not read results from this text. Set `Run.PassThru` and use the result object.

## Result Object Reference

`Invoke-Pester` returns the result object when `Run.PassThru` is set, or with `-PassThru`.

| Use | Property |
| --- | --- |
| Outcome of the run | `Result`: the string `Passed` or `Failed` |
| Counts | `TotalCount`, `PassedCount`, `FailedCount`, `SkippedCount`, `InconclusiveCount`, `NotRunCount` |
| Failures outside tests | `FailedBlocksCount`, `FailedContainersCount` |
| Tests | `Tests`, `Passed`, `Failed`, `Skipped`, `Inconclusive`, `NotRun` |
| Failed setup or teardown blocks | `FailedBlocks` |
| Test files | `Containers`. Each has `Item`, `Result`, `Passed`, `ErrorRecord`, and `BeforeContainerFile`. |
| Test files that failed | `FailedContainers` |
| Coverage percentage | `CodeCoverage.CoveragePercent` |
| Coverage counts | `CodeCoverage.CommandsAnalyzedCount`, `CommandsExecutedCount`, `CommandsMissedCount`, `FilesAnalyzedCount` |
| Commands that did not run | `CodeCoverage.CommandsMissed`. Each has `File`, `Line`, and `Command`. |
| Coverage target | `CodeCoverage.CoveragePercentTarget` |
| Time | `Duration` on the run, on each file, and on each test. It is a `TimeSpan`. |
| Settings the run used | `Configuration` |

`CodeCoverage` is `$null` when coverage was not measured. The Pester 4 names `CoveredPercent`,
`NumberOfCommandsExecuted`, and `NumberOfCommandsAnalyzed` do not exist.

`Duration` is a `TimeSpan`, so compare `$test.Duration.TotalMilliseconds` with a number, not
`$test.Duration` itself. The console shows one duration for each test. The result object also has
`UserDuration` and `FrameworkDuration`.

### What a Failure Looks Like

A failed run does not always have a failed test. Measured on Pester 6.2.0:

| What happened | `Result` | `FailedCount` | `FailedBlocksCount` | `FailedContainersCount` |
| --- | --- | --- | --- | --- |
| Two tests fail | `Failed` | 2 | 0 | 0 |
| `BeforeAll` throws in a block with one test | `Failed` | 1 | 1 | 0 |
| `AfterAll` throws after the tests passed | `Failed` | 0 | 1 | 0 |
| A file throws during discovery | `Failed` | 0 | 0 | 1 |
| `-ForEach` receives an empty list | `Failed` | 0 | 0 | 1 |
| A file contains no tests | `Passed` | 0 | 0 | 0 |

When no test file is found at all, `Invoke-Pester` writes an error, returns no result object, and
sets `$LASTEXITCODE` to `-1`.

This is why the gate tests for a missing result, for `TotalCount`, and for `Result`, and never for
`FailedCount` alone (TST-42):

```powershell
if ($null -eq $result -or $result.TotalCount -eq 0) {
    throw 'Pester ran no tests.'
}

if ($result.Result -ne 'Passed') {
    $counts = $result.FailedCount, $result.FailedBlocksCount, $result.FailedContainersCount
    $summary = 'Failed tests: {0}. Failed blocks: {1}. Failed files: {2}.' -f $counts
    throw "Pester result is '$($result.Result)'. $summary"
}
```

### Messages and Their Causes

| Message | Cause |
| --- | --- |
| `Value can not be null or empty array` | A `-ForEach` list is empty or `$null`, usually because it was built in `BeforeAll`. Build it in `BeforeDiscovery`. |
| `No mock for command '...' matched the call` | Every mock of the command has a `-ParameterFilter` and none matched. Add a mock without a filter. |
| `A parameter cannot be found that matches parameter name 'Focus'` | `-Focus` does not exist in Pester 6. |
| `Pester Should -Be syntax is disabled` | `Should.DisableV5` is set and the file uses the `Should -Be` style. |
| `Expected a [scriptblock] to measure or a [timespan] to compare` | `Should-BeFasterThan` or `Should-BeSlowerThan` received something else. Pipe the script block. |
| `No test files were found and no scriptblocks were provided` | `Run.Path` points at a folder without test files, or `Run.ExcludePath` removed them all. |
| `CommandNotFoundException` for a helper function | The helper was dot-sourced by another test file, or at the top level of a setup file. |

## Checking Structure Without Running Tests

`Run.SkipRun` discovers every file and runs nothing. Use it to find files that fail discovery, and
with `Filter.Tag = 'None'` to find tests without a tag. Both scripts are in
[Pester Test Structure Guide](./test-structure-guide.md#checking-the-structure).

## Parallel Test Execution

`Run.Parallel` is experimental and off by default. Do not enable it in a configuration that you
generate unless the user asks.

With the option on, Pester runs test files at the same time, each file in its own runspace of the
same process. It works on PowerShell 7 and on Windows PowerShell 5.1. In the examples, `$testRoot`
holds the full path of the test folder.

```powershell
$configuration = New-PesterConfiguration
$configuration.Run.Path = $testRoot
$configuration.Run.Parallel = $true
$configuration.Run.ParallelThrottleLimit = 4

Invoke-Pester -Configuration $configuration
```

`Run.ParallelThrottleLimit` is the number of files that run at once. The default `0` uses every
processor. `1` does not turn the mode off: the files still run in worker runspaces, one after
another.

In the result object the files are in the same order as in a sequential run. The `Duration` of the
run is the elapsed time, not the sum of the files, and `UserDuration`, `FrameworkDuration`, and
`DiscoveryDuration` of the run are zero. Each file still has its own values.

### When Pester Runs Sequentially Instead

| Condition | What Pester does |
| --- | --- |
| A script block container is used (`Run.ScriptBlock`, or `New-PesterContainer -ScriptBlock`) | Warns `Run.Parallel currently parallelizes only file-based runs` and runs sequentially. |
| `Run.SkipRemainingOnFailure = 'Run'` | Warns that skipping after the first failure cannot span the worker runspaces, and runs sequentially. |
| Every file has the `#pester:no-parallel` directive | Runs sequentially without a warning. |

A file passed with `New-PesterContainer -Path`, with or without `-Data`, runs in parallel.

### Which Files to Opt Out

A file that cannot share the machine with other tests starts with the `#pester:no-parallel`
directive:

```powershell
#pester:no-parallel
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

Describe 'Service restart' -Tag 'Integration' {
}
```

Pester runs such files one after another in the calling session, after the parallel batch has
finished. Opt out:

- tests that use a fixed port, a shared database, or another resource that exists once
- tests that change process-wide state, such as an environment variable or the current location
- tests that measure time

### Coverage in a Parallel Run

Coverage is collected in a parallel run: each worker measures its file and Pester merges the
results into one report. Measured on 6.2.0, the percentage equals that of a sequential run.

A parallel run always measures with breakpoints, even when `CodeCoverage.UseBreakpoints` is
`$false`, because the profiler-based tracer cannot run in several runspaces at once. Breakpoints
are the slower method, so a parallel run with coverage is not necessarily faster than a sequential
one. Measure both before choosing.

### A Lost File Is an Error

When a worker ends without returning a result, the run throws
`Parallel run lost the results of <n> of <m> file(s)` and names the files. This statement comes
from the source of Pester 6.2.0; it was not reproduced in a run.

### Before Enabling Parallel Runs

Each worker starts with an empty runspace. A test file that relies on a module, a variable, or a
helper that another test file loaded fails in a parallel run. Check first that each file passes when
it is run alone, and put shared helpers in a setup file; see
[Pester Test Structure Guide](./test-structure-guide.md#shared-setup-files).

## Shuffled Test Order

`Run.Shuffle` is experimental and off by default. Turn it on for the unit tests in CI, with the
seed in the failure message (TST-46). It is what keeps importing the module once for each run
(TST-05) safe.

With the option on, Pester changes the order of the test files, of the blocks in each file, and of
the tests in each block. A test stays inside its `Context`, and a `Context` stays inside its
`Describe`. A suite that depends on the declared order then fails, which exposes a breach of
TST-31.

```powershell
$configuration = New-PesterConfiguration
$configuration.Run.Path = $testRoot
$configuration.Run.PassThru = $true
$configuration.Run.Shuffle = $true

$result = Invoke-Pester -Configuration $configuration
```

The run prints the seed that it used, and the result object holds it:

```text
Shuffling execution order using seed 314796220. Set 'Run.ShuffleSeed = 314796220' to repeat this order.
```

```powershell
$seed = $result.Configuration.Run.ShuffleSeed.Value
```

`Run.ShuffleSeed` is `0` by default, which picks a new seed for each run. Setting it to the seed of
an earlier run repeats that order exactly:

```powershell
$configuration.Run.ShuffleSeed = 314796220
```

The option changes only the order. It does not change which tests run or how filters apply.

### When a Test Fails Only in a Shuffled Run

1. Record the seed from the output or from the result object.
2. Run again with `Run.ShuffleSeed` set to that value and confirm that the failure repeats.
3. Find the state that the tests share. It is usually a `$script:` variable, a file outside
   `$TestDrive`, an environment variable, or a mock whose calls are counted across blocks.
4. Correct the test: move the setup into the block that needs it, or restore the state in
   `AfterEach`.

A file whose blocks must run in the declared order starts with the `#pester:no-shuffle` directive.
Its blocks and tests then keep their order:

```powershell
#pester:no-shuffle
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

Describe 'Database migration steps' -Tag 'Integration' {
}
```

The directive states that the file depends on its order. That is acceptable for an integration
scenario that is written as a sequence of steps, and it is a defect in a unit test file.
