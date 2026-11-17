# Mocking Patterns Guide

Patterns for `Mock`, `Should-Invoke`, and `InModuleScope`. The rules are TST-20 to TST-24 in the
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

Mocking also falls back gracefully when a command cannot produce its dynamic parameters. A function
whose `dynamicparam` block throws is still replaced by its mock.

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

A mock declared inside `InModuleScope` applies inside the module and needs no `-ModuleName`. It is
the other way to replace a private function that a public one calls:

```powershell
It 'Returns nothing when the status service cannot be reached' {
    InModuleScope -ModuleName ModuleName -ScriptBlock {
        Mock -CommandName Get-ServiceStatus -MockWith { throw 'service unreachable' }

        $result = 'Billing', 'Identity' | Get-Data -ErrorAction SilentlyContinue

        $result | Should-BeFalsy
        Should-Invoke -CommandName Get-ServiceStatus -Times 2 -Exactly
    }
}
```

`InModuleScope` is also how a test reaches a class that the module defines, for example in its
`Classes` folder. A test file that imports the module does not see the type: there `[ThingCache]`
fails with `Unable to find type`.

```powershell
It 'Keeps the state of a thing that was added to the cache' {
    InModuleScope -ModuleName ModuleName -ScriptBlock {
        $cache = [ThingCache]::new()
        $cache.Add('alpha', 'ready')

        $cache.GetState('alpha') | Should-Be 'ready'
    }
}
```

### How Long A Mock Lasts

A mock lasts until the block that declared it ends, and Pester then restores the command. The mock
itself needs no cleanup code; state that mocks share does, as "Mocks That Share State" shows.

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

### One Context, One Set Of Mocks

Keep mocks isolated between tests: each `Context` declares the mocks that its tests call in its own
`BeforeEach` (TST-24):

```powershell
Describe 'Get-ServiceHealth' -Tag 'Unit', 'Public' {
    Context 'When the service answers' {
        BeforeEach {
            Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith {
                [PSCustomObject]@{ status = 'healthy' }
            }
        }

        It 'Returns the status that the service reported' {
            Get-ServiceHealth | Should-Be 'healthy'
        }
    }

    Context 'When the service is unavailable' {
        BeforeEach {
            Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith {
                throw 'Service unavailable'
            }
        }

        It 'Fails with the error of the service' {
            { Get-ServiceHealth } | Should-Throw -ExceptionMessage '*Service unavailable*'
        }
    }
}
```

From 6.2 a block may also hold several `BeforeEach` blocks, which run in the order they are written,
so a second group of mocks can be a block of its own. Separate `Context` blocks remain the better
split when the two groups serve different tests. Pester 6.0 and 6.1 stop with
`BeforeEach is already defined in this block` at the second one.

### Mocks And Setup Blocks

A `BeforeAll` in a `Context` runs before any `BeforeEach`. A mock defined in the parent's
`BeforeEach` is therefore not active while that `BeforeAll` runs, and the command it calls runs for
real. Define a mock that setup code depends on in an enclosing `BeforeAll` (TST-23), and keep
`BeforeEach` for mocks that only the tests themselves call.

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

One mock can also hold every case, in a `switch` on its arguments. The `default` branch throws for a
request that the test did not expect:

```powershell
BeforeAll {
    Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith {
        switch -Regex ($Uri.AbsolutePath) {
            '^/api/things/[a-z]+$' {
                if ($Method -eq 'Delete') {
                    return [PSCustomObject]@{ success = $true }
                }
                return [PSCustomObject]@{ name = $Uri.Segments[-1]; state = 'ready' }
            }
            '^/api/health$' {
                return [PSCustomObject]@{ status = 'healthy' }
            }
            default {
                $status = [System.Net.WebExceptionStatus]::ProtocolError
                throw [System.Net.WebException]::new("Not Found: $Uri", $status)
            }
        }
    }
}
```

A `param()` block that names the parameters, such as `param($Uri, $Method, $Body, $Headers)`, is
accepted at the top of such a mock body and receives the same values.

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

A slow answer and a timeout are simulated with `Start-Sleep` in the mock. The timeout mock sleeps
past the limit that the test passes, then throws the exception of a request that timed out:

