# Mocking Patterns Guide

Patterns for `Mock`, `Should-Invoke`, and `InModuleScope`. The rules are TST-20 to TST-22 in the
[Pester rules](../powershell-pester.instructions.md); this guide holds the detail behind them. Every
statement about behaviour was checked by running it on Pester 6.2.0.

The examples use the module from the Pester rules: `ModuleName`, whose public function `Get-Thing`
calls `Invoke-RestMethod`.

## What Changed In Pester 6

### Assert-MockCalled And Assert-VerifiableMock Were Removed

| Removed | Classic replacement | Pester 6 replacement |
| --- | --- | --- |
| `Assert-MockCalled Cmd -Times 1 -Exactly` | `Should -Invoke Cmd -Times 1 -Exactly` | `Should-Invoke Cmd -Times 1 -Exactly` |
| `Assert-MockCalled Cmd -Times 0` | `Should -Not -Invoke Cmd` | `Should-NotInvoke Cmd` |
| `Assert-VerifiableMock` | `Should -InvokeVerifiable` | `Should-Invoke -Verifiable` |

The parameters are the same: `-Times`, `-Exactly`, `-ParameterFilter`, `-ExclusiveFilter`,
`-ModuleName`, `-Scope`.

### A Call That Matches No Mock Is An Error

In Pester 5, a call that matched none of a command's parameter filters ran the real command. In
Pester 6 it fails the test:

```text
No mock for command 'Get-Content' matched the call: none of the parameter filters matched, and there
is no default mock to fall back to. Add a default mock (e.g. `Mock Get-Content { ... }`) or adjust an
existing -ParameterFilter.
```

The message goes on to list each filter and the parameters of the call. Declare a mock without a
filter for the calls that the filtered mocks do not cover. The order of the declarations does not
matter:

```powershell
Mock -CommandName Get-Content -ModuleName ModuleName -MockWith { 'default content' }
Mock -CommandName Get-Content -ModuleName ModuleName -ParameterFilter {
    $LiteralPath -like '*special*'
} -MockWith { 'special content' }
```

### A Failed Assertion Prints The Calls

When `Should-Invoke` or `Should-NotInvoke` fails, the message lists every recorded call. `[*]` marks
a call that matched the `-ParameterFilter`:

```text
Expected Get-ServiceStatus in module ModuleName to be called 2 times exactly, but was called 1 time
Performed invocations:
  [*] Get-ServiceStatus -Name 'alice' from C:\Repo\Tests\Get-Data.Tests.ps1:65
  [ ] Get-ServiceStatus -Name 'bob' from C:\Repo\Tests\Get-Data.Tests.ps1:65
```

### A Parameter Filter Can Use An Alias

A filter may name a parameter by one of its aliases. A call to `Get-Content -LiteralPath` matches
`-ParameterFilter { $PSPath -like '*settings*' }`.

## Where A Mock Applies

A mock replaces a command for one caller (TST-21):

| Declaration | Calls that reach the mock |
| --- | --- |
| `Mock -CommandName Get-Content` | Calls made from the test file. A call inside a module runs the real command. |
| `Mock -CommandName Get-Content -ModuleName ModuleName` | Calls made inside `ModuleName`, by public and private functions. |

- `-ModuleName` also works when the command is a private function of that module. Without it, Pester
  reports `Could not find Command`.
- A second module that calls the same command needs its own mock with its own `-ModuleName`.
- Give `Should-Invoke` and `Should-NotInvoke` the same `-ModuleName` as the mock.

Use `InModuleScope` to call a private function directly. The script block runs inside the module,
where the test's variables do not exist, so pass values in with `-Parameters`:

```powershell
It 'Appends the path of the thing to the service address' {
    $expected = 'https://things.example.test/api/things/alpha'

    InModuleScope -ModuleName ModuleName -Parameters @{ expected = $expected } -ScriptBlock {
        $result = Get-ThingUri -ServiceUri 'https://things.example.test/' -Name 'alpha'

        $result.AbsoluteUri | Should-Be $expected
    }
}
```

### How Long A Mock Lasts

A mock lasts until the block that declared it ends, and Pester then restores the command. No cleanup
code is needed.

| Declared in | Applies to |
| --- | --- |
| An `It` block | That test. It takes precedence over a mock of the same command from an outer block. |
| `BeforeEach` | Each test of the block, declared again before every test. |
| `BeforeAll` of a `Describe` or `Context` | Every test in that block. |
| `BeforeAll` at the top of the file | Every test in the file. |

`Should-Invoke` counts the calls made in the current `It` block, wherever the mock was declared, so
one test does not see the calls of another. `-Scope Describe` widens the count to the enclosing
`Describe` block.

A mock never reaches another test file. Pester 6 discovers and runs one file, then the next, and
removes a file's mocks when the file ends.

### Mocks And Setup Blocks

