#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $installScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools/Install-CopilotStandards.ps1'
    $workflowTemplate = Join-Path -Path $repositoryRoot -ChildPath 'Templates/Workflows/sync-copilot-standards.yml'

    # Full path of a file inside the project folder that the current test uses.
    $getProjectFile = {
        param([string]$RelativePath)
        Join-Path -Path $projectPath -ChildPath $RelativePath
    }

    # Whether a path inside the project folder exists.
    $testProjectFile = {
        param([string]$RelativePath)
        Test-Path -LiteralPath (Join-Path -Path $projectPath -ChildPath $RelativePath)
    }

    # Creates a file inside the project folder, with its parent folders, and returns its full path.
    $newProjectFile = {
        param([string]$RelativePath, [string]$Content)
        $fullPath = Join-Path -Path $projectPath -ChildPath $RelativePath
        $null = New-Item -Path (Split-Path -Path $fullPath -Parent) -ItemType Directory -Force
        Set-Content -LiteralPath $fullPath -Value $Content -Encoding ascii
        $fullPath
    }

    # The results that the installer reported for one path with one status.
    $selectResult = {
        param([object[]]$Files, [string]$Path, [string]$Status)
        @($Files | Where-Object { $_.Path -eq $Path -and $_.Status -eq $Status })
    }
}