```powershell
BeforeAll {
    Mock -CommandName Invoke-WebRequest -ModuleName ModuleName -MockWith {
        [PSCustomObject]@{ StatusCode = 200; Content = '{"data": "sample response"}' }
    }
    Mock -CommandName Invoke-WebRequest -ModuleName ModuleName -ParameterFilter {
        $Uri.Host -eq 'slow.test'
    } -MockWith {
        Start-Sleep -Milliseconds 2000
        [PSCustomObject]@{ StatusCode = 200; Content = '{"data": "sample response"}' }
    }
    Mock -CommandName Invoke-WebRequest -ModuleName ModuleName -ParameterFilter {
        $Uri.Host -eq 'timeout.test'
    } -MockWith {
        Start-Sleep -Seconds 2
        $status = [System.Net.WebExceptionStatus]::Timeout
        throw [System.Net.WebException]::new('The operation has timed out', $status)
    }
}

It 'Returns the page from a slow server' {
    Get-PageContent -Uri 'https://slow.test/' | Should-Be '{"data": "sample response"}'
}

It 'Reports a timeout as a WebException' {
    { Get-PageContent -Uri 'https://timeout.test/' -TimeoutSec 1 } |
        Should-Throw -ExceptionType ([System.Net.WebException])
}
```

The delay is written out, because the mock body cannot read `$TimeoutSec` on both editions: on
PowerShell 7.6 that name is an alias of `-ConnectionTimeoutSeconds`, and the variable does not
exist there. The sleep is real time and counts toward the speed budget (TST-47).

### Mocks That Share State

When several mocks stand in for one stateful dependency, such as a database connection, keep the
state in one hashtable that all of them read and change:

```powershell
Describe 'Add-User' -Tag 'Unit', 'Public' {
    BeforeAll {
        $database = @{
            Connected = $false
            TransactionActive = $false
            Users = [System.Collections.Generic.List[object]]::new()
        }

        Mock -CommandName Connect-Database -ModuleName ModuleName -MockWith {
            if ($ConnectionString -match 'invalid') {
                throw [System.InvalidOperationException]::new('Invalid connection string')
            }
            $database.Connected = $true
        }
        Mock -CommandName Start-DatabaseTransaction -ModuleName ModuleName -MockWith {
            if (-not $database.Connected) {
                throw [System.InvalidOperationException]::new('Database connection not established')
            }
            $database.TransactionActive = $true
        }
        Mock -CommandName Invoke-DatabaseQuery -ModuleName ModuleName -MockWith {
            $user = [PSCustomObject]@{
                Id = $database.Users.Count + 1
                Name = $Parameters.Name
                Email = $Parameters.Email
            }
            $database.Users.Add($user)
            [PSCustomObject]@{ RowsAffected = 1; Identity = $user.Id }
        }
        Mock -CommandName Complete-DatabaseTransaction -ModuleName ModuleName -MockWith {
            $database.TransactionActive = $false
        }
    }

    AfterEach {
        $database.Connected = $false
        $database.TransactionActive = $false
        $database.Users.Clear()
    }

    It 'Stores the user and closes the transaction' {
        $id = Add-User -Name 'Ada' -Email 'ada@example.test'

        $id | Should-Be 1
        $database.Users | Should-BeCollection -Count 1
        $database.Users[0].Email | Should-Be 'ada@example.test'
        $database.TransactionActive | Should-BeFalse
    }
}
```

The mocks change members of the hashtable and never assign the variable, so every block works on
the same object. Pester removes the mocks when their block ends, but not the state: reset it in
`AfterEach`. Delete there, too, any temporary file that a mock created outside `$TestDrive`:

