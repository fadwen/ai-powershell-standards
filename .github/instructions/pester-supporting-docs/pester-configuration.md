# Pester Configuration Guide

This guide lists the options of the Pester configuration object and explains the ones that are
easy to get wrong. It supports the testing rules in
[powershell-pester.instructions.md](../powershell-pester.instructions.md). The option names,
defaults, and behaviour were read from the configuration object of Pester 6.2.0 and checked by
running it. `Get-Help about_PesterConfiguration` shows the same list on the installed version.

Do not use emoji in generated code, in documentation, or in test output. Use plain text and ASCII
characters only.

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

`New-PesterConfiguration -Hashtable` accepts a hashtable, so settings can be kept in a `.psd1`
file. Keep one standard file that lists every section, so that each setting and its value can be
read in one place.

The settings files and the runner script are kept in the `Tests` folder, as the layout in
[Pester Test Structure Guide](./test-structure-guide.md#test-directory-layout) shows. A `build`
folder beside `Tests` is the alternative; both are one level below the repository root, so the
scripts are the same in either.

```powershell
# Tests/PesterConfiguration.psd1
@{
    Run = @{
        Path = @('./Tests/Unit', './Tests/Integration')
        ExcludePath = @()
        PassThru = $true
        SkipRun = $false

        # An empty -ForEach fails discovery. Keep this on, and opt out for one test with
        # -AllowNullOrEmptyForEach where an empty set is expected.
        FailOnNullOrEmptyForEach = $true

        # None, Run, Container, or Block
        SkipRemainingOnFailure = 'None'

        # Experimental and off by default. See "Experimental Options".
        Parallel = $false
        ParallelThrottleLimit = 0

        # Experimental and off by default in Pester, but on in every run here (TST-46). Only
        # the performance file turns it off. A seed of 0 picks a new seed for each run and
        # prints it.
        Shuffle = $true
        ShuffleSeed = 0
    }

    Output = @{
        Verbosity = 'Detailed'

        # None, FirstLine, Filtered, or Full
        StackTraceVerbosity = 'Filtered'

        # None, Auto, AzureDevops, or GithubActions
        CIFormat = 'Auto'
        CILogLevel = 'Error'

        # Auto or None. Auto shows verbose and debug output when the CI system runs in debug mode.
        CIDebugOutput = 'Auto'

        # Auto, Ansi, ConsoleColor, or Plaintext
        RenderMode = 'Auto'

        # $true adds [Tags: ...] to each output line.
        ShowTags = $false
    }

    Mock = @{
        # Experimental and off by default. See "Experimental Options".
        Global = $false
    }

    CodeCoverage = @{
        Enabled = $true
        # List only folders that exist. One entry in a folder that does not exist makes Pester
        # measure nothing: remove './Classes/*.ps1' when the module has no Classes folder.
        Path = @('./Public/*.ps1', './Private/*.ps1', './Classes/*.ps1')

        # JaCoCo or Cobertura
        OutputFormat = 'JaCoCo'
        OutputPath = './Tests/Results/Coverage.xml'
        OutputEncoding = 'UTF8'

        # Not "Threshold": that option does not exist.
        CoveragePercentTarget = 80

        # $false measures with the profiler-based tracer, the default in Pester 6.
        UseBreakpoints = $false
        SingleHitBreakpoints = $true

        # Keeps test files out of the coverage figures.
        ExcludeTests = $true
        RecursePaths = $true
    }

    TestResult = @{
        Enabled = $true

        # NUnitXml, NUnit2.5, NUnit3, or JUnitXml
        OutputFormat = 'NUnitXml'
        OutputPath = './Tests/Results/TestResults.xml'
        OutputEncoding = 'UTF8'
        TestSuiteName = 'PowerShell Tests'
    }

    Should = @{
        # 'Continue' reports every failed assertion of a test instead of the first one.
        ErrorAction = 'Stop'

        # $true makes the Should -Be style fail.
        DisableV5 = $false
    }

    Debug = @{
        ShowFullErrors = $false
        WriteDebugMessages = $false
        ShowNavigationMarkers = $false

        # Writes a line when each test starts.
        ShowStartMarkers = $false
        ReturnRawResultObject = $false
    }

    Filter = @{
        Tag = @()
        ExcludeTag = @()
        Line = @()
        ExcludeLine = @()
        FullName = @()
    }
}
```

`CodeCoverage.ReportRoot` is left out of the file: when it is not set, `Run.RepoRoot` is used.
`Run.Throw` and `Run.Exit` are left out as well; the reason is under the [Run](#run) options.

The paths in the file are relative to the current location when the run starts, which a build
script does not control. Measured on 6.2.0 with `Run.Path = './Tests/Unit'`: a run started in the
repository root found the tests, and a run started in another folder failed with
`No test files were found`. The script that loads the file therefore finds the repository root from
`$PSScriptRoot` and runs Pester from there:

```powershell
$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$settingsPath = Join-Path -Path $PSScriptRoot -ChildPath 'PesterConfiguration.psd1'
$settings = Import-PowerShellDataFile -LiteralPath $settingsPath

$configuration = New-PesterConfiguration -Hashtable $settings
$configuration.Run.RepoRoot = $repositoryRoot

Push-Location -LiteralPath $repositoryRoot
try {
    $result = Invoke-Pester -Configuration $configuration
} finally {
    Pop-Location
}
```

The alternative is a file that holds only the options to change and no paths, with the paths set
in the script from `$PSScriptRoot`. The CI gate script uses this form; see
[CI/CD Integration Guide](./cicd-integration.md#the-gate-script).

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

### Settings for Each Environment

Keep one file for each environment beside the standard file. Each holds only the settings that
differ, and is merged over the standard file when the configuration is loaded.

```powershell
# Tests/PesterConfiguration.Development.psd1
@{
    Run = @{
        Path = @('./Tests/Unit')
        PassThru = $true
    }

    Output = @{
        Verbosity = 'Detailed'
    }

    CodeCoverage = @{
        Enabled = $true

        # A lower target for development runs.
        CoveragePercentTarget = 70
    }
}
```

The target only sets the figure that Pester reports against
([The Target Is Not a Gate](#the-target-is-not-a-gate)), so the lower development figure does not
change what CI enforces: the CI file sets 80 (TST-40). The alternative is one figure, 80, in every
file.

```powershell
# Tests/PesterConfiguration.CI.psd1
@{
    Run = @{
        Path = @('./Tests/Unit', './Tests/Integration', './Tests/Security')
        PassThru = $true
    }

    Output = @{
        Verbosity = 'Normal'

        # Or 'AzureDevops'.
        CIFormat = 'GithubActions'
        RenderMode = 'Ansi'
    }

    CodeCoverage = @{
        Enabled = $true
        CoveragePercentTarget = 80
        OutputFormat = 'JaCoCo'
        OutputPath = './Tests/Results/Coverage.xml'
    }

    TestResult = @{
        Enabled = $true
        OutputFormat = 'NUnitXml'
        OutputPath = './Tests/Results/TestResults.xml'
    }
}
```

`Auto` detects the CI system, but setting `CIFormat` in the CI file states which one the file is
for. The alternative is to leave it at `Auto`.

```powershell
# Tests/PesterConfiguration.Performance.psd1
@{
    Run = @{
        Path = @('./Tests/Performance')
        PassThru = $true

        # Performance tests must not share the machine with other work.
        Parallel = $false

        # A baseline assumes the declared order (TST-46).
        Shuffle = $false
    }

    Output = @{
        Verbosity = 'Normal'
    }

    Filter = @{
        Tag = @('Performance', 'Benchmark')
    }

    TestResult = @{
        Enabled = $true
        OutputPath = './Tests/Results/PerformanceResults.xml'
    }
}
```

### Loading and Merging the Files

The loader reads the standard file, merges the file of the environment over it when that file
exists, and creates the configuration. The functions are kept in a helper file that the runner
script dot-sources; see [Test Execution Guide](./test-execution.md#the-test-runner-script).

```powershell
# Tests/TestRunnerHelpers.ps1
function Merge-Hashtable {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Base,

        [Parameter(Mandatory)]
        [hashtable]$Override
    )

    $merged = $Base.Clone()
    foreach ($key in $Override.Keys) {
        $baseValue = $merged[$key]
        $overrideValue = $Override[$key]
        if ($baseValue -is [hashtable] -and $overrideValue -is [hashtable]) {
            $merged[$key] = Merge-Hashtable -Base $baseValue -Override $overrideValue
        } else {
            $merged[$key] = $overrideValue
        }
    }

    $merged
}


function Get-PesterConfiguration {
    [CmdletBinding()]
    [OutputType('PesterConfiguration')]
    param(
        [ValidateSet('Development', 'CI', 'Production', 'Performance', 'Security', 'Integration')]
        [string]$Environment = 'Development',

        [string]$ConfigPath = $PSScriptRoot
    )

    try {
        $basePath = Join-Path -Path $ConfigPath -ChildPath 'PesterConfiguration.psd1'
        $settings = Import-PowerShellDataFile -LiteralPath $basePath -ErrorAction Stop

        $environmentPath = Join-Path -Path $ConfigPath -ChildPath "PesterConfiguration.$Environment.psd1"
        if (Test-Path -LiteralPath $environmentPath) {
            # The file of the environment overrides the standard file.
            $overrides = Import-PowerShellDataFile -LiteralPath $environmentPath -ErrorAction Stop
            $settings = Merge-Hashtable -Base $settings -Override $overrides
        }

        $configuration = New-PesterConfiguration -Hashtable $settings -ErrorAction Stop
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $configuration
}
```

A script chooses the environment from the variables that CI systems set:

```powershell
if ($env:CI -eq 'true' -or $env:BUILD_ID) {
    $environment = 'CI'
} elseif ($env:PERFORMANCE_TESTING -eq 'true') {
    $environment = 'Performance'
} else {
    $environment = 'Development'
}

$configuration = Get-PesterConfiguration -Environment $environment
```

The same merge gives settings for an organisation with overrides for one project:

```powershell
# Settings for every project of the organisation
$organisationSettings = @{
    CodeCoverage = @{
        CoveragePercentTarget = 80
        OutputFormat = 'JaCoCo'
    }
    TestResult = @{
        OutputFormat = 'NUnitXml'
    }
}

# A higher target for one critical project
$projectSettings = @{
    CodeCoverage = @{
        CoveragePercentTarget = 85
    }
}

$settings = Merge-Hashtable -Base $organisationSettings -Override $projectSettings
$configuration = New-PesterConfiguration -Hashtable $settings
```

The alternative to separate files is to load the standard file and then assign the options that
differ for one kind of run.

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

### Validating a Configuration Before the Run

Check a loaded configuration before the run starts: that the Pester version is the pinned one, that
the test paths exist, that the folder for the reports exists, that the coverage target is a
percentage, and that no key was misspelled. The function reports what it finds and changes
nothing; the script that calls it throws.

```powershell
# Tests/TestRunnerHelpers.ps1
function Test-PesterConfiguration {
    [CmdletBinding()]
    [OutputType('TestRunner.Check')]
    param(
        [Parameter(Mandatory)]
        [PesterConfiguration]$Configuration
    )

    $pesterVersion = (Get-Module -Name Pester).Version
    $outputFolder = Split-Path -Path $Configuration.TestResult.OutputPath.Value -Parent
    $target = $Configuration.CodeCoverage.CoveragePercentTarget.Value
    $unknownKeys = @($Configuration.GetUnknownKeys())

    $issues = @(
        if ($pesterVersion -ne [version]'6.2.0') {
            "Pester 6.2.0 is required, and $pesterVersion is loaded."
        }

        foreach ($testPath in $Configuration.Run.Path.Value) {
            if (-not (Test-Path -Path $testPath)) {
                "Test path not found: $testPath"
            }
        }

        if ($outputFolder -and -not (Test-Path -LiteralPath $outputFolder)) {
            "Output folder not found: $outputFolder"
        }

        if ($target -gt 100 -or $target -lt 0) {
            "Invalid coverage target: $target"
        }

        # Invoke-Pester only warns about a key that matches no option.
        if ($unknownKeys.Count -gt 0) {
            "Configuration keys that match no option: $($unknownKeys -join ', ')"
        }
    )

    [PSCustomObject]@{
        PSTypeName = 'TestRunner.Check'
        Valid = $issues.Count -eq 0
        Issues = $issues
    }
}
```

```powershell
$check = Test-PesterConfiguration -Configuration $configuration
if (-not $check.Valid) {
    throw "The Pester configuration is not valid. $($check.Issues -join ' ')"
}
```

`Test-Path -Path` is used for the test paths because `Run.Path` may hold wildcards. The relative
paths of the standard file are tested against the current location, so call the function after the
script has changed to the repository root.

## Option Reference

### Run

| Option | Default | Meaning |
| --- | --- | --- |
| `Run.Path` | `.` | Folders or files to search for tests. Wildcards are allowed. |
| `Run.ExcludePath` | empty | Folders or files to leave out. Each entry is compared with full paths; see [Pester Test Structure Guide](./test-structure-guide.md#hidden-folders-and-excluded-paths). |
| `Run.ScriptBlock` | empty | Script blocks that contain tests. |
| `Run.Container` | empty | Containers made by `New-PesterContainer`, used to pass data to a test file. It is not a way to run files in parallel. |
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
| `Output.RenderMode` | `Auto` | `Auto`, `Ansi`, `ConsoleColor`, or `Plaintext`; see [Render Mode](#render-mode). |
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

`Run.ExcludePath` is not a substitute for `CodeCoverage.ExcludePath`. Measured on 6.2.0, a source
file or folder named in `Run.ExcludePath` by its full path, or matched by a wildcard, was still
measured: the number of analyzed files and commands did not change.

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
enforces the gate itself: it compares the figure with the configured target, which the result
object repeats, and lists the uncovered commands for each file when the gate fails.

```powershell
$result = Invoke-Pester -Configuration $configuration

$coverage = [math]::Round($result.CodeCoverage.CoveragePercent, 2)
$target = $result.CodeCoverage.CoveragePercentTarget
if ($coverage -lt $target) {
    $uncovered = $result.CodeCoverage.CommandsMissed | Group-Object -Property File
    foreach ($file in $uncovered) {
        Write-Host ('  {0}: {1} uncovered command(s)' -f $file.Name, $file.Count)
    }
    throw "Code coverage is $coverage percent. The target is $target."
}
```

The configured target in CI is 80 (TST-40). The gate in the testing rules compares with the literal
`80` instead of the configured target; with a target of 80 the two are the same check.

### Profiler and Breakpoints

By default Pester 6 measures coverage with a profiler-based tracer. Pester 5 set a breakpoint on
every command by default. `CodeCoverage.UseBreakpoints = $true` selects the breakpoint method; use
it only when something depends on breakpoint-based figures.

The tracer is often described as much faster than breakpoints on a large code base. That was not
reproduced on 6.2.0. Measured on a generated code base of 60 files and 33,600 commands, on a machine
that was also doing other work: with 2,400 tests that ran 93 percent of the commands, a run took 34
seconds without coverage, 153 and 203 seconds with the tracer, and 144 and 158 seconds with
breakpoints. With 120 tests that ran 5 percent of the commands, it took 126 and 132 seconds with the
tracer, and 137 and 152 seconds with breakpoints. Measure on the project's own code before choosing
a method for its speed.

A parallel run always measures with breakpoints, whatever the option says; see
[Test Execution Guide](./test-execution.md#coverage-in-a-parallel-run).

### Report Format and Paths

`JaCoCo` is the default format and `Cobertura` is the alternative, for GitLab, Codecov, and similar
tools. The `CoverageGutters` format of Pester 5 was removed. It existed only to write paths relative
to the repository root, and every coverage report is now written that way, so the plain `JaCoCo`
format works with the Coverage Gutters extension.

Paths in the report are relative to `CodeCoverage.ReportRoot`, which defaults to `Run.RepoRoot`.
Measured on 6.2.0 for the file `C/src/Code.ps1` in a repository: the JaCoCo package is `C/src` by
default and `src` with `ReportRoot` set to the folder `C`. Set `ReportRoot` when the tool that reads
the report expects paths relative to another folder.

## Output

`Output.Verbosity` has four values. `None` prints nothing, `Normal` prints one line for each test
file and the failures, `Detailed` prints every block and test, and `Diagnostic` adds Pester's debug
messages. Use `Normal` in CI and `Detailed` in a local run.

### Render Mode

| `Output.RenderMode` | Meaning |
| --- | --- |
| `Auto` | The default. Detects what the terminal can do. |
| `Ansi` | Forces ANSI (VT) escape sequences. |
| `ConsoleColor` | Uses the console colours of the host and writes no escape sequences. |
| `Plaintext` | No colour. The best choice when the log is captured. |

`Auto` becomes `Plaintext` when the `NO_COLOR` environment variable is set, `Ansi` when the host
supports virtual terminal sequences, and `ConsoleColor` otherwise. Measured on 6.2.0 with the output
of a `pwsh` process captured as text: `Auto` and `Ansi` wrote escape sequences into the text, and
`ConsoleColor` and `Plaintext` wrote none. The CI file sets `Ansi`, for a build log that shows
colour.

### CI Output

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
unless the user asks. `Run.Shuffle` is the exception: turn it on in every run except a run of
performance tests (TST-46).

- `Run.Parallel` and `Run.ParallelThrottleLimit`: see
  [Test Execution Guide](./test-execution.md#parallel-test-execution).
- `Run.Shuffle` and `Run.ShuffleSeed`: see
  [Test Execution Guide](./test-execution.md#shuffled-test-order).
- `Mock.Global`: with the option on, a mock applies to calls of the command from any module or
  script, and `-ModuleName` no longer limits where it applies. See
  [Mocking Patterns Guide](./mocking-patterns.md).

### Shuffle in Every Run

Turn shuffling on in every run, on a developer's computer and in CI, with a new seed for each run
and the seed named in the failure message. A developer then meets an order dependence while
writing the test, not in the log of a CI job. The first shuffled run of one suite of 1,300 tests
failed three tests under seed 1 that file order had always hidden: each wrote into a folder that an
earlier test in the same file had created. Two other seeds passed. The same suite later moved to
importing the module once for each run instead of in every file, which makes state visible across
files; the shuffled run is what keeps that trade honest, because a test that passes only after a
fresh import fails there with a seed to replay.

Document the replay command in the README of the tests, so that whoever reads the failing log knows
what to do with the number:

```powershell
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path -Path $PSScriptRoot -ChildPath 'Tests/Unit'
$configuration.Run.Shuffle = $true
$configuration.Run.ShuffleSeed = 852659930

Invoke-Pester -Configuration $configuration
```

With the runner script the same replay is
`./Tests/Invoke-Tests.ps1 -TestType Unit -ShuffleSeed 852659930`.

### Global Mocks

With `Mock.Global` on, a mock is still removed when the block that declared it ends, and it is tied
to the run that created it, so it cannot leak into a nested run of Pester inside a test. Measured on
6.2.0 with a global mock of `Get-Date`: a test in a nested `Invoke-Pester` call got the real
command while the outer test still got the mock, and a `Describe` block after the one that declared
the mock got the real command again.

The option may still change. The Pester team has stated an intent to make it the default in
version 7.