Describe 'Install-CopilotStandards.ps1' -Tag 'Unit' {
    BeforeEach {
        # The script writes to disk, so every test gets its own project folder.
        $projectPath = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $projectPath -ItemType Directory
    }

    Context 'With default parameters' {
        It 'Installs <RelativePath>' -ForEach @(
            @{ RelativePath = '.github/copilot-instructions.md' }
            @{ RelativePath = 'AGENTS.md' }
            @{ RelativePath = '.claude/rules/powershell-standards/copilot-instructions.md' }
            @{ RelativePath = '.github/instructions/powershell-style.instructions.md' }
            @{ RelativePath = '.github/instructions/pester-supporting-docs/assertion-guide.md' }
            @{ RelativePath = '.claude/rules/powershell-standards/powershell-style.md' }
            @{ RelativePath = '.github/skills/powershell-review/SKILL.md' }
            @{ RelativePath = '.claude/skills/powershell-review/SKILL.md' }
            @{ RelativePath = '.agents/skills/powershell-review/SKILL.md' }
        ) {
            $null = & $installScript -ProjectPath $projectPath

            & $testProjectFile -RelativePath $RelativePath | Should-BeTrue
        }

        It 'Reports every file as installed' {
            $files = @(& $installScript -ProjectPath $projectPath)

            $files.Count | Should-BeGreaterThan 40
            $files | Should-All { $_.Status -eq 'Installed' }
        }

        It 'Reports every file as unchanged on a second run' {
            $null = & $installScript -ProjectPath $projectPath
            $files = @(& $installScript -ProjectPath $projectPath)

            $files.Count | Should-BeGreaterThan 40
            $files | Should-All { $_.Status -eq 'Unchanged' }
        }

        It 'Installs neither the analyzer settings nor the sync workflow' {
            $null = & $installScript -ProjectPath $projectPath

            & $testProjectFile -RelativePath 'PSScriptAnalyzerSettings.psd1' | Should-BeFalse
            & $testProjectFile -RelativePath '.github/workflows' | Should-BeFalse
        }

        It 'Writes nothing when -WhatIf is given' {
            $null = & $installScript -ProjectPath $projectPath -WhatIf

            @(Get-ChildItem -LiteralPath $projectPath -Force).Count | Should-Be 0
        }

        It 'Fails when the project folder does not exist' {
            $missingPath = Join-Path -Path $projectPath -ChildPath 'absent'

            { & $installScript -ProjectPath $missingPath } |
                Should-Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
        }
    }

    Context 'When only some agents are selected' {
        It 'Installs only the files that <Agent> reads' -ForEach @(
            @{
                Agent = 'Copilot'
                Present = @('.github/copilot-instructions.md', '.github/skills/powershell-review/SKILL.md')
                Absent = @('AGENTS.md', 'CLAUDE.md', '.claude', '.agents')
            }
            @{
                Agent = 'ClaudeCode'
                Present = @(
                    '.github/copilot-instructions.md'
                    '.claude/rules/powershell-standards/copilot-instructions.md'
                    '.claude/rules/powershell-standards/powershell-style.md'
                    '.claude/skills/powershell-review/SKILL.md'
                )
                Absent = @('AGENTS.md', 'CLAUDE.md', '.github/skills', '.agents')
            }
            @{
                Agent = 'Codex'
                Present = @('AGENTS.md', '.agents/skills/powershell-review/SKILL.md')
                Absent = @('.github/copilot-instructions.md', 'CLAUDE.md', '.claude', '.github/skills')
            }
        ) {
            $null = & $installScript -ProjectPath $projectPath -Agent $Agent

            $Present | Should-All { & $testProjectFile -RelativePath $_ }
            $Absent | Should-All { -not (& $testProjectFile -RelativePath $_) }
            # The core file points at the topic rules, so every agent needs them.
            $topicRule = '.github/instructions/powershell-style.instructions.md'
            & $testProjectFile -RelativePath $topicRule | Should-BeTrue
        }
    }

    Context 'The always-loaded core' {
        BeforeAll {
            $copilotFile = '.github/copilot-instructions.md'
            $coreRule = '.claude/rules/powershell-standards/copilot-instructions.md'

            # Whether a file in the project holds the core rules, as opposed to pointing to them.
            $testHoldsCore = {
                param([string]$RelativePath)
                $fullPath = Join-Path -Path $projectPath -ChildPath $RelativePath
                (Test-Path -LiteralPath $fullPath) -and
                [System.IO.File]::ReadAllText($fullPath) -match '(?m)^- \*\*STY-02\*\* '
            }
        }

        # GitHub Copilot loads both of these files, so the core must be in exactly one of them.
        It 'Is held by one of the two files that GitHub Copilot loads when the agents are <Agent>' -ForEach @(
            @{ Agent = @('Copilot') }
            @{ Agent = @('ClaudeCode') }
            @{ Agent = @('Codex') }
            @{ Agent = @('Copilot', 'ClaudeCode') }
            @{ Agent = @('Copilot', 'Codex') }
            @{ Agent = @('ClaudeCode', 'Codex') }
            @{ Agent = @('Copilot', 'ClaudeCode', 'Codex') }
        ) {
            $null = & $installScript -ProjectPath $projectPath -Agent $Agent

            $holders = @($copilotFile, 'AGENTS.md' | Where-Object { & $testHoldsCore -RelativePath $_ })

            $holders | Should-BeCollection -Count 1
        }

        It 'Gives Claude Code rules whose imports all exist when the agents are <Agent>' -ForEach @(
            @{ Agent = @('ClaudeCode') }
            @{ Agent = @('Copilot', 'ClaudeCode') }
            @{ Agent = @('ClaudeCode', 'Codex') }
            @{ Agent = @('Copilot', 'ClaudeCode', 'Codex') }
        ) {
            $null = & $installScript -ProjectPath $projectPath -Agent $Agent
            $ruleFolder = & $getProjectFile -RelativePath '.claude/rules/powershell-standards'
            $rules = @(Get-ChildItem -LiteralPath $ruleFolder -Filter '*.md' -File)

            $unresolved = foreach ($rule in $rules) {
                $import = [regex]::Match([System.IO.File]::ReadAllText($rule.FullName), '(?m)^@(?<path>\S+)')
                $target = Join-Path -Path $rule.DirectoryName -ChildPath $import.Groups['path'].Value
                if (-not $import.Success -or -not (Test-Path -LiteralPath $target -PathType Leaf)) {
                    $rule.Name
                }
            }

            $rules.Count | Should-BeGreaterThan 10
            @($unresolved) -join ', ' | Should-BeString ''
            & $testHoldsCore -RelativePath $copilotFile | Should-BeTrue
        }

        It 'Makes AGENTS.md a pointer to the Copilot file when both are installed' {
            $null = & $installScript -ProjectPath $projectPath -Agent Copilot, Codex
            $pointer = [System.IO.File]::ReadAllText((& $getProjectFile -RelativePath 'AGENTS.md'))

            $pointer | Should-MatchString ([regex]::Escape('`.github/copilot-instructions.md`'))
            $pointer.Length | Should-BeLessThan 1000
        }

        It 'Installs no AGENTS.md for GitHub Copilot and Claude Code alone' {
            $null = & $installScript -ProjectPath $projectPath -Agent Copilot, ClaudeCode

            & $testProjectFile -RelativePath 'AGENTS.md' | Should-BeFalse
        }

        It 'Puts the core in AGENTS.md when the project wrote its own Copilot file' {
            $ownPath = & $newProjectFile -RelativePath $copilotFile -Content 'Project guidance.'

            $null = & $installScript -ProjectPath $projectPath -WarningAction SilentlyContinue
            $ruleText = [System.IO.File]::ReadAllText((& $getProjectFile -RelativePath $coreRule))

            (Get-Content -LiteralPath $ownPath -Raw).Trim() | Should-BeString 'Project guidance.'
            & $testHoldsCore -RelativePath 'AGENTS.md' | Should-BeTrue
            $ruleText | Should-MatchString '(?m)^@\.\./\.\./\.\./AGENTS\.md\r?$'
        }

        It 'Makes AGENTS.md a pointer when -Force replaces the project''s own Copilot file' {
            $null = & $newProjectFile -RelativePath $copilotFile -Content 'Project guidance.'

            $null = & $installScript -ProjectPath $projectPath -Force

            & $testHoldsCore -RelativePath $copilotFile | Should-BeTrue
            & $testHoldsCore -RelativePath 'AGENTS.md' | Should-BeFalse
        }

        It 'Moves the core to the Copilot file when GitHub Copilot is added later' {
            $null = & $installScript -ProjectPath $projectPath -Agent Codex

            $installParameters = @{
                ProjectPath = $projectPath
                WarningVariable = 'warnings'
                WarningAction = 'SilentlyContinue'
            }
            $files = @(& $installScript @installParameters)

            & $testHoldsCore -RelativePath $copilotFile | Should-BeTrue
            & $testHoldsCore -RelativePath 'AGENTS.md' | Should-BeFalse
            & $selectResult -Files $files -Path 'AGENTS.md' -Status 'Updated' | Should-BeCollection -Count 1
            @($warnings).Count | Should-Be 0
        }

        It 'Removes the files of agents that are no longer selected' {
            $null = & $installScript -ProjectPath $projectPath

            $files = @(& $installScript -ProjectPath $projectPath -Agent Copilot)

            & $testProjectFile -RelativePath 'AGENTS.md' | Should-BeFalse
            & $testProjectFile -RelativePath $coreRule | Should-BeFalse
            & $selectResult -Files $files -Path 'AGENTS.md' -Status 'Removed' | Should-BeCollection -Count 1
            & $selectResult -Files $files -Path $coreRule -Status 'Removed' | Should-BeCollection -Count 1
        }

        It 'Moves the core to AGENTS.md when only Codex remains' {
            $null = & $installScript -ProjectPath $projectPath

            $files = @(& $installScript -ProjectPath $projectPath -Agent Codex)

            & $testProjectFile -RelativePath $copilotFile | Should-BeFalse
            & $testHoldsCore -RelativePath 'AGENTS.md' | Should-BeTrue
            & $selectResult -Files $files -Path $copilotFile -Status 'Removed' | Should-BeCollection -Count 1
        }

        It 'Keeps an AGENTS.md that the project wrote when no selected agent needs it' {
            $ownPath = & $newProjectFile -RelativePath 'AGENTS.md' -Content 'Project guidance.'

            $files = @(& $installScript -ProjectPath $projectPath -Agent Copilot)

            (Get-Content -LiteralPath $ownPath -Raw).Trim() | Should-BeString 'Project guidance.'
            @($files | Where-Object { $_.Path -eq 'AGENTS.md' }).Count | Should-Be 0
        }

        It 'Removes nothing when -WhatIf is given' {
            $null = & $installScript -ProjectPath $projectPath

            $null = & $installScript -ProjectPath $projectPath -Agent Copilot -WhatIf

            & $testProjectFile -RelativePath 'AGENTS.md' | Should-BeTrue
            & $testProjectFile -RelativePath $coreRule | Should-BeTrue
        }

        It 'Never creates or changes CLAUDE.md' {
            $null = & $installScript -ProjectPath $projectPath
            $createdByInstall = & $testProjectFile -RelativePath 'CLAUDE.md'
            $ownPath = & $newProjectFile -RelativePath 'CLAUDE.md' -Content 'Project guidance.'

            $files = @(& $installScript -ProjectPath $projectPath)

            $createdByInstall | Should-BeFalse
            (Get-Content -LiteralPath $ownPath -Raw).Trim() | Should-BeString 'Project guidance.'
            @($files | Where-Object { $_.Path -eq 'CLAUDE.md' }).Count | Should-Be 0
        }

        It 'Refuses to install into the standards repository itself' {
            { & $installScript -ProjectPath $repositoryRoot -WhatIf } |
                Should-Throw -ExceptionMessage '*standards repository itself*'
        }
    }

    Context 'When the project already has its own files' {
        It 'Leaves the project''s own <FileName> unchanged and warns' -ForEach @(
            @{ FileName = 'AGENTS.md' }
            @{ FileName = '.github/copilot-instructions.md' }
        ) {
            $ownPath = & $newProjectFile -RelativePath $FileName -Content 'Project guidance.'

            $installParameters = @{
                ProjectPath = $projectPath
                WarningVariable = 'warnings'
                WarningAction = 'SilentlyContinue'
            }
            $files = @(& $installScript @installParameters)

            (Get-Content -LiteralPath $ownPath -Raw).Trim() | Should-BeString 'Project guidance.'
            & $selectResult -Files $files -Path $FileName -Status 'Skipped' | Should-BeCollection -Count 1
            @($warnings | Where-Object { $_ -like "*'$FileName' already exists*" }) | Should-BeCollection -Count 1
        }

        It 'Replaces the project''s own AGENTS.md when -Force is given' {
            $ownPath = & $newProjectFile -RelativePath 'AGENTS.md' -Content 'Project guidance.'

            $files = @(& $installScript -ProjectPath $projectPath -Force)

            $installedText = Get-Content -LiteralPath $ownPath -Raw
            $installedText | Should-MatchString 'Generated from ai-powershell-standards'
            & $selectResult -Files $files -Path 'AGENTS.md' -Status 'Updated' | Should-BeCollection -Count 1
        }

        It 'Leaves an instruction file that the standards do not own' {
            $teamName = '.github/instructions/team.instructions.md'
            $teamPath = & $newProjectFile -RelativePath $teamName -Content 'Team rules.'

            $null = & $installScript -ProjectPath $projectPath

            (Get-Content -LiteralPath $teamPath -Raw).Trim() | Should-BeString 'Team rules.'
        }
    }

    Context 'When updating an earlier installation' {
        BeforeEach {
            $null = & $installScript -ProjectPath $projectPath
        }

        It 'Replaces <FileName> when an earlier installation wrote it' -ForEach @(
            @{ FileName = '.github/copilot-instructions.md' }
            @{ FileName = 'AGENTS.md' }
        ) {
            $filePath = & $getProjectFile -RelativePath $FileName
            Add-Content -LiteralPath $filePath -Value 'Stale line.' -Encoding ascii

            $files = @(& $installScript -ProjectPath $projectPath)

            Get-Content -LiteralPath $filePath -Raw | Should-NotMatchString 'Stale line\.'
            & $selectResult -Files $files -Path $FileName -Status 'Updated' | Should-BeCollection -Count 1
        }

        It 'Replaces a topic rule that was edited in the project' {
            $rulePath = & $getProjectFile -RelativePath '.github/instructions/powershell-style.instructions.md'
            Set-Content -LiteralPath $rulePath -Value 'Edited locally.' -Encoding ascii

            $null = & $installScript -ProjectPath $projectPath

            Get-Content -LiteralPath $rulePath -Raw | Should-MatchString 'STY-01'
        }

        It 'Removes a file in an owned location that the standards no longer install' {
            $retiredName = '.github/instructions/powershell-retired.instructions.md'
            $retiredPath = & $newProjectFile -RelativePath $retiredName -Content 'Old rule.'

            $files = @(& $installScript -ProjectPath $projectPath)

            Test-Path -LiteralPath $retiredPath | Should-BeFalse
            & $selectResult -Files $files -Path $retiredName -Status 'Removed' | Should-BeCollection -Count 1
        }

        It 'Removes another agent''s files when that agent is no longer selected' {
            $files = @(& $installScript -ProjectPath $projectPath -Agent Copilot)

            $claudeRule = '.claude/rules/powershell-standards/powershell-style.md'
            & $testProjectFile -RelativePath $claudeRule | Should-BeFalse
            & $testProjectFile -RelativePath '.agents/skills/powershell-review/SKILL.md' | Should-BeFalse
            @($files | Where-Object { $_.Status -eq 'Removed' }).Count | Should-BeGreaterThan 10
        }
    }

    Context 'When files from a version before 2.0 are present' {
        BeforeEach {
            $legacyRuleName = '.github/instructions/errorsandlogs.instructions.md'
            $legacyPromptName = '.github/prompts/new-function.prompt.md'
            $legacyRule = & $newProjectFile -RelativePath $legacyRuleName -Content 'Legacy content.'
            $legacyPrompt = & $newProjectFile -RelativePath $legacyPromptName -Content 'Legacy content.'
        }

        It 'Keeps them and warns by default' {
            $installParameters = @{
                ProjectPath = $projectPath
                WarningVariable = 'warnings'
                WarningAction = 'SilentlyContinue'
            }
            $null = & $installScript @installParameters

            Test-Path -LiteralPath $legacyRule | Should-BeTrue
            Test-Path -LiteralPath $legacyPrompt | Should-BeTrue
            @($warnings | Where-Object { $_ -like '*before 2.0*errorsandlogs*' }) | Should-BeCollection -Count 1
        }

        It 'Removes them when -RemoveLegacyFiles is given' {
            $files = @(& $installScript -ProjectPath $projectPath -RemoveLegacyFiles)

            Test-Path -LiteralPath $legacyRule | Should-BeFalse
            Test-Path -LiteralPath $legacyPrompt | Should-BeFalse
            @($files | Where-Object { $_.Status -eq 'Removed' }) | Should-BeCollection -Count 2
        }
    }

    Context 'The attribution file' {
        BeforeDiscovery {
            $hasGit = [bool](Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)
        }

        BeforeAll {
            $attributionName = '.github/powershell-attribution.md'
            $attributionFolder = Join-Path -Path $repositoryRoot -ChildPath 'standards/attribution'

            # The text of a file, with line endings that do not depend on how git checked it out.
            $readText = {
                param([string]$LiteralPath)
                [System.IO.File]::ReadAllText($LiteralPath).Replace("`r`n", "`n")
            }
            $templateText = & $readText -LiteralPath (Join-Path -Path $attributionFolder -ChildPath 'template.md')
            $profilePath = Join-Path -Path $attributionFolder -ChildPath 'profiles/fadwen.md'
            $profileText = & $readText -LiteralPath $profilePath

            # The text of the attribution file in the project folder that the current test uses.
            $readAttribution = {
                & $readText -LiteralPath (& $getProjectFile -RelativePath $attributionName)
            }

            # Makes the project folder a git repository whose origin remote is the given URL.
            $setOrigin = {
                param([string]$Url)
                & git -C $projectPath init -q
                & git -C $projectPath remote add origin $Url
            }
        }

        It 'Installs the empty template when the project has no origin remote' {
            $files = @(& $installScript -ProjectPath $projectPath)

            & $readAttribution | Should-BeString $templateText
            & $selectResult -Files $files -Path $attributionName -Status 'Installed' | Should-BeCollection -Count 1
        }

        It 'Installs the profile of the owner in the origin remote <Url>' -Skip:(-not $hasGit) -ForEach @(
            @{ Url = 'https://github.com/fadwen/example.git' }
            @{ Url = 'git@github.com:FADWEN/example' }
        ) {
            & $setOrigin -Url $Url

            $null = & $installScript -ProjectPath $projectPath

            & $readAttribution | Should-BeString $profileText
        }

        It 'Installs the empty template for an owner without a profile' -Skip:(-not $hasGit) {
            & $setOrigin -Url 'https://github.com/someone-else/example.git'

            $null = & $installScript -ProjectPath $projectPath

            & $readAttribution | Should-BeString $templateText
        }

        It 'Uses the owner given with -Owner instead of the origin remote' -Skip:(-not $hasGit) {
            & $setOrigin -Url 'https://github.com/someone-else/example.git'

            $null = & $installScript -ProjectPath $projectPath -Owner 'fadwen'

            & $readAttribution | Should-BeString $profileText
        }

        It 'Rejects an owner that is not a GitHub name' {
            { & $installScript -ProjectPath $projectPath -Owner '../profiles' } |
                Should-Throw -FullyQualifiedErrorId 'ParameterArgumentValidationError,*'
        }

        It 'Keeps the project''s own attribution file, even with -Force, and does not warn' {
            $ownPath = & $newProjectFile -RelativePath $attributionName -Content '- Author: Project Author'

            $installParameters = @{
                ProjectPath = $projectPath
                Owner = 'fadwen'
                Force = $true
                WarningVariable = 'warnings'
                WarningAction = 'SilentlyContinue'
            }
            $files = @(& $installScript @installParameters)

            (Get-Content -LiteralPath $ownPath -Raw).Trim() | Should-BeString '- Author: Project Author'
            & $selectResult -Files $files -Path $attributionName -Status 'Unchanged' | Should-BeCollection -Count 1
            @($warnings | Where-Object { $_ -like '*powershell-attribution*' }) | Should-BeCollection -Count 0
        }

        It 'Keeps an attribution file that an earlier installation wrote and the project then edited' {
            $null = & $installScript -ProjectPath $projectPath
            $attributionPath = & $getProjectFile -RelativePath $attributionName
            Add-Content -LiteralPath $attributionPath -Value '- GitHub: https://github.com/example' -Encoding ascii

            $null = & $installScript -ProjectPath $projectPath -Force

            Get-Content -LiteralPath $attributionPath -Raw |
                Should-MatchString 'GitHub: https://github\.com/example'
        }

        It 'Keeps the attribution file when agents are dropped and legacy files are removed' {
            $null = & $installScript -ProjectPath $projectPath
            $files = @(& $installScript -ProjectPath $projectPath -Agent Codex -RemoveLegacyFiles)

            & $testProjectFile -RelativePath $attributionName | Should-BeTrue
            & $selectResult -Files $files -Path $attributionName -Status 'Removed' | Should-BeCollection -Count 0
        }
    }

    Context 'With the optional files' {
        It 'Installs the analyzer settings when asked' {
            $null = & $installScript -ProjectPath $projectPath -IncludeAnalyzerSettings
            $settingsPath = & $getProjectFile -RelativePath 'PSScriptAnalyzerSettings.psd1'
            $settings = Import-PowerShellDataFile -LiteralPath $settingsPath

            $settings.Rules.PSAvoidLongLines.MaximumLineLength | Should-Be 115
        }

        It 'Installs the sync workflow when asked' {
            $null = & $installScript -ProjectPath $projectPath -IncludeSyncWorkflow
            $workflowPath = & $getProjectFile -RelativePath '.github/workflows/sync-copilot-standards.yml'

            Get-Content -LiteralPath $workflowPath -Raw | Should-MatchString 'Install-CopilotStandards\.ps1'
        }

        It 'Does not replace a sync workflow the project has changed' {
            $workflowName = '.github/workflows/sync-copilot-standards.yml'
            $workflowPath = & $newProjectFile -RelativePath $workflowName -Content 'name: tuned by the project'

            $null = & $installScript -ProjectPath $projectPath -IncludeSyncWorkflow -WarningAction SilentlyContinue

            (Get-Content -LiteralPath $workflowPath -Raw).Trim() | Should-BeString 'name: tuned by the project'
        }
    }

    Context 'The credential scan' {
        BeforeAll {
            $scanFiles = @(
                '.github/scripts/Invoke-CredentialScan.ps1'
                '.github/workflows/credential-scan.yml'
                '.betterleaks.toml'
                '.gitleaks.toml'
                '.trufflehog-exclude.txt'
            )
        }

        It 'Installs no file of the scan unless a scanner is named' {
            $files = @(& $installScript -ProjectPath $projectPath -IncludeSyncWorkflow -IncludeAnalyzerSettings)

            foreach ($scanFile in $scanFiles) {
                & $testProjectFile -RelativePath $scanFile | Should-BeFalse
            }
            @($files | Where-Object { $_.Path -in $scanFiles }).Count | Should-Be 0
        }

        It 'Installs the script, the workflow, and only <ConfigFile> for <Scanner>' -ForEach @(
            @{ Scanner = 'betterleaks'; ConfigFile = '.betterleaks.toml' }
            @{ Scanner = 'gitleaks'; ConfigFile = '.gitleaks.toml' }
            @{ Scanner = 'trufflehog'; ConfigFile = '.trufflehog-exclude.txt' }
        ) {
            $files = @(& $installScript -ProjectPath $projectPath -IncludeCredentialScan $Scanner)

            $expected = $scanFiles[0], $scanFiles[1], $ConfigFile
            foreach ($path in $expected) {
                (& $selectResult -Files $files -Path $path -Status 'Installed') | Should-BeCollection -Count 1
                & $testProjectFile -RelativePath $path | Should-BeTrue
            }
            $others = @($scanFiles | Where-Object { $_ -notin $expected })
            $others | Should-BeCollection -Count 2
            foreach ($path in $others) {
                & $testProjectFile -RelativePath $path | Should-BeFalse
            }
        }

        It 'Writes a workflow for <Scanner> that names a version and a hash, with every action pinned' -ForEach @(
            @{ Scanner = 'betterleaks' }
            @{ Scanner = 'gitleaks' }
            @{ Scanner = 'trufflehog' }
        ) {
            $null = & $installScript -ProjectPath $projectPath -IncludeCredentialScan $Scanner
            $workflowPath = & $getProjectFile -RelativePath '.github/workflows/credential-scan.yml'
            $workflowText = Get-Content -LiteralPath $workflowPath -Raw
            $actions = @([regex]::Matches($workflowText, '(?m)^\s*uses:\s*(?<action>\S+)') |
                    ForEach-Object { $_.Groups['action'].Value })

            $workflowText | Should-MatchString "(?m)^  CREDENTIAL_SCANNER: '$Scanner'$"
            $workflowText | Should-MatchString "(?m)^  CREDENTIAL_SCANNER_VERSION: '\d+\.\d+\.\d+'$"
            $workflowText | Should-MatchString "(?m)^  CREDENTIAL_SCANNER_SHA256: '[0-9a-f]{64}'$"
            $workflowText | Should-NotMatchString '\{\{'
            $workflowText | Should-MatchString 'fetch-depth: 0'
            $workflowText | Should-MatchString '\./\.github/scripts/Invoke-CredentialScan\.ps1 @scan'
            $actions.Count | Should-BeGreaterThan 0
            $actions | Should-All { $_ -match '@[0-9a-f]{40}$' }
        }

        It 'Installs a script that parses, has its help, and says that it is installed' {
            $null = & $installScript -ProjectPath $projectPath -IncludeCredentialScan gitleaks
            $scriptPath = & $getProjectFile -RelativePath '.github/scripts/Invoke-CredentialScan.ps1'
            $parseErrors = $null
            $parser = [System.Management.Automation.Language.Parser]
            $null = $parser::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)

            @($parseErrors).Count | Should-Be 0
            $firstLine = Get-Content -LiteralPath $scriptPath -TotalCount 1
            $firstLine | Should-BeLikeString '# Generated from ai-powershell-standards*'
            (Get-Help -Name $scriptPath).Synopsis | Should-BeLikeString 'Scans a git repository for credentials*'
        }

        It 'Replaces the script on a later run without the parameter, and installs nothing else of the scan' {
            $null = & $installScript -ProjectPath $projectPath -IncludeCredentialScan gitleaks
            $scriptPath = & $getProjectFile -RelativePath '.github/scripts/Invoke-CredentialScan.ps1'
            Add-Content -LiteralPath $scriptPath -Value '# edited in the project'
            # A file whose name starts with a dot is hidden on Linux and macOS, and needs -Force there.
            Remove-Item -LiteralPath (& $getProjectFile -RelativePath '.gitleaks.toml') -Force
            Remove-Item -LiteralPath (& $getProjectFile -RelativePath '.github/workflows/credential-scan.yml')

            $files = @(& $installScript -ProjectPath $projectPath)

            (& $selectResult -Files $files -Path '.github/scripts/Invoke-CredentialScan.ps1' -Status 'Updated') |
                Should-BeCollection -Count 1
            Get-Content -LiteralPath $scriptPath -Raw | Should-NotMatchString 'edited in the project'
            & $testProjectFile -RelativePath '.gitleaks.toml' | Should-BeFalse
            & $testProjectFile -RelativePath '.github/workflows/credential-scan.yml' | Should-BeFalse
        }

        It 'Never replaces <FileName> that the project already has' -ForEach @(
            @{ FileName = '.betterleaks.toml'; Scanner = 'betterleaks' }
            @{ FileName = '.github/workflows/credential-scan.yml'; Scanner = 'betterleaks' }
            @{ FileName = '.gitleaks.toml'; Scanner = 'gitleaks' }
            @{ FileName = '.trufflehog-exclude.txt'; Scanner = 'trufflehog' }
        ) {
            $filePath = & $newProjectFile -RelativePath $FileName -Content '# tuned by the project'

            $install = @{ ProjectPath = $projectPath; IncludeCredentialScan = $Scanner }
            $null = & $installScript @install -WarningAction SilentlyContinue

            (Get-Content -LiteralPath $filePath -Raw).Trim() | Should-BeString '# tuned by the project'
        }

        It 'Leaves a script of that name that the project wrote itself, and warns' {
            $scriptName = '.github/scripts/Invoke-CredentialScan.ps1'
            $scriptPath = & $newProjectFile -RelativePath $scriptName -Content '# the project''s own scan'

            $install = @{ ProjectPath = $projectPath; IncludeCredentialScan = 'gitleaks' }
            $files = @(& $installScript @install -WarningVariable warnings -WarningAction SilentlyContinue)

            (& $selectResult -Files $files -Path $scriptName -Status 'Skipped') | Should-BeCollection -Count 1
            (Get-Content -LiteralPath $scriptPath -Raw).Trim() | Should-BeString '# the project''s own scan'
            @($warnings | Where-Object { "$_" -like "*$scriptName*" }).Count | Should-Be 1
        }

        It 'Writes nothing of the scan when -WhatIf is given' {
            $null = & $installScript -ProjectPath $projectPath -IncludeCredentialScan trufflehog -WhatIf

            foreach ($scanFile in $scanFiles) {
                & $testProjectFile -RelativePath $scanFile | Should-BeFalse
            }
        }

        It 'Rejects a scanner that the scan does not support' {
            { & $installScript -ProjectPath $projectPath -IncludeCredentialScan 'otherscanner' } |
                Should-Throw -ExceptionMessage '*IncludeCredentialScan*'
        }
    }
}

