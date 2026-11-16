# Pester 6 Migration Guide

This guide lists what has to change when a test suite moves from Pester 5 to Pester 6, and what
changed between the 6.0, 6.1, and 6.2 releases. It supports the testing rules in
[powershell-pester.instructions.md](../powershell-pester.instructions.md), which target Pester
6.2.0.

Pester 6.0.0 was published on 2026-07-07, 6.1.0 on 2026-08-11, and 6.2.0 on 2026-09-09. The
statements in this guide were checked by running Pester 5.9.1, 6.0.1, 6.1.0, and 6.2.0.

## Supported Platforms

Pester 6 runs on Windows PowerShell 5.1 and on PowerShell 7.4 or later. Of the PowerShell 7
versions, only 7.6 is still supported; 7.4 and 7.5 reached their end-of-support date on 10-Nov-2026.
Remove them, and any older version, from CI matrices (CIC-04).

Every test file starts with the line that declares the Pester version (TST-01):

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }
```

Nothing in 6.1 or 6.2 breaks a test file that was written for 6.0. The changes in those releases
that can affect a suite are in configuration, in shared setup files, and in a few assertion
parameters; see [Moving From 6.0 to 6.1](#moving-from-60-to-61) and
[Moving From 6.1 to 6.2](#moving-from-61-to-62).

## Upgrade Checklist

Items 1 to 3 fail at once on Pester 6. The rest change behaviour and can go unnoticed.

1. Replace `Assert-MockCalled` and `Assert-VerifiableMock`. Both commands were removed. In a file
   that uses the Pester 6 assertions, use `Should-Invoke`. In a file that keeps the `Should -Be`
   style, use `Should -Invoke` and `Should -InvokeVerifiable` (TST-10, TST-22).
2. Remove `It -Pending`, `Set-ItResult -Pending`, and `-Focus`. Use `-Skip`, or
   `Set-ItResult -Skipped` or `-Inconclusive`. To run a selection of tests, use tags or a filter.
3. Check every `-ForEach` and `-TestCases` list that can be empty. An empty or `$null` list now
   fails discovery of the file (TST-30).
4. Give every mock that has a `-ParameterFilter` a default mock beside it. A call that matches no
   filter no longer reaches the real command; it throws.
5. Make every test file self-contained (TST-02). Discovery and run now happen file by file.
6. Rename any tag called `None`. It is now a reserved filter value (TST-04).
7. Review the code coverage settings. The default method changed, and the `CoverageGutters` format
   was removed.
8. Check test and block names that contain `<`, `>`, or a backtick. Name expansion changed.
9. Look for `*.Tests.ps1` files in hidden folders. They are now found and run.
10. Replace the Pester 4 parameters of `Invoke-Pester`, such as `-Script` and `-EnableExit`, with a
    configuration object.
11. Change the CI gate so that it tests `Result` and `TotalCount`, not `FailedCount` (TST-42).
12. Write new test files with the Pester 6 assertions (TST-10).

## Discovery and Run Happen Per File

Pester 5 discovered every file and then ran every file. Pester 6 discovers one file and runs it
before it discovers the next. Measured with two files, A and B:

| Version | Order |
| --- | --- |
| Pester 5.9.1 | discover A, discover B, run A, run B |
| Pester 6.2.0 | discover A, run A, discover B, run B |

In a parallel run each file is discovered and run in its own runspace.

What this breaks: a test file that relies on something another test file set up. Anything a file
needs to be discovered, such as a helper module or the data for `-ForEach`, has to be loaded by that
file.

```powershell
# Non-compliant: relies on another test file having imported the module
BeforeDiscovery {
    $cases = Get-ModuleTestCase
}

