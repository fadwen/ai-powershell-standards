# Integration Test Template

Use this template for integration tests that validate how components work together. TST-43 requires
them for code that has external dependencies. In an integration test file the module runs against
the real file system and a real service, with nothing mocked. The rules it follows are in the
[Pester rules](../powershell-pester.instructions.md). The files below pass on Pester 6.2.0 under
PowerShell 7.6 and Windows PowerShell 5.1: with the service running, with the service configured
but not answering, and without it.

Do not use emoji in generated code, documentation, or test output. Use plain text and standard
ASCII characters only (STY-06, TST-07).

## The Code Under Test

The template tests the module `ModuleName` from the [unit test template](./unit-test-template.md).
The test file is in the `Tests` folder directly under the module root.

- `Export-Thing -Thing <object[]> -LiteralPath <string>` writes the things to a JSON file as UTF-8
  without a byte order mark. The file holds a `savedAt` time and a `things` array. The function
  supports `-WhatIf`.
- `Get-Thing -Name <string[]> -ServiceUri <uri>` reads things from the service at that address.
- `Read-ThingFile -Root <string> -ChildPath <string>` reads a file below a root folder.

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

Describe 'Export-Thing with the real file system' -Tag 'Integration', 'SystemIntegration' {
    BeforeAll {
        $things = @(
            [PSCustomObject]@{ PSTypeName = 'ModuleName.Thing'; Name = 'alpha'; State = 'ready' }
            [PSCustomObject]@{ PSTypeName = 'ModuleName.Thing'; Name = 'beta'; State = 'stopped' }
        )
    }

    It 'Should write a file that reads back as the same things' {
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

    It 'Should write UTF-8 without a byte order mark' {
        $exportPath = Join-Path -Path $TestDrive -ChildPath 'encoding.json'

        $things | Export-Thing -LiteralPath $exportPath

        # 123 is the opening brace. A byte order mark would put 239 first.
        $bytes = [System.IO.File]::ReadAllBytes($exportPath)
        $bytes.Count | Should-BeGreaterThan 0
        $bytes[0] | Should-Be 123
    }

    It 'Should write nothing when -WhatIf is passed' {
        $exportPath = Join-Path -Path $TestDrive -ChildPath 'whatif.json'

        $things | Export-Thing -LiteralPath $exportPath -WhatIf

        Test-Path -LiteralPath $exportPath | Should-BeFalse
    }

    It 'Should throw when the folder does not exist' {
        $missingFolder = Join-Path -Path $TestDrive -ChildPath 'missing'
        $exportPath = Join-Path -Path $missingFolder -ChildPath 'things.json'

        $failure = { $things | Export-Thing -LiteralPath $exportPath } |
            Should-Throw -ExceptionType ([System.Management.Automation.MethodInvocationException])

        $failure.Exception.InnerException | Should-HaveType ([System.IO.DirectoryNotFoundException])
    }

    It 'Should handle path separators correctly' {
        $reportFolder = Join-Path -Path $TestDrive -ChildPath 'reports'
        $null = New-Item -Path $reportFolder -ItemType Directory
        $reportPath = Join-Path -Path $reportFolder -ChildPath 'report.txt'
        Set-Content -LiteralPath $reportPath -Value 'report' -Encoding ascii
        $childPath = Join-Path -Path 'reports' -ChildPath 'report.txt'

        Read-ThingFile -Root $TestDrive -ChildPath $childPath | Should-BeString 'report' -TrimWhitespace

        # $IsWindows does not exist on Windows PowerShell 5.1, which always runs on Windows.
        $onWindows = $PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows
        if ($onWindows) {
            $childPath | Should-MatchString '\\'
        } else {
            $childPath | Should-MatchString '/'
        }
    }
}

Describe 'Get-Thing with the real service' -Tag 'Integration', 'SystemIntegration' -Skip:$serviceIsMissing {
    BeforeAll {
        $serviceUri = [uri]$env:THING_SERVICE_URI

        # Verify once that the service can be reached.
        $serviceError = $null
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $client.Connect($serviceUri.Host, $serviceUri.Port)
        } catch [System.Management.Automation.MethodInvocationException] {
            # The tests of this block are skipped with this text as the reason.
            $serviceError = $_.Exception.InnerException.Message
        } finally {
            $client.Dispose()
        }
    }

    BeforeEach {
        if ($null -ne $serviceError) {
            Set-ItResult -Skipped -Because "the external service is not available: $serviceError"
        }
    }

    It 'Should read a thing that exists' {
        $result = @(Get-Thing -Name 'alpha' -ServiceUri $serviceUri)

        $result | Should-BeCollection -Count 1
        $result[0] | Should-HaveType 'ModuleName.Thing'
        $result[0].Name | Should-Be 'alpha'
    }

    It 'Should report a thing that does not exist as one non-terminating error' {
        $output = Get-Thing -Name 'no-such-thing' -ServiceUri $serviceUri 2>&1
        $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

        $output | Should-BeCollection -Count 1
        $errors | Should-BeCollection -Count 1
        $errors[0].FullyQualifiedErrorId | Should-Be 'ThingReadFailed,Get-Thing'
    }

    Context 'End-to-end workflow' -Tag 'EndToEnd' {
        It 'Should complete the full workflow' {
            $exportPath = Join-Path -Path $TestDrive -ChildPath 'workflow.json'

            Get-Thing -Name 'alpha' -ServiceUri $serviceUri -ErrorAction Stop |
                Export-Thing -LiteralPath $exportPath

            $document = Get-Content -LiteralPath $exportPath -Raw | ConvertFrom-Json
            $document.things | Should-BeCollection -Count 1
            $document.things[0].name | Should-Be 'alpha'
        }

        It 'Should handle partial failures gracefully' {
            $exportPath = Join-Path -Path $TestDrive -ChildPath 'partial.json'

            $output = Get-Thing -Name 'alpha', 'no-such-thing' -ServiceUri $serviceUri -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $things = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
            $things | Export-Thing -LiteralPath $exportPath

            # The workflow completed, and the failure was reported for the one thing.
            $errors | Should-BeCollection -Count 1
            $document = Get-Content -LiteralPath $exportPath -Raw | ConvertFrom-Json
            $document.things | Should-BeCollection -Count 1
        }

        It 'Should maintain data consistency across components' {
            $exportPath = Join-Path -Path $TestDrive -ChildPath 'consistent.json'

            $thing = Get-Thing -Name 'alpha' -ServiceUri $serviceUri -ErrorAction Stop
            $thing | Export-Thing -LiteralPath $exportPath

            $document = Get-Content -LiteralPath $exportPath -Raw | ConvertFrom-Json
            $expected = [PSCustomObject]@{ name = $thing.Name; state = $thing.State }
            $document.things[0] | Should-BeEquivalent $expected
        }
    }
}
```

## Tests Against Stand-In Functions

The example module has no retry logic and no data store. The tests in this section therefore run
against a small stand-in module that the template defines itself. In a project, the functions under
test are the project's own. Comment-based help is omitted here to keep the example short.

```powershell
# Tests/TestHelpers/IntegrationSample.psm1
Set-StrictMode -Version Latest


