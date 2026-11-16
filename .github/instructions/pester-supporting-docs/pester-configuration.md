# Pester Configuration Guide

This guide lists the options of the Pester configuration object and explains the ones that are
easy to get wrong. It supports the testing rules in
[powershell-pester.instructions.md](../powershell-pester.instructions.md). The option names,
defaults, and behaviour were read from the configuration object of Pester 6.2.0 and checked by
running it. `Get-Help about_PesterConfiguration` shows the same list on the installed version.

## Creating a Configuration

```powershell
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path -Path $PSScriptRoot -ChildPath 'Tests'
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'

$result = Invoke-Pester -Configuration $configuration
```

Each option is an object with the properties `Value`, `Default`, `IsModified`, and `Description`.
Assign to the option itself, and read the setting from `.Value`:

```powershell
$configuration.CodeCoverage.CoveragePercentTarget = 80
$target = $configuration.CodeCoverage.CoveragePercentTarget.Value
```

`Invoke-Pester` also has a short form for simple runs. Its parameters are `-Path`, `-ExcludePath`,
`-TagFilter`, `-ExcludeTagFilter`, `-FullNameFilter`, `-Output`, `-PassThru`, `-Container`, and
`-CI`. Use a configuration object for anything else. The Pester 4 parameters such as `-Script` and
`-EnableExit` do not exist in Pester 6.

### Loading Settings From a File

`New-PesterConfiguration -Hashtable` accepts a hashtable that contains only the options to change,
so settings can be kept in a `.psd1` file:

```powershell
# build/PesterConfiguration.psd1
@{
    Run = @{
        PassThru = $true
    }

    CodeCoverage = @{
        Enabled = $true
        CoveragePercentTarget = 80
    }

    TestResult = @{
        Enabled = $true
        OutputFormat = 'NUnitXml'
    }
}
```

Paths in a configuration are relative to the current location, which a build script does not
control. Keep paths out of the file and set them in the script from `$PSScriptRoot`:

```powershell
$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$settingsPath = Join-Path -Path $PSScriptRoot -ChildPath 'PesterConfiguration.psd1'
$settings = Import-PowerShellDataFile -LiteralPath $settingsPath

$configuration = New-PesterConfiguration -Hashtable $settings
$configuration.Run.Path = Join-Path -Path $repositoryRoot -ChildPath 'Tests'
$configuration.Run.RepoRoot = $repositoryRoot
$configuration.CodeCoverage.Path = @(
    Join-Path -Path $repositoryRoot -ChildPath 'Public'
    Join-Path -Path $repositoryRoot -ChildPath 'Private'
)
```

To use different settings for one kind of run, load the same file and then assign the options that
differ. The coverage figure that CI enforces is 80 percent (TST-40); do not keep a second, lower
figure for other runs.

### Checking What Was Loaded

Pester 6.2.0 checks a hashtable in three ways, at three different times.

A value of the wrong type throws when the configuration is created. This happens most often with a
Boolean written as a string in a `.psd1` or JSON file:

```powershell
New-PesterConfiguration -Hashtable @{ Run = @{ Parallel = 'yes' } }
# Error: Run.Parallel expects a bool, but got the string 'yes'.
```

An `int` is accepted for a decimal option, and a key whose value is `$null` is treated as not set.

A key that matches no option does not throw. `Invoke-Pester` writes one warning for all of them:

```text
WARNING: Ignoring configuration keys 'Nonsense', 'Run.Paralel', there are no such options. Check
the spelling, 'Get-Help about_PesterConfiguration' lists all the options.
```

A warning does not fail a build. Read the same list from the object and throw:

```powershell
$configuration = New-PesterConfiguration -Hashtable $settings

$unknownKeys = @($configuration.GetUnknownKeys())
if ($unknownKeys.Count -gt 0) {
    throw "Configuration keys that match no option: $($unknownKeys -join ', ')"
}
```