# Compliant: the file loads what its own discovery needs
BeforeDiscovery {
    $testsRoot = Split-Path -Path $PSScriptRoot -Parent
    $repositoryRoot = Split-Path -Path $testsRoot -Parent
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module -Name (Join-Path -Path $repositoryRoot -ChildPath 'ModuleName.psd1')
    }
    $cases = Get-ModuleTestCase
}
```

Setup that many files share can go in a `Pester.BeforeContainer.ps1` file, which Pester marks as
experimental; see [Pester Test Structure Guide](./test-structure-guide.md#shared-setup-files).

The console output changed with this. A run prints `Running tests from <n> files.` and then one line
for each file. Pester 5 printed `Starting discovery in <n> files.`, `Discovery found <n> tests`, and
`Running tests.` A discovery-only run on Pester 6 still prints the discovery lines. Do not parse
this text; use the result object.

## Removed Commands, Parameters, and Behaviour

| Removed in Pester 6 | Replacement |
| --- | --- |
| `Assert-MockCalled` | `Should-Invoke`, or `Should -Invoke` in a file that keeps the old style |
| `Assert-VerifiableMock` | `Should-Invoke -Verifiable`, or `Should -InvokeVerifiable` |
| `It -Pending` and `Set-ItResult -Pending` | `It -Skip`, `Set-ItResult -Skipped`, or `Set-ItResult -Inconclusive` |
| The `Focus` property of a test in the result object | None |
| `CodeCoverage.OutputFormat = 'CoverageGutters'` | `JaCoCo` |
| The parameter set of `Invoke-Pester` with `-Script`, `-EnableExit`, and other Pester 4 parameters | `Invoke-Pester -Configuration` |
| Calling the real command when no mock filter matches | A default mock without `-ParameterFilter` |

`-Focus` is not a parameter of `Describe`, `Context`, or `It` in Pester 6, and a file that uses it
fails discovery with `A parameter cannot be found that matches parameter name 'Focus'`. The
parameter was already absent from these commands in Pester 5.9.1.

### Mocks No Longer Fall Through

In Pester 5.9.1 a call that matched no `-ParameterFilter` ran the real command. In Pester 6 it
throws:

```text
No mock for command 'Get-Thing' matched the call: none of the parameter filters matched, and there
is no default mock to fall back to.
```

Declare the default case as well:

```powershell
Mock -CommandName Get-Thing -MockWith { 'default' }
Mock -CommandName Get-Thing -ParameterFilter { $Name -eq 'alpha' } -MockWith { 'first' }
```

### An Empty ForEach Fails Discovery

In Pester 5.9.1 a test with an empty `-ForEach` list was left out, and the run passed. In Pester 6
the file fails discovery with `Value can not be null or empty array`. The option is
`Run.FailOnNullOrEmptyForEach`, and `-AllowNullOrEmptyForEach` turns it off for one block or test.
See [Test Data Management Guide](./test-data-guide.md#data-built-in-the-wrong-block).

## Test and Block Name Expansion

In Pester 6 only the text between `<` and `>` is evaluated, as a PowerShell expression. Every other
character of a name is kept as written.

| Name | Pester 5.9.1 | Pester 6.2.0 |
| --- | --- | --- |
| `'Adds up to <($Left + $Right)>'` with 1 and 2 | `Adds up to <($Left + $Right)>` | `Adds up to 3` |
| `'Lists <Items>'` with the array 1, 2, 3 | `Lists 1 2 3` | `Lists @(1, 2, 3)` |

A backtick before `<` keeps the bracket as text, and backticks elsewhere stay as written. Pester
5.9.1 read a backtick as the start of an escape sequence when the name also contained a template:

```powershell
It 'Reports <Count> items with `backtick` text' -ForEach @(@{ Count = 1 }) {
}
# Pester 5.9.1: Reports 1 items with acktick text
# Pester 6.2.0: Reports 1 items with `backtick` text

