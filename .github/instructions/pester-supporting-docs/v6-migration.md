# Pester 6 Migration Guide

This guide lists what has to change when a test suite moves from Pester 5 to Pester 6, and what
changed between the 6.0, 6.1, and 6.2 releases. It supports the testing rules in
[powershell-pester.instructions.md](../powershell-pester.instructions.md), which target Pester
6.2.0.

Pester 6.0.0 was published on 2026-07-07, 6.1.0 on 2026-08-11, and 6.2.0 on 2026-09-09. The
statements in this guide were checked by running Pester 5.9.1, 6.0.1, 6.1.0, and 6.2.0. The few
that could not be run say so.

Do not use emoji in generated code, documentation, or test output. Use plain text and standard
ASCII characters only (STY-06, TST-07).

## Supported Platforms

Pester 6 runs on Windows PowerShell 5.1 and on PowerShell 7.4 or later. Of the PowerShell 7
versions, only 7.6 is still supported; 7.4 and 7.5 reached their end-of-support date on 10-Nov-2026.
Remove them, and any older version, from CI matrices (CIC-04).

Every test file starts with the line that declares the Pester version (TST-01). A second line can
state the oldest PowerShell version that the file runs on. Write `5.1`, which is what Pester 6
itself needs, only in a project that declares Windows PowerShell support, because the line is such
a declaration (VER-02); otherwise write the project's own target:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }
#Requires -Version 5.1
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
   fails discovery of the file (TST-30). Opt out for one block or test with
   `-AllowNullOrEmptyForEach` where an empty list is legitimate, or correct the code that builds
   the list so that it cannot be empty.
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

Run-time setup in `BeforeAll` was never affected by this change and works as before.

