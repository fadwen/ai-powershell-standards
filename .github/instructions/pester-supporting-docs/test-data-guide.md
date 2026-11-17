# Test Data Management Guide

This guide covers the data that tests use: cases for `-ForEach`, data files, files that a test
creates, and helper functions that build objects. It supports rules TST-02, TST-03, TST-12, TST-30,
and TST-31 in [powershell-pester.instructions.md](../powershell-pester.instructions.md). The
behaviour described here was checked on Pester 6.2.0.

Do not use emoji in generated code, documentation, or test output. Use plain text and standard
ASCII characters only (STY-06, TST-07).

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
`-AllowNullOrEmptyForEach` on a `Describe`, `Context`, or `It` turns it off for that block. Opt out
with the switch where an empty list is legitimate, or correct the code that builds the list so that
it cannot be empty. In every other case TST-30 requires a list that is not empty.

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

Tests MUST NOT depend on the current time (TST-31), and the data that feeds `-ForEach` must be
stable.

- For cases, prefer fixed fixtures, such as a `.psd1` file loaded with
  `Import-PowerShellDataFile`, or a seeded generator. Do not build cases with an unseeded
  `Get-Random`, with `Get-Date`, or with `[guid]::NewGuid()`: the test names would change on every
  run and in every runspace, and a failure could not be matched with an earlier one or with a
  report.
- Keep `Get-Random` for values that are used inside `It` bodies, where the name is already fixed.
  The assertion must then hold for every value that can come out, and the failure message should
  state the value.
- When the code under test reads the clock, mock `Get-Date`.
- When the code under test needs a unique value and the test asserts on it, pass a fixed one from
  the test.

A seeded generator returns the same values on every run. With the seed below, the three cases were
563, 218, and 838 on PowerShell 7.6 and on Windows PowerShell 5.1. `Get-ThingSummary` is the
function of the [performance test template](./performance-test-template.md); it emits one object
for each state, with the number of things in that state.

```powershell
BeforeDiscovery {
    # Stable names: the same test identity on every run and in every runspace.
    $random = [System.Random]::new(20260331)
    $loadCases = foreach ($number in 1..3) {
        @{ ItemCount = $random.Next(100, 1000) }
    }
}

Describe 'Get-ThingSummary' -Tag 'Unit', 'Public' {
    It 'Counts <ItemCount> things' -ForEach $loadCases {
        $things = foreach ($index in 1..$ItemCount) {
            [PSCustomObject]@{ Name = "thing-$index"; State = 'ready' }
        }

        $summary = @(Get-ThingSummary -Thing $things)

        $summary | Should-BeCollection -Count 1
        $summary[0].Count | Should-Be $ItemCount
    }

    It 'Counts a number of things that is chosen at run time' {
        $thingCount = Get-Random -Minimum 1 -Maximum 100
        $things = foreach ($index in 1..$thingCount) {
            [PSCustomObject]@{ Name = "thing-$index"; State = 'ready' }
        }

        $summary = @(Get-ThingSummary -Thing $things)

        $summary | Should-BeCollection -Count 1
        $summary[0].Count | Should-Be $thingCount -Because "the input held $thingCount things"
    }
}
```

`Get-Random -SetSeed` also repeats its values, but it reseeds the generator of the whole session;
an object of `[System.Random]` keeps the seed to the code that owns it.

When the code under test reads the clock, the test mocks `Get-Date`:

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

Keep fixed data beside the tests, sorted by what it is for:

```text
Tests/
|-- TestData/
|   |-- server-cases.psd1          cases for -ForEach
|   |-- Configurations/            settings for each environment
|   |   |-- development.psd1
|   |   |-- testing.psd1
|   |   `-- production.psd1
|   |-- SampleData/                input that the code under test reads
|   |   |-- users.json
|   |   |-- servers.csv
|   |   `-- configurations.xml
|   |-- MockResponses/             responses that mocks return
|   |   |-- api-responses.json
|   |   |-- database-results.json
|   |   `-- service-responses.json
|   |-- Templates/
|   |   |-- user-template.json
|   |   |-- server-template.json
|   |   `-- config-template.psd1
|   |-- Baselines/                 figures that tests compare with
|   |   |-- performance-baselines.psd1
|   |   `-- security-baselines.json
|   `-- Fixtures/
|       |-- test-certificates/
|       |-- test-files/
|       `-- sample-logs/
`-- TestHelpers/
    |-- TestDataFactory.ps1        builds test objects
    |-- MockDataGenerator.ps1
    `-- DataValidation.ps1         checks a data set
