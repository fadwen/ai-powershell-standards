# Test Execution Guide

This guide covers how to run tests, how to read the result, and the two experimental run modes,
parallel and shuffled. It supports rules TST-40 to TST-42 in
[powershell-pester.instructions.md](../powershell-pester.instructions.md). The behaviour described
here was checked on Pester 6.2.0 under PowerShell 7.6 and Windows PowerShell 5.1.

Do not use emoji in generated code, in documentation, or in test output. Use plain text and ASCII
characters only.

## Loading the Right Pester Version

A test file declares the minimum version with `#Requires` (TST-01). That line does not choose
between installed versions, and Windows PowerShell 5.1 ships with Pester 3.4.0. Install the version
the standard targets and import exactly that version before a run:

```powershell
Install-PSResource -Name Pester -Version 6.2.0 -TrustRepository
Import-Module -Name Pester -RequiredVersion 6.2.0
```

## Running Tests

```powershell
# Every test file under a folder
Invoke-Pester -Path ./Tests

# One file, listing every test
Invoke-Pester -Path ./Tests/Unit/Get-ServerHealth.Tests.ps1 -Output Detailed

# By tag
Invoke-Pester -Path ./Tests -TagFilter 'Unit'
Invoke-Pester -Path ./Tests -ExcludeTagFilter 'Integration', 'Slow'

# By name, with wildcards
Invoke-Pester -Path ./Tests -FullNameFilter '*Get-ServerHealth*'
```

`-Output` takes `None`, `Normal`, `Detailed`, or `Diagnostic`. It also accepts `Minimal`, which
Pester 6 treats as `Normal`.