It 'Keeps `<these brackets> as text' {
}
# Pester 6.2.0: Keeps <these brackets> as text
```

A `$(...)` sequence in a name is not evaluated, in 5.9.1 or in 6.2.0.

## Configuration Changes

Compared with Pester 5.9.1:

| Option | Change |
| --- | --- |
| `Run.Parallel`, `Run.ParallelThrottleLimit` | New, experimental |
| `Run.RepoRoot` | New, experimental |
| `Run.FailOnNullOrEmptyForEach` | New, on by default |
| `Run.Shuffle`, `Run.ShuffleSeed` | New in 6.1, experimental |
| `Run.BeforeContainer` | Existed only in 6.0 |
| `Should.DisableV5` | New |
| `Mock.Global` | New in 6.1, experimental |
| `Output.ShowTags`, `Output.CIDebugOutput` | New in 6.1 |
| `CodeCoverage.UseBreakpoints` | Default changed from `$true` to `$false` |
| `CodeCoverage.OutputFormat` | `CoverageGutters` removed. `JaCoCo` and `Cobertura` remain. |
| `CodeCoverage.ReportRoot` | New. Paths in the report are relative to it, and it defaults to `Run.RepoRoot`. |

These exist in Pester 5.9.1 as well and are unchanged: the `NUnit3` test result format, the
`Cobertura` coverage format, `Output.RenderMode`, `Debug.ShowStartMarkers`,
`CodeCoverage.ExcludeTests`, `Run.SkipRemainingOnFailure`, and the default of 75 for
`CodeCoverage.CoveragePercentTarget`.

Setting any option of `TestResult` or `CodeCoverage` to a value other than its default now turns
that section on. There is no `CodeCoverage.Threshold` option; the target is
`CodeCoverage.CoveragePercentTarget`, and it does not fail a run. Every option is listed in
[Pester Configuration Guide](./pester-configuration.md#option-reference).

## Other Changes in Short

- Files in folders with the hidden attribute are found and run. Pester 5.9.1 skipped them. See
  [Pester Test Structure Guide](./test-structure-guide.md#hidden-folders-and-excluded-paths).
- `None` is a reserved tag filter value that selects tests without a tag. See
  [Pester Test Structure Guide](./test-structure-guide.md#the-reserved-tag-none).
- Test files can run in parallel. See
  [Test Execution Guide](./test-execution.md#parallel-test-execution).
- Pester 6 adds the `Should-*` assertions, and the `Should -Be` style still works. New test files
  use the new assertions, existing files keep their style, and one file does not mix the two
  (TST-10). Do not set `Should.DisableV5` until no file uses the old style. See
  [Assertion Guide](./assertion-guide.md).

## Verifying the Migration

```powershell
$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$testRoot = Join-Path -Path $repositoryRoot -ChildPath 'Tests'
$testFiles = @(Get-ChildItem -LiteralPath $testRoot -Filter '*.Tests.ps1' -File -Recurse)

# 1. The version that is loaded
Import-Module -Name Pester -RequiredVersion 6.2.0
(Get-Module -Name Pester).Version

# 2. Commands and parameters that Pester 6 does not have
$removedPattern = 'Assert-MockCalled|Assert-VerifiableMock|-Focus\b|-Pending\b'
$testFiles |
    Select-String -Pattern $removedPattern |
    Select-Object -Property Path, LineNumber, Line

# 3. A discovery-only run: finds empty -ForEach lists and files that fail discovery
$configuration = New-PesterConfiguration
$configuration.Run.Path = $testRoot
$configuration.Run.SkipRun = $true
$configuration.Run.PassThru = $true
$result = Invoke-Pester -Configuration $configuration
$result.FailedContainers | Select-Object -Property Item, ErrorRecord

