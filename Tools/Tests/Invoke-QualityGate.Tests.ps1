#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $gateScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools/Invoke-QualityGate.ps1'
    $pesterManifest = (Get-Module -Name Pester).Path -replace '\.psm1$', '.psd1'

    # Builds a small project under a folder: one function file and one test file for it.
    $newFixtureProject = {
        param([string]$Root, [string]$TestBody)

        $null = New-Item -Path $Root -ItemType Directory -Force
        $functionCode = @'
function Get-Answer {
    [CmdletBinding()]
    param([switch]$Double)

    if ($Double) {
        84
    } else {
        42
    }
}
'@
        $testCode = @"
BeforeAll {
    . (Join-Path -Path `$PSScriptRoot -ChildPath 'Get-Answer.ps1')
}

Describe 'Get-Answer' -Tag 'Unit' {
$TestBody
}
"@
        $functionPath = Join-Path -Path $Root -ChildPath 'Get-Answer.ps1'
        $testPath = Join-Path -Path $Root -ChildPath 'Get-Answer.Tests.ps1'
        Set-Content -LiteralPath $functionPath -Value $functionCode -Encoding ascii
        Set-Content -LiteralPath $testPath -Value $testCode -Encoding ascii
    }

    # Runs the gate in a new process, as CI does, and returns its output lines and exit code.
    $invokeGate = {
        param([string]$Root, [int]$MinimumCoverage = 80)

        $command = @(
            "Import-Module '$pesterManifest'"
            "`$gateParameters = @{ RepositoryRoot = '$Root'; MinimumCoverage = $MinimumCoverage }"
            "`$gateParameters['CoveragePath'] = Join-Path -Path '$Root' -ChildPath 'Get-Answer.ps1'"
            "`$result = & '$gateScript' @gateParameters"
            "'GATE-RESULT ' + `$result.Result + ' ' + `$result.TotalCount + ' ' + `$result.CoveragePercent"
        ) -join '; '
        $output = & pwsh -NoProfile -NonInteractive -Command $command 2>&1 | ForEach-Object { "$_" }

        [PSCustomObject]@{
            Output = @($output)
            ExitCode = $LASTEXITCODE
        }
    }
}

Describe 'Invoke-QualityGate.ps1' -Tag 'Integration' {
    BeforeEach {
        $projectPath = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
    }

    It 'Passes and reports the result when tests pass and coverage is sufficient' {
        $testBody = @'
    It 'Returns 42' { Get-Answer | Should-Be 42 }
    It 'Returns 84 when doubled' { Get-Answer -Double | Should-Be 84 }
'@
        & $newFixtureProject -Root $projectPath -TestBody $testBody

        $run = & $invokeGate -Root $projectPath

        $run.ExitCode | Should-Be 0
        @($run.Output | Where-Object { $_ -like 'GATE-RESULT Passed 2 100*' }) | Should-BeCollection -Count 1
    }

    It 'Fails when a test fails' {
        $testBody = "    It 'Returns 43' { Get-Answer | Should-Be 43 }"
        & $newFixtureProject -Root $projectPath -TestBody $testBody

        $run = & $invokeGate -Root $projectPath

        $run.ExitCode | Should-NotBe 0
        @($run.Output | Where-Object { $_ -like "*Pester result is 'Failed'*" }).Count | Should-BeGreaterThan 0
    }

    It 'Fails when a teardown block fails although every test passes' {
        $testBody = @'
    It 'Returns 42' { Get-Answer | Should-Be 42 }
    It 'Returns 84 when doubled' { Get-Answer -Double | Should-Be 84 }
    AfterAll { throw 'Teardown failed.' }
'@
        & $newFixtureProject -Root $projectPath -TestBody $testBody

        $run = & $invokeGate -Root $projectPath

        $blockFailure = @($run.Output | Where-Object { $_ -like '*Failed tests: 0. Failed blocks: 1.*' })

        $run.ExitCode | Should-NotBe 0
        $blockFailure.Count | Should-BeGreaterThan 0
    }

    It 'Fails when coverage is below the minimum' {
        $testBody = "    It 'Returns 42' { Get-Answer | Should-Be 42 }"
        & $newFixtureProject -Root $projectPath -TestBody $testBody

        $run = & $invokeGate -Root $projectPath -MinimumCoverage 90

        $run.ExitCode | Should-NotBe 0
        @($run.Output | Where-Object { $_ -like '*Code coverage is * percent. The minimum is 90.*' }).Count |
            Should-BeGreaterThan 0
    }

    It 'Fails when there are no tests' {
        $null = New-Item -Path $projectPath -ItemType Directory
        $functionPath = Join-Path -Path $projectPath -ChildPath 'Get-Answer.ps1'
        Set-Content -LiteralPath $functionPath -Value "'text'" -Encoding ascii

        $run = & $invokeGate -Root $projectPath

        $run.ExitCode | Should-NotBe 0
        @($run.Output | Where-Object { $_ -like '*No tests were run*' }).Count | Should-BeGreaterThan 0
    }
}
