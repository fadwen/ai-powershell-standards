# Unit Test Template

A unit test file for functions of a module, with the module's dependencies mocked. The rules it
follows are in the [Pester rules](../powershell-pester.instructions.md), which also contain a
complete test file for a standalone function. The file below passes on Pester 6.2.0 under
PowerShell 7.6 and Windows PowerShell 5.1.

## The Code Under Test

The template tests a module named `ModuleName`. The test file is in the `Tests` folder directly
under the module root.

- `Get-Thing -Name <string[]>` asks a web service for each name with `Invoke-RestMethod` and emits
  one `ModuleName.Thing` object for each answer. Names are validated with `ValidatePattern`. When the
  service fails for one name, the function writes a non-terminating error with the ID
  `ThingReadFailed` and continues.
- `Remove-Thing -Name <string[]>` sends a DELETE request for each name and supports `-WhatIf` and
  `-Confirm`.
- `Get-ThingUri` is a private function that builds the address of a request.

## The Test File

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ModuleName.psd1')
    }
}

BeforeAll {
    Mock -CommandName Write-Verbose -ModuleName ModuleName -MockWith { }
    Mock -CommandName Write-Information -ModuleName ModuleName -MockWith { }
}

Describe 'Get-Thing' -Tag 'Unit', 'Public' {
    BeforeEach {
        Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith {
            [PSCustomObject]@{ name = $Uri.Segments[-1]; state = 'ready' }
        }
    }

    Context 'Parameter Validation' {
        It 'Should declare Name as a mandatory string array' {
            Get-Command -Name Get-Thing |
                Should-HaveParameter -ParameterName Name -Type ([string[]]) -Mandatory
        }

        It 'Should reject invalid input: <Description>' -ForEach @(
            @{ Description = 'null'; InvalidInput = $null; ExpectedError = '*argument is null*' }
            @{ Description = 'empty'; InvalidInput = ''; ExpectedError = '*does not match*' }
            @{ Description = 'a path separator'; InvalidInput = '../alpha'; ExpectedError = '*does not match*' }
        ) {
            $expectedFailure = @{
                ExceptionMessage = $ExpectedError
                FullyQualifiedErrorId = 'ParameterArgumentValidationError*'
            }
            { Get-Thing -Name $InvalidInput } | Should-Throw @expectedFailure

            Should-NotInvoke -CommandName Invoke-RestMethod -ModuleName ModuleName
        }

        It 'Should emit one thing for each name from the pipeline, in order' {
            $result = @('beta', 'alpha' | Get-Thing)

            $result | Should-BeCollection -Count 2
            $result[0].Name | Should-Be 'beta'
            $result[1].Name | Should-Be 'alpha'
        }
    }

    Context 'Core Functionality' {
        It 'Should return a thing with the name and state that the service reported' {
            $result = Get-Thing -Name 'alpha'

            $result | Should-HaveType 'ModuleName.Thing'
            $result.Name | Should-Be 'alpha'
            $result.State | Should-Be 'ready'
        }

        It 'Should send one GET request for each name' {
            $null = Get-Thing -Name 'alpha', 'beta'

            $alphaRequest = @{
                CommandName = 'Invoke-RestMethod'
                ModuleName = 'ModuleName'
                ParameterFilter = { $Method -eq 'Get' -and $Uri.AbsolutePath -eq '/api/things/alpha' }
            }
            Should-Invoke -CommandName Invoke-RestMethod -ModuleName ModuleName -Times 2 -Exactly
            Should-Invoke @alphaRequest -Times 1 -Exactly
        }
    }

    Context 'Error Handling' {
        BeforeEach {
            $brokenRequest = @{
                CommandName = 'Invoke-RestMethod'
                ModuleName = 'ModuleName'
                ParameterFilter = { $Uri.AbsolutePath -eq '/api/things/broken' }
            }
            Mock @brokenRequest -MockWith {
                throw [System.TimeoutException]::new('The service did not answer.')
            }
        }

        It 'Should write one non-terminating error and still return the other things' {
            $output = Get-Thing -Name 'broken', 'alpha' -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $things = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].FullyQualifiedErrorId | Should-Be 'ThingReadFailed,Get-Thing'
            $errors[0].Exception.InnerException | Should-HaveType ([System.TimeoutException])
            $things | Should-BeCollection -Count 1
            $things[0].Name | Should-Be 'alpha'
        }

        It 'Should continue processing other items when one fails' {
            $result = Get-Thing -Name 'alpha', 'broken', 'beta' -ErrorAction SilentlyContinue

            @($result | Where-Object { $_.State -eq 'ready' }) | Should-BeCollection -Count 2
        }

        It 'Should stop at the failure when the caller passes -ErrorAction Stop' {
            { Get-Thing -Name 'broken', 'alpha' -ErrorAction Stop } |
                Should-Throw -FullyQualifiedErrorId 'ThingReadFailed,Get-Thing'
        }
    }

    Context 'Performance Requirements' {
        It 'Should complete within acceptable time limits' {
            { Get-Thing -Name 'alpha' } | Should-BeFasterThan '5s'
        }

        It 'Should scale linearly with input size' {
            $smallInput = 1..10 | ForEach-Object { "thing$_" }
            $largeInput = 1..100 | ForEach-Object { "thing$_" }

            $smallRuns = foreach ($run in 1..3) {
                (Measure-Command { $null = Get-Thing -Name $smallInput }).TotalMilliseconds
            }
            $largeRuns = foreach ($run in 1..3) {
                (Measure-Command { $null = Get-Thing -Name $largeInput }).TotalMilliseconds
            }
            $smallBest = ($smallRuns | Measure-Object -Minimum).Minimum
            $largeBest = ($largeRuns | Measure-Object -Minimum).Minimum

            # Ten times the input should not take more than 30 times as long (allows for overhead).
            $scalingRatio = $largeBest / [math]::Max($smallBest, 1)
            $scalingRatio | Should-BeLessThan 30
        }
    }
}