```powershell
AfterEach {
    Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'MockTest*' |
        Remove-Item -Force -ErrorAction SilentlyContinue
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

Mock the file commands with realistic behaviour when a unit test is to stay off the disk. The mocks
of `Test-Path`, `Get-Content`, `Set-Content`, `New-Item`, and `Remove-Item` then share an in-memory
store, in the way that "Mocks That Share State" describes:

```powershell
Describe 'Update-Setting' -Tag 'Unit', 'Public' {
    BeforeAll {
        $settingPath = 'C:\Temp\settings.txt'
        $files = @{}

        Mock -CommandName Test-Path -ModuleName ModuleName -MockWith {
            $files.ContainsKey([string]$LiteralPath)
        }
        Mock -CommandName Get-Content -ModuleName ModuleName -MockWith {
            if (-not $files.ContainsKey([string]$LiteralPath)) {
                throw [System.IO.FileNotFoundException]::new("File not found: $LiteralPath")
            }
            $files[[string]$LiteralPath]
        }
        Mock -CommandName Set-Content -ModuleName ModuleName -MockWith {
            $files[[string]$LiteralPath] = $Value -join "`r`n"
        }
    }

    BeforeEach {
        $files.Clear()
        $files[$settingPath] = 'region=westeurope'
    }

    It 'Replaces the content of an existing settings file' {
        Update-Setting -LiteralPath $settingPath -Value 'region=northeurope'

        $files[$settingPath] | Should-Be 'region=northeurope'
        Should-Invoke -CommandName Set-Content -ModuleName ModuleName -Times 1 -Exactly
    }
}
```

`-LiteralPath` reaches the mock as a `[string[]]`, so the mock converts it before it uses it as a
key.

A test that is to exercise the real provider creates real files in `$TestDrive` (TST-03), and Pester
removes them. A condition that cannot be staged there, such as a read that is denied, is mocked:

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

Code that starts the program with `Start-Process` and reads the exit code of the process object is
tested by mocking `Start-Process`. The mock returns an object with an `ExitCode`, and a `switch` on
the command line gives each command its own:

```powershell
BeforeAll {
    Mock -CommandName Start-Process -ModuleName ModuleName -MockWith {
        switch -Regex ("$FilePath $ArgumentList") {
            'git status' {
                if ($PesterBoundParameters.ContainsKey('RedirectStandardOutput')) {
                    Set-Content -LiteralPath $RedirectStandardOutput -Value ' M README.md'
                }
                return [PSCustomObject]@{ ExitCode = 0; ProcessName = 'git' }
            }
            'git clone.*invalid-repo' {
                return [PSCustomObject]@{ ExitCode = 128; ProcessName = 'git' }
            }
            default {
                return [PSCustomObject]@{ ExitCode = 127; ProcessName = $FilePath }
            }
        }
    }
}

It 'Fails when git reports that the repository does not exist' {
    { Copy-Repository -Uri 'https://example.test/invalid-repo' -Destination $TestDrive } |
        Should-Throw -FullyQualifiedErrorId 'GitCloneFailed,Copy-Repository'
}
```

The mock writes the output that the program would print to the file named by
`-RedirectStandardOutput`, when the caller passed that parameter. It asks `$PesterBoundParameters`
first: a mock body runs under the strict mode of the module that calls it, where reading the
variable of a parameter that was not passed is an error.

### A Command With Typed Parameters

PowerShell binds the arguments of a mocked command with the parameter types of the real command,
before the mock body runs. A stand-in object of another type is rejected:

```text
Cannot process argument transformation on parameter 'CimSession'. Cannot convert the
"@{ComputerName=System.String[]}" value of type "System.Management.Automation.PSCustomObject" to
type "Microsoft.Management.Infrastructure.CimSession[]".
```

`-RemoveParameterType` takes the type off the named parameter of the mock, so that the stand-in
session of a CIM test is accepted:

```powershell
BeforeEach {
    Mock -CommandName New-CimSession -ModuleName ModuleName -MockWith {
        [PSCustomObject]@{ ComputerName = $ComputerName }
    }
    Mock -CommandName Remove-CimSession -ModuleName ModuleName -RemoveParameterType CimSession -MockWith { }
    Mock -CommandName Get-CimInstance -ModuleName ModuleName -RemoveParameterType CimSession -MockWith {
        [PSCustomObject]@{ FreePhysicalMemory = 4GB }
    }
}

It 'Reads the free memory through the session and closes the session' {
    $computerName = 'server01.example.test'

    Get-FreeMemory -ComputerName $computerName | Should-Be 4GB

    Should-Invoke -CommandName Remove-CimSession -ModuleName ModuleName -Times 1 -Exactly
}
```

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
- `-Exactly` is a switch. `Should-Invoke Cmd -Exactly 1` binds `1` to `-Times` by position and so
  happens to work, but `-Times 1 -Exactly` is clearer and matches the classic syntax.
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
- `Mock` itself must still run in a setup block or a test, so call the function there. Called at the
  top level of a file or directly in the body of a `Describe`, it runs during discovery: Pester
  6.2.0 reports no error, and the command is not mocked when the tests run.
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
| Lifetime of a mock | Until the declaring block ends | Unchanged |
| A nested Pester run | Does not get the mock. A call from the scope that holds it fails with `No mock for command ... is defined in this scope` | Does not get the mock, which is tied to the run that created it. The command runs for real |

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

`Mock.Global` is experimental and may change. The Pester team has said that it wants this to become
the default in Pester 7, and it collects reports either way, including "turned it on, nothing
changed", through the Pester issue tracker.

Configure it for a run, not for a file. There is no file-level directive to opt in or out, so a
suite either runs with global mocks or it does not.
