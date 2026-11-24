#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    $hasGit = [bool](Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)
    $scannerCases = @(
        @{ Scanner = 'betterleaks' }
        @{ Scanner = 'gitleaks' }
        @{ Scanner = 'trufflehog' }
    )

    # The real scanners are downloaded and run in CI. On a developer's computer that is a choice:
    # set CREDENTIAL_SCAN_INTEGRATION to 1.
    $inCi = $env:GITHUB_ACTIONS -eq 'true'
    $runRealScanners = $hasGit -and ($inCi -or $env:CREDENTIAL_SCAN_INTEGRATION -eq '1')

    # The workflow that the installer writes names the hash of the archive for a Linux runner.
    $processor = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    $onLinuxX64 = $IsLinux -and $processor -eq 'X64'
}

BeforeAll {
    $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $scanScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools/Invoke-CredentialScan.ps1'

    # The form of each scanner's output, and the rules that its probe has to report.
    $scannerFacts = @{
        betterleaks = @{ Family = 'leaks'; ProbeRules = 'generic-password', 'stripe-access-token' }
        gitleaks = @{ Family = 'leaks'; ProbeRules = 'github-pat', 'stripe-access-token' }
        trufflehog = @{ Family = 'hog'; ProbeRules = 'Github', 'Stripe' }
    }

    # A value that the stand-in gives as the raw text of a trufflehog finding. The script must
    # never write it.
    $rawValue = 'RAW-VALUE-THAT-MUST-NOT-APPEAR'

    # Runs git in a folder. The identity of the commits of a fixture comes from the environment
    # of this process, not from any git configuration.
    $invokeGit = {
        param([string]$Path, [string[]]$Arguments)

        $output = & git -C $Path @Arguments 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0) {
            throw "git $($Arguments -join ' ') failed in '$Path': $($output -join ' ')"
        }
    }

    # Writes a file in a repository and commits it.
    $addCommit = {
        param([string]$Path, [string]$FileName, [string[]]$Lines, [string]$Message)

        Set-Content -LiteralPath (Join-Path -Path $Path -ChildPath $FileName) -Value $Lines -Encoding ascii
        & $invokeGit -Path $Path -Arguments 'add', '-A'
        & $invokeGit -Path $Path -Arguments 'commit', '--quiet', '-m', $Message
    }

    # Creates a repository with one commit and returns its path.
    $newRepository = {
        $path = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $path -ItemType Directory
        & $invokeGit -Path $path -Arguments 'init', '--quiet', '--initial-branch', 'main'
        & $addCommit -Path $path -FileName 'README.md' -Lines '# Fixture' -Message 'first'
        $path
    }

    # One finding in the form that a scenario holds.
    $newItem = {
        param([string]$Rule, [string]$File, [int]$Line, [string]$Commit)

        $fingerprint = "$($File):$($Rule):$Line"
        if ($Commit) {
            $fingerprint = "$($Commit):$fingerprint"
        }
        @{ Rule = $Rule; File = $File; Line = $Line; Commit = $Commit; Fingerprint = $fingerprint }
    }

    # The scenario of a scan by a scanner that finds the probe and nothing else.
    $newScenario = {
        param([string]$Scanner)

        $facts = $scannerFacts[$Scanner]
        @{
            Family = $facts.Family
            RawValue = $rawValue
            Probe = @($facts.ProbeRules | ForEach-Object { & $newItem -Rule $_ -File 'probe.txt' -Line 1 })
            History = @()
            Files = @()
            Plain = @{ History = $null; Files = $null; ExitCode = $null }
            ExitCode = @{ Probe = $null; History = $null; Files = $null }
        }
    }

    # Writes a stand-in for a scanner and returns its path. It is a PowerShell script, so that it
    # runs on every system: it records how it was called, writes the findings that its scenario
    # names in the form of the scanner, and ends with the exit code of the scanner.
    $newStandIn = {
        param([hashtable]$Scenario)

        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $folder -ItemType Directory
        $scenarioPath = Join-Path -Path $folder -ChildPath 'scenario.json'
        $Scenario | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $scenarioPath
        $standIn = @'
$folder = $PSScriptRoot
$scenario = Get-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'scenario.json') -Raw | ConvertFrom-Json
$isProbe = (Split-Path -Path (Get-Location).Path -Leaf) -eq 'probe'
$source = if ($isProbe) { 'Probe' } elseif ($args[0] -eq 'git') { 'History' } else { 'Files' }
$excludeIndex = [array]::IndexOf($args, '--exclude-paths')
$excludeLines = if ($excludeIndex -ge 0) { @(Get-Content -LiteralPath $args[$excludeIndex + 1]) } else { @() }
# Only the name before each value of the probe is recorded, not the value.
$probeNames = @()
if ($isProbe) {
    $probeNames = @(Get-Content -LiteralPath 'probe.txt' | ForEach-Object { ($_ -split '[:=]')[0].Trim() })
}
$configIndex = [array]::IndexOf($args, '--config')
$configName = if ($configIndex -ge 0) { Split-Path -Path $args[$configIndex + 1] -Leaf } else { '' }
$call = [ordered]@{
    Source = $source; Arguments = @($args); ExcludeLines = $excludeLines; ProbeNames = $probeNames
    Configuration = $configName
}
$callsPath = Join-Path -Path $folder -ChildPath 'calls.jsonl'
$call | ConvertTo-Json -Depth 4 -Compress | Add-Content -LiteralPath $callsPath

$items = @($scenario.$source)
$override = $scenario.ExitCode.$source
# A scan with the configuration that holds only the built-in rules is the second scan, which
# measures the configuration of the project. It reports what the scenario names under Plain.
if ($configName -eq 'built-in-rules.toml' -and $null -ne $scenario.Plain.$source) {
    $items = @($scenario.Plain.$source)
    $override = $scenario.Plain.ExitCode
}
if ($null -ne $override) {
    'the scanner could not run'
    exit $override
}

if ($scenario.Family -eq 'leaks') {
    $reportPath = $args[[array]::IndexOf($args, '--report-path') + 1]
    $report = @($items | ForEach-Object {
            [ordered]@{
                RuleID = $_.Rule; File = $_.File; StartLine = $_.Line; Commit = $_.Commit
                Secret = 'REDACTED'; Fingerprint = $_.Fingerprint
            }
        })
    ConvertTo-Json -InputObject $report -Depth 4 | Set-Content -LiteralPath $reportPath
    exit $(if ($items.Count -gt 0) { 3 } else { 0 })
}