# 4. Each file alone: finds files that are not self-contained
foreach ($testFile in $testFiles) {
    $fileResult = Invoke-Pester -Path $testFile.FullName -PassThru -Output None
    if ($fileResult.Result -ne 'Passed') {
        Write-Warning "Fails when run alone: $($testFile.FullName)"
    }
}
```

Step 4 also reports a file that fails for another reason, so compare its list with a full run.

## Moving From 6.0 to 6.1

The differences below were measured between Pester 6.0.1 and 6.1.0.

### Check Before Upgrading

- `Run.BeforeContainer` was removed. Assigning it throws
  `The property 'BeforeContainer' cannot be found on this object`. In a hashtable or `.psd1` file,
  6.1 ignores the key without a message, so search for the name. Move the script block into a
  `Pester.BeforeContainer.ps1` file.
- `Should-BeHashtable`: `-Actual` moved from position 1 to position 0. A call that passes the value
  by position can break; a call that pipes it or names the parameter is not affected.
- `-Expected` became mandatory on `Should-NotBeString`, `Should-BeFasterThan`, and
  `Should-BeSlowerThan`.
- `Should-Throw -Because` can only be passed by name. In 6.0 it was also the fourth positional
  parameter.
- `Should-BeEquivalent` has no `-StrictOrder` parameter in 6.0.1, 6.1.0, or 6.2.0. To assert the
  order of a collection, assert the count and then the element at each index (TST-14).

### New in 6.1

| Addition | Described in |
| --- | --- |
| `New-ShouldAssertion`, for writing a custom assertion | [Custom Assertion Guide](./custom-assertions.md) |
| `Mock.Global` (experimental) | [Mocking Patterns Guide](./mocking-patterns.md) |
| `Run.Shuffle` and `Run.ShuffleSeed` (experimental) | [Test Execution Guide](./test-execution.md#shuffled-test-order) |
| `Output.ShowTags` and `Output.CIDebugOutput` | [Pester Configuration Guide](./pester-configuration.md#output) |
| `Should-BeString -NormalizeLineEnding` | [Assertion Guide](./assertion-guide.md) |
| `Should-ContainCollection -IgnoreOrder` | [Assertion Guide](./assertion-guide.md) |
| Code coverage in a parallel run | [Test Execution Guide](./test-execution.md#coverage-in-a-parallel-run) |

### Behaviour That Changed in 6.1

- Coverage in a parallel run is collected. In 6.0.1 a run with both options warned
  `Run.Parallel does not support CodeCoverage yet` and ran sequentially.
- `Run.ExcludePath` excludes a folder given by its full path. In 6.0.1 such an entry had no effect.
- Report paths are made absolute when the run starts. In 6.0.1 a relative
  `TestResult.OutputPath` was resolved when the report was written, so a test that changed the
  location moved the report.
- A file that fails discovery is written to the test result report. In 6.0.1 it was missing.
- A `break` or `continue` with a label that matches no loop fails its test, and the run goes on. In
  6.0.1 it ended the whole run without a result.
- A skipped test with `-ForEach` gets its expanded name, for example `Skips foo`. In 6.0.1 it kept
  the template text.
- `Should-HaveType` accepts a type name as a string, so it works for an object with a `PSTypeName`
  (TST-13). In 6.0.1 the string could not be converted to a type.
- `Should-BeString -Expected ''` is accepted. In 6.0.1 the empty string was rejected.
- `Should-Throw -ExceptionMessage` adds a hint when the pattern and the message are identical apart
  from the wildcard characters `[`, `]`, `*`, and `?`.
- A complex value in a failure message is shortened, for example
  `Management.Automation.FunctionInfo{Name='Invoke-Pester'}`. On 6.0.1 the same failing test did not
  finish within three minutes.

## Moving From 6.1 to 6.2

The differences below were measured between Pester 6.1.0 and 6.2.0.

### Check Before Upgrading

- Top-level code in `Pester.BeforeContainer.ps1` runs during discovery only. A setup file written
  for 6.1 stops working without a message; see
  [The Setup File Needs a BeforeAll](#the-setup-file-needs-a-beforeall).
- `Should-BeFasterThan` and `Should-BeSlowerThan` throw for a value that is neither a script block
  nor a time span. The message starts with
  `Expected a [scriptblock] to measure or a [timespan] to compare`. In 6.1 such a test passed
  without measuring anything. Pipe the script block.
- A configuration value of the wrong type throws when the configuration is created, for example
  `Run.Parallel expects a bool, but got the string 'yes'`. In 6.1 the value was ignored.
- A configuration key that matches no option produces a warning from `Invoke-Pester`, and the keys
  are returned by `$configuration.GetUnknownKeys()`. In 6.1 the key was ignored and the method did
  not exist. See [Pester Configuration Guide](./pester-configuration.md#checking-what-was-loaded).
- The message for a collection passed to `-Expected` names the assertion. It reads
  `is not allowed by Should-Be` where 6.1 said `is not allowed by this assertion`.
- Output written by a setup file no longer produces the warning
  `Pester received unexpected output while running tests and ignored it`.

### The Setup File Needs a BeforeAll

In 6.1 a function defined at the top level of `Pester.BeforeContainer.ps1` was available to the
tests, and a `BeforeAll` in the file had no effect. In 6.2 the file follows the same rule as a test
file: top-level code runs during discovery, and `BeforeAll` runs before the tests.

```powershell
# Pester 6.1
. (Join-Path -Path $PSScriptRoot -ChildPath 'Tests/TestHelpers/TestHelpers.ps1')