A `BeforeAll` in a `Context` runs before any `BeforeEach`. A mock defined in the parent's
`BeforeEach` is therefore not active while that `BeforeAll` runs, and the command it calls runs for
real. Define a mock that setup code depends on in an enclosing `BeforeAll` (TST-23).

`Should-Invoke` counts the calls made inside the current `It`. A call made in `BeforeAll` is outside
every `It`, so assert it with `-Scope Context`. Both were measured on Pester 6.2.0; the Pester rules
show a complete example.

## Patterns

### An Answer That Depends On The Arguments

Declare one filtered mock for each case. A default mock that throws turns an unexpected call into a
clear failure:

```powershell
BeforeAll {
    Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith {
        throw "Unexpected request: $Uri"
    }
    Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -ParameterFilter {
        $Uri.AbsolutePath -eq '/api/things/alpha'
    } -MockWith {
        [PSCustomObject]@{ name = 'alpha'; state = 'ready' }
    }
    Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -ParameterFilter {
        $Uri.AbsolutePath -eq '/api/things/beta'
    } -MockWith {
        [PSCustomObject]@{ name = 'beta'; state = 'stopped' }
    }
}
```

The parameters of the mocked command are variables inside `-MockWith` and `-ParameterFilter`. A
`param()` block is not needed. Return objects with the shape and types of the real command's output,
so that the code under test reads them the way it reads the real thing.

### A Dependency That Fails

Throw the exception type that the real dependency throws, and assert what the function does with it:

```powershell
It 'Reports a service timeout as a read error' {
    Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith {
        throw [System.TimeoutException]::new('The service did not answer.')
    }

    { Get-Thing -Name 'alpha' -ErrorAction Stop } |
        Should-Throw -FullyQualifiedErrorId 'ThingReadFailed,Get-Thing'
}
```

### The Clock

Code that calls `Get-Date` gives a different result on every run. Fix the time (TST-31):

```powershell
It 'Reports the age of the report in days' {
    Mock -CommandName Get-Date -ModuleName ModuleName -MockWith { [datetime]::new(2024, 1, 31) }

    Get-ReportAge -Created ([datetime]::new(2024, 1, 1)) | Should-Be 30
}
```

### The File System

Prefer real files in `$TestDrive` to mocks of `Get-Content`, `Test-Path`, and `Set-Content` (TST-03).
The test then exercises the real provider, and Pester removes the files. Mock a file command only
for a condition that cannot be staged, such as a read that is denied:

```powershell
It 'Reports a settings file that cannot be read' {
    Mock -CommandName Get-Content -ModuleName ModuleName -MockWith {
        throw [System.UnauthorizedAccessException]::new('Access to the path is denied.')
    }

    { Read-Setting -LiteralPath (Join-Path -Path $TestDrive -ChildPath 'settings.json') } |
        Should-Throw -ExceptionType ([System.UnauthorizedAccessException])
}
```

### A Native Executable

An executable is mocked by its name, and it must be installed where the tests run, because Pester
cannot mock a command that it cannot find. The function under test reads `$LASTEXITCODE` (ERR-23),
so the mock sets it. It must write to PowerShell's own variable in the global scope; a plain
assignment stays inside the mock:

```powershell
It 'Throws when git reports an error' {
    Mock -CommandName git -ModuleName ModuleName -MockWith {
        $global:LASTEXITCODE = 128
    }

    { Get-RepositoryStatus } |
        Should-Throw -FullyQualifiedErrorId 'GitStatusFailed,Get-RepositoryStatus'
}

It 'Returns the changed files' {
    Mock -CommandName git -ModuleName ModuleName -MockWith {
        $global:LASTEXITCODE = 0
        ' M README.md'
    }

    Get-RepositoryStatus | Should-Be ' M README.md'
}
```

Set the exit code in every mock of an executable, the successful ones too. The variable keeps the
value that the previous test left in it.

### Running The Real Command From A Mock

To count the calls to a command that should still do its work, or to run the real command for some
calls only, capture the command before the test and call it with the parameters of the mocked call.
Pester provides those as `$PesterBoundParameters`:

```powershell
BeforeAll {
    $realGetContent = Get-Command -Name Get-Content -CommandType Cmdlet
    $settingPath = Join-Path -Path $TestDrive -ChildPath 'settings.txt'
    Set-Content -LiteralPath $settingPath -Value 'region=westeurope' -Encoding ascii
}

It 'Reads the settings file once' {
    Mock -CommandName Get-Content -ModuleName ModuleName -MockWith {
        & $realGetContent @PesterBoundParameters
    }

    Read-Setting -LiteralPath $settingPath | Should-BeString 'region=westeurope' -TrimWhitespace

    Should-Invoke -CommandName Get-Content -ModuleName ModuleName -Times 1 -Exactly
}
```

- `$PSBoundParameters` is empty inside `-MockWith`. Use `$PesterBoundParameters`.
- Pass `-CommandType` to `Get-Command`. Once a mock exists, `Get-Command -Name Get-Content` returns
  the alias that Pester created for the mock.

## Asserting Calls

