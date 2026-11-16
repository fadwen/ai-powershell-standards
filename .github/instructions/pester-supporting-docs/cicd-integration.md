# CI/CD Integration Guide

This guide shows how to run Pester in a pipeline so that the build fails when it should. It supports
the CI rules in [powershell-cicd.instructions.md](../powershell-cicd.instructions.md) and rules
TST-40 to TST-42 in [powershell-pester.instructions.md](../powershell-pester.instructions.md).

The gate script was run on Pester 6.2.0 under PowerShell 7.6 and Windows PowerShell 5.1. The
pipeline definitions are well-formed, and the GitHub Actions and Azure Pipelines keywords were
checked against their documentation, but none of the pipelines was run on a CI service.

## What the Pipeline Must Do

- Install PSScriptAnalyzer and Pester at fixed versions (CIC-02).
- Run both on every pull request, and fail when either reports a problem (CIC-01).
- Fail when no tests ran, when the Pester result is not `Passed`, and when coverage is below
  80 percent (TST-40, TST-42).
- Run on PowerShell 7.6. Add a Windows PowerShell 5.1 job only when the project declares 5.1 support
  (CIC-03).
- Leave out every PowerShell version that is past its end-of-support date (CIC-04). PowerShell 7.4
  and 7.5 reached it on 10-Nov-2026; see
  [powershell-version.instructions.md](../powershell-version.instructions.md).

Three facts about Pester 6.2.0 shape the gate:

1. A failed run does not always have a failed test. A failing `AfterAll` leaves `FailedCount` at 0
   and sets `FailedBlocksCount`. A file that fails discovery sets only `FailedContainersCount`. The
   property that covers every case is `Result`. The table is in
   [Test Execution Guide](./test-execution.md#what-a-failure-looks-like).
2. A run whose files contain no tests has the result `Passed`, and a run that finds no test file
   returns nothing. The gate therefore tests for `$null` and for `TotalCount`.
3. `CodeCoverage.CoveragePercentTarget` does not fail a run. The script compares the percentage.

## The Gate Script

Keep the logic in one script that the pipeline and a developer both call. The test folder is held in
one place, the `TestRoot` parameter.

```powershell
#requires -Version 7.6

<#
.SYNOPSIS
Runs the Pester tests and fails when the quality gate is not met.

.DESCRIPTION
Runs every test under the test root with code coverage, and writes a test result report and a
coverage report. Throws when no tests ran, when the Pester result is not 'Passed', or when code
coverage is below 80 percent.

.PARAMETER TestRoot
Folder that contains the test files. The default is the Tests folder of the repository.

.PARAMETER OutputPath
Folder that receives testResults.xml and coverage.xml. The default is the out folder of the
repository.

.PARAMETER TestResultFormat
Format of the test result report.

.PARAMETER CoverageFormat
Format of the coverage report.

.EXAMPLE
./build/Invoke-Tests.ps1

Runs the tests of the repository and applies the gate.

.EXAMPLE
./build/Invoke-Tests.ps1 -TestResultFormat JUnitXml -CoverageFormat Cobertura

Writes the reports in the formats that GitLab CI reads.

.INPUTS
None. This script does not accept pipeline input.

.OUTPUTS
None. The script throws when the gate is not met.
#>
[CmdletBinding()]
param(
    [string]$TestRoot,

    [string]$OutputPath,

    [ValidateSet('NUnitXml', 'NUnit3', 'JUnitXml')]
    [string]$TestResultFormat = 'NUnitXml',

    [ValidateSet('JaCoCo', 'Cobertura')]
    [string]$CoverageFormat = 'JaCoCo'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
if (-not $TestRoot) {
    $TestRoot = Join-Path -Path $repositoryRoot -ChildPath 'Tests'
}
if (-not $OutputPath) {
    $OutputPath = Join-Path -Path $repositoryRoot -ChildPath 'out'
}
$null = New-Item -Path $OutputPath -ItemType Directory -Force

Import-Module -Name Pester -RequiredVersion 6.2.0

$configuration = New-PesterConfiguration
$configuration.Run.Path = $TestRoot
$configuration.Run.RepoRoot = $repositoryRoot
$configuration.Run.PassThru = $true
$configuration.Run.Shuffle = $true
$configuration.CodeCoverage.Enabled = $true
$configuration.CodeCoverage.Path = @(
    Join-Path -Path $repositoryRoot -ChildPath 'Public'
    Join-Path -Path $repositoryRoot -ChildPath 'Private'
)
$configuration.CodeCoverage.OutputFormat = $CoverageFormat
$configuration.CodeCoverage.OutputPath = Join-Path -Path $OutputPath -ChildPath 'coverage.xml'
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputFormat = $TestResultFormat
$configuration.TestResult.OutputPath = Join-Path -Path $OutputPath -ChildPath 'testResults.xml'

$result = Invoke-Pester -Configuration $configuration

if ($null -eq $result -or $result.TotalCount -eq 0) {
    throw 'Pester ran no tests.'
}

if ($result.Result -ne 'Passed') {
    $counts = $result.FailedCount, $result.FailedBlocksCount, $result.FailedContainersCount
    $summary = 'Failed tests: {0}. Failed blocks: {1}. Failed files: {2}.' -f $counts
    $seed = $result.Configuration.Run.ShuffleSeed.Value
    throw "Pester result is '$($result.Result)'. $summary Replay with Run.ShuffleSeed = $seed."
}

$coverage = [math]::Round($result.CodeCoverage.CoveragePercent, 2)
if ($coverage -lt 80) {
    throw "Code coverage is $coverage percent. The minimum is 80."
}
```

Notes on the script:

- It is the gate from the testing rules, with reports and parameters added. The three checks are
  the same, in the same order.
- Every path comes from `$PSScriptRoot`, so the script works from any current location.
- `Run.RepoRoot` is set, so shared setup files are found even in a checkout that has no `.git`
  folder; see [Pester Configuration Guide](./pester-configuration.md#runreporoot).
- `Run.Throw` and `Run.Exit` are left off. Either would end the script inside `Invoke-Pester` when a
  test fails, before the script can report the counts, and neither reports a run without tests.
- When no test file exists under the test root, `Invoke-Pester` writes an error and returns nothing.
  The error does not always stop the script, because the preference set in a script does not reach
  the functions of a module. The test for `$null` turns the missing result into a failure.
- In a project that declares Windows PowerShell 5.1 support, change the first line to
  `#requires -Version 5.1`. The script uses nothing newer.

To enforce tags in CI (TST-04), add the check for untagged tests from
[Pester Test Structure Guide](./test-structure-guide.md#finding-untagged-tests) before the run.

## GitHub Actions

```yaml
name: Quality gates

on:
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Install build tools
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          Install-PSResource -Name PSScriptAnalyzer -Version 1.25.0 -TrustRepository
          Install-PSResource -Name Pester -Version 6.2.0 -TrustRepository

      - name: Run PSScriptAnalyzer
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          $findings = @(Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error, Warning)
          $findings | Format-Table -Property Severity, RuleName, ScriptName, Line -AutoSize
          if ($findings.Count -gt 0) {
              throw "PSScriptAnalyzer reported $($findings.Count) finding(s)."
          }

      - name: Run Pester
        shell: pwsh
        run: ./build/Invoke-Tests.ps1

      - name: Upload reports
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: test-reports
          path: out/
```

Use `runs-on: windows-latest` when the code is Windows-only.

Each action is referenced by a release tag (CIC-09). A full commit ID is the stricter choice; look
the ID up and write the tag after it in a comment.

The gate script requires PowerShell 7.6 through its `#requires` line, so the job fails with a clear
message on a runner image that has an older version.

Pester detects GitHub Actions and writes each failed test as an `::error::` command, which GitHub
shows as an annotation on the run. No option has to be set for this.

### Windows PowerShell 5.1 Job

Add this job only when the project declares Windows PowerShell 5.1 support (CIC-03). It goes under
`jobs:` beside the `test` job.

```yaml
  test-windows-powershell:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v7

      - name: Install Pester
        shell: powershell
        run: |
          $ErrorActionPreference = 'Stop'
          Install-Module -Name Pester -RequiredVersion 6.2.0 -Scope CurrentUser -Force -SkipPublisherCheck

      - name: Run Pester
        shell: powershell
        run: ./build/Invoke-Tests.ps1
```

`Install-Module` is used here because PSResourceGet is not part of Windows PowerShell 5.1 (VER-08).
Windows PowerShell ships with Pester 3.4.0, which has a different publisher, so the installation
needs `-SkipPublisherCheck`.

## Azure Pipelines

```yaml
trigger:
  branches:
    include:
      - main

pr:
  branches:
    include:
      - main

pool:
  vmImage: ubuntu-latest

steps:
  - task: PowerShell@2
    displayName: Install build tools
    inputs:
      targetType: inline
      pwsh: true
      script: |
        $ErrorActionPreference = 'Stop'
        Install-PSResource -Name PSScriptAnalyzer -Version 1.25.0 -TrustRepository
        Install-PSResource -Name Pester -Version 6.2.0 -TrustRepository

  - task: PowerShell@2
    displayName: Run PSScriptAnalyzer
    inputs:
      targetType: inline
      pwsh: true
      script: |
        $ErrorActionPreference = 'Stop'
        $findings = @(Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error, Warning)
        $findings | Format-Table -Property Severity, RuleName, ScriptName, Line -AutoSize
        if ($findings.Count -gt 0) {
            throw "PSScriptAnalyzer reported $($findings.Count) finding(s)."
        }

  - task: PowerShell@2
    displayName: Run Pester
    inputs:
      targetType: filePath
      filePath: build/Invoke-Tests.ps1
      pwsh: true

  - task: PublishTestResults@2
    displayName: Publish test results
    condition: always()
    inputs:
      testResultsFormat: NUnit
      testResultsFiles: out/testResults.xml

  - task: PublishCodeCoverageResults@2
    displayName: Publish code coverage
    condition: always()
    inputs:
      summaryFileLocation: out/coverage.xml
```

`pwsh: true` runs the step in PowerShell 7. On a Windows agent, `pwsh: false` runs it in Windows
PowerShell 5.1; use that only in a job for a project that declares 5.1 support.

Pester detects Azure Pipelines and writes failures as logging commands. No option has to be set for
this.

## Other CI Systems

The pattern is the same everywhere: install the pinned tools, call the gate script, and publish the
reports that the script wrote. A step fails when the script throws.

GitLab CI reads JUnit test results and Cobertura coverage:

```yaml
test:
  stage: test
  # An image that contains PowerShell 7.6.
  image: registry.example.com/build/powershell:7.6
  script:
    - pwsh -NoProfile -Command "Install-PSResource -Name Pester -Version 6.2.0 -TrustRepository"
    - pwsh -NoProfile -File ./build/Invoke-Tests.ps1 -TestResultFormat JUnitXml -CoverageFormat Cobertura
  artifacts:
    when: always
    reports:
      junit: out/testResults.xml
      coverage_report:
        coverage_format: cobertura
        path: out/coverage.xml
```

Jenkins reads JUnit test results with the `junit` step:

```groovy
pipeline {
    agent { label 'pwsh' }

    stages {
        stage('Test') {
            steps {
                pwsh 'Install-PSResource -Name Pester -Version 6.2.0 -TrustRepository'
                pwsh './build/Invoke-Tests.ps1 -TestResultFormat JUnitXml'
            }
        }
    }

    post {
        always {
            junit 'out/testResults.xml'
        }
    }
}
```

For a container image, Microsoft's documentation states that the .NET SDK images contain PowerShell
and that they are meant for development and testing. Check which PowerShell version an image
contains before you rely on it; the `#requires` line of the gate script fails the job when the
version is too old.

## Report Formats

| CI system | Test result format | Coverage format |
| --- | --- | --- |
| GitHub Actions | Any. The reports are uploaded as an artifact. | Any |
| Azure Pipelines | `NUnitXml`, published with `PublishTestResults@2` | `JaCoCo` or `Cobertura`, published with `PublishCodeCoverageResults@2` |
| GitLab CI | `JUnitXml` | `Cobertura` |
| Jenkins | `JUnitXml`, published with the `junit` step | `JaCoCo` or `Cobertura`, depending on the plugin |

Pester writes one test result format for each run. To write a second one, convert the result object
with `Export-NUnitReport` or `Export-JUnitReport`; see
[Pester Configuration Guide](./pester-configuration.md#test-results).

Paths inside a coverage report are relative to `CodeCoverage.ReportRoot`, which defaults to
`Run.RepoRoot`. Set `ReportRoot` when the CI system expects paths relative to another folder.

## Failing Correctly

A pipeline script fails by throwing, with `$ErrorActionPreference = 'Stop'` set at the top (CIC-05).

```powershell
# Compliant
if ($null -eq $result -or $result.TotalCount -eq 0) {
    throw 'Pester ran no tests.'
}

# Non-compliant: Write-Error ends the script under 'Stop', so the exit statement is never reached,
# and without 'Stop' the pattern depends on every caller checking the exit code.
if ($result.FailedCount -gt 0) {
    Write-Error "$($result.FailedCount) test(s) failed."
    exit 1
}
```

Do not turn a failure into a warning to keep a build green. A pull request pipeline fails when
Pester reports a problem (CIC-01). Tests that need resources a pull request build does not have,
such as integration tests against a live service, belong in a separate workflow that also fails when
they fail.

`Invoke-Pester` sets `$LASTEXITCODE` to the number of failures. Do not reset it before the script
has thrown for the failure it carried (CIC-05).

## Parallel Runs and Coverage in CI

`Run.Parallel` is experimental, so the gate script does not use it. When a project chooses to use
it, keep the coverage gate in a sequential job: a parallel run measures coverage with the slower
breakpoint method. Put the parallel run in a second job without coverage. Details are in
[Test Execution Guide](./test-execution.md#parallel-test-execution).

## Settings Files in CI

When the gate script loads Pester settings from a `.psd1` file, a misspelled key only produces a
warning. Fail the build on it with `GetUnknownKeys()`; see
[Pester Configuration Guide](./pester-configuration.md#checking-what-was-loaded).

## Checklist

- Tool versions are pinned: Pester 6.2.0 and PSScriptAnalyzer 1.25.0.
- The pipeline calls one gate script, and the script tests for no tests, for `Result`, and for
  coverage.
- Every action is referenced by a release tag or a full commit ID (CIC-09).
- The test folder is named in one place.
- Every script sets `$ErrorActionPreference = 'Stop'` and fails by throwing.
- The workflow has an explicit `permissions` block with the least access it needs (CIC-07).
- No secret is written in the workflow or printed to the log (CIC-06).
- No job targets a PowerShell version that is past its end-of-support date.
