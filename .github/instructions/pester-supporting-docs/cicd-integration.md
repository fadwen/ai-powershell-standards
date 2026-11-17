# CI/CD Integration Guide

This guide shows how to run Pester in a pipeline so that the build fails when it should. It supports
the CI rules in [powershell-cicd.instructions.md](../powershell-cicd.instructions.md) and rules
TST-40 to TST-42 in [powershell-pester.instructions.md](../powershell-pester.instructions.md).

The gate script and the runner script were run on Pester 6.2.0 under PowerShell 7.6 and Windows
PowerShell 5.1, and the inline scripts of the GitHub Actions workflow were run locally. The pipeline
definitions are well-formed, but none of the pipelines was run on a CI service, and the keywords of
the restored jobs were not checked again against the documentation of the services.

Do not use emoji in generated code, in documentation, or in test output. Use plain text and ASCII
characters only.

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

## Job Design

Three more facts shape the jobs:

1. Coverage and parallel runs pull against each other. Pester 6.1 and later merge coverage across
   the workers of a parallel run, but collect it with breakpoints to do so. Run a fast parallel job
   without coverage for feedback, and a separate sequential job with the profiler for the gate.
2. A file that fails discovery adds nothing to `FailedCount`. Every gate checks `Result`, and a
   cheap discovery-only job runs first.
3. Pester 6.0 and 6.1 do not import on PowerShell 7.4.0 to 7.4.5. Their `net8.0` assembly referred
   to a newer `System.Management.Automation` than those releases carry, so `Import-Module` failed
   with `Cannot convert "PesterConfigurationDeserializer" from String to Type`. Pester 6.2 fixed it.
   Hosted runners carry the latest patch release, so this bites self-hosted agents and pinned
   container images; the pin on Pester 6.2.0 (CIC-02) avoids it.

```text
validate (discovery only, fast)
    |
    +--> test                     (operating system matrix, parallel, no coverage: fast feedback)
    +--> coverage                 (sequential, shuffled, coverage gate)
    +--> test-windows-powershell  (Windows PowerShell 5.1, when the project declares it)
```

## The Gate Script