function Invoke-WithRetry {
    [CmdletBinding()]
    [OutputType('IntegrationSample.RetryResult')]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [ValidateRange(1, 10)]
        [int]$MaxRetries = 3
    )

    $attemptCount = 0
    $succeeded = $false
    $value = $null
    while (-not $succeeded -and $attemptCount -lt $MaxRetries) {
        $attemptCount++
        try {
            $value = & $ScriptBlock
            $succeeded = $true
        } catch [System.TimeoutException] {
            # A time-out is the transient failure that this function retries.
            Write-Verbose "Attempt $attemptCount timed out."
        }
    }

    [PSCustomObject]@{
        PSTypeName = 'IntegrationSample.RetryResult'
        Success = $succeeded
        AttemptCount = $attemptCount
        Value = $value
    }
}


function Invoke-WithCircuitBreaker {
    [CmdletBinding()]
    [OutputType('IntegrationSample.CircuitResult')]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [ValidateRange(1, 10)]
        [int]$FailureThreshold = 3
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $failureCount = 0
    $succeeded = $false
    while (-not $succeeded -and $failureCount -lt $FailureThreshold) {
        try {
            $null = & $ScriptBlock
            $succeeded = $true
        } catch [System.Net.WebException] {
            # A failed request counts towards the threshold that opens the circuit.
            $failureCount++
        }
    }
    $stopwatch.Stop()

    [PSCustomObject]@{
        PSTypeName = 'IntegrationSample.CircuitResult'
        CircuitOpen = -not $succeeded
        FailureCount = $failureCount
        ExecutionTime = $stopwatch.Elapsed
    }
}