When several files need the same setup, put it in a `Pester.BeforeContainer.ps1` file in the
repository root instead of repeating it. Pester dot-sources that file before every test file is
discovered and run, and marks the mechanism as experimental; see
[Pester Test Structure Guide](./test-structure-guide.md#shared-setup-files).

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

The `JaCoCo` output now works with the Coverage Gutters extension, so that extension needs no
format of its own. This statement was not run for this guide.

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
- `None` is a reserved tag filter value that selects tests without a tag. In a run with that
  filter, read the `Passed` count in the summary, not the count of discovered tests. See
  [Pester Test Structure Guide](./test-structure-guide.md#the-reserved-tag-none).
- Test files can run in parallel with `Run.Parallel`. Treat it as opt-in: the directive name, the
  shape of the configuration, and the behaviour may still change before the option is declared
  stable. See [Test Execution Guide](./test-execution.md#parallel-test-execution).
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

Step 3 is the check with the highest value for its cost: it walks every file through discovery, so
an empty `-ForEach` list fails there without the price of a full run. It does not find every file
that depends on another one. Measured on 6.2.0 with a helper module that only the first file
imports: the sequential discovery-only run passed, because the first file had already loaded what
the second one needed, and the same run failed the second file with `Run.Parallel` set or when
that file was discovered alone. A file whose tests need another file at run time passes discovery
in every case. Step 4 finds both kinds.

Step 4 also reports a file that fails for another reason, so compare its list with a full run.

## Moving From 6.0 to 6.1

The differences below were measured between Pester 6.0.1 and 6.1.0.

### Check Before Upgrading

- `Run.BeforeContainer` was removed. The removal does not appear in the 6.1.0 release
  announcement, so check for the option before upgrading. 6.0 had two ways to share setup: this
  option and the `Pester.BeforeContainer.ps1` file. The option was a script block with no file to
  anchor a relative path to, so it was dropped. Neither of these two statements was run for this
  guide. Assigning the option throws
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

### Adopting the Experimental Options

Pester leaves `Mock.Global` and `Run.Shuffle` off by default. Turning either on can expose real
problems in an existing suite, which is what they are for: with `Mock.Global` a call that was not
mocked before can start to reach a mock, and `Run.Shuffle` fails tests that depend on the declared
order. Both may still change before they are declared stable.

`Run.Shuffle` is on in every run (TST-46). When an existing suite first turns it on, fix the tests
it exposes; a file that must keep its declared order opts out with `#pester:no-shuffle`.
`Mock.Global` stays off unless the user asks for it. When a suite adopts it, turn it on in a job of
its own first, not across the whole suite, and fix what it exposes there.

### Behaviour That Changed in 6.1

- Coverage in a parallel run is collected. In 6.0.1 a run with both options warned
  `Run.Parallel does not support CodeCoverage yet` and ran sequentially.
- `Run.ExcludePath` excludes a folder given by its full path. In 6.0.1 such an entry had no effect.
- Report paths are made absolute when the run starts, and so is a relative
  `CodeCoverage.ReportRoot`. In 6.0.1 a relative `TestResult.OutputPath` was resolved when the
  report was written, so a test that changed the location moved the report, and a relative
  `ReportRoot` stayed relative: the JaCoCo report then named the package by its full path. The
  configuration object that was passed in keeps the relative values in every version; the resolved
  ones are in `$result.Configuration`.
- At `Normal` verbosity the line for a passing file ends with its number of tests, for example
  `(5 tests)`. In 6.0.1 the line ended after the duration. Anything that reads that line has to
  accept the extra field.
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
- `Run.SkipRun` applies the setup files. In 6.1 a discovery-only run skipped them, so a `-ForEach`
  over data that a setup file provides failed discovery with `Value can not be null or empty array`
  while the full run passed. A discovery-only run is what a test explorer such as the one in VS
  Code uses to list tests, so the data came back empty there; the explorer itself was not run for
  this guide.
- A `BeforeAll` that throws is reported with its own error. In 6.1 the block was reported with a
  message about a `break` or `continue` statement whose label matches no enclosing loop.
- An error written in a worker of a parallel run no longer ends the run when the caller has set
  `$ErrorActionPreference = 'Stop'`. Measured with four files, one of which writes a
  non-terminating error in a test: 6.1.0 ended the run and returned no result object, and 6.2.0
  reported all four files.
- A failure points at the line that caused it. For an assertion that fails inside a helper
  function, the output adds the line of the test that called the helper; 6.1 showed only the line
  inside the helper. An error raised inside Pester, such as `Should-Invoke` for a command that does
  not exist, shows the line of the test; 6.1 showed no location for it.
- `Invoke-Pester` keeps the exit code `-1` when it fails outside the tests. Measured for a run
  that finds no test file: 6.2.0 leaves `$LASTEXITCODE` at `-1`, and 6.1.0 overwrote it with
  `$null`. Before 6.2 the code could also become `0` when a plug-in failed after an otherwise
  successful run; that case was not reproduced for this guide.
- Stack traces from Pester's own C# code show `/_/src/csharp/Pester/...`. In 6.1 they showed the
  path on the build agent, `D:\a\1\s\src\csharp\Pester\...`. The change also makes the build
  reproducible, which was not checked for this guide.
- `IO exception during a TestRegistry operation, retrying.` is a debug message. In 6.1 it was a
  warning, shown when the retry recovered. This was read from the source of both versions.
- Pester imports again on PowerShell 7.4.0 to 7.4.5. 6.0 and 6.1 failed there with
  `Cannot convert "PesterConfigurationDeserializer" from String to Type`, because the `net8.0`
  assembly referenced a newer `System.Management.Automation` than those releases carry. Those
  PowerShell versions were not available, so this was not run for this guide.

### Verifying the Upgrade to 6.2

The script uses `$repositoryRoot` as set in [Verifying the Migration](#verifying-the-migration).

```powershell
# 1. Setup files with top-level statements other than BeforeAll and AfterAll.
#    On 6.2 those statements run during discovery only.
$setupFiles = Get-ChildItem -LiteralPath $repositoryRoot -Filter 'Pester.BeforeContainer.ps1' -File -Recurse
foreach ($setupFile in $setupFiles) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($setupFile.FullName, [ref]$null, [ref]$null)
    $topLevel = @(
        foreach ($statement in $ast.EndBlock.Statements) {
            $isSetupBlock = $false
            if ($statement -is [System.Management.Automation.Language.PipelineAst]) {
                $first = $statement.PipelineElements[0]
                $isSetupBlock = $first -is [System.Management.Automation.Language.CommandAst] -and
                    $first.GetCommandName() -in 'BeforeAll', 'AfterAll'
            }

            if (-not $isSetupBlock) {
                $statement
            }
        }
    )
    if ($topLevel.Count -gt 0) {
        "$($setupFile.FullName): $($topLevel.Count) top-level statement(s) run during discovery only"
    }
}

# 2. Timing assertions whose left side does not end with the closing brace of a script block.
$testFiles = Get-ChildItem -LiteralPath $repositoryRoot -Filter '*.Tests.ps1' -File -Recurse
$testFiles |
    Select-String -Pattern '[^}\s]\s*\|\s*Should-Be(Faster|Slower)Than' |
    Select-Object -Property Path, LineNumber, Line
```

Review each line that the script reports. In step 1, a statement that only discovery needs, such
as the data for a `-ForEach`, is correct at the top level; everything else moves into `BeforeAll`.
In step 2, a `[timespan]` value on the left side is valid input, and the pattern does not find a
pipeline that breaks the line after the pipe character.

To see which setup files each test file received, read `BeforeContainerFile` from the result
object; to fail on configuration keys that match no option, use `GetUnknownKeys()`. Both are in
the guides that the table in [New in 6.2](#new-in-62) names.