Keep the logic in one script, `Tests/Invoke-Tests.ps1`, that the pipeline and a developer both call.
The standard one is the runner in
[Test Execution Guide](./test-execution.md#the-test-runner-script): it takes the test type and the
environment, writes the reports, and applies the gate. The pipelines in this guide call it. CI
passes `-Environment CI`, and `-CodeCoverage` in the job that holds the coverage gate; without that
switch the runner does not measure coverage.

The script and the settings files are kept in the `Tests` folder, as the layout in
[Pester Test Structure Guide](./test-structure-guide.md#test-directory-layout) shows. A `build`
folder beside `Tests` is the alternative; both are one level below the repository root, so only the
path in each call changes.

The alternative is the minimal script below: only the gate, with its reports. With it, each call
in a pipeline becomes `./Tests/Invoke-Tests.ps1` without the test type and environment, and the
reports are `out/testResults.xml` and `out/coverage.xml`. The test folder is held in one place, the
`TestRoot` parameter.

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
./Tests/Invoke-Tests.ps1

Runs the tests of the repository and applies the gate.

.EXAMPLE
./Tests/Invoke-Tests.ps1 -TestResultFormat JUnitXml -CoverageFormat Cobertura

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
$configuration.CodeCoverage.CoveragePercentTarget = 80
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
$target = $result.CodeCoverage.CoveragePercentTarget
if ($coverage -lt $target) {
    foreach ($file in $result.CodeCoverage.CommandsMissed | Group-Object -Property File) {
        Write-Host "  $($file.Name): $($file.Count) uncovered command(s)"
    }
    throw "Code coverage is $coverage percent. The minimum is $target."
}
```

Notes on the script:

- It is the gate from the testing rules, with reports and parameters added. The three checks are
  the same, in the same order. The coverage check compares with the configured target, which the
  script sets to 80 (TST-40), and lists the uncovered commands for each file when it fails.
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
name: PowerShell Testing

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
  schedule:
    # Every night at 02:00 UTC
    - cron: '0 2 * * *'

permissions:
  contents: read

env:
  POWERSHELL_TELEMETRY_OPTOUT: 1
  PESTER_VERSION: '6.2.0'

jobs:
  # Fast structural check. It finds an empty -ForEach, a file that cannot be discovered on its
  # own, and a configuration value of the wrong type, without running a test.
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Install Pester
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          Install-PSResource -Name Pester -Version $env:PESTER_VERSION -TrustRepository

      - name: Discovery-only pass
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          Import-Module -Name Pester -RequiredVersion $env:PESTER_VERSION

          $configuration = New-PesterConfiguration
          $configuration.Run.Path = Join-Path -Path $env:GITHUB_WORKSPACE -ChildPath 'Tests'
          $configuration.Run.RepoRoot = $env:GITHUB_WORKSPACE
          $configuration.Run.SkipRun = $true
          $configuration.Run.PassThru = $true
          $configuration.Output.CIFormat = 'GithubActions'

          $result = Invoke-Pester -Configuration $configuration

          if ($null -eq $result) {
              throw 'Pester found no test files.'
          }
          if ($result.Result -ne 'Passed') {
              foreach ($container in $result.FailedContainers) {
                  Write-Host "::error file=$($container.Item)::Discovery failed"
              }
              throw "$($result.FailedContainersCount) file(s) failed discovery."
          }
          Write-Host "Discovered $($result.TotalCount) tests in $(@($result.Containers).Count) files."

      - name: Verify every test is tagged
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          Import-Module -Name Pester -RequiredVersion $env:PESTER_VERSION

          $configuration = New-PesterConfiguration
          $configuration.Run.Path = Join-Path -Path $env:GITHUB_WORKSPACE -ChildPath 'Tests'
          $configuration.Run.RepoRoot = $env:GITHUB_WORKSPACE
          $configuration.Run.SkipRun = $true
          $configuration.Run.PassThru = $true
          # The reserved value None selects the tests that have no tag.
          $configuration.Filter.Tag = 'None'
          $configuration.Output.Verbosity = 'None'

          $result = Invoke-Pester -Configuration $configuration

          # ShouldRun marks what the filter selected. TotalCount ignores the filter.
          $untagged = @($result.Tests | Where-Object -Property ShouldRun)
          foreach ($test in $untagged) {
              Write-Host "::error::Untagged test: $($test.ExpandedPath)"
          }
          if ($untagged.Count -gt 0) {
              throw "$($untagged.Count) test(s) have no tag."
          }

  test:
    needs: validate
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        # Hosted runners carry a supported PowerShell 7. Do not add a PowerShell version that is
        # past its end-of-support date (CIC-04).
        os: [windows-latest, ubuntu-latest, macos-latest]
    steps:
      - uses: actions/checkout@v7

      - name: Cache PowerShell modules
        uses: actions/cache@v6
        with:
          path: |
            ~/.local/share/powershell/Modules
            ~/Documents/PowerShell/Modules
            ~/Documents/WindowsPowerShell/Modules
          key: ${{ runner.os }}-pester-${{ env.PESTER_VERSION }}-${{ hashFiles('**/*.psd1') }}
          restore-keys: |
            ${{ runner.os }}-pester-${{ env.PESTER_VERSION }}-

      - name: Install build tools
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          Install-PSResource -Name PSScriptAnalyzer -Version 1.25.0 -TrustRepository
          Install-PSResource -Name Pester -Version $env:PESTER_VERSION -TrustRepository

      - name: Run PSScriptAnalyzer
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          $findings = @(Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSGallery)
          $findings | Format-Table -Property Severity, RuleName, ScriptName, Line -AutoSize
          if ($findings.Count -gt 0) {
              throw "PSScriptAnalyzer reported $($findings.Count) finding(s)."
          }

      # Fast feedback: the unit tests in parallel, without coverage.
      - name: Run unit tests
        shell: pwsh
        run: ./Tests/Invoke-Tests.ps1 -TestType Unit -Environment CI -Parallel

      # Integration tests share external resources, so they never run in parallel.
      - name: Run integration tests
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          $result = ./Tests/Invoke-Tests.ps1 -TestType Integration -Environment CI -PassThru
          if ($result.Result -ne 'Passed') {
              # A failed integration test is reported as a warning and does not fail the build.
              Write-Warning "Integration tests failed: $($result.FailedCount) failure(s)."
          }
          # Invoke-Pester left the number of failures in the exit code, which fails the step.
          $global:LASTEXITCODE = 0

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: test-results-${{ matrix.os }}
          path: Tests/Results/

  # Coverage runs sequentially, so it can use the profiler-based tracer. It is also the job that
  # runs shuffled: a new seed for each run, printed at the start and named when the run fails.
  coverage:
    needs: validate
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v7

      - name: Install Pester
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          Install-PSResource -Name Pester -Version $env:PESTER_VERSION -TrustRepository

      - name: Run tests with coverage
        shell: pwsh
        run: ./Tests/Invoke-Tests.ps1 -TestType Unit -Environment CI -CodeCoverage -Shuffle

      - name: Upload coverage
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: coverage
          path: Tests/Results/

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v7
        with:
          files: Tests/Results/Coverage-*.xml
          flags: powershell
        env:
          CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}

  security-scan:
    needs: validate
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v7

      - name: Install Pester
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          Install-PSResource -Name Pester -Version $env:PESTER_VERSION -TrustRepository

      # A security suite that discovers no tests must fail the build: the runner throws
      # 'Pester ran no tests.' Attack data built in BeforeAll instead of BeforeDiscovery empties
      # the suite without any other message.
      - name: Run security tests
        shell: pwsh
        run: ./Tests/Invoke-Tests.ps1 -TestType Security -Environment CI

      - name: Run credential scan
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          $credentialPatterns = @(
              '(?i)(password|pwd|pass)\s*[:=]\s*["''][^"''\s]{8,}'
              '(?i)(api[_-]?key|apikey)\s*[:=]\s*["'']?[a-zA-Z0-9]{20,}'
              '(?i)(secret|token)\s*[:=]\s*["'']?[a-zA-Z0-9]{16,}'
          )

          $files = Get-ChildItem -Path . -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1'
          $leaks = @(
              foreach ($file in $files) {
                  Select-String -LiteralPath $file.FullName -Pattern $credentialPatterns
              }
          )

          # Only the place is printed. The matched text may be a secret (CIC-06).
          foreach ($leak in $leaks) {
              Write-Warning "Potential credential leak in $($leak.Path), line $($leak.LineNumber)"
          }
          if ($leaks.Count -gt 0) {
              throw "Credential leaks detected: $($leaks.Count) issue(s)."
          }

  performance-baseline:
    needs: validate
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v7

      - name: Install Pester
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          Install-PSResource -Name Pester -Version $env:PESTER_VERSION -TrustRepository

      # Never in parallel and never with coverage: both distort the measurement.
      - name: Run performance tests
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          $result = ./Tests/Invoke-Tests.ps1 -TestType Performance -Environment CI -PassThru
          if ($result.Result -ne 'Passed') {
              # Performance tests give warnings, not failures.
              Write-Warning "Performance regression: $($result.FailedCount) test(s) exceeded the baseline."
          }
          $global:LASTEXITCODE = 0

      # The folder holds the test results and the metrics file of the run, for trending.
      - name: Upload performance results
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: performance-results
          path: Tests/Results/
```

### GitHub Actions Notes

- `actions/setup-powershell` is not an official action. GitHub-hosted runners have a supported
  PowerShell 7 installed (`shell: pwsh`), and `windows-latest` also has Windows PowerShell 5.1
  (`shell: powershell`). Select the shell instead of installing a version.
- When a step needs a specific release, assert it instead of assuming the runner image. The runner
  script and the gate script do so with their `#requires -Version 7.6` line; an inline step does it
  with a test:

  ```powershell
  if ($PSVersionTable.PSVersion -lt [version]'7.6') {
      throw "PowerShell 7.6 or later is needed, and this is $($PSVersionTable.PSVersion)."
  }
  ```

- `::set-output` is deprecated: the runner warns when a step uses it. Write step outputs to the file that
  `GITHUB_OUTPUT` names, as the runner does:
  `Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value 'name=value'`. The runner also writes a table
  of the counts, and the coverage figure, to `GITHUB_STEP_SUMMARY`.
- `Output.CIFormat = 'GithubActions'` makes Pester write `::error` and `::warning` annotations,
  which show a failure inline on the pull request diff. `Auto` detects GitHub Actions, but setting
  the value explicitly is clearer; `Tests/PesterConfiguration.CI.psd1` sets it. The alternative is
  to set nothing and rely on `Auto`.
- `fail-fast: false` keeps the failure of one platform from cancelling the others, so that the run
  shows every platform that broke.
- The cache key holds the Pester version and the hash of the `.psd1` files, so a new pin or a
  changed manifest fills the cache again.
- The matrix covers Windows, Linux, and macOS (CIC-16). A project that supports one operating
  system keeps one job; see [Alternative: One Job](#alternative-one-job).
- The nightly schedule runs the same jobs without a commit (CIC-17), which finds a failure that
  comes from the runner image or from a dependency.
- The PSScriptAnalyzer step uses the `PSGallery` preset, the rules that the PowerShell Gallery
  applies. The alternatives are `-Severity Error, Warning` and the settings file of the repository;
  see [powershell-cicd.instructions.md](../powershell-cicd.instructions.md).
- The Codecov token comes from a repository secret (CIC-06). Codecov reads `JaCoCo` and
  `Cobertura` reports.
- The credential scan is part of the security gate (CIC-12). It prints the file and the line of a
  match, never the matched text.
- The integration and performance steps report a failure as a warning; see
  [Failing Correctly](#failing-correctly).
- The security and performance jobs (CIC-12, CIC-13) run the tests that TST-43 requires: security
  tests for credential handling and input validation, and performance tests for a function that
  processes more than 100 items. Remove a job whose test folder does not exist: a run that finds
  no test file fails.
- `Run.Parallel` is experimental. The `-Parallel` switch of the unit test step is the owner's
  default for fast feedback; without the switch the step runs the same tests sequentially.
- Each action is referenced by a release tag (CIC-09). A full commit ID is the stricter choice; look
  the ID up and write the tag after it in a comment.

### Alternative: One Job

A project that supports one operating system, and that uses the minimal gate script, needs one job
that runs on pull requests:

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
        run: ./Tests/Invoke-Tests.ps1

      - name: Upload reports
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: test-reports
          path: out/
```

Use `runs-on: windows-latest` when the code is Windows-only.

The gate script requires PowerShell 7.6 through its `#requires` line, so the job fails with a clear
message on a runner image that has an older version.

Pester detects GitHub Actions and writes each failed test as an `::error::` command, which GitHub
shows as an annotation on the run. No option has to be set for this.

### Windows PowerShell 5.1 Job

Add this job only when the project declares Windows PowerShell 5.1 support (CIC-03). It goes under
`jobs:` beside the `test` job. From Pester 6.2 a parallel run works under Windows PowerShell 5.1 as
well.

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
        run: ./Tests/Invoke-Tests.ps1
```

With the runner script, the last step calls it with `-TestType Unit -Environment CI`. With either
script, the first line of the script is then `#requires -Version 5.1`.

`Install-Module` is used here because PSResourceGet is not part of Windows PowerShell 5.1 (VER-08).
Windows PowerShell ships with Pester 3.4.0, which has a different publisher, so the installation
needs `-SkipPublisherCheck`. A step that runs under both versions tests for the command first:

```powershell
# Install-PSResource is part of PowerShell 7.4 and later. Windows PowerShell 5.1 needs Install-Module.
if (Get-Command -Name Install-PSResource -ErrorAction Ignore) {
    Install-PSResource -Name Pester -Version 6.2.0 -TrustRepository
} else {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name Pester -RequiredVersion 6.2.0 -Scope CurrentUser -Force -SkipPublisherCheck
}
```

## Azure Pipelines

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include:
      - main
      - develop
  paths:
    exclude:
      - README.md
      - docs/*

pr:
  branches:
    include:
      - main
  paths:
    exclude:
      - README.md
      - docs/*

schedules:
  - cron: '0 2 * * *'
    displayName: Daily build
    branches:
      include:
        - main

variables:
  POWERSHELL_TELEMETRY_OPTOUT: 1

stages:
  - stage: Test
    displayName: Testing stage
    jobs:
      - job: TestWindows
        displayName: Test on Windows
        pool:
          vmImage: windows-latest
        strategy:
          matrix:
            PS7:
              powershellVersion: '7'
              usePwsh: true
            # Keep this leg only when the project declares Windows PowerShell 5.1 support (CIC-03).
            PS5:
              powershellVersion: '5.1'
              usePwsh: false
        steps:
          - task: PowerShell@2
            displayName: Install build tools
            inputs:
              targetType: inline
              pwsh: $(usePwsh)
              script: |
                $ErrorActionPreference = 'Stop'
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                Install-Module -Name Pester -RequiredVersion 6.2.0 -Scope CurrentUser -Force -SkipPublisherCheck
                Install-Module -Name PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force

          - task: PowerShell@2
            displayName: Run PSScriptAnalyzer
            inputs:
              targetType: inline
              pwsh: $(usePwsh)
              script: |
                $ErrorActionPreference = 'Stop'
                $findings = @(Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSGallery)
                $findings | Format-Table -Property Severity, RuleName, ScriptName, Line -AutoSize
                if ($findings.Count -gt 0) {
                    Write-Host "##vso[task.logissue type=error]PSScriptAnalyzer found $($findings.Count) issue(s)"
                    throw "PSScriptAnalyzer reported $($findings.Count) finding(s)."
                }

          # The runner sets the variables TotalTests, PassedTests, FailedTests, and CodeCoverage
          # with ##vso[task.setvariable].
          - task: PowerShell@2
            displayName: Run tests
            inputs:
              targetType: filePath
              filePath: Tests/Invoke-Tests.ps1
              arguments: -TestType All -Environment CI -CodeCoverage
              pwsh: $(usePwsh)

          - task: PublishTestResults@2
            displayName: Publish test results
            condition: always()
            inputs:
              testResultsFormat: NUnit
              testResultsFiles: Tests/Results/TestResults*.xml
              testRunTitle: PowerShell Tests - $(Agent.OS) - PS$(powershellVersion)

          # PublishCodeCoverageResults@1 is deprecated. Version 2 takes summaryFileLocation
          # directly and infers the format.
          - task: PublishCodeCoverageResults@2
            displayName: Publish code coverage
            condition: always()
            inputs:
              summaryFileLocation: Tests/Results/Coverage*.xml

      - job: TestLinux
        displayName: Test on Linux
        pool:
          vmImage: ubuntu-latest
        steps:
          - task: PowerShell@2
            displayName: Install Pester
            inputs:
              targetType: inline
              pwsh: true
              script: |
                $ErrorActionPreference = 'Stop'
                Install-PSResource -Name Pester -Version 6.2.0 -TrustRepository

          # Only the unit tests that are tagged CrossPlatform run on Linux.
          - task: PowerShell@2
            displayName: Run cross-platform tests
            inputs:
              targetType: filePath
              filePath: Tests/Invoke-Tests.ps1
              arguments: -TestType Unit -Tag CrossPlatform -Environment CI
              pwsh: true

  - stage: Security
    displayName: Security scanning
    dependsOn: Test
    condition: succeeded()
    jobs:
      - job: SecurityScan
        displayName: Security analysis
        pool:
          vmImage: windows-latest
        steps:
          - task: PowerShell@2
            displayName: Install Pester
            inputs:
              targetType: inline
              pwsh: true
              script: |
                $ErrorActionPreference = 'Stop'
                Install-PSResource -Name Pester -Version 6.2.0 -TrustRepository

          - task: PowerShell@2
            displayName: Security tests
            inputs:
              targetType: filePath
              filePath: Tests/Invoke-Tests.ps1
              arguments: -TestType Security -Environment CI
              pwsh: true

  - stage: Deploy
    displayName: Deployment
    dependsOn:
      - Test
      - Security
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - deployment: DeployProduction
        displayName: Deploy to PowerShell Gallery
        environment: Production
        strategy:
          runOnce:
            deploy:
              steps:
                - task: PowerShell@2
                  displayName: Publish to PowerShell Gallery
                  inputs:
                    targetType: inline
                    pwsh: true
                    script: |
                      # Publish logic here
                      Write-Host 'Publishing to PowerShell Gallery...'
```

Notes on the pipeline:

- The `PS5` leg is for a project that declares Windows PowerShell 5.1 support (CIC-03); remove it
  otherwise. `pwsh: true` runs a step in PowerShell 7, and on a Windows agent `pwsh: false` runs
  it in Windows PowerShell 5.1. With that leg, the first line of the runner is
  `#requires -Version 5.1`.
- The Windows job installs with `Set-PSRepository` and `Install-Module`, which work in both legs.
  A job that runs only PowerShell 7, such as the Linux job, uses `Install-PSResource` (VER-08).
- The path filters keep a change that touches only `README.md` or `docs/` from starting a build.
- `PublishTestResults@2` reads the NUnit report, and both publish tasks run with
  `condition: always()` so that a failed run still shows its results.
- Pester detects Azure Pipelines and writes failures as logging commands. The CI configuration
  file can set `Output.CIFormat = 'AzureDevops'` to state it; no option has to be set.
- Tag the tests that run on every platform `CrossPlatform`. `-Tag` replaces the tag of the test
  type, so the Linux job runs the tests under `Tests/Unit` that have that tag.
- The deployment stage runs after the test and security stages, on the main branch. The rule for
  publishing a module is narrower: CIC-08 publishes only from a tagged release, with the API key
  from a secret. To follow it here, make the condition
  `and(succeeded(), startsWith(variables['Build.SourceBranch'], 'refs/tags/v'))` and add the tag
  to the trigger.

## Other CI Systems

The pattern is the same everywhere: install the pinned tools, call the script, and publish the
reports that the script wrote. A step fails when the script throws.

### Jenkins

Jenkins reads JUnit test results with the `junit` step, so set
`TestResult.OutputFormat = 'JUnitXml'` in `Tests/PesterConfiguration.CI.psd1`.

```groovy
pipeline {
    agent none

    environment {
        POWERSHELL_TELEMETRY_OPTOUT = '1'
    }

    stages {
        stage('Test') {
            parallel {
                // Keep this stage only when the project declares Windows PowerShell 5.1 support.
                stage('Windows PowerShell 5.1') {
                    agent { label 'windows' }
                    steps {
                        powershell '''
                            $ErrorActionPreference = 'Stop'
                            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                            Install-Module -Name Pester -RequiredVersion 6.2.0 -Scope CurrentUser -Force -SkipPublisherCheck
                            ./Tests/Invoke-Tests.ps1 -TestType All -Environment CI
                        '''
                    }
                    post {
                        always {
                            junit 'Tests/Results/TestResults*.xml'
                        }
                    }
                }

                stage('PowerShell 7') {
                    agent { label 'pwsh' }
                    steps {
                        pwsh '''
                            $ErrorActionPreference = 'Stop'
                            Install-PSResource -Name Pester -Version 6.2.0 -TrustRepository
                            ./Tests/Invoke-Tests.ps1 -TestType All -Environment CI -CodeCoverage
                        '''
                    }
                    post {
                        always {
                            junit 'Tests/Results/TestResults*.xml'
                            publishCoverage adapters: [jacocoAdapter('Tests/Results/Coverage*.xml')]
                        }
                    }
                }
            }
        }

        stage('Security Scan') {
            agent { label 'pwsh' }
            steps {
                pwsh './Tests/Invoke-Tests.ps1 -TestType Security -Environment CI'
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }
            agent { label 'pwsh' }
            steps {
                pwsh '''
                    # Deployment logic
                    Write-Host 'Deploying to PowerShell Gallery...'
                '''
            }
        }
    }

    post {
        always {
            emailext(
                to: '${DEFAULT_RECIPIENTS}',
                subject: '${PROJECT_NAME} - Build ${BUILD_NUMBER} - ${BUILD_STATUS}',
                body: '''${PROJECT_NAME} - Build ${BUILD_NUMBER} - ${BUILD_STATUS}

Test Results:
Total Tests: ${TEST_COUNTS,var="total"}
Failed Tests: ${TEST_COUNTS,var="fail"}
Passed Tests: ${TEST_COUNTS,var="pass"}
Skipped Tests: ${TEST_COUNTS,var="skip"}

Build URL: ${BUILD_URL}
'''
            )
        }
    }
}
```

The `post` block mails a summary of the build and of the test counts after every run. The coverage
step publishes the JaCoCo report; which step does this depends on the coverage plugin that is
installed.

### GitLab CI

```yaml
stages:
  - test
  - security
  - deploy

variables:
  POWERSHELL_TELEMETRY_OPTOUT: "1"

.powershell_template: &powershell_template
  before_script:
    - pwsh -NoProfile -Command "Install-PSResource -Name Pester -Version 6.2.0 -TrustRepository"

# GitLab needs JUnit for test results and Cobertura for coverage. Pester 6 writes both: set
# TestResult.OutputFormat = 'JUnitXml' and CodeCoverage.OutputFormat = 'Cobertura' in
# Tests/PesterConfiguration.CI.psd1.
#
# Container images: the mcr.microsoft.com/powershell images are deprecated. PowerShell now ships
# inside the .NET SDK images: mcr.microsoft.com/dotnet/sdk:10.0 carries PowerShell 7.6 (.NET 10
# LTS). Microsoft publishes these for development and testing only; build and maintain your own
# image for production pipelines.
test:windows:
  stage: test
  image: mcr.microsoft.com/dotnet/sdk:10.0-windowsservercore-ltsc2022
  <<: *powershell_template
  script:
    - pwsh -NoProfile -File ./Tests/Invoke-Tests.ps1 -TestType Unit -Environment CI -CodeCoverage
  artifacts:
    when: always
    reports:
      junit: Tests/Results/TestResults*.xml
      coverage_report:
        coverage_format: cobertura
        path: Tests/Results/Coverage*.xml
    paths:
      - Tests/Results/
    expire_in: 1 week
  coverage: '/Code Coverage: (\d+\.?\d*)%/'

test:linux:
  stage: test
  image: mcr.microsoft.com/dotnet/sdk:10.0
  <<: *powershell_template
  script:
    # This job measures no coverage, so it can run in parallel.
    - pwsh -NoProfile -File ./Tests/Invoke-Tests.ps1 -TestType Unit -Tag CrossPlatform -Environment CI -Parallel
  artifacts:
    when: always
    reports:
      junit: Tests/Results/TestResults*.xml

security:
  stage: security
  image: mcr.microsoft.com/dotnet/sdk:10.0-windowsservercore-ltsc2022
  <<: *powershell_template
  script:
    - pwsh -NoProfile -File ./Tests/Invoke-Tests.ps1 -TestType Security -Environment CI
  allow_failure: false

deploy:
  stage: deploy
  image: mcr.microsoft.com/dotnet/sdk:10.0-windowsservercore-ltsc2022
  script:
    - pwsh -NoProfile -Command "Write-Host 'Deploying to PowerShell Gallery...'"
  only:
    - main
  when: manual
```

The `coverage:` pattern reads the figure from the line `Code Coverage: <figure>%` that the runner
prints in its summary, and GitLab shows it on the merge request. It reads the runner's own line,
not the output of Pester.

Check which PowerShell version an image contains before you rely on it; the `#requires` line of the
script fails the job when the version is too old.

As in Azure Pipelines, the deployment jobs of Jenkins and GitLab run from the main branch after the
tests. CIC-08 is narrower for publishing a module: only from a tagged release.

## Shared Settings

Set the same environment variables in every pipeline:

```powershell
# Common environment variables for CI
$env:POWERSHELL_TELEMETRY_OPTOUT = '1'
$env:PESTER_CI_MODE = 'true'
$env:CODE_COVERAGE_ENABLED = 'true'
$env:TEST_RESULTS_PATH = './Tests/Results'
```

`POWERSHELL_TELEMETRY_OPTOUT` stops PowerShell from sending telemetry from the build agent. Pester
does not read the other three; they are shared names for the scripts of the pipeline. Pin the Pester
version in one variable, `PESTER_VERSION`, as the GitHub Actions workflow does.

Collect the reports with the same patterns in every pipeline:

```powershell
# Standard artifact patterns
$artifacts = @{
    TestResults = './Tests/Results/TestResults*.xml'
    CodeCoverage = './Tests/Results/Coverage*.xml'
    TestMetrics = './Tests/Results/TestMetrics*.json'
    TestReports = './Tests/Results/TestReport*.html'
}
```

## Report Formats

| CI system | Test result format | Coverage format |
| --- | --- | --- |
| GitHub Actions | `NUnitXml`, shown with `dorny/test-reporter`. Alternative: any format, uploaded as an artifact. | `JaCoCo` |
| Azure Pipelines | `NUnitXml`, published with `PublishTestResults@2` | `JaCoCo` or `Cobertura`, published with `PublishCodeCoverageResults@2` |
| GitLab CI | `JUnitXml` | `Cobertura` |
| Jenkins | `JUnitXml`, published with the `junit` step of the JUnit plugin | `JaCoCo` or `Cobertura`, depending on the plugin |
| Codecov | Any | `JaCoCo` or `Cobertura` |

Pester writes one test result format for each run. To write a second one, convert the result object
with `Export-NUnitReport` or `Export-JUnitReport`; see
[Pester Configuration Guide](./pester-configuration.md#test-results).

The `CoverageGutters` format was removed. Every coverage report is now relative to the repository
root, so the plain `JaCoCo` format works with the Coverage Gutters extension.

Paths inside a coverage report are relative to `CodeCoverage.ReportRoot`, which defaults to
`Run.RepoRoot`. Set `ReportRoot` when the CI system checks out to a subfolder or expects paths
relative to another folder.

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

The analyzer, the unit tests, the security tests, and the coverage figure are the gate: a pull
request pipeline fails when one of them reports a problem (CIC-01). Do not turn a failure of the
gate into a warning to keep a build green.

Integration tests and performance tests report instead: their steps write a warning when a test
fails, and the build goes on. Those tests depend on external resources and on the load of the
runner. The alternative is to let them fail the build as well: call the runner without `-PassThru`,
or put tests that need resources a pull request build does not have in a separate workflow that
fails when they fail.

`Invoke-Pester` sets `$LASTEXITCODE` to the number of failures, and the `pwsh` shell of GitHub
Actions fails a step whose last exit code is not zero. Do not reset it before the script has acted
on the failure it carried (CIC-05): the gate throws, and the two steps that only warn reset it
after they have written the warning.

## Parallel Runs and Coverage in CI

Pester 6 has a parallel runner, `Run.Parallel`. `Run.Container` is for passing data to test files,
not for parallelism: measured on 6.2.0, three containers that each took two seconds ran one after
another in the calling runspace in nine seconds, and in three seconds with `Run.Parallel` set.

```powershell
$configuration = New-PesterConfiguration
$configuration.Run.Path = $testRoot
$configuration.Run.Parallel = $true
$configuration.Run.ParallelThrottleLimit = 4
```

Containers with data still work, and they run in parallel too. The data of each file reaches its
worker:

```powershell
$configuration.Run.Container = @(
    New-PesterContainer -Path $testRoot -Data @{ Environment = 'CI' }
)
$configuration.Run.Parallel = $true
```

Splitting into two jobs is the default: a parallel job without coverage for feedback, and a
sequential job with the coverage gate. A parallel run measures coverage with breakpoints, not with
the profiler, so keep the coverage gate in the sequential job; but measure before assuming that
either is faster.

`Run.Parallel` is experimental. The alternative, for a project that does not turn it on, is the one
sequential job of the gate script. Details are in
[Test Execution Guide](./test-execution.md#parallel-test-execution).

## Settings Files in CI

When the script loads Pester settings from a `.psd1` file, a misspelled key only produces a
warning. Fail the build on it with `GetUnknownKeys()`; see
[Pester Configuration Guide](./pester-configuration.md#checking-what-was-loaded). The runner does
this through `Test-PesterConfiguration`.

## Checklist

- Tool versions are pinned: Pester 6.2.0 and PSScriptAnalyzer 1.25.0.
- The pipeline calls one script, and the script tests for no tests, for `Result`, and for
  coverage.
- A discovery-only job runs first, and the other jobs depend on it.
- Coverage is measured in a sequential job; a parallel job measures none.
- Every action is referenced by a release tag or a full commit ID (CIC-09).
- The test folder is named in one place.
- Every script sets `$ErrorActionPreference = 'Stop'` and fails by throwing.
- The workflow has an explicit `permissions` block with the least access it needs (CIC-07).
- No secret is written in the workflow or printed to the log (CIC-06).
- No job targets a PowerShell version that is past its end-of-support date.
- Reports are uploaded even when the run fails.