Describe 'Remove-Thing' -Tag 'Unit', 'Public' {
    BeforeEach {
        Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith { }
    }

    It 'Should not call the service when -WhatIf is passed' {
        Remove-Thing -Name 'alpha' -WhatIf

        Should-NotInvoke -CommandName Invoke-RestMethod -ModuleName ModuleName
    }

    It 'Should send one DELETE request when the caller confirms' {
        Remove-Thing -Name 'alpha' -Confirm:$false

        $deleteRequest = @{
            CommandName = 'Invoke-RestMethod'
            ModuleName = 'ModuleName'
            ParameterFilter = { $Method -eq 'Delete' -and $Uri.AbsolutePath -eq '/api/things/alpha' }
        }
        Should-Invoke @deleteRequest -Times 1 -Exactly
    }
}

Describe 'Get-ThingUri' -Tag 'Unit', 'Private' {
    It 'Should append the path of the thing to the service address' {
        InModuleScope -ModuleName ModuleName -ScriptBlock {
            $result = Get-ThingUri -ServiceUri 'https://things.example.test/' -Name 'alpha'

            $result.AbsoluteUri | Should-Be 'https://things.example.test/api/things/alpha'
        }
    }
}
```

## What The Template Shows

- **Structure.** The `Describe` block of `Get-Thing` has the standard structure (TST-06): the
  contexts `Parameter Validation`, `Core Functionality`, `Error Handling`, and
  `Performance Requirements`. Each `Describe` block carries the test type and a second tag
  (TST-04), and the test names begin with `Should`. The two short `Describe` blocks test one
  behaviour each and have no contexts.
- **Loading.** The first top-level `BeforeAll` imports the module from a path built on
  `$PSScriptRoot` (TST-02, TST-03). With the test file one folder deeper, add one more `Split-Path`.
  The second one mocks `Write-Verbose` and `Write-Information` at module level (TST-20).
- **Mocks.** Every mock and every `Should-Invoke` names the module (TST-21). The `BeforeEach` of the
  `Describe` block declares the answer for the normal case before every test, so that no context
  reaches the network, and the `Error Handling` context adds a filtered mock for one address in its
  own `BeforeEach` (TST-24). `Should-Invoke` counts only the calls of the current `It` block. The
  [mocking guide](./mocking-patterns.md) explains scopes and filters.
- **Validation failures.** Each case carries the message pattern that it expects. The error ID
  pattern `ParameterArgumentValidationError*` identifies a rejected argument without depending on
  message text, and `Should-NotInvoke` shows that the service was not reached.
- **Order.** The pipeline test asserts the count and then each index, because `Should-BeCollection`
  does not compare order (TST-14).
- **Both pipeline paths.** Test a parameter that accepts pipeline input with a piped call and with a
  call by parameter (TST-44). A function that reduces its input to one result runs different code
  on each path, and only the piped test proves that it collects first (FUN-25).
- **Per-item failures.** The error stream is merged into the output and the records are counted
  (TST-17). `Should-Throw` would not see this error, because a module function ignores the error
  preference that `Should-Throw` sets; with `-ErrorAction Stop` in the call it does. The test
  between those two passes `-ErrorAction SilentlyContinue` and counts only the things that were
  still returned.
- **Performance.** `Should-BeFasterThan` sets the time limit. The scaling test compares 10 names
  with 100 and takes the best of three runs of each: measured once each, the ratio for the same
  code varied between 2 and 15. The [performance template](./performance-test-template.md)
  describes stable measurements.
- **State changes.** `-WhatIf` must not reach the service, and `-Confirm:$false` lets the test run a
  function whose `ConfirmImpact` is `High` without a prompt.
- **Private functions.** `InModuleScope` is used only to call `Get-ThingUri` directly (TST-21).

What to cover is set by TST-41: each parameter set, each documented output, each validation
failure, and each error path. The four contexts divide it:

| Context | What it tests |
| --- | --- |
| `Parameter Validation` | Valid input variations, invalid input rejection, pipeline input both piped and by parameter, parameter metadata (`Should-HaveParameter`), mandatory parameters |
| `Core Functionality` | Expected return values and types, object structure, interaction with external dependencies, processing of several items, business rules |
| `Error Handling` | External dependency failures, invalid state, meaningful error messages, graceful degradation and recovery, downstream calls that are not made after a failure (`Should-NotInvoke`) |
| `Performance Requirements` | Execution time limits (`Should-BeFasterThan`), scaling, memory usage, resource cleanup, bottlenecks |

Unit tests are one of the test types that TST-43 names. The
[integration](./integration-test-template.md), [performance](./performance-test-template.md), and
[security](./security-test-template.md) templates show the others.

## Authoring Details

The [assertion guide](./assertion-guide.md) describes each assertion used above.

### Setup Blocks

From 6.2 a block may declare several `BeforeAll`, `BeforeEach`, `AfterAll`, or `AfterEach` blocks.
Setup blocks run in the order they are written and teardown blocks in reverse, so group setup by
what it sets up instead of merging it into a single block. The template has one `BeforeAll` that
imports the module and another that declares the module-level mocks. Pester 6.0 and 6.1 stop at the
second block, so a suite that must still run on those versions keeps one of each kind in a block.

### Test Cases

Each key of a `-ForEach` hashtable is a variable in the `It` block, so the block needs no `param()`
block. Do not add one, and do not name a key after an automatic variable (TST-30). With a key named
`Input`, the block reads an empty value in place of the test case:

```powershell
# Non-compliant: Input is an automatic variable, and the param() block is not needed
It 'Converts <Input>' -ForEach @(@{ Input = 'alpha' }) {
    param($Input)
    ConvertTo-UpperText -Text $Input | Should-Be 'ALPHA'
}

# Compliant
It 'Converts <Text>' -ForEach @(@{ Text = 'alpha' }) {
    ConvertTo-UpperText -Text $Text | Should-Be 'ALPHA'
}
```

A `-ForEach` value that is empty or `$null` stops discovery of the file with
`Value can not be null or empty array`. That is usually a real defect: the code that builds the
cases returned nothing. Where an empty list is legitimate, say so on the block:

```powershell
It 'Reaches <Endpoint>' -ForEach $configuredEndpoints -AllowNullOrEmptyForEach {
    Test-Endpoint -Uri $Endpoint | Should-BeTrue
}
```

### Test Names

Only text inside `<` and `>` is expanded in a test name. Everything else is literal, including `$`
and quotes.

| Name | Displayed as |
| --- | --- |
| `'Returns <Expected> for <Text>'` | The values of the keys `Expected` and `Text` |
| `'Totals <($First + $Second)>'` | The value of the expression |
| ``'Handles a literal `<placeholder>'`` | `Handles a literal <placeholder>` |
| `'Uses <Missing>'`, with no such key | `Uses $null` |
