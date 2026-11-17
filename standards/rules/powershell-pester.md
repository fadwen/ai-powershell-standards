# PowerShell testing with Pester

These rules apply to test files (`*.Tests.ps1`) and to the helper scripts in a `Tests` folder. They
target Pester 6.2.0, which runs on PowerShell 7 and Windows PowerShell 5.1. Longer guides for
specific topics are listed at the end.

## Rules

### Files

- **TST-01** A test file is named after the file it tests, `<FileName>.Tests.ps1`, and starts with
  `#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }`.
- **TST-02** Every test file is self-contained. It loads the code under test in its own top-level
  `BeforeAll`, and builds the data for `-ForEach` in `BeforeDiscovery`.
- **TST-03** Build paths from `$PSScriptRoot`. Files that a test creates go in `$TestDrive`.
- **TST-04** Tag every `Describe` block. Use consistent tags: the test type, such as `Unit` or
  `Integration`, and a second tag for the category within it, as in `-Tag 'Unit', 'Public'`. `None`
  is reserved by Pester and MUST NOT be used as a tag.
- **TST-05** Import a module under test only when it is not already loaded, and do not remove it
  afterwards. Only the module's contract test imports it with `-Force`.
- **TST-06** The tests of a function SHOULD have the standard structure: one `Describe` named after
  the function, with the contexts `Parameter Validation`, `Core Functionality`, `Error Handling`,
  and `Performance Requirements`.
- **TST-07** Test code and test output MUST be ASCII: no emoji in a test name, a `-Because` reason,
  or anything else that a test writes (STY-06).

### Assertions

- **TST-10** In a new test file use the Pester 6 assertions (`Should-Be`, `Should-Throw`). In an
  existing file keep the style it already uses. The two styles MUST NOT be mixed in one file.
- **TST-11** Every `It` block MUST contain at least one assertion that fails when the behaviour is
  wrong. Asserting only that a result is not null is not enough when a specific value is known.
- **TST-12** Assert the number of results before reading one by index, and use `Should-All` instead of
  assertions inside a `foreach` loop, so that an empty result cannot pass.
- **TST-13** Assert a type with `Should-HaveType`, not by comparing `.GetType().Name` with a string.
  For a custom object give its type name: `Should-HaveType '<TypeName>'`.
  `Should-HaveType ([PSCustomObject])` MUST NOT be used; it passes for any value.
- **TST-14** `Should-BeCollection` does not check order in Pester 6.2.0. To assert order, assert the
  count and then the element at each index.
- **TST-15** Assert an expected failure with `Should-Throw`, giving the exception type or the error ID
  where the code defines one. A message pattern needs wildcards: `-ExceptionMessage '*not found*'`.
- **TST-16** There is no `Should-NotThrow`. To assert that a command does not fail, call it with
  `-ErrorAction Stop`; any error then fails the test. Without it, a non-terminating error does not.
- **TST-17** Assert a non-terminating error by calling the command with `-ErrorAction Continue`,
  merging the error stream (`2>&1`), and counting the `ErrorRecord` objects.

### Mocks

- **TST-20** Mock only what crosses a boundary: network, file system, clock, other modules. The
  function under test MUST NOT be mocked, and a helper in the same module is mocked only when the
  helper is itself the boundary. A unit test file for a module also mocks `Write-Verbose` and
  `Write-Information` at module level.
- **TST-21** A mock for a command that a module calls MUST name the module, with `Mock -ModuleName`
  or by being declared inside `InModuleScope`. Run assertions against private functions and module
  classes inside `InModuleScope`.
- **TST-22** Assert calls with `Should-Invoke -Times <n> -Exactly`. `Assert-MockCalled` was removed in
  Pester 6.
- **TST-23** Define a mock that setup code depends on in an enclosing `BeforeAll`, and assert a call
  that was made in `BeforeAll` with `Should-Invoke -Scope Context`.
- **TST-24** Keep mocks isolated between tests: each `Context` declares the mocks that its tests
  call in its own `BeforeEach`. When two groups of mocks serve different tests, use separate
  `Context` blocks rather than several `BeforeEach` blocks in one.

### Test data

- **TST-30** Pass cases with `-ForEach` as hashtables. The list MUST NOT be empty or `$null`, and a key
  MUST NOT have the name of an automatic variable such as `Input` or `Args`.
- **TST-31** Tests MUST NOT depend on each other, on execution order, on the real network, or on the
  current time. Mock `Get-Date` when time matters, and restore anything the test changes.

### Coverage and CI

- **TST-40** Tests cover at least 80% of shipped code, as Pester's `CoveragePercent` reports it, and
  CI fails below that.