'{"level":"info-0","msg":"running source"}'
foreach ($item in $items) {
    $place = [ordered]@{ file = $item.File; line = $item.Line }
    if ($item.Commit) {
        $place.commit = $item.Commit
        $data = @{ Git = $place }
    } else {
        $data = @{ Filesystem = $place }
    }
    $finding = @{ SourceMetadata = @{ Data = $data }; DetectorName = $item.Rule; Raw = $scenario.RawValue }
    $finding | ConvertTo-Json -Depth 6 -Compress
}
exit $(if ($items.Count -gt 0) { 183 } else { 0 })
'@
        $path = Join-Path -Path $folder -ChildPath 'scanner.ps1'
        Set-Content -LiteralPath $path -Value $standIn -Encoding ascii
        $path
    }

    # The calls that a stand-in recorded.
    $getCalls = {
        param([string]$StandInPath)

        $callsPath = Join-Path -Path (Split-Path -Path $StandInPath -Parent) -ChildPath 'calls.jsonl'
        @(Get-Content -LiteralPath $callsPath | ForEach-Object { $_ | ConvertFrom-Json })
    }

    # Runs the scan and returns what it wrote and the error that ended it, if any.
    $invokeScan = {
        param([hashtable]$Parameters)

        $findings = [System.Collections.Generic.List[object]]::new()
        $leftOutPlaces = [System.Collections.Generic.List[string]]::new()
        $problem = $null
        $scanWarnings = $null
        $streams = @{ WarningVariable = 'scanWarnings'; WarningAction = 'SilentlyContinue'; Verbose = $true }
        try {
            # With -Verbose the scan names each place that a configuration leaves out.
            & $scanScript @Parameters @streams 4>&1 | ForEach-Object {
                if ($_ -isnot [System.Management.Automation.VerboseRecord]) {
                    $findings.Add($_)
                } elseif ($_.Message -like 'Left out by *') {
                    $leftOutPlaces.Add($_.Message)
                }
            }
        } catch {
            $problem = $_
        }

        @{
            Findings = $findings.ToArray()
            Problem = $problem
            Warnings = @($scanWarnings | ForEach-Object { "$_" })
            LeftOutPlaces = $leftOutPlaces.ToArray()
        }
    }

    # Runs the scan of a repository with a stand-in for the scanner.
    $invokeStandInScan = {
        param([string]$Scanner, [string]$Repository, [string]$StandIn)

        & $invokeScan -Parameters @{ Scanner = $Scanner; RepositoryPath = $Repository; ScannerPath = $StandIn }
    }

    $identityNames = 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL'
    $savedIdentity = @{}
    foreach ($name in $identityNames) {
        $savedIdentity[$name] = [System.Environment]::GetEnvironmentVariable($name)
    }
    $env:GIT_AUTHOR_NAME = 'Fixture'
    $env:GIT_AUTHOR_EMAIL = 'fixture@example.invalid'
    $env:GIT_COMMITTER_NAME = 'Fixture'
    $env:GIT_COMMITTER_EMAIL = 'fixture@example.invalid'
}

AfterAll {
    foreach ($name in $savedIdentity.Keys) {
        [System.Environment]::SetEnvironmentVariable($name, $savedIdentity[$name])
    }
}