Describe 'Install-CopilotStandards.ps1 on Windows PowerShell 5.1' -Tag 'Integration' {
    BeforeDiscovery {
        $hasWindowsPowerShell = [bool](Get-Command -Name 'powershell.exe' -ErrorAction SilentlyContinue)
    }

    It 'Installs the same files as it does on PowerShell 7' -Skip:(-not $hasWindowsPowerShell) {
        $projectPath = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $projectPath -ItemType Directory
        $arguments = @(
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass'
            '-File', $installScript, '-ProjectPath', $projectPath
        )

        $output = & powershell.exe @arguments
        $exitCode = $LASTEXITCODE

        $exitCode | Should-Be 0
        @($output).Count | Should-BeGreaterThan 40
        & $testProjectFile -RelativePath 'AGENTS.md' | Should-BeTrue
        & $testProjectFile -RelativePath '.claude/rules/powershell-standards/powershell-style.md' | Should-BeTrue
    }
}

Describe 'Sync workflow template' -Tag 'Unit' {
    BeforeAll {
        $workflowText = Get-Content -LiteralPath $workflowTemplate -Raw
    }

    It 'Pins every action to a commit' {
        $actions = @([regex]::Matches($workflowText, '(?m)^\s*uses:\s*(?<action>\S+)') |
                ForEach-Object { $_.Groups['action'].Value })

        $actions.Count | Should-BeGreaterThan 0
        $actions | Should-All { $_ -match '@[0-9a-f]{40}$' }
    }

    It 'Installs with the installer script instead of copying folders' {
        $workflowText | Should-MatchString 'Tools/Install-CopilotStandards\.ps1 -ProjectPath \.'
        $workflowText | Should-NotMatchString 'rm -rf "\.github'
    }

    It 'Lets the project choose the reference to install from' {
        $workflowText | Should-MatchString '(?m)^\s*STANDARDS_REF: \S+'
        $workflowText | Should-MatchString 'ref: \$\{\{ env\.STANDARDS_REF \}\}'
    }
}
