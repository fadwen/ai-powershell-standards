# Integration Test Template

An integration test file: the module runs against the real file system and a real service, with
nothing mocked. The rules it follows are in the [Pester rules](../powershell-pester.instructions.md).
The file below passes on Pester 6.2.0 under PowerShell 7.6 and Windows PowerShell 5.1, with the
service configured and without it.

## The Code Under Test

The template tests the module `ModuleName` from the [unit test template](./unit-test-template.md).
The test file is in the `Tests` folder directly under the module root.

- `Export-Thing -Thing <object[]> -LiteralPath <string>` writes the things to a JSON file as UTF-8
  without a byte order mark. The file holds a `savedAt` time and a `things` array. The function
  supports `-WhatIf`.
- `Get-Thing -Name <string[]> -ServiceUri <uri>` reads things from the service at that address.

The address of a test instance of the service comes from the environment variable
`THING_SERVICE_URI`.

## The Test File

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

#pester:no-parallel

BeforeDiscovery {
    $serviceIsMissing = [string]::IsNullOrEmpty($env:THING_SERVICE_URI)
}

BeforeAll {
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ModuleName.psd1')
    }
}

Describe 'Export-Thing with the real file system' -Tag 'Integration' {
    BeforeAll {
        $things = @(
            [PSCustomObject]@{ PSTypeName = 'ModuleName.Thing'; Name = 'alpha'; State = 'ready' }
            [PSCustomObject]@{ PSTypeName = 'ModuleName.Thing'; Name = 'beta'; State = 'stopped' }
        )
    }

    It 'Writes a file that reads back as the same things' {
        $exportPath = Join-Path -Path $TestDrive -ChildPath 'things.json'

        $things | Export-Thing -LiteralPath $exportPath

        $document = Get-Content -LiteralPath $exportPath -Raw | ConvertFrom-Json
        $expected = [PSCustomObject]@{
            things = @(
                [PSCustomObject]@{ name = 'alpha'; state = 'ready' }
                [PSCustomObject]@{ name = 'beta'; state = 'stopped' }
            )
        }
        $document | Should-BeEquivalent $expected -ExcludePath 'savedAt'
    }

    It 'Writes UTF-8 without a byte order mark' {
        $exportPath = Join-Path -Path $TestDrive -ChildPath 'encoding.json'

        $things | Export-Thing -LiteralPath $exportPath

        # 123 is the opening brace. A byte order mark would put 239 first.
        $bytes = [System.IO.File]::ReadAllBytes($exportPath)
        $bytes.Count | Should-BeGreaterThan 0
        $bytes[0] | Should-Be 123
    }

    It 'Writes nothing when -WhatIf is passed' {
        $exportPath = Join-Path -Path $TestDrive -ChildPath 'whatif.json'

        $things | Export-Thing -LiteralPath $exportPath -WhatIf

        Test-Path -LiteralPath $exportPath | Should-BeFalse
    }

    It 'Throws when the folder does not exist' {
        $missingFolder = Join-Path -Path $TestDrive -ChildPath 'missing'
        $exportPath = Join-Path -Path $missingFolder -ChildPath 'things.json'

        $failure = { $things | Export-Thing -LiteralPath $exportPath } |
            Should-Throw -ExceptionType ([System.Management.Automation.MethodInvocationException])

        $failure.Exception.InnerException | Should-HaveType ([System.IO.DirectoryNotFoundException])
    }
}

Describe 'Get-Thing with the real service' -Tag 'Integration' -Skip:$serviceIsMissing {
    BeforeAll {
        $serviceUri = $env:THING_SERVICE_URI
    }

    It 'Reads a thing that exists' {
        $result = @(Get-Thing -Name 'alpha' -ServiceUri $serviceUri)

        $result | Should-BeCollection -Count 1
        $result[0] | Should-HaveType 'ModuleName.Thing'
        $result[0].Name | Should-Be 'alpha'
    }

    It 'Reports a thing that does not exist as one non-terminating error' {
        $output = Get-Thing -Name 'no-such-thing' -ServiceUri $serviceUri 2>&1
        $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

        $output | Should-BeCollection -Count 1
        $errors | Should-BeCollection -Count 1
        $errors[0].FullyQualifiedErrorId | Should-Be 'ThingReadFailed,Get-Thing'
    }
}
```

## What The Template Shows

### Real Files Go In The Test Drive

Every file is created under `$TestDrive` (TST-03). Pester creates that folder for the test file and
removes it afterwards, so the tests need no cleanup code and cannot leave files behind. Anything
else that a test changes, such as an environment variable or a record in the service, must be
restored in `AfterAll` or `AfterEach` (TST-31).

### A Missing Environment Is Skipped At Discovery

`-Skip:` takes a value that is known during discovery, so it is computed in `BeforeDiscovery`. The
tests of a skipped block are reported as `Skipped`, and the block's `BeforeAll` does not run.

Skip only for an environment that is not configured. When the address is set and the service does
not answer, the tests must fail; a skip there would hide the outage. A test can still mark itself at
run time with `Set-ItResult -Skipped -Because '<reason>'` or `Set-ItResult -Inconclusive`, from the
`It` block or from `BeforeEach`. `Set-ItResult -Pending` was removed in Pester 6.

Tag the `Describe` blocks `Integration` (TST-04), so that a run can leave them out with
`Filter.ExcludeTag`.

### Test Cases From The Environment

A `-ForEach` list that is built from configuration is empty when the configuration is missing, and
Pester 6 then stops discovery of the file instead of running no tests. That is usually the right
outcome. The unit test template shows `-AllowNullOrEmptyForEach` for the case where an empty list is
legitimate.

### Whole Objects Are Compared With Should-BeEquivalent

One `Should-BeEquivalent` reports every property that differs after a round trip. `-ExcludePath`
leaves out a value that changes on every run, here `savedAt`. `Should-BeEquivalent` does not compare
the order of a collection; add index assertions after a count when order is part of the contract.

### A .NET Failure Arrives Wrapped

`Export-Thing` writes with `[System.IO.File]::WriteAllText()` and passes a failure on with
`$PSCmdlet.ThrowTerminatingError($_)`. `Should-Throw -ExceptionType` compares the outer exception,
which is a `MethodInvocationException`. The test asserts that type and then reads the original
exception from the error record that `Should-Throw` returns.

### The File Does Not Run In Parallel

The comment `#pester:no-parallel` keeps the file out of the worker runspaces when a run sets
`Run.Parallel`; such files run one after another in the main session. It has no effect otherwise.
`Run.Parallel` is experimental and off by default. Mark a file this way when it uses a resource that
two files cannot share, such as a fixed port or a record in a test service.

### Both Editions

The file runs unchanged on Windows PowerShell 5.1 because it avoids what differs there:

- Each `Join-Path` call has one child path. `Join-Path 'a' 'b' 'c'` is an error on 5.1; nest the
  calls.
- `$IsWindows` does not exist on 5.1, and reading it under strict mode is an error. Test
  `$PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows`, which reads it only on PowerShell 7.
- The byte order mark is asserted from the bytes of the file, not from the encoding name, because
  `-Encoding utf8` means different things on the two editions (STY-33).

To limit a test to one edition, pass a discovery-time condition such as
`-Skip:($PSVersionTable.PSEdition -ne 'Core')`.
