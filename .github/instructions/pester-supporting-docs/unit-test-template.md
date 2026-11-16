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

Describe 'Get-Thing' -Tag 'Unit' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith {
            [PSCustomObject]@{ name = $Uri.Segments[-1]; state = 'ready' }
        }
    }

    Context 'Parameters' {
        It 'Declares Name as a mandatory string array' {
            Get-Command -Name Get-Thing |
                Should-HaveParameter -ParameterName Name -Type ([string[]]) -Mandatory
        }

        It 'Rejects a name <Description> before calling the service' -ForEach @(
            @{ Description = 'with a path separator'; BadName = '../alpha' }
            @{ Description = 'with a query string'; BadName = 'alpha?all=true' }
            @{ Description = 'with a space'; BadName = 'alpha beta' }
        ) {
            { Get-Thing -Name $BadName } |
                Should-Throw -FullyQualifiedErrorId 'ParameterArgumentValidationError,Get-Thing'

            Should-NotInvoke -CommandName Invoke-RestMethod -ModuleName ModuleName
        }
    }

    Context 'When the service answers' {
        It 'Returns a thing with the name and state that the service reported' {
            $result = Get-Thing -Name 'alpha'

            $result | Should-HaveType 'ModuleName.Thing'
            $result.Name | Should-Be 'alpha'
            $result.State | Should-Be 'ready'
        }

        It 'Emits one thing for each name from the pipeline, in order' {
            $result = @('beta', 'alpha' | Get-Thing)

            $result | Should-BeCollection -Count 2
            $result[0].Name | Should-Be 'beta'
            $result[1].Name | Should-Be 'alpha'
        }

        It 'Sends one GET request for each name' {
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

    Context 'When the service fails for one name' {
        BeforeAll {
            $brokenRequest = @{
                CommandName = 'Invoke-RestMethod'
                ModuleName = 'ModuleName'
                ParameterFilter = { $Uri.AbsolutePath -eq '/api/things/broken' }
            }
            Mock @brokenRequest -MockWith {
                throw [System.TimeoutException]::new('The service did not answer.')
            }
        }

        It 'Writes one non-terminating error and still returns the other things' {
            $output = Get-Thing -Name 'broken', 'alpha' 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $things = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].FullyQualifiedErrorId | Should-Be 'ThingReadFailed,Get-Thing'
            $errors[0].Exception.InnerException | Should-HaveType ([System.TimeoutException])
            $things | Should-BeCollection -Count 1
            $things[0].Name | Should-Be 'alpha'
        }

        It 'Stops at the failure when the caller passes -ErrorAction Stop' {
            { Get-Thing -Name 'broken', 'alpha' -ErrorAction Stop } |
                Should-Throw -FullyQualifiedErrorId 'ThingReadFailed,Get-Thing'
        }
    }
}

Describe 'Remove-Thing' -Tag 'Unit' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith { }
    }

    It 'Does not call the service when -WhatIf is passed' {
        Remove-Thing -Name 'alpha' -WhatIf

        Should-NotInvoke -CommandName Invoke-RestMethod -ModuleName ModuleName
    }

    It 'Sends one DELETE request when the caller confirms' {
        Remove-Thing -Name 'alpha' -Confirm:$false

        $deleteRequest = @{
            CommandName = 'Invoke-RestMethod'
            ModuleName = 'ModuleName'
            ParameterFilter = { $Method -eq 'Delete' -and $Uri.AbsolutePath -eq '/api/things/alpha' }
        }
        Should-Invoke @deleteRequest -Times 1 -Exactly
    }
}

Describe 'Get-ThingUri' -Tag 'Unit' {
    It 'Appends the path of the thing to the service address' {
        InModuleScope -ModuleName ModuleName -ScriptBlock {
            $result = Get-ThingUri -ServiceUri 'https://things.example.test/' -Name 'alpha'

            $result.AbsoluteUri | Should-Be 'https://things.example.test/api/things/alpha'
        }
    }
}
```

## What The Template Shows

- **Loading.** The top-level `BeforeAll` imports the module from a path built on `$PSScriptRoot`
  (TST-02, TST-03). With the test file one folder deeper, add one more `Split-Path`.
- **Mocks.** Every mock and every `Should-Invoke` names the module (TST-21). The `Describe` block
  declares the answer for the normal case once, and the failure context adds a filtered mock for one
  address. `Should-Invoke` counts only the calls of the current `It` block. The
  [mocking guide](./mocking-patterns.md) explains scopes and filters.
- **Validation failures.** The error ID `ParameterArgumentValidationError,Get-Thing` identifies a
  rejected argument without depending on message text, and `Should-NotInvoke` shows that the service
  was not reached.
- **Order.** The pipeline test asserts the count and then each index, because `Should-BeCollection`
  does not compare order (TST-14).
- **Both pipeline paths.** Test a parameter that accepts pipeline input with a piped call and with a
  call by parameter (TST-44). A function that reduces its input to one result runs different code
  on each path, and only the piped test proves that it collects first (FUN-25).
- **Per-item failures.** The error stream is merged into the output and the records are counted
  (TST-17). `Should-Throw` would not see this error, because a module function ignores the error
  preference that `Should-Throw` sets; with `-ErrorAction Stop` in the call it does.
- **State changes.** `-WhatIf` must not reach the service, and `-Confirm:$false` lets the test run a
  function whose `ConfirmImpact` is `High` without a prompt.
- **Private functions.** `InModuleScope` is used only to call `Get-ThingUri` directly (TST-21).

What to cover is set by TST-41: each parameter set, each documented output, each validation
failure, and each error path. Add timing or security tests only where the function has such a
requirement (TST-43); the [performance](./performance-test-template.md) and
[security](./security-test-template.md) templates show how.

## Authoring Details

The [assertion guide](./assertion-guide.md) describes each assertion used above.

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
