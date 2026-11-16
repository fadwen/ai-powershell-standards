# Test Data Management Guide

This guide covers the data that tests use: cases for `-ForEach`, data files, files that a test
creates, and helper functions that build objects. It supports rules TST-02, TST-03, TST-12, TST-30,
and TST-31 in [powershell-pester.instructions.md](../powershell-pester.instructions.md). The
behaviour described here was checked on Pester 6.2.0.

## Discovery-Time and Run-Time Data

Pester reads a test file twice. During discovery it runs the file to find the `Describe`, `Context`,
and `It` blocks. During the run it executes the setup blocks and the tests. Where data is built
decides which of the two can see it.

| The data is used by | Build it in | Reason |
| --- | --- | --- |
| `-ForEach`, which shapes the test tree | `BeforeDiscovery` | Discovery happens before any `BeforeAll` runs. |
| Assertions inside `It` | `BeforeAll` or `BeforeEach` | These blocks run with the tests. |

```powershell
BeforeDiscovery {
    # Shapes the test tree: one It for each case.
    $userCases = @(
        @{ UserName = 'ann'; Department = 'Finance' }
        @{ UserName = 'bob'; Department = 'Operations' }
    )
}

Describe 'Get-UserDepartment' -Tag 'Unit' {
    BeforeAll {
        # Used inside the test bodies.
        $directoryPath = Join-Path -Path $TestDrive -ChildPath 'directory.json'
        $directory = @(
            @{ userName = 'ann'; department = 'Finance' }
            @{ userName = 'bob'; department = 'Operations' }
        )
        $json = ConvertTo-Json -InputObject $directory
        Set-Content -LiteralPath $directoryPath -Value $json -Encoding ascii
    }

    It 'Returns <Department> for <UserName>' -ForEach $userCases {
        Get-UserDepartment -LiteralPath $directoryPath -UserName $UserName | Should-Be $Department
    }
}
```

### Data Built in the Wrong Block

A variable that is assigned in `BeforeAll` is `$null` during discovery. What follows depends on how
the `-ForEach` argument is written. Measured on Pester 6.2.0:

| `-ForEach` argument, with `$users` assigned in `BeforeAll` | Result |
| --- | --- |
| `-ForEach $users` | Discovery of the file fails: `Value can not be null or empty array`. |
| `-ForEach $users.ForEach({ @{ Name = $_.Name } })` | Discovery of the file fails with the same message. |
| `-ForEach ($users \| ForEach-Object { @{ Name = $_.Name } })` | One test is created with the name `$null` in place of the value, and it runs with empty data. |

The third form is the dangerous one. Piping `$null` to `ForEach-Object` runs the script block once,
so the file reports one test where it should report many, and that test can pass.

A file that fails discovery adds nothing to `FailedCount`. It sets `FailedContainersCount` and makes
the run result `Failed`, which is why the CI gate tests `Result` (TST-42).

The check for an empty list is the `Run.FailOnNullOrEmptyForEach` option, which is on by default.
`-AllowNullOrEmptyForEach` on a `Describe`, `Context`, or `It` turns it off for that block. TST-30
requires a list that is not empty, so correct the data instead of adding the switch.

### Each File Builds Its Own Data