### Parameters Of A Call

```powershell
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
```

- `-Times 1` alone means at least once. Add `-Exactly` (TST-22). Without `-Times`, `Should-Invoke`
  passes for one call or more.
- `-ExclusiveFilter` passes only when every recorded call matches the filter. Use it to prove that
  nothing else was requested:

```powershell
Should-Invoke -CommandName Invoke-RestMethod -ModuleName ModuleName -ExclusiveFilter {
    $Uri.Host -eq 'things.example.test'
}
```

### A Command That Must Not Run

`Should-NotInvoke` shows that a failure path stopped before the call that changes something. That is
often worth more than showing that the function threw:

```powershell
It 'Does not call the service when the name is not valid' {
    Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith { }

    { Remove-Thing -Name '../alpha' -Confirm:$false } |
        Should-Throw -FullyQualifiedErrorId 'ParameterArgumentValidationError,Remove-Thing'

    Should-NotInvoke -CommandName Invoke-RestMethod -ModuleName ModuleName
}

It 'Does not call the service when -WhatIf is passed' {
    Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith { }

    Remove-Thing -Name 'alpha' -WhatIf

    Should-NotInvoke -CommandName Invoke-RestMethod -ModuleName ModuleName
}
```

### The Order Of Calls

Record the calls in a list that the mocks add to, then assert the count and each position.
`Should-BeCollection @('Connect', 'Query')` cannot do this: it passes for the same items in any
order (TST-14).

```powershell
It 'Connects before it queries and disconnects last' {
    $calls = [System.Collections.Generic.List[string]]::new()
    Mock -CommandName Connect-Database -ModuleName ModuleName -MockWith { $calls.Add('Connect') }
    Mock -CommandName Invoke-DatabaseQuery -ModuleName ModuleName -MockWith { $calls.Add('Query') }
    Mock -CommandName Disconnect-Database -ModuleName ModuleName -MockWith { $calls.Add('Disconnect') }

    Update-Record -Id 42

    $calls | Should-BeCollection -Count 3
    $calls[0] | Should-Be 'Connect'
    $calls[1] | Should-Be 'Query'
    $calls[2] | Should-Be 'Disconnect'
}
```

`$calls -join ', ' | Should-Be 'Connect, Query, Disconnect'` asserts the same thing in one line, and
its failure message shows the whole sequence.

## Shared Mocks

Each test file declares the mocks it needs (TST-02). When many files need the same set, put it in a
function and load that function from `Pester.BeforeContainer.ps1`, the setup file that Pester runs
for every test file below its folder:

```powershell
# Tests/TestHelpers/MockFactory.ps1
function Set-ServiceMock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    Mock -CommandName Invoke-RestMethod -ModuleName $ModuleName -MockWith {
        [PSCustomObject]@{ status = 'healthy' }
    }
}
```

```powershell
# Pester.BeforeContainer.ps1, in the repository root
BeforeAll {
    $helperFolder = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Tests') -ChildPath 'TestHelpers'
    . (Join-Path -Path $helperFolder -ChildPath 'MockFactory.ps1')
}
```

```powershell
# In a test file
BeforeAll {
    Set-ServiceMock -ModuleName ModuleName
}
```

- The dot-sourcing must be inside `BeforeAll`. Top-level code in `Pester.BeforeContainer.ps1` runs
  during discovery only, so a function defined there no longer exists when the tests run.
- The mock belongs to the block that calls the function, as if the block had declared it.
- Pester's source marks `Pester.BeforeContainer.ps1` as experimental.

## Global Mocks (Experimental)

`Mock.Global` is off by default, and the Pester rules say not to enable an experimental option
unless the user asks. When it is on, a mock reaches the command from every module and script, not
from one caller:

```powershell
$configuration = New-PesterConfiguration
$configuration.Mock.Global = $true
```

| | Default | `Mock.Global = $true` |
| --- | --- | --- |
| Reach of a mock | The test file, or the module named by `-ModuleName` | Every module and script |
| `-ModuleName` | Selects the caller that the mock applies to | Still accepted; it no longer limits the mock |
| A call that matches no filter | Error, as described above | Error, as described above |

Its use is a guard: a mock that fails the test when any code, in any module, runs a command for
real. A guard that has a filter needs a default mock beside it, because the calls that the guard
permits must still match something:

```powershell
BeforeAll {
    Mock -CommandName Remove-Item -ParameterFilter {
        $target = if ($LiteralPath) { $LiteralPath } else { $Path }
        $target -notlike "$TestDrive*"
    } -MockWith {
        throw 'Remove-Item was called outside the test drive.'
    }
    Mock -CommandName Remove-Item -MockWith { }
}
```

The filter reads both path parameters, because the code under test may use either. With the option
off, the same two mocks apply to calls from the test file only. A module that calls `Remove-Item`
runs the real command, and the guard never fires. To let the permitted calls delete for real, make
the default mock call the real command as shown under "Running The Real Command From A Mock".