Describe 'Invoke-CredentialScan.ps1' -Tag 'Unit' -Skip:(-not $hasGit) {
    Context 'When the scan finds nothing in the repository' {
        It 'Writes nothing and does not fail for <Scanner>' -ForEach $scannerCases {
            $repository = & $newRepository
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner $Scanner)

            $result = & $invokeStandInScan -Scanner $Scanner -Repository $repository -StandIn $standIn

            $result.Problem | Should-BeNull
            $result.Findings.Count | Should-Be 0
        }

        It 'Scans the probe, then the history, then the files for <Scanner>' -ForEach $scannerCases {
            $repository = & $newRepository
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner $Scanner)

            $null = & $invokeStandInScan -Scanner $Scanner -Repository $repository -StandIn $standIn
            $calls = & $getCalls -StandInPath $standIn

            $calls | Should-BeCollection -Count 3
            $calls[0].Source | Should-Be 'Probe'
            $calls[1].Source | Should-Be 'History'
            $calls[2].Source | Should-Be 'Files'
        }

        It 'Plants four values of each form in the probe' {
            # A scanner leaves out a random value now and then, so one value of a form is a probe
            # that fails at random.
            $repository = & $newRepository
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner 'trufflehog')

            $null = & $invokeStandInScan -Scanner 'trufflehog' -Repository $repository -StandIn $standIn
            $names = @((& $getCalls -StandInPath $standIn)[0].ProbeNames)

            $names | Should-BeCollection -Count 12
            $counts = @($names | Group-Object | Sort-Object -Property Name |
                    ForEach-Object { "$($_.Name) $($_.Count)" })
            $counts | Should-BeCollection -Count 3
            $counts[0] | Should-Be 'key 4'
            $counts[1] | Should-Be 'password 4'
            $counts[2] | Should-Be 'token 4'
        }

        It 'Gives <Scanner> the option <Required> and not <Forbidden>' -ForEach @(
            # A value stays out of the output, and none is sent to a service.
            @{ Scanner = 'betterleaks'; Required = '--redact'; Forbidden = '--validation' }
            @{ Scanner = 'gitleaks'; Required = '--redact'; Forbidden = '--verbose' }
            @{ Scanner = 'trufflehog'; Required = '--no-verification'; Forbidden = '--results' }
            # A finding has another exit code than a failure.
            @{ Scanner = 'betterleaks'; Required = '--exit-code'; Forbidden = '--verbose' }
            @{ Scanner = 'gitleaks'; Required = '--exit-code'; Forbidden = '--validation' }
            @{ Scanner = 'trufflehog'; Required = '--fail'; Forbidden = '--github-actions' }
            @{ Scanner = 'trufflehog'; Required = '--fail-on-scan-errors'; Forbidden = '--no-fail' }
        ) {
            $repository = & $newRepository
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner $Scanner)

            $null = & $invokeStandInScan -Scanner $Scanner -Repository $repository -StandIn $standIn
            $calls = & $getCalls -StandInPath $standIn

            $calls | Should-All { $_.Arguments -contains $Required }
            $calls | Should-All { $_.Arguments -notcontains $Forbidden }
        }

        It 'Scans the repository that contains the script when no path is given' {
            $repository = & $newRepository
            $scriptFolder = Join-Path -Path $repository -ChildPath '.github/scripts'
            $null = New-Item -Path $scriptFolder -ItemType Directory
            $copy = Join-Path -Path $scriptFolder -ChildPath 'Invoke-CredentialScan.ps1'
            Copy-Item -LiteralPath $scanScript -Destination $copy
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner 'gitleaks')

            $null = & $copy -Scanner gitleaks -ScannerPath $standIn

            (& $getCalls -StandInPath $standIn) | Should-BeCollection -Count 3
        }
    }

    Context 'When the scan reports a value' {
        It 'Writes one object for each finding of <Scanner> and then fails' -ForEach $scannerCases {
            $repository = & $newRepository
            $rules = $scannerFacts[$Scanner].ProbeRules
            $commit = 'a' * 40
            $scenario = & $newScenario -Scanner $Scanner
            $scenario.History = @(& $newItem -Rule $rules[0] -File 'old.txt' -Line 3 -Commit $commit)
            $scenario.Files = @(& $newItem -Rule $rules[1] -File 'now.txt' -Line 7)
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner $Scanner -Repository $repository -StandIn $standIn

            $result.Findings | Should-BeCollection -Count 2
            $result.Findings[0] | Should-HaveType 'PowerShellStandards.CredentialFinding'
            $result.Findings[0].Scanner | Should-Be $Scanner
            $result.Findings[0].Source | Should-Be 'History'
            $result.Findings[0].Rule | Should-Be $rules[0]
            $result.Findings[0].File | Should-Be 'old.txt'
            $result.Findings[0].Line | Should-Be 3
            $result.Findings[0].Commit | Should-Be $commit
            $result.Findings[0].Fingerprint | Should-Be "$($commit):old.txt:$($rules[0]):3"
            $result.Findings[1].Source | Should-Be 'Files'
            $result.Findings[1].Fingerprint | Should-Be "now.txt:$($rules[1]):7"
            $result.Problem.Exception.Message | Should-BeLikeString "*$Scanner reported 2 value(s)*"
            $result.Problem.Exception.Message | Should-BeLikeString "*now.txt:$($rules[1]):7*"
        }

        It 'Never writes the value that trufflehog found' {
            $repository = & $newRepository
            $scenario = & $newScenario -Scanner 'trufflehog'
            $scenario.Files = @(& $newItem -Rule 'Github' -File 'now.txt' -Line 7)
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner 'trufflehog' -Repository $repository -StandIn $standIn

            $result.Findings | Should-BeCollection -Count 1
            ($result.Findings | ConvertTo-Json -Depth 4) | Should-NotBeLikeString "*$rawValue*"
            $result.Problem.Exception.Message | Should-NotBeLikeString "*$rawValue*"
        }
    }

    Context 'When the scan cannot be trusted' {
        It 'Fails when <Scanner> finds only one value of the probe' -ForEach $scannerCases {
            $repository = & $newRepository
            $rules = $scannerFacts[$Scanner].ProbeRules
            $scenario = & $newScenario -Scanner $Scanner
            $scenario.Probe = @(& $newItem -Rule $rules[0] -File 'probe.txt' -Line 1)
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner $Scanner -Repository $repository -StandIn $standIn

            $result.Problem.Exception.Message | Should-BeLikeString "*probe reported $($rules[0])*has to report*"
            (& $getCalls -StandInPath $standIn) | Should-BeCollection -Count 1
        }

        It 'Fails when the probe finds nothing at all' {
            $repository = & $newRepository
            $scenario = & $newScenario -Scanner 'trufflehog'
            $scenario.Probe = @()
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner 'trufflehog' -Repository $repository -StandIn $standIn

            $result.Problem.Exception.Message | Should-BeLikeString '*probe reported nothing*'
        }

        It 'Fails when <Scanner> cannot scan the <Source>, and still runs the other scan' -ForEach @(
            @{ Scanner = 'gitleaks'; Source = 'History' }
            @{ Scanner = 'gitleaks'; Source = 'Files' }
            @{ Scanner = 'trufflehog'; Source = 'History' }
        ) {
            $repository = & $newRepository
            $scenario = & $newScenario -Scanner $Scanner
            $scenario.ExitCode[$Source] = 1
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner $Scanner -Repository $repository -StandIn $standIn

            $expected = "*scan of the $($Source.ToLowerInvariant()) failed. Exit code 1*"
            $result.Problem.Exception.Message | Should-BeLikeString $expected
            (& $getCalls -StandInPath $standIn) | Should-BeCollection -Count 3
        }

        It 'Fails when the scanner cannot scan the probe' {
            $repository = & $newRepository
            $scenario = & $newScenario -Scanner 'gitleaks'
            $scenario.ExitCode.Probe = 1
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner 'gitleaks' -Repository $repository -StandIn $standIn

            $expected = '*scan of the probe failed. Exit code 1*'
            $result.Problem.Exception.Message | Should-BeLikeString $expected
        }

        It 'Fails when <Scanner> ends as for a finding and none can be read in its <Where>' -ForEach @(
            @{ Scanner = 'betterleaks'; Source = 'History'; ExitCode = 3; Where = 'report' }
            @{ Scanner = 'gitleaks'; Source = 'Files'; ExitCode = 3; Where = 'report' }
            @{ Scanner = 'trufflehog'; Source = 'History'; ExitCode = 183; Where = 'output' }
        ) {
            $repository = & $newRepository
            $scenario = & $newScenario -Scanner $Scanner
            $scenario.ExitCode[$Source] = $ExitCode
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner $Scanner -Repository $repository -StandIn $standIn

            $word = $Source.ToLowerInvariant()
            $expected = "*scan of the $word failed*exit code for a finding*$Where holds none*"
            $result.Problem.Exception.Message | Should-BeLikeString $expected
            $result.Findings.Count | Should-Be 0
        }

        It 'Fails on a clone that does not hold the whole history' {
            $repository = & $newRepository
            & $addCommit -Path $repository -FileName 'second.txt' -Lines 'second' -Message 'second'
            $shallow = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
            $source = 'file://' + $repository.Replace('\', '/')
            & $invokeGit -Path $TestDrive -Arguments 'clone', '--quiet', '--depth', '1', $source, $shallow
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner 'gitleaks')

            $result = & $invokeStandInScan -Scanner 'gitleaks' -Repository $shallow -StandIn $standIn

            $expected = '*does not hold the whole history*fetch-depth: 0*'
            $result.Problem.Exception.Message | Should-BeLikeString $expected
        }

        It 'Fails for a folder that is not in a repository' {
            $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
            $null = New-Item -Path $folder -ItemType Directory
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner 'gitleaks')

            $result = & $invokeStandInScan -Scanner 'gitleaks' -Repository $folder -StandIn $standIn

            $result.Problem.Exception.Message | Should-BeLikeString '*is not inside a git repository*'
        }
    }

    Context 'The configuration and the ignore file' {
        It 'Passes <ConfigFile> and <IgnoreFile> of the repository to <Scanner>' -ForEach @(
            @{ Scanner = 'betterleaks'; ConfigFile = '.betterleaks.toml'; IgnoreFile = '.betterleaksignore' }
            @{ Scanner = 'gitleaks'; ConfigFile = '.gitleaks.toml'; IgnoreFile = '.gitleaksignore' }
        ) {
            $repository = & $newRepository
            $configPath = Join-Path -Path $repository -ChildPath $ConfigFile
            $ignorePath = Join-Path -Path $repository -ChildPath $IgnoreFile
            Set-Content -LiteralPath $configPath -Value '[extend]', 'useDefault = true' -Encoding ascii
            Set-Content -LiteralPath $ignorePath -Value '# nothing' -Encoding ascii
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner $Scanner)

            $null = & $invokeStandInScan -Scanner $Scanner -Repository $repository -StandIn $standIn
            $calls = & $getCalls -StandInPath $standIn

            $calls | Should-BeCollection -Count 3
            foreach ($call in $calls) {
                $arguments = @($call.Arguments)
                $givenConfig = $arguments[[array]::IndexOf($arguments, '--config') + 1]
                $givenIgnore = $arguments[[array]::IndexOf($arguments, '--gitleaks-ignore-path') + 1]
                $givenConfig | Should-Be (Convert-Path -LiteralPath $configPath)
                $givenIgnore | Should-Be (Convert-Path -LiteralPath $ignorePath)
            }
        }

        It 'Passes neither option when the repository has neither file' {
            $repository = & $newRepository
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner 'gitleaks')

            $null = & $invokeStandInScan -Scanner 'gitleaks' -Repository $repository -StandIn $standIn
            $calls = & $getCalls -StandInPath $standIn

            $calls | Should-All { $_.Arguments -notcontains '--config' }
            $calls | Should-All { $_.Arguments -notcontains '--gitleaks-ignore-path' }
        }

        It 'Fails when the <Parameter> that the caller names does not exist' -ForEach @(
            @{ Parameter = 'ConfigPath'; Word = 'configuration' }
            @{ Parameter = 'IgnorePath'; Word = 'ignore' }
        ) {
            $repository = & $newRepository
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner 'gitleaks')
            $parameters = @{ Scanner = 'gitleaks'; RepositoryPath = $repository; ScannerPath = $standIn }
            $parameters[$Parameter] = Join-Path -Path $repository -ChildPath 'absent.file'

            $result = & $invokeScan -Parameters $parameters

            $result.Problem.Exception.Message | Should-BeLikeString "*The $Word file*does not exist*"
        }

        It 'Leaves the .git folder and the paths of the project out of every trufflehog scan' {
            $repository = & $newRepository
            $excludePath = Join-Path -Path $repository -ChildPath '.trufflehog-exclude.txt'
            Set-Content -LiteralPath $excludePath -Value '# Generated output', '^out/', '' -Encoding ascii
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner 'trufflehog')

            $null = & $invokeStandInScan -Scanner 'trufflehog' -Repository $repository -StandIn $standIn
            $calls = & $getCalls -StandInPath $standIn

            $calls | Should-BeCollection -Count 3
            foreach ($call in $calls) {
                $lines = @($call.ExcludeLines)
                $lines | Should-BeCollection -Count 2
                '.git/config' | Should-MatchString $lines[0]
                'src/.git/config' | Should-MatchString $lines[0]
                'src/legit/config' | Should-NotMatchString $lines[0]
                $lines[1] | Should-Be '^out/'
            }
        }

        It 'Leaves out a finding of trufflehog whose fingerprint is in .trufflehogignore' {
            $repository = & $newRepository
            $commit = 'b' * 40
            $ignorePath = Join-Path -Path $repository -ChildPath '.trufflehogignore'
            $ignoreLines = '# A placeholder in a test', "$($commit):old.txt:Github:3"
            Set-Content -LiteralPath $ignorePath -Value $ignoreLines -Encoding ascii
            $scenario = & $newScenario -Scanner 'trufflehog'
            $scenario.History = @(
                & $newItem -Rule 'Github' -File 'old.txt' -Line 3 -Commit $commit
                & $newItem -Rule 'Stripe' -File 'old.txt' -Line 4 -Commit $commit
            )
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner 'trufflehog' -Repository $repository -StandIn $standIn

            $result.Findings | Should-BeCollection -Count 1
            $result.Findings[0].Fingerprint | Should-Be "$($commit):old.txt:Stripe:4"
        }

        It 'Gives a trufflehog finding in a file its path from the root of the repository' {
            $repository = & $newRepository
            $absolute = Join-Path -Path (Convert-Path -LiteralPath $repository) -ChildPath 'src/now.txt'
            $scenario = & $newScenario -Scanner 'trufflehog'
            $scenario.Files = @(
                & $newItem -Rule 'Github' -File $absolute -Line 7
                & $newItem -Rule 'Stripe' -File './other.txt' -Line 2
            )
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner 'trufflehog' -Repository $repository -StandIn $standIn

            $result.Findings | Should-BeCollection -Count 2
            $result.Findings[0].Fingerprint | Should-Be 'src/now.txt:Github:7'
            $result.Findings[1].Fingerprint | Should-Be 'other.txt:Stripe:2'
        }
    }

    Context 'What the project leaves out of the scan' {
        It 'Writes no warning when <Scanner> has no ignore file and no configuration' -ForEach $scannerCases {
            $repository = & $newRepository
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner $Scanner)

            $result = & $invokeStandInScan -Scanner $Scanner -Repository $repository -StandIn $standIn

            $result.Warnings.Count | Should-Be 0
        }

        It 'Says how many fingerprints <IgnoreFile> names' -ForEach @(
            @{ Scanner = 'betterleaks'; IgnoreFile = '.betterleaksignore' }
            @{ Scanner = 'gitleaks'; IgnoreFile = '.gitleaksignore' }
        ) {
            $repository = & $newRepository
            $ignorePath = Join-Path -Path $repository -ChildPath $IgnoreFile
            $ignoreLines = '# Placeholders in tests', 'old.txt:github-pat:3', '', 'now.txt:stripe-access-token:7'
            Set-Content -LiteralPath $ignorePath -Value $ignoreLines -Encoding ascii
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner $Scanner)

            $result = & $invokeStandInScan -Scanner $Scanner -Repository $repository -StandIn $standIn

            $result.Problem | Should-BeNull
            $result.Warnings | Should-BeCollection -Count 1
            $result.Warnings[0] | Should-BeLikeString "Left out of this scan:*2 fingerprint(s) in $IgnoreFile*"
        }

        It 'Scans twice with the default configuration of betterleaks, and writes no warning for a clean scan' {
            $repository = & $newRepository
            $templatePath = Join-Path -Path $repositoryRoot -ChildPath 'Templates/CredentialScan/betterleaks.toml'
            $configPath = Join-Path -Path $repository -ChildPath '.betterleaks.toml'
            Copy-Item -LiteralPath $templatePath -Destination $configPath
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner 'betterleaks')

            $result = & $invokeStandInScan -Scanner 'betterleaks' -Repository $repository -StandIn $standIn
            $calls = & $getCalls -StandInPath $standIn

            $result.Problem | Should-BeNull
            $result.Warnings.Count | Should-Be 0
            $calls | Should-BeCollection -Count 5
        }

        It 'Scans once with the default configuration of <Scanner>, which leaves nothing out' -ForEach @(
            @{ Scanner = 'gitleaks'; Template = 'gitleaks.toml' }
            @{ Scanner = 'trufflehog'; Template = 'trufflehog-exclude.txt' }
        ) {
            $repository = & $newRepository
            $templatePath = Join-Path -Path $repositoryRoot -ChildPath "Templates/CredentialScan/$Template"
            Copy-Item -LiteralPath $templatePath -Destination (Join-Path -Path $repository -ChildPath ".$Template")
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner $Scanner)

            $result = & $invokeStandInScan -Scanner $Scanner -Repository $repository -StandIn $standIn

            $result.Warnings.Count | Should-Be 0
            (& $getCalls -StandInPath $standIn) | Should-BeCollection -Count 3
        }

        It 'Counts by rule the places that <Scanner> reports only without its configuration' -ForEach @(
            @{ Scanner = 'betterleaks' }
            @{ Scanner = 'gitleaks' }
        ) {
            $repository = & $newRepository
            $configName = ".$Scanner.toml"
            $configLines = '[extend]', 'useDefault = true', "disabledRules = ['aws-access-token']"
            $configPath = Join-Path -Path $repository -ChildPath $configName
            Set-Content -LiteralPath $configPath -Value $configLines -Encoding ascii
            $commit = 'c' * 40
            $scenario = & $newScenario -Scanner $Scanner
            $scenario.Plain.History = @(
                & $newItem -Rule 'github-pat' -File 'old.txt' -Line 3 -Commit $commit
                & $newItem -Rule 'aws-access-token' -File 'leak.txt' -Line 1 -Commit $commit
            )
            $scenario.Plain.Files = @(& $newItem -Rule 'aws-access-token' -File 'leak.txt' -Line 1)
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner $Scanner -Repository $repository -StandIn $standIn
            $calls = & $getCalls -StandInPath $standIn

            $result.Problem | Should-BeNull
            $result.Findings.Count | Should-Be 0
            $result.Warnings | Should-BeCollection -Count 1
            $byRule = '2 by aws-access-token, 1 by github-pat'
            $expected = "3 place(s) that $Scanner reports without $configName, $byRule"
            $result.Warnings[0] | Should-Be "Left out of this scan: $expected."
            $calls | Should-BeCollection -Count 5
            $order = @($calls | ForEach-Object { '{0} with {1}' -f $_.Source, $_.Configuration })
            $own = "with $configName"
            $builtIn = 'with built-in-rules.toml'
            $order -join ', ' | Should-Be "Probe $own, History $own, History $builtIn, Files $own, Files $builtIn"
        }

        It 'Does not count a place that another rule still reports under the configuration' {
            $repository = & $newRepository
            $configPath = Join-Path -Path $repository -ChildPath '.gitleaks.toml'
            $configLines = '[extend]', 'useDefault = true', "disabledRules = ['github-pat']"
            Set-Content -LiteralPath $configPath -Value $configLines -Encoding ascii
            $commit = 'c' * 40
            $scenario = & $newScenario -Scanner 'gitleaks'
            $scenario.History = @(& $newItem -Rule 'generic-api-key' -File 'old.txt' -Line 3 -Commit $commit)
            $scenario.Plain.History = @(& $newItem -Rule 'github-pat' -File 'old.txt' -Line 3 -Commit $commit)
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner 'gitleaks' -Repository $repository -StandIn $standIn

            $result.Findings | Should-BeCollection -Count 1
            $result.Warnings.Count | Should-Be 0
        }

        It 'Names each place that the configuration leaves out when -Verbose is given' {
            $repository = & $newRepository
            $configPath = Join-Path -Path $repository -ChildPath '.gitleaks.toml'
            Set-Content -LiteralPath $configPath -Value '[[allowlists]]', "paths = ['''leak''']" -Encoding ascii
            $scenario = & $newScenario -Scanner 'gitleaks'
            $scenario.Plain.Files = @(& $newItem -Rule 'aws-access-token' -File 'leak.txt' -Line 7)
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner 'gitleaks' -Repository $repository -StandIn $standIn

            $expected = 'Left out by .gitleaks.toml: Files, aws-access-token in leak.txt, line 7.'
            $result.LeftOutPlaces | Should-BeCollection -Count 1
            $result.LeftOutPlaces[0] | Should-Be $expected
        }

        It 'Scans twice when the configuration holds <Spelling>' -ForEach @(
            @{ Spelling = 'a quoted key'; Lines = '[extend]', "`"disabledRules`" = ['a-rule']" }
            @{ Spelling = 'a header with spaces'; Lines = '[ extend ]', 'useDefault = true' }
            @{ Spelling = 'a rule under a header with spaces'; Lines = '[extend]', '[[ rules ]]' }
            @{ Spelling = 'a dotted key'; Lines = 'extend.useDefault = true', "extend.disabledRules = ['a-rule']" }
            @{ Spelling = 'an inline table'; Lines = @('extend = { useDefault = true }') }
            @{ Spelling = 'a comment after a setting'; Lines = '[extend]', 'useDefault = true # built in' }
            @{ Spelling = 'a title over several lines'; Lines = "title = '''", "'''", '[extend]' }
            @{ Spelling = 'a setting that no scanner knows'; Lines = '[extend]', 'useDefault = true', 'other = 1' }
        ) {
            $repository = & $newRepository
            $configPath = Join-Path -Path $repository -ChildPath '.gitleaks.toml'
            Set-Content -LiteralPath $configPath -Value $Lines -Encoding ascii
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner 'gitleaks')

            $null = & $invokeStandInScan -Scanner 'gitleaks' -Repository $repository -StandIn $standIn

            (& $getCalls -StandInPath $standIn) | Should-BeCollection -Count 5
        }

        It 'Scans once when the configuration holds only <Content>' -ForEach @(
            @{ Content = 'comments and blank lines'; Lines = '# A comment', '', '  # [[allowlists]]' }
            @{
                Content = 'a title and the built-in rules'
                Lines = '# Scan', 'title = "Credential scan"', '', '[extend]', '    useDefault = true'
            }
        ) {
            $repository = & $newRepository
            $configPath = Join-Path -Path $repository -ChildPath '.gitleaks.toml'
            Set-Content -LiteralPath $configPath -Value $Lines -Encoding ascii
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner 'gitleaks')

            $null = & $invokeStandInScan -Scanner 'gitleaks' -Repository $repository -StandIn $standIn

            (& $getCalls -StandInPath $standIn) | Should-BeCollection -Count 3
        }

        It 'Fails when the scan without the configuration cannot run' {
            $repository = & $newRepository
            $configPath = Join-Path -Path $repository -ChildPath '.gitleaks.toml'
            Set-Content -LiteralPath $configPath -Value '[[allowlists]]', "paths = ['''leak''']" -Encoding ascii
            $scenario = & $newScenario -Scanner 'gitleaks'
            $scenario.Plain.History = @()
            $scenario.Plain.Files = @()
            $scenario.Plain.ExitCode = 1
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner 'gitleaks' -Repository $repository -StandIn $standIn

            $message = $result.Problem.Exception.Message
            $message | Should-BeLikeString '*The scan of the history without the configuration failed*'
            $message | Should-BeLikeString '*The scan of the files without the configuration failed*'
        }

        It 'Says how many findings of trufflehog the ignore list left out, and how many paths are left out' {
            $repository = & $newRepository
            $commit = 'c' * 40
            $ignorePath = Join-Path -Path $repository -ChildPath '.trufflehogignore'
            $ignoreLines = "$($commit):old.txt:Github:3", 'never.txt:Stripe:1'
            Set-Content -LiteralPath $ignorePath -Value $ignoreLines -Encoding ascii
            $excludePath = Join-Path -Path $repository -ChildPath '.trufflehog-exclude.txt'
            Set-Content -LiteralPath $excludePath -Value '# Generated output', '^out/' -Encoding ascii
            $scenario = & $newScenario -Scanner 'trufflehog'
            $scenario.History = @(& $newItem -Rule 'Github' -File 'old.txt' -Line 3 -Commit $commit)
            $standIn = & $newStandIn -Scenario $scenario

            $result = & $invokeStandInScan -Scanner 'trufflehog' -Repository $repository -StandIn $standIn

            $result.Problem | Should-BeNull
            $result.Warnings | Should-BeCollection -Count 1
            $result.Warnings[0] | Should-BeLikeString '*1 finding(s) whose fingerprint is in .trufflehogignore*'
            $result.Warnings[0] | Should-BeLikeString '*1 pattern(s) in .trufflehog-exclude.txt*'
        }

        It 'Does not count a fingerprint of .trufflehogignore that matches no finding' {
            $repository = & $newRepository
            $ignorePath = Join-Path -Path $repository -ChildPath '.trufflehogignore'
            Set-Content -LiteralPath $ignorePath -Value 'never.txt:Stripe:1' -Encoding ascii
            $standIn = & $newStandIn -Scenario (& $newScenario -Scanner 'trufflehog')

            $result = & $invokeStandInScan -Scanner 'trufflehog' -Repository $repository -StandIn $standIn

            $result.Warnings.Count | Should-Be 0
        }
    }

    Context 'The exception for PowerShell in the default configuration of betterleaks' {
        BeforeAll {
            # The first pattern of the template excepts an unquoted value in a PowerShell file. It is
            # tried here on the text that betterleaks 1.10.1 gives as the match of its rule.
            $templatePath = Join-Path -Path $repositoryRoot -ChildPath 'Templates/CredentialScan/betterleaks.toml'
            $templateText = Get-Content -LiteralPath $templatePath -Raw
            $patternMatches = [regex]::Matches($templateText, "regexes = \['''(?<pattern>.*?)'''\]")
            $patterns = @($patternMatches | ForEach-Object { $_.Groups['pattern'].Value })
        }

        It 'Holds two patterns' {
            $patterns | Should-BeCollection -Count 2
        }

        It 'Excepts <Text>, which is an expression' -ForEach @(
            @{ Text = 'password = [System.Security.SecureString]::new()' }
            @{ Text = 'Password = $plainText' }
            @{ Text = 'password=Get-Secret' }
        ) {
            [regex]::IsMatch($Text, $patterns[0]) | Should-BeTrue
        }

        It 'Does not except <Text>, which is a string literal' -ForEach @(
            @{ Text = "password = 'qwerty'" }
            @{ Text = 'password = "qwerty"' }
            @{ Text = "Password = 'Summer2026!'" }
            @{ Text = "password='Summer2026!'" }
            @{ Text = "password =  'Summer2026!'" }
        ) {
            [regex]::IsMatch($Text, $patterns[0]) | Should-BeFalse
        }
    }

    Context 'The version of the scanner' {
        It 'Fails when <Given> is given without the other' -ForEach @(
            @{ Given = 'Version'; Value = '8.30.1' }
            @{ Given = 'Sha256'; Value = 'a' * 64 }
        ) {
            $repository = & $newRepository
            $parameters = @{ Scanner = 'gitleaks'; RepositoryPath = $repository }
            $parameters[$Given] = $Value

            $result = & $invokeScan -Parameters $parameters

            $result.Problem.Exception.Message | Should-BeLikeString '*Version and Sha256 belong together*'
        }

        It 'Refuses <Version> of <Scanner>, which has another major version' -ForEach @(
            @{ Scanner = 'betterleaks'; Version = '2.0.0' }
            @{ Scanner = 'gitleaks'; Version = '9.0.0' }
            @{ Scanner = 'trufflehog'; Version = '4.0.0' }
        ) {
            $repository = & $newRepository
            $parameters = @{ Scanner = $Scanner; RepositoryPath = $repository; Version = $Version }
            $parameters['Sha256'] = 'a' * 64

            $result = & $invokeScan -Parameters $parameters

            $result.Problem.Exception.Message | Should-BeLikeString '*has another major version*'
        }

        It 'Holds a SHA-256 for six archives of <Scanner>' -ForEach $scannerCases {
            $text = Get-Content -LiteralPath $scanScript -Raw
            $block = [regex]::Match($text, "(?s)\n    $Scanner = @\{.*?\n    \}").Value
            $hashPattern = "'(?:linux|darwin|windows)_[a-z0-9]+' = '(?<hash>[0-9a-f]{64})'"
            $hashes = @([regex]::Matches($block, $hashPattern) | ForEach-Object { $_.Groups['hash'].Value })

            $hashes | Should-BeCollection -Count 6
            @($hashes | Sort-Object -Unique) | Should-BeCollection -Count 6
        }
    }
}

Describe 'Invoke-CredentialScan.ps1 with the real scanners' -Tag 'Integration' -Skip:(-not $runRealScanners) {
    BeforeAll {
        # A value in the form of a key, put together from parts so that this file holds none.
        $newKey = {
            param([string]$Kind)

            $bytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(96)
            $random = [System.Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', ''
            if ($Kind -eq 'stripe') {
                'key: ' + 'sk_' + 'live_' + $random.Substring(0, 32)
            } else {
                'token: ' + 'gh' + 'p_' + $random.Substring(0, 36)
            }
        }

        # A repository with a value that a later commit removed, and one that a merge commit added.
        $newLeakyRepository = {
            $path = & $newRepository
            & $addCommit -Path $path -FileName 'old.txt' -Lines (& $newKey -Kind 'stripe') -Message 'add a value'
            & $invokeGit -Path $path -Arguments 'rm', '--quiet', 'old.txt'
            & $invokeGit -Path $path -Arguments 'commit', '--quiet', '-m', 'remove the value'
            & $invokeGit -Path $path -Arguments 'switch', '--quiet', '-c', 'side'
            & $addCommit -Path $path -FileName 'side.txt' -Lines 'side' -Message 'side'
            & $invokeGit -Path $path -Arguments 'switch', '--quiet', 'main'
            & $addCommit -Path $path -FileName 'main.txt' -Lines 'main' -Message 'main'
            & $invokeGit -Path $path -Arguments 'merge', '--quiet', '--no-ff', '--no-commit', 'side'
            $token = & $newKey -Kind 'github'
            & $addCommit -Path $path -FileName 'merged.txt' -Lines $token -Message 'merge, and add a value'
            $path
        }

        # A repository whose PowerShell names a password, in a script and in a Markdown code block.
        $newPowerShellRepository = {
            param([string]$ScriptLine)

            $path = & $newRepository
            $fence = '`' * 3
            $guide = '# Guide', '', "$($fence)powershell", $ScriptLine, $fence
            Set-Content -LiteralPath (Join-Path -Path $path -ChildPath 'Guide.md') -Value $guide -Encoding ascii
            & $addCommit -Path $path -FileName 'Sample.ps1' -Lines $ScriptLine -Message 'sample'
            $path
        }

        # Each scanner is downloaded once, by the script, and used from that folder afterwards.
        # It happens here and not in a test: Pester removes what a Context wrote to the test
        # drive when the Context ends, and the tests run in a shuffled order.
        $cleanRepository = & $newRepository
        $executables = @{}
        foreach ($name in 'betterleaks', 'gitleaks', 'trufflehog') {
            $toolFolder = Join-Path -Path $TestDrive -ChildPath "tool-$name"
            $null = & $scanScript -Scanner $name -RepositoryPath $cleanRepository -ToolPath $toolFolder
            $fileName = if ($IsWindows) { "$name.exe" } else { $name }
            $executables[$name] = Join-Path -Path $toolFolder -ChildPath $fileName
        }

        # Runs the scan of a repository with a scanner that was downloaded.
        $invokeRealScan = {
            param([string]$Scanner, [string]$Repository)

            $executable = $executables[$Scanner]
            $parameters = @{ Scanner = $Scanner; RepositoryPath = $Repository; ScannerPath = $executable }
            $result = & $invokeScan -Parameters $parameters
            # A scan that could not run fails the test with its own message.
            if ($result.Problem -and $result.Problem.Exception.Message -notlike '*may be credentials*') {
                throw $result.Problem
            }

            $result
        }

        # Copies the default configuration of a scanner into a repository.
        $templateFolder = Join-Path -Path $repositoryRoot -ChildPath 'Templates/CredentialScan'
        $addTemplate = {
            param([string]$Repository, [string]$Template, [string]$ConfigFile)

            $templatePath = Join-Path -Path $templateFolder -ChildPath $Template
            Copy-Item -LiteralPath $templatePath -Destination (Join-Path -Path $Repository -ChildPath $ConfigFile)
        }
    }

    Context 'The download' {
        It 'Has downloaded <Scanner> after its hash matched, and finds nothing in a clean repository' -ForEach @(
            @{ Scanner = 'betterleaks' }
            @{ Scanner = 'gitleaks' }
            @{ Scanner = 'trufflehog' }
        ) {
            $result = & $invokeRealScan -Scanner $Scanner -Repository $cleanRepository

            Test-Path -LiteralPath $executables[$Scanner] -PathType Leaf | Should-BeTrue
            $result.Problem | Should-BeNull
            $result.Findings.Count | Should-Be 0
        }

        It 'Refuses an archive of <Scanner> whose hash is not the expected one' -ForEach @(
            @{ Scanner = 'betterleaks'; Version = '1.10.1' }
            @{ Scanner = 'gitleaks'; Version = '8.30.1' }
        ) {
            $repository = & $newRepository
            $toolFolder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
            $parameters = @{
                Scanner = $Scanner
                RepositoryPath = $repository
                Version = $Version
                Sha256 = 'a' * 64
                ToolPath = $toolFolder
            }

            $result = & $invokeScan -Parameters $parameters

            $result.Problem.Exception.Message | Should-BeLikeString '*The SHA-256 of*Nothing was unpacked*'
            @(Get-ChildItem -LiteralPath $toolFolder -File).Count | Should-Be 0
        }

        It 'Scans with the pin that the installer writes for <Scanner>' -Skip:(-not $onLinuxX64) -ForEach @(
            @{ Scanner = 'betterleaks' }
            @{ Scanner = 'gitleaks' }
            @{ Scanner = 'trufflehog' }
        ) {
            $project = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
            $null = New-Item -Path $project -ItemType Directory
            $installScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools/Install-CopilotStandards.ps1'
            $null = & $installScript -ProjectPath $project -IncludeCredentialScan $Scanner
            $workflowPath = Join-Path -Path $project -ChildPath '.github/workflows/credential-scan.yml'
            $workflowText = Get-Content -LiteralPath $workflowPath -Raw
            $versionMatch = [regex]::Match($workflowText, "SCANNER_VERSION: '(?<value>[^']+)'")
            $hashMatch = [regex]::Match($workflowText, "SCANNER_SHA256: '(?<value>[^']+)'")
            $parameters = @{
                Scanner = $Scanner
                RepositoryPath = & $newRepository
                Version = $versionMatch.Groups['value'].Value
                Sha256 = $hashMatch.Groups['value'].Value
            }

            $result = & $invokeScan -Parameters $parameters

            $result.Problem | Should-BeNull
        }
    }

    Context 'What the installer writes' {
        It 'Holds nothing that <Scanner> reports, the workflow with its pin included' -ForEach @(
            @{ Scanner = 'betterleaks' }
            @{ Scanner = 'gitleaks' }
            @{ Scanner = 'trufflehog' }
        ) {
            # The project gets the rules, the skills, the script, the workflow, and the
            # configuration. A finding in one of them would fail the first scan of every project.
            $project = & $newRepository
            $installScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools/Install-CopilotStandards.ps1'
            $null = & $installScript -ProjectPath $project -IncludeCredentialScan $Scanner
            & $invokeGit -Path $project -Arguments 'add', '-A'
            & $invokeGit -Path $project -Arguments 'commit', '--quiet', '-m', 'install the standards'
            $workflowPath = Join-Path -Path $project -ChildPath '.github/workflows/credential-scan.yml'

            $result = & $invokeRealScan -Scanner $Scanner -Repository $project

            Get-Content -LiteralPath $workflowPath -Raw | Should-MatchString "SCANNER_SHA256: '[0-9a-f]{64}'"
            $result.Problem | Should-BeNull
            $result.Findings.Count | Should-Be 0
        }
    }

    Context 'A repository that holds values' {
        It 'Finds with <Scanner> what a commit removed and what a merge added' -ForEach $scannerCases {
            $repository = & $newLeakyRepository

            $result = & $invokeRealScan -Scanner $Scanner -Repository $repository

            $history = @($result.Findings | Where-Object { $_.Source -eq 'History' })
            $files = @($result.Findings | Where-Object { $_.Source -eq 'Files' })
            $history | Should-BeCollection -Count 1
            $history[0].File | Should-Be 'old.txt'
            $history[0].Commit | Should-MatchString '^[0-9a-f]{40}$'
            $files | Should-BeCollection -Count 1
            $files[0].File | Should-Be 'merged.txt'
            $result.Problem.Exception.Message | Should-BeLikeString "*$Scanner reported 2 value(s)*"
        }

        It 'Passes with <Scanner> once both fingerprints are in <IgnoreFile>' -ForEach @(
            @{ Scanner = 'betterleaks'; IgnoreFile = '.betterleaksignore' }
            @{ Scanner = 'gitleaks'; IgnoreFile = '.gitleaksignore' }
            @{ Scanner = 'trufflehog'; IgnoreFile = '.trufflehogignore' }
        ) {
            $repository = & $newLeakyRepository
            $first = & $invokeRealScan -Scanner $Scanner -Repository $repository
            $ignorePath = Join-Path -Path $repository -ChildPath $IgnoreFile
            $fingerprints = @($first.Findings | ForEach-Object { $_.Fingerprint })
            Set-Content -LiteralPath $ignorePath -Value $fingerprints -Encoding ascii

            $second = & $invokeRealScan -Scanner $Scanner -Repository $repository

            $first.Findings | Should-BeCollection -Count 2
            $second.Problem | Should-BeNull
            $second.Findings.Count | Should-Be 0
            $second.Warnings | Should-BeCollection -Count 1
            $second.Warnings[0] | Should-BeLikeString "Left out of this scan:*$IgnoreFile*"
        }
    }

    Context 'A configuration that leaves a value out' {
        BeforeAll {
            # A value that a rule outside the probe reports. It stands alone on its line, so that no
            # generic rule reports the line once that rule is off.
            $newOtherValue = {
                param([string]$Rule)

                if ($Rule -eq 'aws-access-token') {
                    # Sixteen different characters, so that the value is random enough for the rule.
                    $tail = 'BCDEFGHJLMNOPQRSTUVWXYZ234567'.ToCharArray() | Get-Random -Count 16
                    'AK' + 'IA' + (-join $tail)
                } else {
                    (& $newKey -Kind 'github') -replace '^token: ', ''
                }
            }

            # A configuration that keeps the built-in rules and leaves the value out in one way. The
            # last four are other spellings of the same settings, which TOML allows.
            $newConfiguration = {
                param([string]$Setting, [string]$Rule)

                $extend = '[extend]', 'useDefault = true'
                switch ($Setting) {
                    'disabledRules' {
                        $extend + "disabledRules = ['$Rule']"
                    }
                    'a rule of the same name' {
                        $extend + '', '[[rules]]', "id = '$Rule'", "regex = '''never-there-zzzz'''"
                    }
                    'an extended file' {
                        $basePath = Join-Path -Path $TestDrive -ChildPath "$([guid]::NewGuid().ToString('N')).toml"
                        $baseLines = $extend + '', '[[allowlists]]', "paths = ['''leak\.txt''']"
                        Set-Content -LiteralPath $basePath -Value $baseLines -Encoding ascii
                        '[extend]', "path = '$($basePath.Replace('\', '/'))'"
                    }
                    'a filter' {
                        @("filter = '''filter.containsAny(finding[`"secret`"], [`"ghp_`"])'''") + '' + $extend
                    }
                    'disabledRules as a quoted key' {
                        $extend + "`"disabledRules`" = ['$Rule']"
                    }
                    'a header with spaces and a key in single quotes' {
                        '[ extend ]', 'useDefault = true', "'disabledRules' = ['$Rule']"
                    }
                    'a rule of the same name under a header with spaces' {
                        $extend + '', '[[ rules ]]', "id = '$Rule'", "regex = '''never-there-zzzz'''"
                    }
                    'an exception under a header with spaces' {
                        $extend + '', '[[ allowlists ]]', "paths = ['''leak\.txt''']"
                    }
                }
            }
        }

        It 'Passes with <Scanner> under <Setting>, and says what is left out' -ForEach @(
            @{ Scanner = 'gitleaks'; Rule = 'aws-access-token'; Setting = 'disabledRules' }
            @{ Scanner = 'gitleaks'; Rule = 'aws-access-token'; Setting = 'a rule of the same name' }
            @{ Scanner = 'gitleaks'; Rule = 'aws-access-token'; Setting = 'an extended file' }
            @{ Scanner = 'gitleaks'; Rule = 'aws-access-token'; Setting = 'disabledRules as a quoted key' }
            @{
                Scanner = 'gitleaks'
                Rule = 'aws-access-token'
                Setting = 'a header with spaces and a key in single quotes'
            }
            @{
                Scanner = 'gitleaks'
                Rule = 'aws-access-token'
                Setting = 'a rule of the same name under a header with spaces'
            }
            @{
                Scanner = 'gitleaks'
                Rule = 'aws-access-token'
                Setting = 'an exception under a header with spaces'
            }
            @{ Scanner = 'betterleaks'; Rule = 'github-pat'; Setting = 'disabledRules' }
            @{ Scanner = 'betterleaks'; Rule = 'github-pat'; Setting = 'a rule of the same name' }
            @{ Scanner = 'betterleaks'; Rule = 'github-pat'; Setting = 'an extended file' }
            @{ Scanner = 'betterleaks'; Rule = 'github-pat'; Setting = 'a filter' }
            @{ Scanner = 'betterleaks'; Rule = 'github-pat'; Setting = 'disabledRules as a quoted key' }
            @{
                Scanner = 'betterleaks'
                Rule = 'github-pat'
                Setting = 'a header with spaces and a key in single quotes'
            }
            @{
                Scanner = 'betterleaks'
                Rule = 'github-pat'
                Setting = 'a rule of the same name under a header with spaces'
            }
            @{ Scanner = 'betterleaks'; Rule = 'github-pat'; Setting = 'an exception under a header with spaces' }
        ) {
            $repository = & $newRepository
            $value = & $newOtherValue -Rule $Rule
            & $addCommit -Path $repository -FileName 'leak.txt' -Lines $value -Message 'add a value'
            $first = & $invokeRealScan -Scanner $Scanner -Repository $repository
            $configName = ".$Scanner.toml"
            $configLines = & $newConfiguration -Setting $Setting -Rule $Rule
            $configPath = Join-Path -Path $repository -ChildPath $configName
            Set-Content -LiteralPath $configPath -Value $configLines -Encoding ascii

            $second = & $invokeRealScan -Scanner $Scanner -Repository $repository

            $first.Findings | Should-BeCollection -Count 2
            $firstRules = @($first.Findings | ForEach-Object { $_.Rule } | Sort-Object -Unique)
            $firstRules -join ',' | Should-Be $Rule
            $second.Problem | Should-BeNull
            $second.Findings.Count | Should-Be 0
            $second.Warnings | Should-BeCollection -Count 1
            $expected = "2 place(s) that $Scanner reports without $configName, 2 by $Rule"
            $second.Warnings[0] | Should-Be "Left out of this scan: $expected."
        }

        It 'Fails with <Scanner> when the configuration switches off a rule of the probe' -ForEach @(
            @{ Scanner = 'betterleaks' }
            @{ Scanner = 'gitleaks' }
        ) {
            $repository = & $newRepository
            $configPath = Join-Path -Path $repository -ChildPath ".$Scanner.toml"
            $configLines = '[extend]', 'useDefault = true', "disabledRules = ['stripe-access-token']"
            Set-Content -LiteralPath $configPath -Value $configLines -Encoding ascii
            $executable = $executables[$Scanner]
            $parameters = @{ Scanner = $Scanner; RepositoryPath = $repository; ScannerPath = $executable }

            $result = & $invokeScan -Parameters $parameters

            $message = $result.Problem.Exception.Message
            $message | Should-BeLikeString '*The scan of the probe reported*It has to report*stripe-access-token*'
        }
    }

    Context 'The default configurations' {
        It 'Still finds both values with <Scanner> when <Template> is in the repository' -ForEach @(
            @{ Scanner = 'betterleaks'; Template = 'betterleaks.toml'; ConfigFile = '.betterleaks.toml' }
            @{ Scanner = 'gitleaks'; Template = 'gitleaks.toml'; ConfigFile = '.gitleaks.toml' }
            @{
                Scanner = 'trufflehog'
                Template = 'trufflehog-exclude.txt'
                ConfigFile = '.trufflehog-exclude.txt'
            }
        ) {
            $repository = & $newLeakyRepository
            & $addTemplate -Repository $repository -Template $Template -ConfigFile $ConfigFile

            $result = & $invokeRealScan -Scanner $Scanner -Repository $repository

            $result.Findings | Should-BeCollection -Count 2
            $reportedFiles = @($result.Findings | ForEach-Object { $_.File } | Sort-Object)
            $reportedFiles -join ',' | Should-Be 'merged.txt,old.txt'
        }

        It 'Reports an empty secure string with betterleaks, and no longer with its default configuration' {
            $line = '$password = [System.Security.SecureString]::new()'
            $repository = & $newPowerShellRepository -ScriptLine $line

            $without = & $invokeRealScan -Scanner 'betterleaks' -Repository $repository
            & $addTemplate -Repository $repository -Template 'betterleaks.toml' -ConfigFile '.betterleaks.toml'
            $with = & $invokeRealScan -Scanner 'betterleaks' -Repository $repository

            $without.Findings | Should-BeCollection -Count 4
            $without.Findings | Should-All { $_.Rule -eq 'generic-password' }
            $reportedFiles = @($without.Findings | ForEach-Object { $_.File } | Sort-Object -Unique)
            $reportedFiles -join ',' | Should-Be 'Guide.md,Sample.ps1'
            $with.Problem | Should-BeNull
            $with.Findings.Count | Should-Be 0
            # The fifth place is in the configuration itself, whose comment quotes the expression.
            $expected = '5 place(s) that betterleaks reports without .betterleaks.toml, 5 by generic-password'
            $with.Warnings | Should-BeCollection -Count 1
            $with.Warnings[0] | Should-Be "Left out of this scan: $expected."
            $leftOutFiles = @($with.LeftOutPlaces | ForEach-Object { ($_ -split ' in |, line ')[1] } | Sort-Object)
            $leftOutFiles -join ',' | Should-Be '.betterleaks.toml,Guide.md,Guide.md,Sample.ps1,Sample.ps1'
        }

        It 'Still reports a quoted password with betterleaks under its default configuration' {
            $line = "`$password = '$([guid]::NewGuid().ToString('N'))'"
            $repository = & $newPowerShellRepository -ScriptLine $line
            & $addTemplate -Repository $repository -Template 'betterleaks.toml' -ConfigFile '.betterleaks.toml'

            $result = & $invokeRealScan -Scanner 'betterleaks' -Repository $repository

            $result.Findings | Should-BeCollection -Count 4
            $result.Findings | Should-All { $_.Rule -eq 'generic-password' }
        }

        It 'Does not report an empty secure string with <Scanner>, which needs no exception for it' -ForEach @(
            @{ Scanner = 'gitleaks' }
            @{ Scanner = 'trufflehog' }
        ) {
            $line = '$password = [System.Security.SecureString]::new()'
            $repository = & $newPowerShellRepository -ScriptLine $line

            $result = & $invokeRealScan -Scanner $Scanner -Repository $repository

            $result.Problem | Should-BeNull
            $result.Findings.Count | Should-Be 0
        }
    }
}