```

A suite with a handful of data files can keep them directly in `TestData`, with one helper file
such as `TestHelpers/TestData.ps1`, and add the subfolders when the number of files grows.

The samples in this guide are written for a test file one level below `Tests`. For a file in
`Tests/Unit/Public`, add one more `Split-Path` to reach the `Tests` folder.

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
    $samplePath = Join-Path -Path $dataPath -ChildPath 'SampleData'
    $userJson = Get-Content -LiteralPath (Join-Path -Path $samplePath -ChildPath 'users.json') -Raw
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

## Test Data Factory

When many tests need the same kinds of object, build them in one place: a `TestDataFactory` class
with one method for each kind of object and a cache, and a wrapper function for each method. The
generator is seeded, so the factory returns the same objects on every run. Comment-based help is
omitted here to keep the example short.

```powershell
# Tests/TestHelpers/TestDataFactory.ps1

class TestDataFactory {
    static [hashtable] $Cache = @{}

    static [object[]] CreateUsers([int]$Count, [string]$Type) {
        $cacheKey = "Users_${Count}_$Type"
        if ([TestDataFactory]::Cache.ContainsKey($cacheKey)) {
            return [TestDataFactory]::Cache[$cacheKey]
        }

        # The seed makes the generator return the same users on every run.
        $random = [System.Random]::new(20260331)
        $firstNames = 'James', 'Mary', 'John', 'Patricia', 'Robert', 'Jennifer'
        $lastNames = 'Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia'
        $departments = 'IT', 'HR', 'Finance', 'Marketing', 'Operations'
        $users = foreach ($id in 1..$Count) {
            $firstName = $firstNames[$random.Next($firstNames.Count)]
            $lastName = $lastNames[$random.Next($lastNames.Count)]
            [PSCustomObject]@{
                PSTypeName = 'Test.User'
                Id = $id
                FullName = "$firstName $lastName"
                Email = "$firstName.$lastName@example.com".ToLowerInvariant()
                Department = $departments[$random.Next($departments.Count)]
                Active = $Type -ne 'Disabled'
                IsAdmin = $Type -eq 'Admin'
            }
        }

        [TestDataFactory]::Cache[$cacheKey] = $users
        return $users
    }

    static [void] ClearCache() {
        [TestDataFactory]::Cache = @{}
    }

    static [void] SaveTestData([string]$Name, [object]$Data, [string]$Folder) {
        $filePath = Join-Path -Path $Folder -ChildPath "$Name.json"
        $json = ConvertTo-Json -InputObject $Data -Depth 10
        Set-Content -LiteralPath $filePath -Value $json -Encoding ascii
    }
}


function New-TestUserList {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates objects in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType('Test.User')]
    param(
        [ValidateRange(1, 100000)]
        [int]$Count = 5,

        [ValidateSet('Standard', 'Admin', 'Disabled')]
        [string]$Type = 'Standard'
    )

    [TestDataFactory]::CreateUsers($Count, $Type)
}


function Clear-TestDataCache {
    [CmdletBinding()]
    param()

    [TestDataFactory]::ClearCache()
}
```

Add a method and a wrapper function for each further kind of object that the suite needs, such as
servers, configurations, API responses, and log entries. `SaveTestData` writes a data set to a file
for a test that needs one; pass it a folder under `$TestDrive` (TST-03). The attribute on
`New-TestUserList` is explained under
[Functions That Build Test Objects](#functions-that-build-test-objects).

A test file dot-sources the factory in its top-level `BeforeAll`, and in `BeforeDiscovery` as well
when `-ForEach` data comes from it:

```powershell
BeforeDiscovery {
    $testsRoot = Split-Path -Path $PSScriptRoot -Parent
    $helperPath = Join-Path -Path $testsRoot -ChildPath 'TestHelpers'
    . (Join-Path -Path $helperPath -ChildPath 'TestDataFactory.ps1')

    # Shapes the test tree: one It for each user.
    $userCases = (New-TestUserList -Count 3).ForEach({ @{ FullName = $_.FullName; User = $_ } })
}

