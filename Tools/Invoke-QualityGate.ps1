#requires -Version 7.6
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

<#
.SYNOPSIS
Runs the repository's tests with code coverage and fails when the result is not good enough.

.DESCRIPTION
Runs every Pester test under RepositoryRoot, measures code coverage of the files in CoveragePath,
and fails when the Pester result is not 'Passed', when no tests ran, or when coverage is below
MinimumCoverage. CI runs this script, and it can be run locally to get the same answer.

The tests include the check that generated instruction files match their sources and the
compliance check of the repository's own PowerShell files, so this one script is the whole gate.

.PARAMETER RepositoryRoot
Folder whose tests are run. The default is the repository that contains this script.

.PARAMETER CoveragePath
Files whose coverage is measured. The default is the scripts under Tools, standards/examples, and
powershell-standards/Examples, leaving out test files, Test-QualityGates.ps1 (which breaks the rules on
purpose), and this script.

.PARAMETER MinimumCoverage
Lowest acceptable code coverage, as a percentage. The default is 80.

.EXAMPLE
./Tools/Invoke-QualityGate.ps1

Runs the gate for this repository.

.INPUTS
None.

.OUTPUTS
PowerShellStandards.QualityGateResult. One object with Result, TotalCount, PassedCount,
FailedCount, FailedBlocksCount, FailedContainersCount, and CoveragePercent properties.
#>
[CmdletBinding()]
[OutputType('PowerShellStandards.QualityGateResult')]
param(
    [Parameter()]
    [string]$RepositoryRoot = (Split-Path -Path $PSScriptRoot -Parent),

    [Parameter()]
    [string[]]$CoveragePath,

    [Parameter()]
    [ValidateRange(0, 100)]
    [int]$MinimumCoverage = 80
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootPath = Convert-Path -LiteralPath $RepositoryRoot

if (-not $CoveragePath) {
    $coverageFolders = 'Tools', 'standards/examples', 'powershell-standards/Examples'
    # Test-QualityGates.ps1 breaks the rules on purpose. This script runs the tests, so its own lines
    # cannot be measured from inside them; its tests run it in a separate process instead.
    $notMeasured = 'Test-QualityGates.ps1', 'Invoke-QualityGate.ps1'
    $CoveragePath = @(
        foreach ($coverageFolder in $coverageFolders) {
            $folderPath = Join-Path -Path $rootPath -ChildPath $coverageFolder
            if (-not (Test-Path -LiteralPath $folderPath)) {
                continue
            }
            Get-ChildItem -LiteralPath $folderPath -Include '*.ps1', '*.psm1' -File -Recurse |
                Where-Object { $_.Name -notlike '*.Tests.ps1' -and $notMeasured -notcontains $_.Name } |
                ForEach-Object { $_.FullName }
        }
    )
}

$configuration = New-PesterConfiguration
$configuration.Run.Path = $rootPath
$configuration.Run.PassThru = $true
# A new order on every run exposes a test that passes only after another one has run (TST-46).
$configuration.Run.Shuffle = $true
$configuration.Output.Verbosity = 'Normal'
$configuration.CodeCoverage.Enabled = $CoveragePath.Count -gt 0
$configuration.CodeCoverage.Path = $CoveragePath
$configuration.CodeCoverage.OutputPath = Join-Path -Path $rootPath -ChildPath 'coverage.xml'

# Strict mode and the error preference are inherited by the scopes below this one, which would
# include every test. Tests must run as they do when a developer calls Invoke-Pester directly, so
# both are set back to PowerShell's defaults for the run. Code inside a module under test still sees
# the session's global preference, which CI runners set to 'Stop'; see TST-17.
$result = & {
    Set-StrictMode -Off
    $ErrorActionPreference = 'Continue'
    Invoke-Pester -Configuration $configuration
}

# Invoke-Pester leaves the number of failures in $LASTEXITCODE. This script reports failure by
# throwing below, so the exit code must not fail the caller a second time or mask a pass.
$global:LASTEXITCODE = 0

# With no test files, Pester 6 reports an error of its own and returns nothing.
if ($null -eq $result) {
    throw "Pester returned no result for '$rootPath'. No tests were run."
}

$coverage = 0
if ($CoveragePath.Count -gt 0) {
    $coverage = [math]::Round($result.CodeCoverage.CoveragePercent, 2)
}

[PSCustomObject]@{
    PSTypeName = 'PowerShellStandards.QualityGateResult'
    Result = $result.Result
    TotalCount = $result.TotalCount
    PassedCount = $result.PassedCount
    FailedCount = $result.FailedCount
    FailedBlocksCount = $result.FailedBlocksCount
    FailedContainersCount = $result.FailedContainersCount
    CoveragePercent = $coverage
}

if ($result.Result -ne 'Passed') {
    $counts = $result.FailedCount, $result.FailedBlocksCount, $result.FailedContainersCount
    $summary = 'Failed tests: {0}. Failed blocks: {1}. Failed files: {2}.' -f $counts
    $seed = $result.Configuration.Run.ShuffleSeed.Value
    throw "Pester result is '$($result.Result)'. $summary Replay with Run.ShuffleSeed = $seed."
}

if ($result.TotalCount -eq 0) {
    throw "Pester discovered no tests under '$rootPath'."
}

if ($CoveragePath.Count -gt 0 -and $coverage -lt $MinimumCoverage) {
    throw "Code coverage is $coverage percent. The minimum is $MinimumCoverage."
}