- **TST-41** Cover the contract, not only the lines: each parameter set, each documented output, each
  validation failure, each error path, and both outcomes of a `Test-` function.
- **TST-42** CI fails when the Pester result is not `Passed` or when no tests ran. Checking
  `FailedCount` alone misses a failed `BeforeAll` or `AfterAll` and a file that failed discovery.
- **TST-43** Unit tests are mandatory. Integration tests are required for code that has external
  dependencies, performance tests for a function that processes more than 100 items, and security
  tests for credential handling and input validation. Performance tests validate timing and memory
  use; security tests cover input sanitization and credential handling.
- **TST-44** For every parameter that accepts pipeline input, test both the piped call and the call
  by parameter, piping what the real upstream command emits.
- **TST-45** Every usage example in the README and in help has a test that runs it as written.
- **TST-46** CI runs the unit tests with `Run.Shuffle` enabled and puts the seed in the failure
  message.
- **TST-47** The unit tests run in less than 30 seconds in total, and the integration tests in less
  than 5 minutes.

## Notes and examples

### A complete test file

The function under test is the template in the core instructions.

<!-- include: standards/examples/Get-ConfigValue.Tests.ps1 -->

This file passes on Pester 6.2.0 under PowerShell 7.6 and Windows PowerShell 5.1.

### Loading the code under test (TST-02, TST-03, TST-21)

For a standalone function file, dot-source it as the file above does. For a module, import the
manifest and name the module in mocks:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    if (-not (Get-Module -Name ModuleName)) {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ModuleName.psd1')
    }
}