Pester 6 discovers and runs one file at a time, and in a parallel run each file has its own
runspace. A file therefore cannot use data or a helper that another test file loaded. Build the
data in the file's own `BeforeDiscovery`, or in a shared setup file; see
[Pester Test Structure Guide](./test-structure-guide.md#shared-setup-files).

## Case Format

Pass each case as a hashtable (TST-30). Each key becomes a variable inside the `It` block, and
`<Key>` in the test name is replaced with its value.

```powershell
BeforeDiscovery {
    $cases = @(
        @{ Text = 'alpha'; Expected = 'ALPHA' }
        @{ Text = 'beta'; Expected = 'BETA' }
    )
}

Describe 'ConvertTo-UpperText' -Tag 'Unit' {
    It 'Converts <Text> to <Expected>' -ForEach $cases {
        ConvertTo-UpperText -Text $Text | Should-Be $Expected
    }
}
```

Other kinds of case behave differently:

| Case | Inside the `It` block | In the test name |
| --- | --- | --- |
| Hashtable `@{ Text = 'alpha' }` | `$Text` and `$_.Text` | `<Text>` |
| Object `[PSCustomObject]@{ Text = 'alpha' }` | `$_.Text` only. `$Text` is not set. | `<_.Text>`. `<Text>` renders as `$null`. |
| Scalar `'alpha'` | `$_` | `<_>` |

Pester evaluates the text between `<` and `>` as a PowerShell expression, so a name can contain
`<User.Name>` or `<($Left + $Right)>`.

### Keys That Must Not Be Used

A key MUST NOT have the name of an automatic variable (TST-30, STY-13). PowerShell sets these
variables itself, so the value from the case is lost or the test fails. Measured on Pester 6.2.0:

| Key | What happens | Use instead |
| --- | --- | --- |
| `Input` | The test receives an empty enumerator. | `Text`, `InputObject`, `Value` |
| `Args` | The test receives the argument list of the test script block. | `Arguments`, `ArgumentList` |
| `Matches` | The value is replaced by the next `-match` in the test. | `ExpectedMatch` |
| `Host`, `PID` | The test fails: `Cannot overwrite variable Host because it is read-only or constant`. | `ComputerName`, `ProcessId` |

The other names in STY-13, such as `Error` and `Event`, are not allowed either, even where a simple
test happens to pass with them.

```powershell
# Non-compliant: $Input is an automatic variable, so the function receives nothing.
It 'Converts <Input>' -ForEach @(
    @{ Input = 'alpha'; Expected = 'ALPHA' }
) {
    ConvertTo-UpperText -Text $Input | Should-Be $Expected
}

# Compliant
It 'Converts <Text> to <Expected>' -ForEach @(
    @{ Text = 'alpha'; Expected = 'ALPHA' }
) {
    ConvertTo-UpperText -Text $Text | Should-Be $Expected
}
```

## Deterministic Data

Tests MUST NOT depend on the current time or on values that change between runs (TST-31).

- Cases for `-ForEach` are fixed values. Do not build them with `Get-Random`, `Get-Date`, or
  `[guid]::NewGuid()`: the test names would change on every run, and a failure could not be matched
  with an earlier one.
- When the code under test reads the clock, mock `Get-Date`.
- When the code under test needs a unique value, pass a fixed one from the test.

```powershell
Describe 'Test-ReportStale' -Tag 'Unit' {
    BeforeAll {
        Mock -CommandName Get-Date -ModuleName ModuleName -MockWith { [datetime]::new(2026, 3, 31) }
    }

    It 'Returns <Expected> for a report written on day <Day> of March 2026' -ForEach @(
        @{ Day = 30; Expected = $false }
        @{ Day = 1; Expected = $true }
    ) {
        $written = [datetime]::new(2026, 3, $Day)

        Test-ReportStale -LastWriteTime $written -MaximumAgeDays 7 | Should-Be $Expected
    }
}
```

## Data Files

Keep fixed data beside the tests:

```text
Tests/
|-- TestData/
|   |-- server-cases.psd1      cases for -ForEach
|   |-- users.json             input that the code under test reads
|   `-- api-responses.json     responses that mocks return
`-- TestHelpers/
    `-- TestData.ps1           functions that build test objects
```

A `.psd1` file suits cases, because `Import-PowerShellDataFile` returns hashtables without running
code:

```powershell
# Tests/TestData/server-cases.psd1
@{
    Cases = @(
        @{ ComputerName = 'web01'; Reachable = $true; Expected = 'Healthy' }
        @{ ComputerName = 'web02'; Reachable = $false; Expected = 'Unreachable' }
    )
}
```

```powershell
BeforeDiscovery {
    $testsRoot = Split-Path -Path $PSScriptRoot -Parent
    $dataPath = Join-Path -Path $testsRoot -ChildPath 'TestData'
    $data = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $dataPath -ChildPath 'server-cases.psd1')
    $serverCases = $data.Cases
}
```

A JSON file suits input that the code under test parses, and responses that a mock returns:

```json
[
    {
        "id": 1,
        "userName": "ann",
        "department": "Finance",
        "active": true
    },
    {
        "id": 2,
        "userName": "bob",
        "department": "Operations",
        "active": false
    }
]
```

```powershell
BeforeAll {
    $testsRoot = Split-Path -Path $PSScriptRoot -Parent
    $dataPath = Join-Path -Path $testsRoot -ChildPath 'TestData'
    $userJson = Get-Content -LiteralPath (Join-Path -Path $dataPath -ChildPath 'users.json') -Raw
    $users = ConvertFrom-Json -InputObject $userJson
}
```

Pass the text with `-InputObject` and assign the result. On Windows PowerShell 5.1,
`$userJson | ConvertFrom-Json` sends a JSON array down the pipeline as one object, so wrapping that
pipeline in `@()` gives an array with one element.

Treat the files under `TestData` as read-only. A test that has to change a file copies it to
`$TestDrive` first. Data files MUST NOT contain real secrets or personal data (SEC-01).

## Files That a Test Creates

Files that a test creates go in `$TestDrive` (TST-03). Measured on Pester 6.2.0:

- Each test file gets its own `$TestDrive` folder, so files do not leak from one test file to
  another.
- A file is removed when the block that created it ends. A file created in a `Describe`-level
  `BeforeAll` exists for the whole `Describe` block. A file created inside an `It` exists until the
  enclosing `Context` or `Describe` ends, so a later `It` in the same block can still see it.
- `$TestDrive` holds a real file system path, so it also works with .NET methods and native
  programs. The `TestDrive:` drive points at the same folder.

Create the files in `BeforeAll` or `BeforeEach`, not in one test for use by another (TST-31):

```powershell
Describe 'Import-UserList' -Tag 'Unit' {
    BeforeAll {
        $userFile = Join-Path -Path $TestDrive -ChildPath 'users.json'
        $json = '[{ "userName": "ann" }, { "userName": "bob" }]'
        Set-Content -LiteralPath $userFile -Value $json -Encoding ascii
    }

    It 'Reads every user in the file' {
        $result = @(Import-UserList -LiteralPath $userFile)

        $result | Should-BeCollection -Count 2
        $result[0].UserName | Should-Be 'ann'
        $result[1].UserName | Should-Be 'bob'
    }
}
```

A test that changes anything outside `$TestDrive` restores it (TST-31):

```powershell
Describe 'Get-DeploymentRegion' -Tag 'Unit' {
    BeforeAll {
        $originalRegion = $env:DEPLOYMENT_REGION
        $env:DEPLOYMENT_REGION = 'westeurope'
    }

    AfterAll {
        $env:DEPLOYMENT_REGION = $originalRegion
    }

    It 'Reads the region from the environment' {
        Get-DeploymentRegion | Should-Be 'westeurope'
    }
}
```

## Functions That Build Test Objects

When many tests need the same kind of object, write a small function that builds it from fixed
defaults, and let each test pass only the values it cares about. Keep the function free of random
values and of the clock. Comment-based help is omitted here to keep the example short.

```powershell
# Tests/TestHelpers/TestData.ps1