function Save-Record {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('IntegrationSample.SaveResult')]
    param(
        [Parameter(Mandatory)]
        [string]$StorePath,

        [Parameter(Mandatory)]
        [hashtable]$Data,

        [string]$Id = [guid]::NewGuid().ToString('N'),

        [string]$ParentId = ''
    )

    $recordPath = Join-Path -Path $StorePath -ChildPath "$Id.json"
    if (-not $PSCmdlet.ShouldProcess($recordPath, 'Save record')) {
        return
    }

    $record = [ordered]@{ id = $Id; parentId = $ParentId; data = $Data }
    $json = ConvertTo-Json -InputObject $record -Depth 5

    # One writer at a time, in this process and in others, so that a record is never half written.
    $mutex = [System.Threading.Mutex]::new($false, 'IntegrationSampleStore')
    $null = $mutex.WaitOne()
    try {
        [System.IO.File]::WriteAllText($recordPath, $json, [System.Text.UTF8Encoding]::new($false))
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }

    [PSCustomObject]@{
        PSTypeName = 'IntegrationSample.SaveResult'
        Success = $true
        RecordId = $Id
    }
}


function Get-Record {
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    [OutputType('IntegrationSample.Record')]
    param(
        [Parameter(Mandatory)]
        [string]$StorePath,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByParent')]
        [string]$ParentId
    )

    $byId = $PSCmdlet.ParameterSetName -eq 'ById'
    $filter = if ($byId) { "$Id.json" } else { '*.json' }
    foreach ($file in Get-ChildItem -LiteralPath $StorePath -Filter $filter -File) {
        $json = Get-Content -LiteralPath $file.FullName -Raw
        $record = ConvertFrom-Json -InputObject $json
        if ($byId -or $record.parentId -eq $ParentId) {
            [PSCustomObject]@{
                PSTypeName = 'IntegrationSample.Record'
                Id = $record.id
                ParentId = $record.parentId
                Data = $record.data
            }
        }
    }
}


function Remove-Record {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$StorePath,

        [Parameter(Mandatory)]
        [string]$Id,

        [switch]$Cascade
    )

    $recordIds = @($Id)
    if ($Cascade) {
        $recordIds = @(
            foreach ($child in Get-Record -StorePath $StorePath -ParentId $Id) {
                $child.Id
            }
            $Id
        )
    }

    foreach ($recordId in $recordIds) {
        $recordPath = Join-Path -Path $StorePath -ChildPath "$recordId.json"
        if ($PSCmdlet.ShouldProcess($recordPath, 'Remove record')) {
            try {
                Remove-Item -LiteralPath $recordPath -ErrorAction Stop
            } catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
        }
    }
}
```

The test file for these functions:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

#pester:no-parallel

BeforeAll {
    $helperPath = Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers'
    $samplePath = Join-Path -Path $helperPath -ChildPath 'IntegrationSample.psm1'
    if (-not (Get-Module -Name IntegrationSample)) {
        Import-Module -Name $samplePath
    }
}

Describe 'Calls to an unreliable service' -Tag 'Integration', 'SystemIntegration' {
    It 'Should retry on transient failures' {
        # The script block fails twice and then answers.
        $calls = @{ Count = 0 }
        $operation = {
            $calls.Count++
            if ($calls.Count -lt 3) {
                throw [System.TimeoutException]::new('The service did not answer.')
            }
            'answer'
        }

        $retryResult = Invoke-WithRetry -ScriptBlock $operation -MaxRetries 3

        $retryResult.Success | Should-BeTrue
        $retryResult.Value | Should-Be 'answer'
        $retryResult.AttemptCount | Should-BeGreaterThan 1
        $retryResult.AttemptCount | Should-BeLessThanOrEqual 3 -Because 'MaxRetries caps the attempts at 3'
    }

    It 'Should circuit break on persistent failures' {
        $calls = @{ Count = 0 }
        $operation = {
            $calls.Count++
            throw [System.Net.WebException]::new('The service cannot be reached.')
        }

        $circuitResult = Invoke-WithCircuitBreaker -ScriptBlock $operation -FailureThreshold 3

        $circuitResult.CircuitOpen | Should-BeTrue
        $calls.Count | Should-Be 3 -Because 'an open circuit stops the calls'
        $circuitResult.ExecutionTime | Should-BeLessThan ([timespan]::FromSeconds(10))
    }
}

Describe 'Data persistence' -Tag 'Integration', 'SystemIntegration' {
    BeforeAll {
        $storePath = Join-Path -Path $TestDrive -ChildPath 'store'
        $null = New-Item -Path $storePath -ItemType Directory
    }

    It 'Should persist data correctly' {
        $testData = @{
            Name = 'IntegrationTest'
            Value = 'TestValue'
            Timestamp = [datetime]::new(2026, 3, 31, 12, 0, 0)
            ComplexData = @{
                NestedProperty = 'NestedValue'
                ArrayProperty = @(1, 2, 3)
            }
        }

        $saveResult = Save-Record -StorePath $storePath -Data $testData
        $saveResult.Success | Should-BeTrue
        $saveResult.RecordId | Should-MatchString '^[0-9a-f]{32}$'

        $record = Get-Record -StorePath $storePath -Id $saveResult.RecordId

        # One deep comparison reports every property that the round trip changed. Timestamp is
        # excluded because storage does not return it unchanged on every edition.
        $expected = [PSCustomObject]@{
            Name = 'IntegrationTest'
            Value = 'TestValue'
            Timestamp = $testData.Timestamp
            ComplexData = [PSCustomObject]@{
                NestedProperty = 'NestedValue'
                ArrayProperty = @(1, 2, 3)
            }
        }
        $record.Data | Should-BeEquivalent $expected -ExcludePath 'Timestamp'
    }

    It 'Should handle concurrent data access' {
        $recordId = 'shared-record'
        $jobScript = {
            param($SamplePath, $StorePath, $RecordId, $WorkerId)

            Import-Module -Name $SamplePath
            Save-Record -StorePath $StorePath -Id $RecordId -Data @{ Value = "Worker$WorkerId" }
        }

        $jobs = foreach ($workerId in 1..5) {
            Start-Job -ScriptBlock $jobScript -ArgumentList $samplePath, $storePath, $recordId, $workerId
        }
        $results = @($jobs | Wait-Job | Receive-Job)
        $jobs | Remove-Job

        # Every writer finished, and the record is the complete record of one of them.
        $results | Should-BeCollection -Count 5
        $record = Get-Record -StorePath $storePath -Id $recordId
        $record.Data.Value | Should-MatchString '^Worker[1-5]$'
    }

    It 'Should maintain referential integrity' {
        $parentId = 'parent-1'
        $null = Save-Record -StorePath $storePath -Id $parentId -Data @{ Name = 'TestParent' }
        foreach ($number in 1..3) {
            $child = @{ Name = "TestChild$number" }
            (Save-Record -StorePath $storePath -ParentId $parentId -Data $child).Success | Should-BeTrue
        }

        # The relationships are stored.
        $children = @(Get-Record -StorePath $storePath -ParentId $parentId)
        $children | Should-BeCollection -Count 3
        $children | Should-All { $_.ParentId -eq $parentId }

        # Removing the parent with -Cascade removes the children.
        Remove-Record -StorePath $storePath -Id $parentId -Cascade -Confirm:$false

        @(Get-Record -StorePath $storePath -ParentId $parentId).Count | Should-Be 0
        Get-Record -StorePath $storePath -Id $parentId | Should-BeNull
    }
}
```