A value that has the right type but is not one of the allowed words is reported when the run
starts. `Invoke-Pester` writes an error such as
`TestResult.OutputFormat must be 'NUnitXml', 'NUnit2.5', 'NUnit3' or 'JUnitXml', but it was 'VSTest'`
and returns no result. Test the result for `$null`, as the CI gate does.

Before 6.2 a misspelled key and a value of the wrong type were both ignored without a message.

## Option Reference

### Run

| Option | Default | Meaning |
| --- | --- | --- |
| `Run.Path` | `.` | Folders or files to search for tests. Wildcards are allowed. |
| `Run.ExcludePath` | empty | Folders or files to leave out. Each entry is compared with full paths; see [Pester Test Structure Guide](./test-structure-guide.md#hidden-folders-and-excluded-paths). |
| `Run.ScriptBlock` | empty | Script blocks that contain tests. |
| `Run.Container` | empty | Containers made by `New-PesterContainer`, used to pass data to a test file. |
| `Run.TestExtension` | `.Tests.ps1` | Suffix that identifies a test file. |
| `Run.PassThru` | `$false` | Return the result object. |
| `Run.SkipRun` | `$false` | Discover the tests but do not run them. |
| `Run.Throw` | `$false` | Throw when the run fails. |
| `Run.Exit` | `$false` | End the process with a non-zero exit code when the run fails. |
| `Run.SkipRemainingOnFailure` | `None` | What to skip after the first failure: `None`, `Block`, `Container`, or `Run`. |
| `Run.FailOnNullOrEmptyForEach` | `$true` | Fail discovery when `-ForEach` receives `$null` or an empty array. |
| `Run.RepoRoot` | found when the run starts | Experimental. Where the search for setup files starts; see [Run.RepoRoot](#runreporoot). |
| `Run.Parallel` | `$false` | Experimental. Run test files at the same time. |
| `Run.ParallelThrottleLimit` | `0` | Experimental. Number of files to run at once; `0` uses every processor. |
| `Run.Shuffle` | `$false` | Experimental. Run files, blocks, and tests in a random order. |
| `Run.ShuffleSeed` | `0` | Experimental. Seed for the order; `0` picks a new seed for each run. |

`Run.Throw` and `Run.Exit` stop the script inside `Invoke-Pester` when the run fails, so the
statements after it, such as a coverage check, do not run. The CI gate in the testing rules leaves
both off, sets `Run.PassThru`, and inspects the result itself. Neither option reports a run that
found no tests: measured on 6.2.0, a file without tests gives the result `Passed` with `Run.Throw`
set.

`Invoke-Pester` always sets `$LASTEXITCODE`: to the number of failed tests, blocks, and files, or to
`-1` when Pester itself fails, for example because no test file was found.

### Filter

| Option | Default | Meaning |
| --- | --- | --- |
| `Filter.Tag` | empty | Run tests that have any of these tags. `None` selects tests without a tag. |
| `Filter.ExcludeTag` | empty | Leave out tests that have any of these tags. `None` leaves out tests without a tag. |
| `Filter.FullName` | empty | Run tests whose full name matches a wildcard pattern, for example `*Get-Thing*`. |
| `Filter.Line` | empty | Run the test or block that starts at a line, written as `<full path>:<line>`. |
| `Filter.ExcludeLine` | empty | Leave out the test or block that starts at a line. It takes precedence over `Filter.Line`. |

Several tags in `Filter.Tag` select a test that has any one of them, not a test that has all of
them. The reserved value `None` is explained in
[Pester Test Structure Guide](./test-structure-guide.md#the-reserved-tag-none).

### CodeCoverage

| Option | Default | Meaning |
| --- | --- | --- |
| `CodeCoverage.Enabled` | `$false` | Measure coverage. |
| `CodeCoverage.Path` | empty | Folders or files to measure. When empty, `Run.Path` is used. |
| `CodeCoverage.ExcludeTests` | `$true` | Leave test files out of the figures. |
| `CodeCoverage.RecursePaths` | `$true` | Search the folders in `CodeCoverage.Path` recursively. |
| `CodeCoverage.CoveragePercentTarget` | `75` | The figure that Pester reports against. It does not fail the run. |
| `CodeCoverage.OutputFormat` | `JaCoCo` | Report format: `JaCoCo` or `Cobertura`. |
| `CodeCoverage.OutputPath` | `coverage.xml` | Report file. |
| `CodeCoverage.OutputEncoding` | `UTF8` | Encoding of the report file. |
| `CodeCoverage.ReportRoot` | not set | Folder that paths in the report are relative to. When not set, `Run.RepoRoot` is used. |
| `CodeCoverage.UseBreakpoints` | `$false` | `$false` measures with the profiler-based tracer; `$true` sets a breakpoint on every command. |
| `CodeCoverage.SingleHitBreakpoints` | `$true` | Remove a breakpoint after its first hit. Applies only to breakpoint mode. |

### TestResult

| Option | Default | Meaning |
| --- | --- | --- |
| `TestResult.Enabled` | `$false` | Write a test result report. |
| `TestResult.OutputFormat` | `NUnitXml` | Report format: `NUnitXml`, `NUnit2.5`, `NUnit3`, or `JUnitXml`. |
| `TestResult.OutputPath` | `testResults.xml` | Report file. |
| `TestResult.OutputEncoding` | `UTF8` | Encoding of the report file. |
| `TestResult.TestSuiteName` | `Pester` | Name of the root test suite in the report. |

### Output

| Option | Default | Meaning |
| --- | --- | --- |
| `Output.Verbosity` | `Normal` | `None`, `Normal`, `Detailed`, or `Diagnostic`. |
| `Output.StackTraceVerbosity` | `Filtered` | `None`, `FirstLine`, `Filtered`, or `Full`. `Filtered` hides Pester's own frames. |
| `Output.CIFormat` | `Auto` | Format of failures in a build log: `None`, `Auto`, `AzureDevops`, or `GithubActions`. |
| `Output.CILogLevel` | `Error` | Level that failures are logged at in a build log: `Error` or `Warning`. |
| `Output.CIDebugOutput` | `Auto` | `Auto` shows verbose and debug output when the CI system runs in debug mode; `None` does not. |
| `Output.RenderMode` | `Auto` | `Auto`, `Ansi`, `ConsoleColor`, or `Plaintext`. |
| `Output.ShowTags` | `$false` | Add the tags of each block and test to its output line. |

### Should, Mock, TestDrive, and TestRegistry

| Option | Default | Meaning |
| --- | --- | --- |
| `Should.ErrorAction` | `Stop` | `Stop` ends the test at the first failed assertion. `Continue` runs the rest of the test and reports every failed assertion. |
| `Should.DisableV5` | `$false` | `$true` makes the `Should -Be` style fail. |
| `Mock.Global` | `$false` | Experimental. Every mock applies to calls from any module or script. |
| `TestDrive.Enabled` | `$true` | Provide `$TestDrive`. |
| `TestRegistry.Enabled` | `$true` | Provide the `TestRegistry:` drive on Windows. |

Do not set `Should.DisableV5` while any test file still uses the `Should -Be` style. With the option
on, such an assertion fails with `Pester Should -Be syntax is disabled`.

### Debug

| Option | Default | Meaning |
| --- | --- | --- |
| `Debug.WriteDebugMessages` | `$false` | Write Pester's debug messages. |
| `Debug.WriteDebugMessagesFrom` | `Discovery`, `Skip`, `Mock`, `CodeCoverage` | Sources of the debug messages. Wildcards are allowed. |
| `Debug.ShowNavigationMarkers` | `$false` | Write the path after every block and test. |
| `Debug.ShowStartMarkers` | `$false` | Write a line when each test starts. |
| `Debug.ShowFullErrors` | `$false` | Deprecated. Use `Output.StackTraceVerbosity = 'Full'`. |
| `Debug.ReturnRawResultObject` | `$false` | For the development of Pester only. |

## Options and Values That Do Not Exist

These names appear in older guidance. On Pester 6.2.0 a key from the first table is reported as an
unknown key, and a value from the second table is rejected when the run starts.

| Not an option | Use instead |
| --- | --- |
| `CodeCoverage.Threshold` | `CodeCoverage.CoveragePercentTarget`, with the check in the gate script |
| `CodeCoverage.PerFileThreshold` | No option. Compute it in the gate script from `CodeCoverage.CommandsMissed`. |
| `CodeCoverage.ExcludePath` | Narrow `CodeCoverage.Path` |
| `Run.BeforeContainer` | A `Pester.BeforeContainer.ps1` file; see [Pester Test Structure Guide](./test-structure-guide.md#shared-setup-files) |

| Not a value | Use instead |
| --- | --- |
| `TestResult.OutputFormat = 'VSTest'` | `NUnitXml`, `NUnit2.5`, `NUnit3`, or `JUnitXml` |
| `CodeCoverage.OutputFormat = 'CoverageGutters'` | `JaCoCo` |
| `Output.Verbosity = 'Minimal'` | `Normal`. Pester accepts `Minimal` and changes it to `Normal`. |

## Reports Turn On by Themselves

Setting any option of `CodeCoverage` or `TestResult` to a value other than its default turns that
section on for the run, even when `Enabled` still reads `$false` on the object. Measured on 6.2.0:
setting only `CodeCoverage.Path` wrote `coverage.xml`, and setting only `TestResult.OutputFormat`
wrote `testResults.xml`.

Set `Enabled` explicitly anyway. It states the intent, and it is what a reader looks for.

## Run.RepoRoot

`Run.RepoRoot` is the folder where Pester starts to look for `Pester.BeforeContainer.ps1` files, and
the default for `CodeCoverage.ReportRoot`. Pester marks the option as experimental. The setup files
themselves are described in
[Pester Test Structure Guide](./test-structure-guide.md#shared-setup-files).

When the option is not set, `Invoke-Pester` finds the root when the run starts: it searches upwards
from the current location (`$PWD`) for a folder that contains `.git`, and uses the current location
when it finds none. It never derives the root from `Run.Path`. Measured on 6.2.0 with a setup file
at the repository root:

| Current location when the run starts | Root that the run used | Setup file applied |
| --- | --- | --- |
| The repository root, or a folder inside it | The repository root | Yes |
| An unrelated folder | That folder | No |
| A folder inside a checkout that has no `.git` folder | That folder | No, unless the setup file is in that folder or below |

Nothing is written when a setup file is not found. The tests then fail with
`CommandNotFoundException` or read `$null`, which does not point at the cause.

Two details make this harder to see:

- `New-PesterConfiguration` fills in a value before the run, from the working directory of the
  process, which `Set-Location` does not change. The object can therefore show a different folder
  from the one the run uses. The folder that was used is in
  `$result.Configuration.Run.RepoRoot.Value`.
- Pester 6.1 used the working directory of the process for the run as well.

Set the option in every script and CI job, from a path that does not depend on the current location:

```powershell
$configuration.Run.RepoRoot = Split-Path -Path $PSScriptRoot -Parent
```

## Code Coverage

### What Is Measured

Pester counts commands, not lines. `CodeCoverage.CoveragePercent` on the result is
`CommandsExecutedCount` divided by `CommandsAnalyzedCount`, as a percentage. The commands that did
not run are in `CodeCoverage.CommandsMissed`, each with its file and line.

`CodeCoverage.Path` takes folders or files. With `CodeCoverage.ExcludeTests` at its default, files
that match `Run.TestExtension` are left out of the figures.

### The Target Is Not a Gate

`CodeCoverage.CoveragePercentTarget` changes what Pester prints and writes to the report. Measured
on 6.2.0, a run with 60 percent coverage and a target of 99 has the result `Passed`. The script
compares the figure itself (TST-40):

```powershell
$result = Invoke-Pester -Configuration $configuration

$coverage = [math]::Round($result.CodeCoverage.CoveragePercent, 2)
if ($coverage -lt 80) {
    throw "Code coverage is $coverage percent. The minimum is 80."
}
```

### Profiler and Breakpoints

By default Pester 6 measures coverage with a profiler-based tracer. Pester 5 set a breakpoint on
every command by default. `CodeCoverage.UseBreakpoints = $true` selects the breakpoint method.

A parallel run always measures with breakpoints, whatever the option says; see
[Test Execution Guide](./test-execution.md#coverage-in-a-parallel-run).

### Report Format and Paths

`JaCoCo` is the default format and `Cobertura` is the alternative. The `CoverageGutters` format of
Pester 5 was removed.

Paths in the report are relative to `CodeCoverage.ReportRoot`, which defaults to `Run.RepoRoot`.
Measured on 6.2.0 for the file `C/src/Code.ps1` in a repository: the JaCoCo package is `C/src` by
default and `src` with `ReportRoot` set to the folder `C`. Set `ReportRoot` when the tool that reads
the report expects paths relative to another folder.

## Output

`Output.Verbosity` has four values. `Normal` prints one line for each test file and the failures,
`Detailed` prints every block and test, and `Diagnostic` adds Pester's debug messages.

`Output.CIFormat = 'Auto'` detects Azure Pipelines (`TF_BUILD`) and GitHub Actions
(`GITHUB_ACTIONS`) from their environment variables. In GitHub Actions a failed test is written as
an `::error::` command followed by a group that holds the message. `Output.CILogLevel = 'Warning'`
writes failures as warnings instead.

`Output.CIDebugOutput = 'Auto'` shows verbose and debug output when the pipeline runs with
`System.Debug` set in Azure Pipelines, or with step debug logging on in GitHub Actions.

`Output.ShowTags` helps to see why a tag filter selected a test:

```text
Describing Get-Planet [Tags: Unit, Slow]
  [+] Returns the planet by name 11ms
 Context When the name is unknown [Tags: Negative]
   [+] Writes an error [Tags: Fast] 4ms
```

## Test Results

`TestResult` writes one report in one format for each run. `NUnitXml` and `NUnit2.5` are the same
NUnit 2.5 format, `NUnit3` is the NUnit 3 format, and `JUnitXml` is the JUnit format.

To write a second format, convert the result object after the run:

```powershell
$configuration.Run.PassThru = $true
$result = Invoke-Pester -Configuration $configuration

Export-NUnitReport -Result $result -Path (Join-Path -Path $outputPath -ChildPath 'nunit.xml')
Export-JUnitReport -Result $result -Path (Join-Path -Path $outputPath -ChildPath 'junit.xml')
```

`Export-NUnitReport` also has `-Format NUnit3`.

A file that fails discovery is written to the report as a failure.

A raw control character in a test name or in a failure message breaks the report. Measured on
6.2.0, a message that contains the escape character (0x1B) makes the export fail with
`hexadecimal value 0x1B, is an invalid character` in all three formats, and the report file is left
incomplete. Remove ANSI colour sequences from text before a test throws it or uses it in a name.

## Experimental Options

`Run.Parallel`, `Run.Shuffle`, and `Mock.Global` are off by default, and Pester marks them as
experimental. Do not enable `Run.Parallel` or `Mock.Global` in a configuration that you generate
unless the user asks. `Run.Shuffle` is the exception: turn it on for the unit tests in CI (TST-46).

- `Run.Parallel` and `Run.ParallelThrottleLimit`: see
  [Test Execution Guide](./test-execution.md#parallel-test-execution).
- `Run.Shuffle` and `Run.ShuffleSeed`: see
  [Test Execution Guide](./test-execution.md#shuffled-test-order).
- `Mock.Global`: with the option on, a mock applies to calls of the command from any module or
  script, and `-ModuleName` no longer limits where it applies. See
  [Mocking Patterns Guide](./mocking-patterns.md).