function New-TestUser {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an object in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType('Test.User')]
    param(
        [Parameter(Mandatory)]
        [string]$UserName,

        [string]$Department = 'Operations',

        [switch]$Disabled
    )

    [PSCustomObject]@{
        PSTypeName = 'Test.User'
        UserName = $UserName
        Department = $Department
        Enabled = -not $Disabled
        MailAddress = "$UserName@example.com"
    }
}
```

PSScriptAnalyzer reports `PSUseShouldProcessForStateChangingFunctions` for any function whose verb is
`New`. The attribute records why the rule does not apply here.

Dot-source the file in the top-level `BeforeAll` of each test file that uses it, or in the
`BeforeAll` of a shared setup file. A function that `-ForEach` data needs is dot-sourced in
`BeforeDiscovery` as well.

```powershell
BeforeAll {
    $testsRoot = Split-Path -Path $PSScriptRoot -Parent
    $helperPath = Join-Path -Path $testsRoot -ChildPath 'TestHelpers'
    . (Join-Path -Path $helperPath -ChildPath 'TestData.ps1')
}

Describe 'Get-UserSummary' -Tag 'Unit' {
    It 'Describes a disabled user as inactive' {
        $user = New-TestUser -UserName 'ann' -Disabled

        Get-UserSummary -User $user | Should-Be 'ann (inactive)'
    }
}
```

## Credentials in Test Data

A password MUST NOT be written in a test file or a data file, and
`ConvertTo-SecureString -AsPlainText` MUST NOT be applied to a literal (SEC-01, SEC-04). When a test
needs a `PSCredential` object only to pass it to the code under test, build one from a value created
at run time:

```powershell
BeforeAll {
    $password = [System.Security.SecureString]::new()
    foreach ($character in [guid]::NewGuid().ToString('N').ToCharArray()) {
        $password.AppendChar($character)
    }
    $testCredential = [System.Management.Automation.PSCredential]::new('test-user', $password)
}
```

The tests assert on the user name or on the call that received the credential, never on the
password. A test that needs a real secret is an integration test, and the secret comes from the CI
system (CIC-06).

## Checking a Data Set

To assert something about every item in a collection, assert the count and then use `Should-All`
(TST-12):

```powershell
It 'Loads three users that all have a name and a known department' {
    $users | Should-BeCollection -Count 3
    $users | Should-All { -not [string]::IsNullOrWhiteSpace($_.userName) }
    $users | Should-All { $_.department -in 'Finance', 'Operations' }
}
```

`Should-All` fails for an empty collection and names the items that did not pass the filter. A
`foreach` loop with an assertion inside it passes when the collection is empty, because the
assertion never runs.

## Data in Parallel Runs

In a parallel run each test file has its own runspace. A `$script:` variable, a cache in a helper,
or a loaded module in one file is not visible in another, and each file has its own `$TestDrive`.
Data that follows this guide needs no change for a parallel run. See
[Test Execution Guide](./test-execution.md#parallel-test-execution).