## What The Template Shows

### Real Files Go In The Test Drive

Every file is created under `$TestDrive` (TST-03). Pester creates that folder for the test file and
removes it afterwards, so the tests need no cleanup code and cannot leave files behind. Anything
else that a test changes, such as an environment variable or a record in the service, must be
restored in `AfterAll` or `AfterEach` (TST-31).

A resource that cannot be in `$TestDrive`, such as a working folder that the code under test looks
for in a fixed place, is created in `BeforeAll` and removed in `AfterAll`:

```powershell
BeforeAll {
    # Create the test resources.
    $workFolder = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'IntegrationTests'
    if (-not (Test-Path -LiteralPath $workFolder)) {
        $null = New-Item -Path $workFolder -ItemType Directory
    }
}

AfterAll {
    # Clean up the test resources.
    if (Test-Path -LiteralPath $workFolder) {
        Remove-Item -LiteralPath $workFolder -Recurse -Force
    }
}
```

### A Missing Environment Is Skipped At Discovery

Take the configuration of the test environment from environment variables. `-Skip:` takes a value
that is known during discovery, so it is computed in `BeforeDiscovery`. The tests of a skipped
block are reported as `Skipped`, and the block's `BeforeAll` does not run.

### An Unreachable Service Is Skipped At Run Time

When the address is set, `BeforeAll` verifies once that the service can be reached, and
`BeforeEach` calls `Set-ItResult -Skipped -Because '<reason>'` for every test of the block when it
cannot. Run with an address where nothing listens, the five service tests were reported as
`Skipped` with the connection error as the reason, and the run passed.

A project that wants an outage of a configured service to fail the build leaves out the check.
The tests then fail when the service does not answer, which a skip would hide.

A test can mark itself the same way from the `It` block, with `-Skipped` or `-Inconclusive`.
`Set-ItResult -Pending` was removed in Pester 6.

### Real Services In A Controlled Environment