Describe 'Get-Thing' -Tag 'Unit', 'Public' {
    It 'Asks the service once for each name' {
        Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith {
            [PSCustomObject]@{ name = 'alpha'; state = 'ready' }
        }

        $result = Get-Thing -Name 'alpha'

        $result.State | Should-Be 'ready'
        Should-Invoke -CommandName Invoke-RestMethod -ModuleName ModuleName -Times 1 -Exactly
    }
}
```

A mock declared without `-ModuleName` replaces the command only for calls made from the test file. A
call made inside the module still reaches the real command. The exception is a mock declared inside
`InModuleScope`, which applies inside that module. `InModuleScope` is also how a test reaches a
class that the module defines; a test file that imports the module does not see the type.

A mock of a native executable reports its exit code with `$global:LASTEXITCODE = 3`. An assignment
to `$LASTEXITCODE` without the scope creates a local variable that the code under test never reads.

**TST-05.** Self-contained does not mean imported again. `Import-Module -Force` in every `BeforeAll`
and `Remove-Module` in every `AfterAll` reloads the module once for each file; one suite of 111 files
spent 21 seconds of an 80-second run doing only that. Measured on one module, `Import-Module -Force`
cost about 190 ms warm and 800 ms cold, and importing a module that is already loaded cost about
9 ms. The contract test, which asserts what a newly imported module looks like, is the one file
that passes `-Force`. Two consequences follow. State that one file leaves in module scope is
visible to the next, which is what the shuffled run in TST-46 exists to catch. And an interactive
session keeps the code it loaded, so after editing the module, import it once with `-Force` or run
the tests in a new process, as CI does.

**TST-23.** A `BeforeAll` in a `Context` runs before any `BeforeEach`, so a mock defined in the
parent's `BeforeEach` is not active while it runs, and the command it calls runs for real.
`Should-Invoke` counts only the calls made inside the current `It` unless a scope is given. Both
were measured on Pester 6.2.0. Keep `BeforeEach` for mocks that only the tests themselves call
(TST-24).

```powershell
Describe 'Get-ServerHealth' -Tag 'Unit', 'Public' {
    BeforeAll {
        Mock -CommandName Get-CimInstance -ModuleName ModuleName -MockWith {
            [PSCustomObject]@{ FreePhysicalMemory = 4GB }
        }
    }

    Context 'When one server is queried for the whole context' {
        BeforeAll {
            $health = Get-ServerHealth -ComputerName 'server01.example.com'
        }

        It 'Queries the server once' {
            $health | Should-NotBeNull
            Should-Invoke -CommandName Get-CimInstance -ModuleName ModuleName -Times 1 -Exactly -Scope Context
        }
    }
}
```

`Split-Path` and a two-argument `Join-Path` also work on Windows PowerShell 5.1, and so does a path
written as one string, `"$PSScriptRoot/../../ModuleName.psd1"`. `Join-Path` with several child paths
fails there.

### Assertions that cannot pass by accident (TST-11 to TST-17)

Each statement was verified on Pester 6.2.0.

| Assertion | Behaviour |
| --- | --- |
| `5 \| Should-HaveType ([PSCustomObject])` | Passes. Every piped value is wrapped, so this proves nothing. |
| `$widget \| Should-HaveType 'Contoso.Widget'` | Passes only when that is the object's type name. |
| `$widget.PSTypeName \| Should-Be 'Contoso.Widget'` | Always fails. `PSTypeName` is not a property. |
| `1, 2, 3 \| Should-BeCollection @(3, 2, 1)` | Passes. Order is not checked. |
| `1, 2, 3 \| Should-BeCollection -Count 3` | Passes. Use this before indexing. |
| `@() \| Should-All { $_ -gt 0 }` | Fails. An empty input cannot pass. |
| `@() \| Should-NotBeNull` | Fails. |
| `{ throw 'a b c' } \| Should-Throw -ExceptionMessage 'b'` | Fails. The pattern must match the whole message. |
| `{ throw 'a b c' } \| Should-Throw -ExceptionMessage '*b*'` | Passes. |

Pin the Pester version in CI. The ordering behaviour of `Should-BeCollection` is changing in Pester's
development branch, so an unpinned install can change what a test means.

For a typed array, pass the value with `-Actual` so that the pipeline does not unroll it:

```powershell
Should-HaveType -Actual $result.Names -Expected ([string[]])
```

`-ErrorVariable` can hold more than one record for a single failure, so count records from the merged
stream as the complete test file does.

Pass `-ErrorAction Continue` on a call that is expected to write a non-terminating error. Without it
the outcome depends on `$ErrorActionPreference` in the session that runs the tests. GitHub Actions
sets that to `Stop` for `pwsh` steps, which turns the error into a terminating one, so the test fails
in CI and passes on a developer's computer.

`Should-Throw -ExceptionType` compares the outer exception. A failure inside a .NET method call
arrives wrapped in a `MethodInvocationException`, so assert that type, or assert the message or the
error ID instead.

`Should-Throw -FullyQualifiedErrorId` compares the whole ID with `-like`. The ID that a function gives
its `ErrorRecord` is followed by a comma and the command name, so write
`'ConfigValueNotFound,Get-ConfigValue'` or `'ConfigValueNotFound,*'`, not `'ConfigValueNotFound'`.

`Should-Throw` runs its script block with the error preference `Stop`, so a non-terminating error
from a compiled cmdlet, or from a function defined in the test file, counts as thrown. A function in
a module does not see that preference. Its non-terminating error counts only where the session
preference is `Stop`, so the same test passes in CI and fails on a developer's computer. To assert
that a module function fails when its caller asks it to stop, pass `-ErrorAction Stop` inside the
script block. With `-AllowNonTerminatingError`, only a terminating error passes.

### Pipeline input and documented examples (TST-44, TST-45)

```powershell
It 'Gives the same summary for piped input and for an array argument' {
    $lengths = 10, 20, 30

    $piped = @($lengths | Get-SizeSummary)
    $byParameter = @(Get-SizeSummary -Length $lengths)

    $piped | Should-BeCollection -Count 1
    $piped[0].Total | Should-Be $byParameter[0].Total
}
```

The call by parameter passes whether or not the function collects its input (FUN-25). Only the piped
call proves that it does. A usage example in the README or in help is an untested claim until a test
runs it as written.

### Test data (TST-30)

```powershell
BeforeDiscovery {
    $cases = @(
        @{ Text = 'alpha'; Expected = 'ALPHA' }
        @{ Text = 'beta'; Expected = 'BETA' }
    )
}

Describe 'ConvertTo-UpperText' -Tag 'Unit', 'Public' {
    It 'Converts <Text> to <Expected>' -ForEach $cases {
        ConvertTo-UpperText -Text $Text | Should-Be $Expected
    }
}
```

Each key becomes a variable inside the `It` block. A `-ForEach` value that is empty or `$null` fails
discovery in Pester 6.

### The CI gate (TST-40, TST-42)

```powershell
Import-Module -Name Pester -RequiredVersion 6.2.0

$configuration = New-PesterConfiguration
$configuration.Run.Path = './Tests'
$configuration.Run.PassThru = $true
$configuration.Run.Shuffle = $true
$configuration.CodeCoverage.Enabled = $true
$configuration.CodeCoverage.Path = './Public', './Private'
$configuration.CodeCoverage.CoveragePercentTarget = 80

$result = Invoke-Pester -Configuration $configuration

if ($null -eq $result -or $result.TotalCount -eq 0) {
    throw 'Pester ran no tests.'
}