BeforeAll {
    $testsRoot = Split-Path -Path $PSScriptRoot -Parent
    $helperPath = Join-Path -Path $testsRoot -ChildPath 'TestHelpers'
    . (Join-Path -Path $helperPath -ChildPath 'TestDataFactory.ps1')
}

Describe 'Test users' -Tag 'Unit', 'Public' {
    It 'Gives <FullName> an address at the example domain' -ForEach $userCases {
        $User.Email | Should-MatchString '@example\.com$'
    }
}
```

With the seed above, the three names are `Patricia Smith`, `Jennifer Jones`, and `Jennifer Brown`
on PowerShell 7.6 and on Windows PowerShell 5.1.

### Data Isolation

Create isolated test data for each test, and clean it up after the test:

```powershell
Describe 'Factory users' -Tag 'Unit', 'Public' {
    BeforeEach {
        # Create isolated test data for each test.
        $script:testUsers = New-TestUserList -Count 3 -Type 'Standard'
    }

    AfterEach {
        # Clean up the test data.
        Clear-TestDataCache
        Remove-Variable -Name 'testUsers' -Scope Script -ErrorAction SilentlyContinue
    }

    It 'Builds three active users' {
        $script:testUsers | Should-BeCollection -Count 3
        $script:testUsers | Should-All { $_.Active -and -not $_.IsAdmin }
    }
}
```

The factory returns the cached objects for a request that it has seen, so a test that changes one
of them would change it for the next test. Clearing the cache in `AfterEach` gives the next test
objects of its own.

### Performance Test Data

Generate large data sets for performance tests with a shared helper in the same file:

```powershell
function New-PerformanceTestData {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates objects in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType('Test.User', 'Test.LargeText')]
    param(
        [ValidateRange(1, 100000)]
        [int]$ItemCount = 1000,

        [ValidateSet('Users', 'LargeText')]
        [string]$DataType = 'Users'
    )

    # Generate large data sets for performance tests.
    switch ($DataType) {
        'Users' {
            [TestDataFactory]::CreateUsers($ItemCount, 'Standard')
        }
        'LargeText' {
            # About 2.7 KB of text for each item.
            $content = 'Lorem ipsum dolor sit amet ' * 100
            foreach ($id in 1..$ItemCount) {
                [PSCustomObject]@{
                    PSTypeName = 'Test.LargeText'
                    Id = $id
                    Content = $content
                }
            }
        }
    }
}
```

## Functions That Build Test Objects

A suite that needs one kind of object can do without the factory. Write a small function that
builds the object from fixed defaults, and let each test pass only the values it cares about. Keep
the function free of random values and of the clock. Comment-based help is omitted here to keep the
example short.

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

When several test files need a credential, the same code is a helper function beside the factory:

```powershell
function New-TestCredential {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an object in memory and changes no state.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCredential])]
    param(
        [string]$UserName = 'test-user'
    )

    # The password is created at run time, so no secret is stored in source.
    $password = [System.Security.SecureString]::new()
    foreach ($character in [guid]::NewGuid().ToString('N').ToCharArray()) {
        $password.AppendChar($character)
    }

    [System.Management.Automation.PSCredential]::new($UserName, $password)
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
assertion never runs. When the collection has items, the loop stops at the first failure and does
not say which item it was. Measured on Pester 6.2.0 with the items 1, 2, 5, 4, 7 and the limit 5:
the loop reported `Actual: [int] 5` and nothing about 7, and `Should-All` reported
`2 of them @(5, 7) did not pass the filter`.

There is no `Should-BeIn` assertion. Test membership with `-in` inside the filter, as the last line
of the example does, or with `Should-Any` over the allowed values. For a single value, the
[assertion guide](./assertion-guide.md) pipes the list to `Should-ContainCollection`.

## Data in Parallel Runs

In a parallel run each test file has its own runspace. A `$script:` variable, a cache in a helper,
or a loaded module in one file is not visible in another, and each file has its own `$TestDrive`.
Data that follows this guide needs no change for a parallel run. See
[Test Execution Guide](./test-execution.md#parallel-test-execution).
