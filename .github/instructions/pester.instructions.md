---
applyTo: "**/Tests/**/*.ps1,**/*.Tests.ps1"
description: 'Creates comprehensive Pester 6 test suites for PowerShell code with enterprise testing standards'
---

# PowerShell Pester Testing - Core Instructions

Generate enterprise-grade Pester test suites following these core requirements.

**Target version: Pester 6.2+** on Windows PowerShell 5.1 or PowerShell 7.4+. Pester 6 removed
support for PowerShell 3, 4, 6, and unsupported 7.x. 6.1 and 6.2 are additive for test files - no
test file needs to change to move between 6.0, 6.1, and 6.2. The one thing 6.2 changes underneath a
suite is `Pester.BeforeContainer.ps1`: top-level code in it now runs at discovery only, so run-time
setup there must sit in a `BeforeAll` - see
[Moving From 6.1 to 6.2](./pester-supporting-docs/v6-migration.md#moving-from-61-to-62).

**NOTE**: Do not use Unicode emojis in any generated code, documentation, or test output. Use plain
text descriptions and standard ASCII characters only.

## Quick Reference

### Test Structure Requirements

- **Directory Structure**: Follow [Test Structure Guide](./pester-supporting-docs/test-structure-guide.md)
- **Coverage Target**: Minimum 80% code coverage for production code
- **Test Types**: Unit (mandatory), Integration, Performance, Security
- **Quality Gates**: All tests pass, performance within limits, security validation
- **File Isolation**: Every test file must be self-contained - see below

### Core Test Patterns

Generate tests using these templates:

- **Unit Tests**: Use [Unit Test Template](./pester-supporting-docs/unit-test-template.md)
- **Integration Tests**: Use [Integration Test Template](./pester-supporting-docs/integration-test-template.md)
- **Performance Tests**: Use [Performance Test Template](./pester-supporting-docs/performance-test-template.md)
- **Security Tests**: Use [Security Test Template](./pester-supporting-docs/security-test-template.md)

### Assertions

- **Guide**: Use [Assertion Guide](./pester-supporting-docs/assertion-guide.md)
- **New test files**: prefer the Pester 6 `Should-*` assertions (dash, no space) - they are
  type-aware and produce far better failure messages.
- **Existing files**: keep the file's existing style. Do not mix `Should -Be` and `Should-Be`
  within a single file.
- **Do not** set `Should.DisableV5 = $true` until every test file in the repository is migrated.
- **Custom assertions**: the `Should-*` set is open for extension in 6.1 via `New-ShouldAssertion` -
  see [Custom Assertion Guide](./pester-supporting-docs/custom-assertions.md). Write one only when
  the same domain rule is asserted across several files and naming the offending value is the point.

### Migrating From Pester 5

Follow the [Pester 6 Migration Guide](./pester-supporting-docs/v6-migration.md). The three changes
that break existing suites outright:

1. `Assert-MockCalled` and `Assert-VerifiableMock` were **removed** - use `Should -Invoke` /
   `Should -InvokeVerifiable` (or `Should-Invoke` / `Should-NotInvoke`).
2. `-Focus` and `Set-ItResult -Pending` were **removed**.
3. A `-ForEach` / `-TestCases` that evaluates to `$null` or `@()` now **fails discovery**.

A second `BeforeAll` (or `BeforeEach`, `AfterAll`, `AfterEach`) in one block threw in 6.0 and 6.1.
6.2 allows it again, so it is no longer a migration item.

### Test Requirements Checklist

- [ ] **File Isolation**: File imports its own modules and does its own discovery-time setup
- [ ] **Parameter Validation**: Test all input validation scenarios
- [ ] **Error Handling**: Verify graceful error handling with meaningful messages
- [ ] **Mocking**: Mock all external dependencies appropriately
- [ ] **Performance**: Include timing and memory usage validation
- [ ] **Security**: Test input sanitization and credential handling
- [ ] **Pipeline Support**: For every `ValueFromPipeline` parameter, test both `$collection | Verb-Noun` and
  `-Parameter $collection`, piping the shape the real upstream command produces. A function that reduces
  its input to one result runs different code on each path
- [ ] **Documented Examples**: Every usage example in the README and in help has a test that runs it as written
- [ ] **Non-Empty Test Cases**: No `-ForEach`/`-TestCases` expression can yield `$null` or `@()`
- [ ] **Mock Scope**: A mock that a `BeforeAll` depends on is defined in an enclosing `BeforeAll`, and
  `Should-Invoke` for a call made in setup passes `-Scope Context`
- [ ] **One Import**: Only the module contract test imports with `-Force`; every other file imports only when
  the module is not already loaded, and none removes it afterwards

### Configuration & Execution

- **Configuration**: Use [Pester Configuration Guide](./pester-supporting-docs/pester-configuration.md)
- **Test Execution**: Use [Test Execution Guide](./pester-supporting-docs/test-execution.md)
- **CI/CD Integration**: Follow [CI/CD Integration Guide](./pester-supporting-docs/cicd-integration.md)

### Experimental Options

Three configuration options are experimental, off by default, and may change. Do not enable
`Run.Parallel` or `Mock.Global` in generated code unless asked. `Run.Shuffle` is the exception: turn
it on in CI with the seed printed, as
[Shuffled Test Order](./pester-supporting-docs/pester-configuration.md#shuffled-test-order-experimental)
describes, because it is what makes importing the module once per run safe. When a project enables
one, these are the consequences:

| Option | Effect | Note |
| --- | --- | --- |
| `Run.Parallel` | One test file per runspace | Requires file-based containers. Runs on PowerShell 7 and, from 6.2, on Windows PowerShell 5.1. Coverage works from 6.1 but is forced onto slower breakpoint mode |
| `Run.Shuffle` | Randomizes file, block, and test order | Fails tests that depend on declaration order. Prints a seed; `Run.ShuffleSeed` replays it. Opt a file out with `#pester:no-shuffle`. Recommended in CI: it found three tests in one suite that passed only because an earlier test had created their folder |
| `Mock.Global` | A mock applies to calls from any module in the runspace | `-ModuleName` becomes a resolution hint, not a scope. Does **not** reinstate fall-through - a `-ParameterFilter` guard still needs a default mock |

All three are per-run configuration, not per-file, apart from the `#pester:no-parallel` and
`#pester:no-shuffle` directives.

### Quality Standards

- **Execution Speed**: Unit tests <30s total, integration tests <5min
- **Test Isolation**: Tests must be independent and repeatable
- **Documentation**: Include troubleshooting references in `./Troubleshooting/` folder
- **Enterprise Standards**: Follow PowerShell community best practices

## Implementation Requirements

When generating Pester tests:

1. **Analyze Function**: Determine test types needed (Unit/Integration/Performance/Security)
2. **Apply Templates**: Use appropriate templates from supporting documentation
3. **Mock Dependencies**: Mock all external calls using the
   [Mocking Patterns Guide](./pester-supporting-docs/mocking-patterns.md)
4. **Validate Coverage**: Ensure 80%+ code coverage with meaningful assertions
5. **Test Data**: Use [Test Data Management Guide](./pester-supporting-docs/test-data-guide.md)
6. **Integration**: Configure for CI/CD pipeline execution

### Every Test File Must Be Self-Contained

Pester 6 discovers and runs **one file at a time**, interleaving discovery and execution, rather
than discovering every file up front. Discovery-time side effects therefore do not carry across
files, and under `Run.Parallel` each file is discovered in its own runspace.

Each test file must import the modules it needs and perform its own discovery-time setup:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    # Anything needed to BUILD the test tree (-ForEach data, helper commands)
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module "$PSScriptRoot/../../ModuleName.psd1"
    }
}