if ($result.Result -ne 'Passed') {
    $counts = $result.FailedCount, $result.FailedBlocksCount, $result.FailedContainersCount
    $summary = 'Failed tests: {0}. Failed blocks: {1}. Failed files: {2}.' -f $counts
    $seed = $result.Configuration.Run.ShuffleSeed.Value
    throw "Pester result is '$($result.Result)'. $summary Replay with Run.ShuffleSeed = $seed."
}

$coverage = [math]::Round($result.CodeCoverage.CoveragePercent, 2)
$target = $result.CodeCoverage.CoveragePercentTarget
if ($coverage -lt $target) {
    foreach ($file in $result.CodeCoverage.CommandsMissed | Group-Object -Property File) {
        Write-Host "  $($file.Name): $($file.Count) uncovered command(s)"
    }
    throw "Code coverage is $coverage percent. The minimum is $target."
}
```

`CodeCoverage.CoveragePercentTarget` only sets the figure that Pester reports against. It does not
fail the run, so the script compares the percentage with it and lists the uncovered commands of
each file. When Pester 6.2.0 finds no test files it reports an error and returns nothing, which is
why the script tests for `$null` first.

`CoveragePercent` is the share of commands that ran, not of lines. A line that holds several
commands counts once for each of them.

Every entry of `CodeCoverage.Path` must point at something that exists. Measured on Pester 6.2.0:
with `'./Public/*.ps1', './Classes/*.ps1'` and no `Classes` folder, Pester analysed 0 commands in 0
files and reported 0 percent, and the result was still `Passed`. A project without a coverage gate
would not notice.

### Pester 6 specifics

- A second `BeforeAll`, `BeforeEach`, `AfterAll`, or `AfterEach` in one block is allowed from 6.2.
  Pester 6.1 reports it as an error. Setup blocks run in the order they are written and teardown
  blocks in reverse, so group setup by what it sets up rather than merging unrelated work into one
  block.
- `Run.Parallel`, `Mock.Global`, and shared setup in `Pester.BeforeContainer.ps1` files are marked
  experimental in 6.2.0. Do not enable or add them unless the user asks; TST-02 keeps each test file
  self-contained. When the same setup is repeated in many test files, propose a
  `Pester.BeforeContainer.ps1` file to the user instead of adding one.
- The exception for `Run.Parallel` is the fast-feedback job of the CI workflow in
  `.github/instructions/pester-supporting-docs/cicd-integration.md`: it runs the unit tests in
  parallel without coverage, and a second, sequential job holds the coverage gate.
- `Run.Shuffle` is marked experimental too, and is the exception (TST-46). It randomizes the order
  of files, blocks, and tests, which exposes a test that passes only after another one has run. Leave
  `Run.ShuffleSeed` at `0` for a new seed on each run, and replay a failure by setting it to the seed
  in the message. A file opts out with a `#pester:no-shuffle` comment. In one suite it found three
  tests that passed only because an earlier test had created their folder.
- `Run.Parallel`, `Run.Shuffle`, and `Mock.Global` are set for a whole run, not for one file. The
  only per-file controls are the `#pester:no-parallel` and `#pester:no-shuffle` comments.
- Do not set `Should.DisableV5` while any test file still uses the `Should -Be` style.
- Removed in Pester 6: `Assert-MockCalled`, `Assert-VerifiableMock`, `It -Pending`, and
  `Set-ItResult -Pending`. Use `Should-Invoke`, and `It -Skip` or `Set-ItResult -Skipped`.

### Further reading

These guides are reference material. They are not loaded automatically; open the one that matches
the task.

| Topic | File |
| --- | --- |
| Assertion reference | `.github/instructions/pester-supporting-docs/assertion-guide.md` |
| Mocking patterns | `.github/instructions/pester-supporting-docs/mocking-patterns.md` |
| Test layout and tagging | `.github/instructions/pester-supporting-docs/test-structure-guide.md` |
| Test data | `.github/instructions/pester-supporting-docs/test-data-guide.md` |
| Configuration options | `.github/instructions/pester-supporting-docs/pester-configuration.md` |
| Running tests | `.github/instructions/pester-supporting-docs/test-execution.md` |
| CI integration | `.github/instructions/pester-supporting-docs/cicd-integration.md` |
| Custom assertions | `.github/instructions/pester-supporting-docs/custom-assertions.md` |
| Migrating from Pester 5 | `.github/instructions/pester-supporting-docs/v6-migration.md` |
| Unit, integration, performance, and security templates | `.github/instructions/pester-supporting-docs/unit-test-template.md` and the three files beside it |
