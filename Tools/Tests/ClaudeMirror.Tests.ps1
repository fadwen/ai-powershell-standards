#Requires -Module Pester

# The Claude Code files under .claude/ mirror the Copilot files under .github/ by reference: each
# rule imports one instruction file, each command attaches one prompt file. Nothing regenerates them,
# so this suite is what fails when the two drift apart - a new instruction file with no rule, a
# changed applyTo, a prompt with no command.

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    $instructionCases = Get-ChildItem (Join-Path $repoRoot '.github/instructions') -Filter '*.instructions.md' |
        ForEach-Object { @{ Name = $_.Name -replace '\.instructions\.md$' } }

    $promptCases = Get-ChildItem (Join-Path $repoRoot '.github/prompts') -Filter '*.prompt.md' |
        ForEach-Object { @{ Name = $_.Name -replace '\.prompt\.md$' } }
}

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:InstructionsDir = Join-Path $script:RepoRoot '.github/instructions'
    $script:PromptsDir = Join-Path $script:RepoRoot '.github/prompts'
    $script:RulesDir = Join-Path $script:RepoRoot '.claude/rules/powershell-standards'
    $script:CommandsDir = Join-Path $script:RepoRoot '.claude/commands/powershell-standards'

    function Get-FrontMatter {
        param([string]$Path)

        $lines = @(Get-Content -Path $Path)
        if ($lines.Count -lt 2 -or $lines[0] -ne '---') { return @() }

        $end = [array]::IndexOf($lines, '---', 1)
        if ($end -lt 2) { return @() }

        $lines[1..($end - 1)]
    }

    function Get-FrontMatterValue {
        param([string]$Path, [string]$Key)

        $line = Get-FrontMatter -Path $Path | Where-Object { $_ -match "^${Key}:" } | Select-Object -First 1
        if (-not $line) { return $null }

        ($line -replace "^${Key}:\s*", '').Trim().Trim('"', "'")
    }
}

Describe 'Claude Code rules mirror the Copilot instruction files' -Tag 'Unit', 'Mirror' {

    It 'Has a rule for <Name>.instructions.md with the same globs as its applyTo' -ForEach $instructionCases {
        $rule = Join-Path $script:RulesDir "$Name.md"
        Test-Path $rule | Should-BeTrue

        $instruction = Join-Path $script:InstructionsDir "$Name.instructions.md"
        $expected = (Get-FrontMatterValue -Path $instruction -Key 'applyTo') -split ',' |
            ForEach-Object { $_.Trim() }

        $actual = Get-FrontMatter -Path $rule |
            Where-Object { $_ -match '^\s+-\s' } |
            ForEach-Object { ($_ -replace '^\s+-\s*', '').Trim().Trim('"', "'") }

        # applyTo '**' means every file. The Claude equivalent is a rule with no paths, which loads
        # at launch instead of waiting for a file read that some tasks, like opening a PR, never make.
        if (($expected -join ',') -eq '**') {
            ($actual -join ', ') | Should-Be ''
            return
        }

        # Joined so a mismatch prints both glob lists side by side
        ($actual -join ', ') | Should-Be ($expected -join ', ')
    }

    It 'Imports <Name>.instructions.md rather than copying it' -ForEach $instructionCases {
        $body = Get-Content (Join-Path $script:RulesDir "$Name.md") -Raw
        $import = [regex]::Escape("@../../../.github/instructions/$Name.instructions.md")

        $body | Should-MatchString $import
    }

    It 'Has an always-on rule that imports copilot-instructions.md' {
        $rule = Join-Path $script:RulesDir 'copilot-instructions.md'
        Test-Path $rule | Should-BeTrue

        (Get-Content $rule -Raw) | Should-MatchString ([regex]::Escape('@../../../.github/copilot-instructions.md'))

        # No frontmatter means no paths, which is what makes the rule load at launch
        ((Get-Content $rule)[0] -eq '---') | Should-BeFalse
    }

    It 'Has no rule left behind for an instruction file that is gone' {
        $expected = @(
            (Get-ChildItem $script:InstructionsDir -Filter '*.instructions.md').Name -replace '\.instructions\.md$'
        ) + 'copilot-instructions'

        $orphans = (Get-ChildItem $script:RulesDir -Filter '*.md').BaseName | Where-Object { $_ -notin $expected }

        ($orphans -join ', ') | Should-Be ''
    }
}

Describe 'Claude Code commands mirror the Copilot prompt files' -Tag 'Unit', 'Mirror' {

    It 'Has a command for <Name>.prompt.md that attaches the prompt file' -ForEach $promptCases {
        $command = Join-Path $script:CommandsDir "$Name.md"
        Test-Path $command | Should-BeTrue

        (Get-Content $command -Raw) | Should-MatchString ([regex]::Escape("@.github/prompts/$Name.prompt.md"))
    }

    It 'Carries the same description as <Name>.prompt.md' -ForEach $promptCases {
        $expected = Get-FrontMatterValue -Path (Join-Path $script:PromptsDir "$Name.prompt.md") -Key 'description'
        $actual = Get-FrontMatterValue -Path (Join-Path $script:CommandsDir "$Name.md") -Key 'description'

        $expected | Should-NotBeNull
        $actual | Should-Be $expected
    }

    It 'Has no command left behind for a prompt file that is gone' {
        $expected = (Get-ChildItem $script:PromptsDir -Filter '*.prompt.md').Name -replace '\.prompt\.md$'

        $orphans = (Get-ChildItem $script:CommandsDir -Filter '*.md').BaseName | Where-Object { $_ -notin $expected }

        ($orphans -join ', ') | Should-Be ''
    }
}