Use real services in a controlled test environment, and mock only when a real service is not
available. The retry and circuit-breaker tests show the second case: no real service fails on
request, so a script block that fails a set number of times stands in for it.

### Tags

Tag the `Describe` blocks `Integration` and with the category, `EndToEnd` or `SystemIntegration`
(TST-04), so that a run can leave them out with `Filter.ExcludeTag`. In the template the workflow
tests need the service block's setup, so their category tag is on the `Context`.

### Test Cases From The Environment

A `-ForEach` list that is built from configuration is empty when the configuration is missing, and
Pester 6 then stops discovery of the file instead of running no tests. That is usually the right
outcome. The unit test template shows `-AllowNullOrEmptyForEach` for the case where an empty list is
legitimate.

### Whole Objects Are Compared With Should-BeEquivalent

One `Should-BeEquivalent` reports every property that differs after a round trip. `-ExcludePath`
leaves out a value that changes on every run, here `savedAt`, or one that storage does not return
unchanged, here `Timestamp`: on Windows PowerShell 5.1 the JSON round trip returned that time in
UTC, and the comparison failed without the exclusion. `Should-BeEquivalent` does not compare the
order of a collection; add index assertions after a count when order is part of the contract.

### A .NET Failure Arrives Wrapped

`Export-Thing` writes with `[System.IO.File]::WriteAllText()` and passes a failure on with
`$PSCmdlet.ThrowTerminatingError($_)`. `Should-Throw -ExceptionType` compares the outer exception,
which is a `MethodInvocationException`. The test asserts that type and then reads the original
exception from the error record that `Should-Throw` returns.

### Workflows, Partial Failures, And Consistency

The workflow tests run the functions together, as a caller would: read from the service, then write
the file. One test completes the workflow, one injects a failure for part of the input and asserts
that the rest still arrives and the failure is reported, and one compares what the first component
returned with what the last one stored.

### Retry And Circuit Breaker

The retry test asserts that the call succeeded, that more than one attempt was made, and that the
number of attempts stayed within `MaxRetries`. The circuit-breaker test asserts that the circuit is
open, that the calls stopped at the threshold, and that the whole call returned quickly. The time
limit is a `[timespan]` compared with a `[timespan]`.

### Persistence

The persistence tests cover the three things that a store must get right: a record reads back as
it was saved, concurrent writers leave a whole record, and child records stay with their parent
and are removed with it. The concurrency test starts five jobs. A job is a new process, so the
script block receives every path as an argument and imports the module itself.

### The File Does Not Run In Parallel

Integration tests hold shared external resources: a database, a fixed port, a live endpoint. Two
files that touch the same resource at the same time produce failures that are hard to diagnose.
Put the comment `#pester:no-parallel` at the top of every integration test file. It keeps the file
out of the worker runspaces when a run sets `Run.Parallel`; such files run one after another in the
main session. It has no effect otherwise. `Run.Parallel` is experimental and off by default.

A file whose tests touch nothing but their own `$TestDrive` can leave the comment out.

### Both Editions

The file runs unchanged on Windows PowerShell 5.1 because it avoids what differs there:

- Each `Join-Path` call has one child path. `Join-Path 'a' 'b' 'c'` is an error on 5.1; nest the
  calls.
- `$IsWindows` does not exist on 5.1, and reading it under strict mode is an error. Test
  `$PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows`, which reads it only on PowerShell 7.
- The path-separator test builds its path with `Join-Path` and asserts the separator of the
  platform: a backslash on Windows, a slash elsewhere.
- The byte order mark is asserted from the bytes of the file, not from the encoding name, because
  `-Encoding utf8` means different things on the two editions (STY-33).

To limit a test to one edition, pass a discovery-time condition such as
`-Skip:($PSVersionTable.PSEdition -ne 'Core')`.

## Integration Test Guidelines

### Test Environment Setup

- Use environment variables for configuration.
- Create isolated test resources.
- Verify that external services are available.
- Clean up resources after the tests.

### End-to-End Testing

- Test complete business workflows.
- Validate the interactions between components.
- Verify data flow and consistency.
- Test error propagation and recovery.

### External Dependencies

- Use real services in a controlled environment.
- Test connectivity and error handling.
- Validate retry and circuit-breaker patterns.
- Mock only when real services are not available.

### Data Persistence Testing

- Test create, read, update, and delete operations.
- Verify data integrity and consistency.
- Test concurrent access.
- Validate referential integrity.

### Cross-Platform Considerations

- Test on every PowerShell version that the project supports.
- Verify the differences in path handling.
- Test platform-specific features.
- Use conditional test execution.