For coverage, reports, or any other option, pass a configuration object; see
[Pester Configuration Guide](./pester-configuration.md). To run exactly what CI runs, call the
script that CI calls: the [runner script](#the-test-runner-script) below, or the gate script in
[CI/CD Integration Guide](./cicd-integration.md#the-gate-script).

### Console Output

A run prints one banner, one line for each test file, and one summary:

```text
Running tests from 4 files.
[+] C:\repo\Tests\Unit\Get-ServerHealth.Tests.ps1 638ms (5 tests)
Tests completed in 1.2s
Tests Passed: 20, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
```

A discovery-only run (`Run.SkipRun`) prints `Starting discovery in 4 files.`,
`Discovery found 20 tests in 39ms.`, and `Test run was skipped.` instead.

Do not read results from this text. Set `Run.PassThru` and use the result object.

## The Test Runner Script

Keep one standard script, `Tests/Invoke-Tests.ps1`, so that tests run the same way on every machine
and in CI. It takes the type of test and the environment, loads the configuration files of
[Pester Configuration Guide](./pester-configuration.md#settings-for-each-environment), prints a
summary, writes the reports, and applies the gate.

The script, its helper file, and the settings files are kept in the `Tests` folder, as the layout
in [Pester Test Structure Guide](./test-structure-guide.md#test-directory-layout) shows. A `build`
folder beside `Tests` is the alternative; both are one level below the repository root, so the
script is the same in either.

```powershell
#requires -Version 7.6

<#
.SYNOPSIS
Runs the Pester tests of one type and applies the quality gate.

.DESCRIPTION
Loads the Pester configuration of the environment, selects the tests of the requested type, runs
them, and prints a summary. Writes a test result report and a metrics file, and on request a
coverage report and an HTML report. Throws when no tests ran, when the Pester result is not
'Passed', or when code coverage is below the configured target. With PassThru the result object is
returned and the last two checks are left to the caller.

.PARAMETER TestType
Tests to run: Unit, Integration, Performance, Security, or All.

.PARAMETER Environment
Environment whose configuration file is merged over the standard file.

.PARAMETER OutputPath
Folder that receives the reports. The default is Tests/Results in the repository.

.PARAMETER CodeCoverage
Measures code coverage and applies the coverage gate.

.PARAMETER PassThru
Returns the Pester result object.

.PARAMETER ShowReport
Writes an HTML report of the run.

.PARAMETER Tag
Tags to run in place of the tag of the test type. A test that has any one of the tags runs, and
the folder of the test type still limits the run.

.PARAMETER ExcludeTag
Tags to leave out.

.PARAMETER Parallel
Experimental. Runs test files at the same time. Ignored for performance and integration tests.

.PARAMETER ThrottleLimit
Number of files to run at once in a parallel run. 0 uses every processor.

.PARAMETER Shuffle
Experimental. Runs files, blocks, and tests in a random order. Ignored for performance tests.

.PARAMETER ShuffleSeed
Seed of an earlier shuffled run, to repeat its order. 0 picks a new seed and prints it.

.EXAMPLE
./Tests/Invoke-Tests.ps1 -TestType Unit

Runs the unit tests with the development configuration.

.EXAMPLE
./Tests/Invoke-Tests.ps1 -TestType Unit -Environment CI -CodeCoverage -Shuffle

Runs the unit tests as CI does, in a shuffled order, with the coverage gate.

.INPUTS
None. This script does not accept pipeline input.

.OUTPUTS
None, or the Pester result object when PassThru is given.
#>
[CmdletBinding()]
param(
    [ValidateSet('Unit', 'Integration', 'Performance', 'Security', 'All')]
    [string]$TestType = 'All',

    [ValidateSet('Development', 'CI', 'Production')]
    [string]$Environment = 'Development',

    [string]$OutputPath,

    [switch]$CodeCoverage,

    [switch]$PassThru,

    [switch]$ShowReport,

    [string[]]$Tag = @(),

    [string[]]$ExcludeTag = @(),

    [switch]$Parallel,

    [int]$ThrottleLimit = 0,

    [switch]$Shuffle,

    [int]$ShuffleSeed = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$testRoot = Join-Path -Path $repositoryRoot -ChildPath 'Tests'
if (-not $OutputPath) {
    $OutputPath = Join-Path -Path $testRoot -ChildPath 'Results'
}
$null = New-Item -Path $OutputPath -ItemType Directory -Force

. (Join-Path -Path $PSScriptRoot -ChildPath 'TestRunnerHelpers.ps1')

Write-Host "Test type: $TestType | Environment: $Environment" -ForegroundColor Green

$environmentCheck = Test-TestEnvironment -TestDataPath (Join-Path -Path $testRoot -ChildPath 'TestData')
if (-not $environmentCheck.Valid) {
    throw "The test environment is not ready. $($environmentCheck.Issues -join ' ')"
}
Import-Module -Name Pester -RequiredVersion 6.2.0

$configuration = Get-PesterConfiguration -Environment $Environment -ConfigPath $PSScriptRoot
$configuration.Run.RepoRoot = $repositoryRoot
$configuration.Run.PassThru = $true
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# The tests of the requested type
if ($TestType -eq 'All') {
    # The Performance and Security folders exist only where such tests do (TST-43).
    $configuration.Run.Path = @(
        Get-ChildItem -LiteralPath $testRoot -Directory |
            Where-Object { $_.Name -in 'Unit', 'Integration', 'Performance', 'Security' } |
            ForEach-Object { $_.FullName }
    )
} else {
    $configuration.Run.Path = Join-Path -Path $testRoot -ChildPath $TestType
    $configuration.Filter.Tag = $TestType
}
if ($Tag.Count -gt 0) {
    # Several tags select a test that has any one of them, so these tags replace the tag of the
    # test type. The folder of the type still limits the run.
    $configuration.Filter.Tag = $Tag
}
if ($ExcludeTag.Count -gt 0) {
    $configuration.Filter.ExcludeTag = $ExcludeTag
}

# Code coverage
$configuration.CodeCoverage.Enabled = [bool]$CodeCoverage
if ($CodeCoverage) {
    $coverageFile = "Coverage-$TestType-$timestamp.xml"
    $configuration.CodeCoverage.OutputPath = Join-Path -Path $OutputPath -ChildPath $coverageFile
    Write-Host 'Code coverage enabled (profiler-based)' -ForegroundColor Green
}

# Parallel execution
if ($Parallel) {
    if ($TestType -in 'Performance', 'Integration') {
        Write-Warning "$TestType tests should not run in parallel; ignoring -Parallel."
    } else {
        $configuration.Run.Parallel = $true
        $configuration.Run.ParallelThrottleLimit = $ThrottleLimit
        $limitText = if ($ThrottleLimit -eq 0) { 'all processors' } else { "$ThrottleLimit files" }
        Write-Host "Parallel execution enabled (throttle: $limitText)" -ForegroundColor Green

        if ($CodeCoverage) {
            # A parallel run collects coverage, but with breakpoints instead of the profiler.
            Write-Warning 'Coverage in a parallel run uses breakpoints, not the profiler.'
        }
    }
}

# Shuffled order
if ($Shuffle) {
    if ($TestType -eq 'Performance') {
        Write-Warning 'Performance baselines assume a fixed order; ignoring -Shuffle.'
    } else {
        $configuration.Run.Shuffle = $true
        if ($ShuffleSeed -ne 0) {
            $configuration.Run.ShuffleSeed = $ShuffleSeed
            Write-Host "Shuffled execution replaying seed $ShuffleSeed" -ForegroundColor Green
        } else {
            Write-Host 'Shuffled execution enabled (the seed is printed below)' -ForegroundColor Green
        }
    }
}

# Test result report, with the type and the time in its name
$resultFile = "TestResults-$TestType-$timestamp.xml"
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputPath = Join-Path -Path $OutputPath -ChildPath $resultFile

# Verbosity for the environment
if ($Environment -eq 'CI') {
    $configuration.Output.Verbosity = 'Normal'
} else {
    $configuration.Output.Verbosity = 'Detailed'
}

# The relative paths of the configuration files are resolved from the repository root.
Push-Location -LiteralPath $repositoryRoot
try {
    $configurationCheck = Test-PesterConfiguration -Configuration $configuration
    if (-not $configurationCheck.Valid) {
        throw "The Pester configuration is not valid. $($configurationCheck.Issues -join ' ')"
    }

    $startTime = Get-Date
    Write-Host "Test execution started at $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    $result = Invoke-Pester -Configuration $configuration
    $duration = (Get-Date) - $startTime
} finally {
    Pop-Location
}

if ($null -eq $result -or $result.TotalCount -eq 0) {
    throw 'Pester ran no tests.'
}

# Summary
$failedColor = if ($result.FailedCount -gt 0) { 'Red' } else { 'Green' }
Write-Host ''
Write-Host 'Test Execution Summary:' -ForegroundColor Green
Write-Host "  Environment:  $Environment"
Write-Host "  Test type:    $TestType"
Write-Host "  Duration:     $($duration.ToString('hh\:mm\:ss'))"
Write-Host "  Total tests:  $($result.TotalCount)"
Write-Host "  Passed:       $($result.PassedCount)" -ForegroundColor Green
Write-Host "  Failed:       $($result.FailedCount)" -ForegroundColor $failedColor
Write-Host "  Skipped:      $($result.SkippedCount)" -ForegroundColor Yellow
Write-Host "  Inconclusive: $($result.InconclusiveCount)" -ForegroundColor Yellow
Write-Host "  Not run:      $($result.NotRunCount)"

# Coverage summary. The names are CoveragePercent, CommandsExecutedCount, and
# CommandsAnalyzedCount. The Pester 4 names CoveredPercent and NumberOfCommandsExecuted do not
# exist.
$coveragePercent = $null
if ($CodeCoverage -and $null -ne $result.CodeCoverage) {
    $coveragePercent = [math]::Round($result.CodeCoverage.CoveragePercent, 2)
    $coverageTarget = $result.CodeCoverage.CoveragePercentTarget
    $coverageColor = if ($coveragePercent -ge $coverageTarget) {
        'Green'
    } elseif ($coveragePercent -ge ($coverageTarget * 0.75)) {
        'Yellow'
    } else {
        'Red'
    }
    Write-Host "  Code Coverage: $coveragePercent% (target $coverageTarget%)" -ForegroundColor $coverageColor
    Write-Host "    Commands covered: $($result.CodeCoverage.CommandsExecutedCount)"
    Write-Host "    Commands total:   $($result.CodeCoverage.CommandsAnalyzedCount)"
    Write-Host "    Files analyzed:   $($result.CodeCoverage.FilesAnalyzedCount)"
}

# Performance summary. The Duration of a test is a TimeSpan: use TotalMilliseconds, not the
# object itself.
if ($TestType -in 'Performance', 'All') {
    $performanceRoot = Join-Path -Path $testRoot -ChildPath 'Performance'
    $performanceTests = @(
        $result.Tests | Where-Object {
            $_.ScriptBlock.File.StartsWith($performanceRoot, [System.StringComparison]::OrdinalIgnoreCase)
        }
    )
    if ($performanceTests.Count -gt 0) {
        $averageMs = ($performanceTests.Duration.TotalMilliseconds | Measure-Object -Average).Average
        Write-Host ''
        Write-Host 'Performance Summary:' -ForegroundColor Cyan
        Write-Host "  Average test duration: $([math]::Round($averageMs, 2))ms"

        $slowTests = $performanceTests |
            Where-Object { $_.Duration.TotalSeconds -gt 5 } |
            Sort-Object -Property Duration -Descending
        foreach ($slowTest in $slowTests) {
            $seconds = [math]::Round($slowTest.Duration.TotalSeconds, 2)
            Write-Host "  Slow test (over 5 s): $($slowTest.ExpandedPath): ${seconds}s" -ForegroundColor Yellow
        }
    }
}

# Failed tests, each with its error and a hint
if ($result.FailedCount -gt 0) {
    Write-Host ''
    Write-Host 'Failed tests:' -ForegroundColor Red
    foreach ($test in $result.Failed) {
        $testError = $test.ErrorRecord[0]
        Write-Host "  - $($test.ExpandedPath)" -ForegroundColor Red
        Write-Host "    Error: $($testError.Exception.Message)" -ForegroundColor Red

        $hint = Get-TroubleshootingHint -TestName $test.Name -ErrorRecord $testError
        if ($hint) {
            Write-Host "    Hint: $hint" -ForegroundColor Cyan
        }
    }
}

# Files that failed discovery or setup. Such a file adds nothing to FailedCount, so a suite can
# report 0 failed tests while whole files never ran.
if ($result.FailedContainersCount -gt 0) {
    Write-Host ''
    Write-Host 'Failed files (discovery or setup errors):' -ForegroundColor Red
    foreach ($container in $result.FailedContainers) {
        Write-Host "  - $($container.Item)" -ForegroundColor Red
        foreach ($containerError in $container.ErrorRecord) {
            Write-Host "    $($containerError.Exception.Message)" -ForegroundColor Red
        }
    }
}

# HTML report
if ($ShowReport) {
    $reportPath = Join-Path -Path $OutputPath -ChildPath "TestReport-$TestType-$timestamp.html"
    New-TestReport -TestResult $result -OutputPath $reportPath -CodeCoverage:$CodeCoverage
    Write-Host "Test report written: $reportPath" -ForegroundColor Green
}

# Metrics for trending. The seed is recorded because a shuffled failure can be repeated only
# while the seed outlives the console log.
$metrics = [ordered]@{
    TestType = $TestType
    Environment = $Environment
    Timestamp = Get-Date -Format 'o'
    Duration = $duration.TotalSeconds
    TotalTests = $result.TotalCount
    PassedTests = $result.PassedCount
    FailedTests = $result.FailedCount
    SkippedTests = $result.SkippedCount
    CodeCoverage = $coveragePercent
    Parallel = [bool]$configuration.Run.Parallel.Value
    Shuffle = [bool]$configuration.Run.Shuffle.Value
    ShuffleSeed = $result.Configuration.Run.ShuffleSeed.Value
    PesterVersion = (Get-Module -Name Pester).Version.ToString()
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    Platform = [System.Environment]::OSVersion.Platform.ToString()
}
$metricsPath = Join-Path -Path $OutputPath -ChildPath "TestMetrics-$TestType-$timestamp.json"
$metrics | ConvertTo-Json | Set-Content -LiteralPath $metricsPath -Encoding utf8

if ($Environment -eq 'CI') {
    # GitHub Actions step outputs. The ::set-output command is deprecated and the runner warns: write
    # to the file that GITHUB_OUTPUT names.
    if ($env:GITHUB_OUTPUT) {
        $outputLines = @(
            "total-tests=$($result.TotalCount)"
            "passed-tests=$($result.PassedCount)"
            "failed-tests=$($result.FailedCount)"
            if ($null -ne $coveragePercent) {
                "code-coverage=$coveragePercent"
            }
        )
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value $outputLines -Encoding utf8
    }

    # GitHub Actions job summary
    if ($env:GITHUB_STEP_SUMMARY) {
        $summaryLines = @(
            "## Test Results - $TestType"
            ''
            '| Metric | Value |'
            '| --- | --- |'
            "| Total | $($result.TotalCount) |"
            "| Passed | $($result.PassedCount) |"
            "| Failed | $($result.FailedCount) |"
            "| Skipped | $($result.SkippedCount) |"
            if ($null -ne $coveragePercent) {
                "| Code coverage | $coveragePercent% (target $coverageTarget%) |"
            }
            ''
        )
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summaryLines -Encoding utf8
    }

    # Azure Pipelines variables
    if ($env:BUILD_BUILDID) {
        Write-Host "##vso[task.setvariable variable=TotalTests]$($result.TotalCount)"
        Write-Host "##vso[task.setvariable variable=PassedTests]$($result.PassedCount)"
        Write-Host "##vso[task.setvariable variable=FailedTests]$($result.FailedCount)"
        if ($null -ne $coveragePercent) {
            Write-Host "##vso[task.setvariable variable=CodeCoverage]$coveragePercent"
        }
    }
}

if ($PassThru) {
    $result
    return
}

# The gate. Result also covers a failed BeforeAll or AfterAll and a file that failed discovery.
if ($result.Result -ne 'Passed') {
    $counts = $result.FailedCount, $result.FailedBlocksCount, $result.FailedContainersCount
    $summary = 'Failed tests: {0}. Failed blocks: {1}. Failed files: {2}.' -f $counts
    if ($configuration.Run.Shuffle.Value) {
        $seed = $result.Configuration.Run.ShuffleSeed.Value
        $summary = "$summary Replay with Run.ShuffleSeed = $seed."
    }
    throw "Pester result is '$($result.Result)'. $summary"
}

# CoveragePercentTarget sets the reported target and does not fail the run, so the script
# compares the figure and lists the uncovered commands for each file.
if ($null -ne $coveragePercent -and $coveragePercent -lt $coverageTarget) {
    Write-Host 'Uncovered commands:'
    foreach ($file in $result.CodeCoverage.CommandsMissed | Group-Object -Property File) {
        Write-Host "  $($file.Name): $($file.Count) command(s)"
        if ($env:GITHUB_ACTIONS) {
            Write-Host "::warning file=$($file.Name)::$($file.Count) uncovered command(s)"
        }
    }
    throw "Code coverage is $coveragePercent percent. The target is $coverageTarget."
}

Write-Host 'All tests passed.' -ForegroundColor Green
```

Notes on the script:

- It fails by throwing (CIC-05), and the gate tests `Result`, not `FailedCount` alone (TST-42).
- `-Tag` replaces the tag of the test type, because several tags select a test that has any one of
  them and adding a tag would widen the run. The folder of the type still limits it, so
  `-TestType Unit -Tag CrossPlatform` runs the tests under `Tests/Unit` that are tagged
  `CrossPlatform`. Use `-ExcludeTag` to narrow a selection further.
- Every report has the test type and the time in its name, in `Tests/Results`, so that runs do not
  overwrite each other and one artifact pattern collects them: `Tests/Results/TestResults*.xml`,
  `Tests/Results/Coverage*.xml`, and `Tests/Results/TestMetrics*.json`. Do not commit the folder.
- `Run.Parallel` and `Run.Shuffle` are experimental. The script turns them on only when the caller
  passes the switch.
- The script targets PowerShell 7.6. For a project that declares Windows PowerShell 5.1 support,
  change the first line to `#requires -Version 5.1`. The script and its helper functions were run
  under Windows PowerShell 5.1 with that line, with and without `-Parallel`.

### Quick Commands

```powershell
# Unit tests during development
./Tests/Invoke-Tests.ps1 -TestType Unit -Environment Development

# Unit tests with coverage and an HTML report
./Tests/Invoke-Tests.ps1 -TestType Unit -CodeCoverage -ShowReport

# Tests with a tag, leaving out the slow ones
./Tests/Invoke-Tests.ps1 -Tag 'Critical' -ExcludeTag 'Slow'

# Fast feedback: unit tests in parallel, without coverage
./Tests/Invoke-Tests.ps1 -TestType Unit -Parallel

# Find order dependence, then repeat the order that failed
./Tests/Invoke-Tests.ps1 -TestType Unit -Shuffle
./Tests/Invoke-Tests.ps1 -TestType Unit -Shuffle -ShuffleSeed 852659930

# What CI runs
./Tests/Invoke-Tests.ps1 -TestType All -Environment CI -CodeCoverage
./Tests/Invoke-Tests.ps1 -TestType Performance -Environment CI
./Tests/Invoke-Tests.ps1 -TestType Security -Environment CI
```

### Checking the Environment First

The runner validates the environment before it loads Pester: the PowerShell version, the pinned
Pester version, and the test data folder. The configuration is validated by
`Test-PesterConfiguration`; see
[Pester Configuration Guide](./pester-configuration.md#validating-a-configuration-before-the-run).

```powershell
# Tests/TestRunnerHelpers.ps1
function Test-TestEnvironment {
    [CmdletBinding()]
    [OutputType('TestRunner.Check')]
    param(
        [string]$TestDataPath
    )

    $psVersion = $PSVersionTable.PSVersion
    $pesterVersions = @((Get-Module -Name Pester -ListAvailable).Version)

    $issues = @(
        # Pester 6 runs on Windows PowerShell 5.1 and on PowerShell 7.4 or later.
        if ($psVersion.Major -eq 5 -and $psVersion.Minor -lt 1) {
            "Windows PowerShell 5.1 is required (found $psVersion)."
        } elseif ($psVersion.Major -eq 6 -or ($psVersion.Major -eq 7 -and $psVersion.Minor -lt 4)) {
            "PowerShell 7.4 or later is required (found $psVersion)."
        }

        if ($pesterVersions.Count -eq 0) {
            'Required module missing: Pester.'
        } elseif ($pesterVersions -notcontains [version]'6.2.0') {
            "Pester 6.2.0 is required (found $($pesterVersions -join ', '))."
        }

        if ($TestDataPath -and -not (Test-Path -LiteralPath $TestDataPath)) {
            "Test data folder missing: $TestDataPath"
        }
    )

    [PSCustomObject]@{
        PSTypeName = 'TestRunner.Check'
        Valid = $issues.Count -eq 0
        Issues = $issues
    }
}
```

### Failure Hints

For each failed test the runner prints the error and, where the message is a known one, a hint. Add
the messages that a project meets often.

```powershell
# Tests/TestRunnerHelpers.ps1
function Get-TroubleshootingHint {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$TestName,

        # Not named $Error: that name belongs to an automatic variable (STY-13).
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $hints = [ordered]@{
        'Connection' = 'Check network connectivity and firewall settings.'
        'Authentication' = 'Verify credentials and permissions.'
        'Permission' = 'Run as administrator or check file permissions.'
        'Memory' = 'Increase available memory or optimize the code.'
        'Timeout' = 'Increase timeout values or optimize performance.'
        'not recognized' = 'Command not found. In Pester 6 each test file imports its own modules.'
        'ForEach' = 'An empty -ForEach fails discovery in Pester 6. Build test data in BeforeDiscovery.'
        'Assert-Mock' = 'Assert-MockCalled was removed in Pester 6. Use Should -Invoke or Should-Invoke.'
        'to measure or a' = 'Pipe the script block, not its result, to Should-BeFasterThan.'
    }

    $message = $ErrorRecord.Exception.Message
    foreach ($keyword in $hints.Keys) {
        $pattern = [regex]::Escape($keyword)
        if ($message -match $pattern -or $TestName -match $pattern) {
            return $hints[$keyword]
        }
    }
}
```

The Pester messages behind the last four hints are explained under
[Messages and Their Causes](#messages-and-their-causes).

### HTML Report

`-ShowReport` writes an HTML report of the run. Test names and error messages often contain `<`,
`>`, and `&`, which corrupt the report unless they are encoded.

```powershell
# Tests/TestRunnerHelpers.ps1
function New-TestReport {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object]$TestResult,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [switch]$CodeCoverage
    )

    $rows = foreach ($test in $TestResult.Tests) {
        $rowClass = switch ($test.Result) {
            'Passed' { 'test-passed' }
            'Failed' { 'test-failed' }
            default { '' }
        }
        $name = [System.Net.WebUtility]::HtmlEncode($test.ExpandedPath)
        $message = ''
        if ($test.ErrorRecord.Count -gt 0) {
            $message = [System.Net.WebUtility]::HtmlEncode($test.ErrorRecord[0].Exception.Message)
        }
        $milliseconds = [math]::Round($test.Duration.TotalMilliseconds, 2)

        $rowFormat = '        <tr class="{0}"><td>{1}</td><td>{2}</td><td>{3}ms</td><td>{4}</td></tr>'
        $rowFormat -f $rowClass, $name, $test.Result, $milliseconds, $message
    }

    $coverageRow = ''
    if ($CodeCoverage -and $null -ne $TestResult.CodeCoverage) {
        $percent = [math]::Round($TestResult.CodeCoverage.CoveragePercent, 2)
        $coverageRow = "<p><strong>Code Coverage:</strong> $percent%</p>"
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>PowerShell Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .summary { background: #f0f0f0; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .test-failed { background-color: #ffebee; }
        .test-passed { background-color: #e8f5e8; }
    </style>
</head>
<body>
    <h1>PowerShell Test Report</h1>
    <div class="summary">
        <h2>Summary</h2>
        <p><strong>Total Tests:</strong> $($TestResult.TotalCount)</p>
        <p><strong>Passed:</strong> $($TestResult.PassedCount)</p>
        <p><strong>Failed:</strong> $($TestResult.FailedCount)</p>
        <p><strong>Skipped:</strong> $($TestResult.SkippedCount)</p>
        <p><strong>Duration:</strong> $($TestResult.Duration)</p>
        $coverageRow
    </div>
    <h2>Test Results</h2>
    <table>
        <tr><th>Test Name</th><th>Result</th><th>Duration</th><th>Error Message</th></tr>
$($rows -join [Environment]::NewLine)
    </table>
</body>
</html>
"@

    if ($PSCmdlet.ShouldProcess($OutputPath, 'Write the HTML test report')) {
        try {
            Set-Content -LiteralPath $OutputPath -Value $html -Encoding utf8 -ErrorAction Stop
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
```

The function encodes with `[System.Net.WebUtility]::HtmlEncode`, which needs no assembly to be
loaded. `[System.Web.HttpUtility]::HtmlEncode` gives the same text but, measured on Windows
PowerShell 5.1, fails with `Unable to find type [System.Web.HttpUtility]` until
`Add-Type -AssemblyName System.Web` has run. On PowerShell 7.6 it worked without that line.

### Metrics for Trending

Each run writes its counts, the seed, and the versions to `TestMetrics-<type>-<time>.json`. Keep the
files as build artifacts and read them back to see a trend:

```powershell
# Tests/TestRunnerHelpers.ps1
function Get-TestTrend {
    [CmdletBinding()]
    [OutputType('TestRunner.Metrics')]
    param(
        [Parameter(Mandatory)]
        [string]$ResultsPath
    )

    try {
        $files = Get-ChildItem -LiteralPath $ResultsPath -Filter 'TestMetrics-*.json' -File -ErrorAction Stop
        $entries = foreach ($file in $files) {
            Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    foreach ($entry in $entries | Sort-Object -Property Timestamp) {
        $entry.PSObject.TypeNames.Insert(0, 'TestRunner.Metrics')
        $entry
    }
}
```

### Outputs for the CI System

With `-Environment CI` the runner publishes the counts to the CI system that it finds:

| CI system | How the runner knows | What it writes |
| --- | --- | --- |
| GitHub Actions | `GITHUB_OUTPUT` is set | Step outputs `total-tests`, `passed-tests`, `failed-tests`, and `code-coverage`, appended to the file that the variable names |
| GitHub Actions | `GITHUB_STEP_SUMMARY` is set | A Markdown table of the counts, shown as the job summary |
| Azure Pipelines | `BUILD_BUILDID` is set | The variables `TotalTests`, `PassedTests`, `FailedTests`, and `CodeCoverage`, with `##vso[task.setvariable]` |

Do not use the `::set-output` workflow command for step outputs. GitHub deprecated it in 2022; the
file that `GITHUB_OUTPUT` names replaces it. These three behaviours belong to the CI services and
were not run there; writing the two files was run locally with the variables pointing at temporary
files.

### Cleaning Up After a Run

Tests write their files to `$TestDrive`, which Pester removes (TST-03), and such tests need no
cleanup. For a suite that still leaves files behind, in the temporary folder or as a temporary
database, run a cleanup function after the tests:

```powershell
# Tests/TestRunnerHelpers.ps1
function Clear-TestArtifact {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$TempPath = [System.IO.Path]::GetTempPath(),

        [string]$DatabasePath
    )

    $leftovers = @(
        Get-ChildItem -LiteralPath $TempPath -Filter 'PesterTest*' -Force
        if ($DatabasePath -and (Test-Path -LiteralPath $DatabasePath)) {
            Get-Item -LiteralPath $DatabasePath
        }
    )

    foreach ($leftover in $leftovers) {
        if ($PSCmdlet.ShouldProcess($leftover.FullName, 'Remove the test artifact')) {
            try {
                Remove-Item -LiteralPath $leftover.FullName -Recurse -Force -ErrorAction Stop
            } catch {
                $PSCmdlet.WriteError($_)
            }
        }
    }
}
```

```powershell
$databasePath = Join-Path -Path $testRoot -ChildPath 'TestData/temp.db'
Clear-TestArtifact -DatabasePath $databasePath -Confirm:$false
```

## Result Object Reference

`Invoke-Pester` returns the result object when `Run.PassThru` is set, or with `-PassThru`.

| Use | Property |
| --- | --- |
| Outcome of the run | `Result`: the string `Passed` or `Failed` |
| Counts | `TotalCount`, `PassedCount`, `FailedCount`, `SkippedCount`, `InconclusiveCount`, `NotRunCount` |
| Failures outside tests | `FailedBlocksCount`, `FailedContainersCount` |
| Tests | `Tests`, `Passed`, `Failed`, `Skipped`, `Inconclusive`, `NotRun` |
| Failed setup or teardown blocks | `FailedBlocks` |
| Test files | `Containers`. Each has `Item`, `Result`, `Passed`, `ErrorRecord`, and `BeforeContainerFile`. |
| Test files that failed | `FailedContainers` |
| Coverage percentage | `CodeCoverage.CoveragePercent` |
| Coverage counts | `CodeCoverage.CommandsAnalyzedCount`, `CommandsExecutedCount`, `CommandsMissedCount`, `FilesAnalyzedCount` |
| Commands that did not run | `CodeCoverage.CommandsMissed`. Each has `File`, `Line`, and `Command`. |
| Coverage target | `CodeCoverage.CoveragePercentTarget` |
| Time | `Duration` on the run, on each file, and on each test. It is a `TimeSpan`. |
| Settings the run used | `Configuration` |

`CodeCoverage` is `$null` when coverage was not measured. The Pester 4 names `CoveredPercent`,
`NumberOfCommandsExecuted`, and `NumberOfCommandsAnalyzed` do not exist.

`Duration` is a `TimeSpan`, so compare `$test.Duration.TotalMilliseconds` with a number, not
`$test.Duration` itself. The console shows one duration for each test, where Pester 5 printed the
user and framework times separately. The result object also has `UserDuration` and
`FrameworkDuration`.

A tag on a `Describe` or `Context` block is not copied to the `Tag` property of the tests inside
it. Measured on 6.2.0, a test in a block tagged `Performance` has an empty `Tag`, and the tag is on
`$test.Block.Tag`.

### What a Failure Looks Like

A failed run does not always have a failed test. Measured on Pester 6.2.0:

| What happened | `Result` | `FailedCount` | `FailedBlocksCount` | `FailedContainersCount` |
| --- | --- | --- | --- | --- |
| Two tests fail | `Failed` | 2 | 0 | 0 |
| `BeforeAll` throws in a block with one test | `Failed` | 1 | 1 | 0 |
| `AfterAll` throws after the tests passed | `Failed` | 0 | 1 | 0 |
| A file throws during discovery | `Failed` | 0 | 0 | 1 |
| `-ForEach` receives an empty list | `Failed` | 0 | 0 | 1 |
| A file contains no tests | `Passed` | 0 | 0 | 0 |

When no test file is found at all, `Invoke-Pester` writes an error, returns no result object, and
sets `$LASTEXITCODE` to `-1`.

This is why the gate tests for a missing result, for `TotalCount`, and for `Result`, and never for
`FailedCount` alone (TST-42):

```powershell
if ($null -eq $result -or $result.TotalCount -eq 0) {
    throw 'Pester ran no tests.'
}

if ($result.Result -ne 'Passed') {
    $counts = $result.FailedCount, $result.FailedBlocksCount, $result.FailedContainersCount
    $summary = 'Failed tests: {0}. Failed blocks: {1}. Failed files: {2}.' -f $counts
    throw "Pester result is '$($result.Result)'. $summary"
}
```

### Messages and Their Causes

| Message | Cause |
| --- | --- |
| `Value can not be null or empty array` | A `-ForEach` list is empty or `$null`, usually because it was built in `BeforeAll`. Build it in `BeforeDiscovery`. |
| `No mock for command '...' matched the call` | Every mock of the command has a `-ParameterFilter` and none matched. Add a mock without a filter. |
| `A parameter cannot be found that matches parameter name 'Focus'` | `-Focus` does not exist in Pester 6. |
| `Pester Should -Be syntax is disabled` | `Should.DisableV5` is set and the file uses the `Should -Be` style. |
| `Expected a [scriptblock] to measure or a [timespan] to compare` | `Should-BeFasterThan` or `Should-BeSlowerThan` received something else. Pipe the script block. |
| `No test files were found and no scriptblocks were provided` | `Run.Path` points at a folder without test files, or `Run.ExcludePath` removed them all. |
| `CommandNotFoundException` for a helper function | The helper was dot-sourced by another test file, or at the top level of a setup file. |

## Checking Structure Without Running Tests

`Run.SkipRun` discovers every file and runs nothing. Use it to find files that fail discovery, and
with `Filter.Tag = 'None'` to find tests without a tag. Both scripts are in
[Pester Test Structure Guide](./test-structure-guide.md#checking-the-structure).

Run the discovery-only check as the first CI step. A discovery failure is cheap to find there and
confusing to diagnose inside a full run.

## Parallel Test Execution

`Run.Parallel` is experimental and off by default. Do not enable it in a configuration that you
generate unless the user asks.

With the option on, Pester runs test files at the same time, each file in its own runspace of the
same process. It works on PowerShell 7 and on Windows PowerShell 5.1. In the examples, `$testRoot`
holds the full path of the test folder.

```powershell
$configuration = New-PesterConfiguration
$configuration.Run.Path = $testRoot
$configuration.Run.Parallel = $true
$configuration.Run.ParallelThrottleLimit = 4

Invoke-Pester -Configuration $configuration
```

`Run.ParallelThrottleLimit` is the number of files that run at once. The default `0` uses every
processor. `1` does not turn the mode off: the files still run in worker runspaces, one after
another.

Each worker runs silently, and the calling session then replays the output of every file in
discovery order. Console output, the `TestResult` report, and IDE integration therefore behave as
they do in a sequential run; only the concurrency differs. Measured on 6.2.0 with three files:
apart from the durations, the console output of the two runs differed only in the banner, which
reads `Running tests from 3 files in parallel.`, and the NUnit reports differed only in their times
and in the attribute order of the `environment` element. IDE integration was not tested.

In the result object the files are in the same order as in a sequential run. The `Duration` of the
run is the elapsed time, not the sum of the files, and `UserDuration`, `FrameworkDuration`, and
`DiscoveryDuration` of the run are zero. Each file still has its own values.

### When Pester Runs Sequentially Instead

| Condition | What Pester does |
| --- | --- |
| A script block container is used (`Run.ScriptBlock`, or `New-PesterContainer -ScriptBlock`) | Warns `Run.Parallel currently parallelizes only file-based runs` and runs sequentially. |
| `Run.SkipRemainingOnFailure = 'Run'` | Warns that skipping after the first failure cannot span the worker runspaces, and runs sequentially. |
| Every file has the `#pester:no-parallel` directive | Runs sequentially without a warning. |

A file passed with `New-PesterContainer -Path`, with or without `-Data`, runs in parallel.

### Which Files to Opt Out

A file that cannot share the machine with other tests starts with the `#pester:no-parallel`
directive:

```powershell
#pester:no-parallel
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

Describe 'Service restart' -Tag 'Integration' {
}
```

Pester runs such files one after another in the calling session, after the parallel batch has
finished. There they share the session state of the caller and write their output as they run.
Measured on 6.2.0: an opted-out file read a global variable and a function of the calling session,
and a value that an earlier opted-out file had left; a file in a worker saw none of them. Opt out:

- tests that use a fixed port, a shared database, or another resource that exists once
- tests that change process-wide state, such as an environment variable or the current location
- tests that measure time

### Coverage in a Parallel Run

Coverage is collected in a parallel run: each worker measures its file and Pester merges the
results into one report. Measured on 6.2.0, the percentage equals that of a sequential run.

A parallel run always measures with breakpoints, even when `CodeCoverage.UseBreakpoints` is
`$false`, because the profiler-based tracer cannot run in several runspaces at once. Breakpoints
are usually described as the slower method, so a parallel run with coverage is not necessarily
faster than a sequential one. Measure both before choosing; one measurement of the two methods is
in [Pester Configuration Guide](./pester-configuration.md#profiler-and-breakpoints).

Splitting CI into two jobs is still the recommendation: a fast parallel job without coverage for
feedback, and a sequential job with the profiler for the coverage gate. It is a performance choice
that can be measured, not a hard requirement. The jobs are shown in
[CI/CD Integration Guide](./cicd-integration.md#parallel-runs-and-coverage-in-ci).

### A Lost File Is an Error

A worker that ends without returning a result fails the run. Measured on 6.2.0 with four files, one
of which stops its worker because its top-level code throws a `PipelineStoppedException`: Pester
writes the error of the worker, collects the other workers, and then fails with this message.

```text
Parallel run lost the results of 1 of 4 file(s), the worker(s) running them did not return a
result. See the errors above for why. Lost: C:\repo\Tests\Unit\Bad.Tests.ps1
```

`Invoke-Pester` returns no result object, which the gate treats as a failure. The outcome is the
same when the caller runs with `$ErrorActionPreference = 'Stop'`: the error of the worker is
written as a non-terminating error, so the run does not end before the lost file is named.

Before 6.2 such a file disappeared. Measured on 6.1.0 with the same files: with the default error
preference the run returned `Passed` with three files and three tests, one file fewer than it was
given, and nothing in the result showed it. With `$ErrorActionPreference = 'Stop'` the run ended at
the error of the worker, `The pipeline has been stopped`, without naming a file.

### Before Enabling Parallel Runs

Each worker starts with an empty runspace. A test file that relies on a module, a variable, or a
helper that another test file loaded fails in a parallel run. Check first that each file passes when
it is run alone, and put shared helpers in a setup file; see
[Pester Test Structure Guide](./test-structure-guide.md#shared-setup-files).

## Shuffled Test Order

`Run.Shuffle` is experimental and off by default. Turn it on for the unit tests in CI, with the
seed in the failure message (TST-46). It is what keeps importing the module once for each run
(TST-05) safe.

With the option on, Pester changes the order of the test files, of the blocks in each file, and of
the tests in each block. A test stays inside its `Context`, and a `Context` stays inside its
`Describe`. A suite that depends on the declared order then fails, which exposes a breach of
TST-31.

```powershell
$configuration = New-PesterConfiguration
$configuration.Run.Path = $testRoot
$configuration.Run.PassThru = $true
$configuration.Run.Shuffle = $true

$result = Invoke-Pester -Configuration $configuration
```

The run prints the seed that it used, and the result object holds it:

```text
Shuffling execution order using seed 314796220. Set 'Run.ShuffleSeed = 314796220' to repeat this order.
```

```powershell
$seed = $result.Configuration.Run.ShuffleSeed.Value
```

`Run.ShuffleSeed` is `0` by default, which picks a new seed for each run. Setting it to the seed of
an earlier run repeats that order exactly:

```powershell
$configuration.Run.ShuffleSeed = 314796220
```

The option changes only the order. It does not change which tests run or how filters apply.

Do not shuffle performance tests. A performance baseline assumes a fixed order, so the runner
script ignores `-Shuffle` for them.

### When a Test Fails Only in a Shuffled Run

A failure that appears only in a shuffled run is a defect in the tests, not in Pester. Each file is
discovered and run on its own, so most of the order dependence that is left is inside a file: a
`Describe` block that leaves a `$script:` variable that another one reads, or a `BeforeAll` that
creates a fixture that a later `Context` changes. State in module scope still crosses files when
the module is imported once for each run (TST-05).

1. Record the seed from the output or from the result object. Without it the order cannot be
   repeated.
2. Run again with `Run.ShuffleSeed` set to that value and confirm that the failure repeats.
3. Find the state that the tests share. It is usually a `$script:` variable, a file outside
   `$TestDrive`, an environment variable, or a mock whose calls are counted across blocks.
4. Correct the test, not the order: move the setup into the block that needs it, or restore the
   state in `AfterEach`.

A file whose blocks must run in the declared order starts with the `#pester:no-shuffle` directive.
Its blocks and tests then keep their order:

```powershell
#pester:no-shuffle
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

Describe 'Database migration steps' -Tag 'Integration' {
}
```

The directive states that the file depends on its order. That is acceptable for an integration
scenario that is written as a sequence of steps, and it is a defect in a unit test file.