BeforeAll {
    # Anything needed to RUN the tests
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module "$PSScriptRoot/../../ModuleName.psd1"
    }
}
```

Self-contained does not mean re-imported. `Import-Module -Force` costs about 190 ms warm and 800 ms
cold; importing a module that is already loaded costs about 9 ms. One suite of 111 files that forced
the import in every `BeforeAll` and removed the module in every `AfterAll` spent 21 seconds of an
80-second run doing nothing else. Import only when the module is not loaded, and do not remove it
afterwards. Keep the forced import in exactly one file, the module contract test, which asserts what
a freshly imported module looks like.

The trade is that state one file leaves in module scope is visible to the next. That is what the
shuffled CI run exists to catch: a test that passes only after a fresh import, or only before another
file connected, fails there with a seed to replay. The other consequence is local: CI starts a fresh
process, but an interactive session that already holds the module keeps serving the code it loaded,
so after editing the module import it once with `-Force` before `Invoke-Pester`, or run the suite in
a fresh process the way CI does.

When several files share bootstrap, put it in a `Pester.BeforeContainer.ps1` rather than relying on
another file having run first. From 6.2 every such file from `Run.RepoRoot` down to the test file's
own folder applies, outermost first, so unit and integration tests can each carry their own setup.
The file follows the same rule as a test file: top-level code runs at **discovery** only, and
anything the tests need at run time goes in a `BeforeAll`:

```powershell
# Pester.BeforeContainer.ps1 - at the repository root, or in any folder under it
BeforeAll {
    Import-Module "$PSScriptRoot/Source/ModuleName.psd1" -Force
    . "$PSScriptRoot/Tests/TestHelpers/TestHelpers.ps1"
}
```

The `Run.BeforeContainer` option that also did this was **removed in 6.1**; the convention file is
the only mechanism. The chain starts at `Run.RepoRoot` - see
[Pester Configuration Guide](./pester-supporting-docs/pester-configuration.md).

### Quick Test Generation Pattern

```powershell
# Standard test structure for any function
Describe "Function-Name" -Tag "Unit", "Public" {
    Context "Parameter Validation" { <# Validation tests #> }
    Context "Core Functionality" { <# Main logic tests #> }
    Context "Error Handling" { <# Error scenarios #> }
    Context "Performance Requirements" { <# Performance tests #> }
}
```

From 6.2 a block may hold more than one `BeforeAll`, `BeforeEach`, `AfterAll`, or `AfterEach`.
Setups run in declaration order and teardowns in reverse, so group setup by what it sets up rather
than merging unrelated work into one block. 6.0 and 6.1 throw on the second one.

### Tagging

Tag every `Describe` block. `None` is a **reserved** filter value in Pester 6 meaning "tests with no
tags" - never use it as a literal tag. Verify tagging coverage with:

```powershell
Invoke-Pester -Path ./Tests -TagFilter 'None'   # a well-tagged suite RUNS zero tests
```

Read the **Passed** count, not the discovered count - `TotalCount` ignores the filter. Scripted
gates must count `$result.Tests | Where-Object ShouldRun`; see
[Test Structure Guide](./pester-supporting-docs/test-structure-guide.md).

### Testing Private Functions

A module built to these standards exports only what `FunctionsToExport` names, so private functions
are unreachable from a test file. Use `InModuleScope` to run assertions inside the module's scope,
where internal functions and classes are visible:

```powershell
It 'Returns a session for the target environment' {
    InModuleScope MyModule {
        $session = Connect-Service -Environment 'Test' -CorrelationId ([guid]::NewGuid())
        $session.Environment | Should-Be 'Test'
    }
}
```

`InModuleScope` is also how you mock a private function that a public one calls, and how you reach a
class defined in `Classes/`:

```powershell
InModuleScope MyModule {
    Mock Get-ServiceStatus { throw 'unreachable' }
    'A', 'B' | Get-Data -ErrorAction SilentlyContinue | Should-BeFalsy
}
```

Do not export a function purely to make it testable - that widens the public contract to serve the
tests. Reach into the module instead.

### Worked Examples

These are complete, passing implementations of the patterns above. Prefer matching them over
inventing a structure:

- [Module-Structure-Example/Tests](../../powershell-standards/Examples/Module-Structure-Example/Tests/) -
  module contract, class assertions, `InModuleScope` for two private functions, and a per-item
  failure path
- [Basic-Function.Tests.ps1](../../powershell-standards/Examples/Testing-Examples/Basic-Function.Tests.ps1) -
  CIM mocking, `-RemoveParameterType`, `-TestCases`, and mock scoping across contexts
- [Tools/Tests](https://github.com/fadwen/ai-powershell-standards/tree/main/Tools/Tests) - tests for the standards
  repository's own tooling, including fixture files written per test and error-path coverage. Not
  mirrored into consuming projects

### Documentation Integration

All test implementations must reference:

- **Troubleshooting**: Link to `./Troubleshooting/` folder documentation
- **Supporting Guides**: Reference detailed templates and patterns
- **Enterprise Standards**: Follow established PowerShell development practices

For detailed implementation guidance, templates, and examples, refer to the supporting documentation
files in the `pester-supporting-docs/` folder.