# Pester 6.2
BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Tests/TestHelpers/TestHelpers.ps1')
}
```

One file cannot serve both versions. What reaches the tests in 6.2, and what does not, is in the
table in [Pester Test Structure Guide](./test-structure-guide.md#discovery-time-and-run-time).

### A Block Can Have Several Setup Blocks

In 6.2 a block can contain more than one `BeforeAll`, `BeforeEach`, `AfterEach`, or `AfterAll`.
Setup blocks run in the order they are written, and teardown blocks run in the reverse order. In 6.0
and 6.1 the second one failed discovery of the file with the message
`BeforeAll is already defined in this block`.

```powershell
Describe 'Get-User' -Tag 'Unit' {
    BeforeAll {
        $userFile = Join-Path -Path $TestDrive -ChildPath 'users.json'
    }

    BeforeAll {
        Set-Content -LiteralPath $userFile -Value '[{ "userName": "ann" }]' -Encoding ascii
    }
}
```

### New in 6.2

| Addition | Described in |
| --- | --- |
| `Pester.BeforeContainer.ps1` in any folder between the repository root and the test file. In 6.1 only the file at the root applied. | [Pester Test Structure Guide](./test-structure-guide.md#setup-for-one-folder) |
| The `#pester:no-inherit` directive | [Pester Test Structure Guide](./test-structure-guide.md#setup-for-one-folder) |
| `BeforeContainerFile` on each file in the result object | [Pester Test Structure Guide](./test-structure-guide.md#setup-for-one-folder) |
| `GetUnknownKeys()` on the configuration object | [Pester Configuration Guide](./pester-configuration.md#checking-what-was-loaded) |
| `Run.Parallel` on Windows PowerShell 5.1. In 6.1 it warned and ran sequentially there. | [Test Execution Guide](./test-execution.md#parallel-test-execution) |
| An error when a parallel run loses the result of a file | [Test Execution Guide](./test-execution.md#a-lost-file-is-an-error) |
| `Should-BeString` shows every region that differs, with line numbers, for a long string | [Assertion Guide](./assertion-guide.md) |

### Behaviour That Changed in 6.2

- `Run.RepoRoot`, when it is not set, is found from the current location when the run starts. In 6.1
  the run used the working directory of the process, which `Set-Location` does not change. See
  [Pester Configuration Guide](./pester-configuration.md#runreporoot).
- A `BeforeAll` that throws is reported with its own error. In 6.1 the block was reported with a
  message about a `break` or `continue` statement whose label matches no enclosing loop.
