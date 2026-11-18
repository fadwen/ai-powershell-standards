#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $manifestPath = Join-Path -Path $repositoryRoot -ChildPath 'standards/manifest.psd1'
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath

    $ruleCases = foreach ($rule in $manifest.Rules) {
        @{ RuleId = $rule.Id; Globs = $rule.Globs }
    }

    $skillCases = foreach ($skill in $manifest.Skills) {
        @{ SkillName = $skill }
    }

    $instructionFolder = Join-Path -Path $repositoryRoot -ChildPath '.github/instructions'
    $skillFolder = Join-Path -Path $repositoryRoot -ChildPath 'standards/skills'
    $markdownFiles = @(
        Get-ChildItem -LiteralPath $instructionFolder -Filter '*.md' -File -Recurse
        Get-Item -LiteralPath (Join-Path -Path $repositoryRoot -ChildPath '.github/copilot-instructions.md')
        Get-Item -LiteralPath (Join-Path -Path $repositoryRoot -ChildPath 'AGENTS.md')
        Get-ChildItem -LiteralPath $skillFolder -Filter 'SKILL.md' -File -Recurse
    )
    $markdownCases = foreach ($file in $markdownFiles) {
        @{
            RelativePath = $file.FullName.Substring($repositoryRoot.Length + 1).Replace('\', '/')
            FullPath = $file.FullName
        }
    }
}

BeforeAll {
    $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $buildScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools/Build-AgentInstructions.ps1'
    $manifestPath = Join-Path -Path $repositoryRoot -ChildPath 'standards/manifest.psd1'
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath

    # Reads a file, given its path relative to a root folder.
    $readFile = {
        param([string]$Root, [string]$RelativePath)
        [System.IO.File]::ReadAllText((Join-Path -Path $Root -ChildPath $RelativePath))
    }

    # Returns the code fences of a Markdown text as objects with Language, Line, and Code.
    $getCodeFence = {
        param([string]$Text)

        $lines = $Text.Replace("`r`n", "`n").Split("`n")
        $fenceMarker = $null
        $language = $null
        $startLine = 0
        $codeLines = [System.Collections.Generic.List[string]]::new()

        for ($index = 0; $index -lt $lines.Count; $index++) {
            $line = $lines[$index]
            if ($null -eq $fenceMarker) {
                if ($line -match '^\s*(?<marker>`{3,})(?<language>[\w-]*)\s*$') {
                    $fenceMarker = $Matches['marker']
                    $language = $Matches['language']
                    $startLine = $index + 1
                    $codeLines.Clear()
                }
                continue
            }

            if ($line.Trim() -eq $fenceMarker) {
                [PSCustomObject]@{
                    Language = $language
                    Line = $startLine
                    Code = $codeLines -join "`n"
                }
                $fenceMarker = $null
                continue
            }

            $codeLines.Add($line)
        }
    }

    # Builds a minimal standards tree under a folder, for tests of the script's own behaviour.
    $newFixtureRepository = {
        param([string]$Root, [string]$RuleText, [string]$CoreText)

        $null = New-Item -Path (Join-Path -Path $Root -ChildPath 'standards/rules') -ItemType Directory -Force
        $manifestText = @'
@{
    Name = 'Fixture-Standards'
    Version = '0.0.1'
    Core = 'standards/core.md'
    Pointer = 'standards/pointer.md'
    Rules = @(
        @{
            Id = 'powershell-sample'
            Prefix = 'SMP'
            Description = 'Sample rules.'
            Globs = @('**/*.ps1', '**/*.psm1')
        }
    )
    Skills = @()
    Reference = @()
}
'@
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $fixtureFiles = @{
            'standards/manifest.psd1' = $manifestText
            'standards/rules/powershell-sample.md' = $RuleText
            'standards/core.md' = $CoreText
            'standards/pointer.md' = "# Pointer`n`nRead the core file.`n"
        }
        foreach ($relativePath in $fixtureFiles.Keys) {
            $fullPath = Join-Path -Path $Root -ChildPath $relativePath
            [System.IO.File]::WriteAllText($fullPath, $fixtureFiles[$relativePath], $utf8)
        }
    }

    $sampleRuleText = @(
        '# Sample rules'
        ''
        '- **SMP-01** First rule, which continues'
        '  on a second line.'
        '- **SMP-02** Second rule.'
        ''
    ) -join "`n"
    $sampleCoreText = "# Core`n`n<!-- rules: SMP-02 -->`n"
}

Describe 'Generated instruction files' -Tag 'Unit' {
    It 'Match their sources' {
        $files = @(& $buildScript -RepositoryRoot $repositoryRoot -Check)

        $files | Should-All { $_.Status -eq 'Current' }
    }

    It 'Put the core rules in the Copilot file' {
        $core = & $readFile -Root $repositoryRoot -RelativePath '.github/copilot-instructions.md'

        $core | Should-MatchString '(?m)^- \*\*STY-02\*\* '
        $core | Should-MatchString '(?m)^- \*\*ERR-10\*\* '
    }

    # GitHub Copilot loads AGENTS.md as well as its own file, so a second copy would load twice.
    It 'Make AGENTS.md a pointer to the Copilot file that repeats no rule' {
        $pointerPath = Join-Path -Path $repositoryRoot -ChildPath 'AGENTS.md'
        $pointer = [System.IO.File]::ReadAllText($pointerPath)

        $pointer | Should-MatchString ([regex]::Escape('`.github/copilot-instructions.md`'))
        $pointer | Should-MatchString "Generated from $([regex]::Escape($manifest.Name))"
        $pointer | Should-NotMatchString '(?m)^- \*\*[A-Z]{3}-\d{2}\*\* '
        (Get-Item -LiteralPath $pointerPath).Length | Should-BeLessThanOrEqual 1000
    }

    It 'Make a Claude Code rule without paths import the core' {
        $relativePath = '.claude/rules/powershell-standards/copilot-instructions.md'
        $rule = (& $readFile -Root $repositoryRoot -RelativePath $relativePath).Replace("`r`n", "`n")

        $rule.StartsWith("@../../../.github/copilot-instructions.md`n") | Should-BeTrue
    }

    It 'Give the Copilot file for <RuleId> only applyTo and description front matter' -ForEach $ruleCases {
        $path = Join-Path -Path $repositoryRoot -ChildPath ".github/instructions/$RuleId.instructions.md"
        $lines = @(Get-Content -LiteralPath $path)
        $closingLine = [array]::IndexOf($lines, '---', 1)

        $lines[0] | Should-BeString '---'
        $closingLine | Should-Be 3
        $lines[1] | Should-BeString "applyTo: `"$($Globs -join ',')`""
        $lines[2] | Should-MatchString '^description: ".+"$'
    }

    # The Claude Code rule repeats no rule text: it carries the globs and imports the Copilot file.
    It 'Make the Claude Code rule for <RuleId> import the Copilot file under the same globs' -ForEach $ruleCases {
        $relativePath = ".claude/rules/powershell-standards/$RuleId.md"
        $rule = (& $readFile -Root $repositoryRoot -RelativePath $relativePath).Replace("`r`n", "`n")
        $copilotFile = ".github/instructions/$RuleId.instructions.md"

        # A rule that applies to every file has no paths, so that it loads when the session starts.
        $expectedStart = "@../../../$copilotFile`n"
        if (($Globs -join ',') -ne '**') {
            $pathLines = ($Globs | ForEach-Object { "  - `"$_`"" }) -join "`n"
            $expectedStart = "---`npaths:`n$pathLines`n---`n`n" + $expectedStart
        }

        $rule.StartsWith($expectedStart) | Should-BeTrue
        $rule | Should-NotMatchString '(?m)^- \*\*[A-Z]{3}-\d{2}\*\* '
        Test-Path -LiteralPath (Join-Path -Path $repositoryRoot -ChildPath $copilotFile) | Should-BeTrue
    }

    It 'Keep the core within 16,000 bytes' {
        $corePath = Join-Path -Path $repositoryRoot -ChildPath '.github/copilot-instructions.md'

        (Get-Item -LiteralPath $corePath).Length | Should-BeLessThanOrEqual 16000
    }

    It 'Keep what loads for <SamplePath> within <Budget> bytes' -ForEach @(
        @{ SamplePath = 'src/Get-Thing.ps1'; Budget = 132000; ExpectedRuleCount = 7 }
        @{ SamplePath = 'Tests/Get-Thing.Tests.ps1'; Budget = 154000; ExpectedRuleCount = 8 }
        @{ SamplePath = 'Module/Module.psm1'; Budget = 150000; ExpectedRuleCount = 8 }
    ) {
        $loadedPaths = [System.Collections.Generic.List[string]]::new()
        $loadedPaths.Add('.github/copilot-instructions.md')
        foreach ($rule in $manifest.Rules) {
            foreach ($glob in $rule.Globs) {
                # '**/' matches any number of folders, including none; '*' stays inside one segment.
                $escaped = [regex]::Escape($glob).Replace('\*\*/', '(.*/)?').Replace('\*\*', '.*')
                $pattern = '^' + $escaped.Replace('\*', '[^/]*') + '$'
                if ($SamplePath -match $pattern) {
                    $loadedPaths.Add(".github/instructions/$($rule.Id).instructions.md")
                    break
                }
            }
        }

        $total = 0
        foreach ($loadedPath in $loadedPaths) {
            $total += (Get-Item -LiteralPath (Join-Path -Path $repositoryRoot -ChildPath $loadedPath)).Length
        }

        $loadedPaths | Should-BeCollection -Count ($ExpectedRuleCount + 1)
        $total | Should-BeLessThanOrEqual $Budget
    }

    It 'Give the skill <SkillName> a name that matches its folder and a usable description' -ForEach $skillCases {
        $text = & $readFile -Root $repositoryRoot -RelativePath ".github/skills/$SkillName/SKILL.md"
        $lines = $text.Replace("`r`n", "`n").Split("`n")
        $description = ($lines[2] -replace '^description: ', '')

        $lines[0] | Should-BeString '---'
        $lines[1] | Should-BeString "name: $SkillName"
        $lines[2] | Should-MatchString '^description: \S'
        $lines[3] | Should-BeString '---'
        $SkillName.Length | Should-BeLessThanOrEqual 64
        $description.Length | Should-BeLessThanOrEqual 1024
        $description | Should-MatchString 'Use when'
    }

    It 'Give every agent the same copy of the skill <SkillName>' -ForEach $skillCases {
        $copilotCopy = & $readFile -Root $repositoryRoot -RelativePath ".github/skills/$SkillName/SKILL.md"
        $claudeCopy = & $readFile -Root $repositoryRoot -RelativePath ".claude/skills/$SkillName/SKILL.md"
        $codexCopy = & $readFile -Root $repositoryRoot -RelativePath ".agents/skills/$SkillName/SKILL.md"

        $claudeCopy | Should-BeString $copilotCopy
        $codexCopy | Should-BeString $copilotCopy
    }
}

Describe 'Content of instruction files' -Tag 'Unit' {
    It 'Has only PowerShell samples that parse in <RelativePath>' -ForEach $markdownCases {
        $text = [System.IO.File]::ReadAllText($FullPath).Replace("`r`n", "`n")
        $fences = @(& $getCodeFence -Text $text | Where-Object { $_.Language -eq 'powershell' })

        $failures = foreach ($fence in $fences) {
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput(
                $fence.Code, [ref]$null, [ref]$parseErrors)
            if ($parseErrors.Count -gt 0) {
                "line $($fence.Line): $($parseErrors[0].Message)"
            }
        }

        @($failures) -join '; ' | Should-BeString ''
    }

    It 'Names only files that exist in <RelativePath>' -ForEach $markdownCases {
        $text = [System.IO.File]::ReadAllText($FullPath).Replace("`r`n", "`n")
        $mentioned = [regex]::Matches($text, '`(?<path>\.github/instructions/[\w./-]+\.md)`') |
            ForEach-Object { $_.Groups['path'].Value } |
            Sort-Object -Unique

        $missing = foreach ($mentionedPath in $mentioned) {
            if (-not (Test-Path -LiteralPath (Join-Path -Path $repositoryRoot -ChildPath $mentionedPath))) {
                $mentionedPath
            }
        }

        @($missing) -join ', ' | Should-BeString ''
    }

    It 'Links only to files that ship with the instructions in <RelativePath>' -ForEach $markdownCases {
        $text = [System.IO.File]::ReadAllText($FullPath).Replace("`r`n", "`n")
        $prose = $text
        foreach ($fence in & $getCodeFence -Text $text) {
            if ($fence.Code) {
                $prose = $prose.Replace($fence.Code, '')
            }
        }
        # Inline code can contain text that looks like a link, such as `[void](...)`.
        $prose = $prose -replace '`[^`\n]+`', ''
        $targets = [regex]::Matches($prose, '\]\((?<target>[^)#\s]+)(#[^)]*)?\)') |
            ForEach-Object { $_.Groups['target'].Value } |
            Where-Object { $_ -notmatch '^(https?:|mailto:)' } |
            Sort-Object -Unique

        $separator = [System.IO.Path]::DirectorySeparatorChar
        $shippedRoot = (Join-Path -Path $repositoryRoot -ChildPath '.github/instructions') + $separator
        $fileFolder = Split-Path -Path $FullPath -Parent
        $broken = foreach ($target in $targets) {
            $resolved = [System.IO.Path]::GetFullPath((Join-Path -Path $fileFolder -ChildPath $target))
            $isShipped = $resolved.StartsWith($shippedRoot, [System.StringComparison]::OrdinalIgnoreCase)
            if (-not $isShipped -or -not (Test-Path -LiteralPath $resolved)) {
                $target
            }
        }

        @($broken) -join ', ' | Should-BeString ''
    }

    It 'Has only ASCII PowerShell samples and no emoji in <RelativePath>' -ForEach $markdownCases {
        $text = [System.IO.File]::ReadAllText($FullPath).Replace("`r`n", "`n")
        $fences = @(& $getCodeFence -Text $text | Where-Object { $_.Language -eq 'powershell' })

        # Agents copy samples into source files, where non-ASCII characters break Windows PowerShell 5.1.
        $nonAsciiSamples = foreach ($fence in $fences) {
            if ($fence.Code -match '[^\x00-\x7F]') {
                "line $($fence.Line)"
            }
        }

        # Surrogate pairs, the symbol and dingbat blocks, and the emoji variation selector. The
        # pattern is built from character codes so that this file stays ASCII.
        $surrogatePair = '[{0}-{1}][{2}-{3}]' -f [char]0xD83C, [char]0xDBFF, [char]0xDC00, [char]0xDFFF
        $symbolBlocks = '[{0}-{1}]' -f [char]0x2600, [char]0x27BF
        $emojiPattern = "$surrogatePair|$symbolBlocks|$([char]0xFE0F)"
        $emojiCount = [regex]::Matches($text, $emojiPattern).Count

        @($nonAsciiSamples) -join ', ' | Should-BeString ''
        $emojiCount | Should-Be 0
    }
}

Describe 'Build-AgentInstructions.ps1' -Tag 'Unit' {
    BeforeEach {
        $fixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        & $newFixtureRepository -Root $fixtureRoot -RuleText $sampleRuleText -CoreText $sampleCoreText
    }

    It 'Writes a Copilot file, a Claude Code rule, and the three core files' {
        $files = @(& $buildScript -RepositoryRoot $fixtureRoot)
        $copilotFile = '.github/instructions/powershell-sample.instructions.md'
        $claudeFile = '.claude/rules/powershell-standards/powershell-sample.md'

        $files | Should-BeCollection -Count 5
        $files | Should-All { $_.Status -eq 'Written' }
        Test-Path -LiteralPath (Join-Path -Path $fixtureRoot -ChildPath $copilotFile) | Should-BeTrue
        Test-Path -LiteralPath (Join-Path -Path $fixtureRoot -ChildPath $claudeFile) | Should-BeTrue
    }

    It 'Copies a listed rule into the core and leaves out the others' {
        $null = & $buildScript -RepositoryRoot $fixtureRoot
        $core = & $readFile -Root $fixtureRoot -RelativePath '.github/copilot-instructions.md'

        $core | Should-MatchString '- \*\*SMP-02\*\* Second rule\.'
        $core | Should-NotMatchString 'SMP-01'
        $core | Should-MatchString 'Generated from Fixture-Standards 0\.0\.1'
    }

    It 'Writes the pointer to AGENTS.md, a rule that imports the core, and no CLAUDE.md' {
        $null = & $buildScript -RepositoryRoot $fixtureRoot
        $pointer = & $readFile -Root $fixtureRoot -RelativePath 'AGENTS.md'
        $coreRulePath = '.claude/rules/powershell-standards/copilot-instructions.md'
        $coreRule = & $readFile -Root $fixtureRoot -RelativePath $coreRulePath

        $pointer | Should-MatchString '(?s)^# Pointer\n\n> Generated from Fixture-Standards 0\.0\.1'
        $pointer | Should-MatchString 'Read the core file\.'
        $pointer | Should-NotMatchString 'SMP-0'
        $coreRule.StartsWith("@../../../.github/copilot-instructions.md`n") | Should-BeTrue
        Test-Path -LiteralPath (Join-Path -Path $fixtureRoot -ChildPath 'CLAUDE.md') | Should-BeFalse
    }

    It 'Fails when the pointer source does not start with a heading' {
        $pointerPath = Join-Path -Path $fixtureRoot -ChildPath 'standards/pointer.md'
        Set-Content -LiteralPath $pointerPath -Value 'No heading.' -Encoding ascii

        { & $buildScript -RepositoryRoot $fixtureRoot } |
            Should-Throw -ExceptionMessage '*must start with a level-one heading*'
    }

    It 'Keeps a rule''s continuation line when it copies the rule into the core' {
        $coreText = "# Core`n`n<!-- rules: SMP-01 -->`n"
        & $newFixtureRepository -Root $fixtureRoot -RuleText $sampleRuleText -CoreText $coreText

        $null = & $buildScript -RepositoryRoot $fixtureRoot
        $core = & $readFile -Root $fixtureRoot -RelativePath '.github/copilot-instructions.md'

        $core | Should-MatchString '(?s)First rule, which continues\n  on a second line\.'
    }

    It 'Reports every file as current on a second run' {
        $null = & $buildScript -RepositoryRoot $fixtureRoot
        $files = @(& $buildScript -RepositoryRoot $fixtureRoot -Check)

        $files | Should-BeCollection -Count 5
        $files | Should-All { $_.Status -eq 'Current' }
    }

    It 'Fails the check when a generated file was edited by hand' {
        $null = & $buildScript -RepositoryRoot $fixtureRoot
        $corePath = Join-Path -Path $fixtureRoot -ChildPath '.github/copilot-instructions.md'
        Add-Content -LiteralPath $corePath -Value 'edited' -Encoding ascii

        { & $buildScript -RepositoryRoot $fixtureRoot -Check } |
            Should-Throw -ExceptionMessage '*do not match their sources*'
    }

    It 'Removes a generated file that the sources no longer produce' {
        $null = & $buildScript -RepositoryRoot $fixtureRoot
        $stalePath = Join-Path -Path $fixtureRoot -ChildPath '.claude/rules/powershell-retired.md'
        Set-Content -LiteralPath $stalePath -Value 'old' -Encoding ascii

        $files = @(& $buildScript -RepositoryRoot $fixtureRoot)

        @($files | Where-Object { $_.Status -eq 'Removed' }) | Should-BeCollection -Count 1
        Test-Path -LiteralPath $stalePath | Should-BeFalse
    }

    It 'Fails the check when a stale generated file is present' {
        $null = & $buildScript -RepositoryRoot $fixtureRoot
        $stalePath = Join-Path -Path $fixtureRoot -ChildPath '.claude/rules/powershell-retired.md'
        Set-Content -LiteralPath $stalePath -Value 'old' -Encoding ascii

        { & $buildScript -RepositoryRoot $fixtureRoot -Check } |
            Should-Throw -ExceptionMessage '*do not match their sources*'
        Test-Path -LiteralPath $stalePath | Should-BeTrue
    }

    It 'Expands an include directive into a code fence' {
        $includedPath = Join-Path -Path $fixtureRoot -ChildPath 'sample.ps1'
        Set-Content -LiteralPath $includedPath -Value "'included text'" -Encoding ascii
        $ruleText = $sampleRuleText + "`n<!-- include: sample.ps1 -->`n"
        & $newFixtureRepository -Root $fixtureRoot -RuleText $ruleText -CoreText $sampleCoreText

        $null = & $buildScript -RepositoryRoot $fixtureRoot
        $rulePath = '.github/instructions/powershell-sample.instructions.md'
        $rule = & $readFile -Root $fixtureRoot -RelativePath $rulePath

        $rule | Should-MatchString '(?s)```powershell\n''included text''\n```'
    }

    It 'Fails when an included file does not exist' {
        $ruleText = $sampleRuleText + "`n<!-- include: absent.ps1 -->`n"
        & $newFixtureRepository -Root $fixtureRoot -RuleText $ruleText -CoreText $sampleCoreText

        { & $buildScript -RepositoryRoot $fixtureRoot } | Should-Throw -ExceptionMessage '*absent.ps1*'
    }

    It 'Fails when <Problem>' -ForEach @(
        @{
            Problem = 'a rule ID is defined twice'
            RuleText = "# Sample rules`n`n- **SMP-01** One.`n- **SMP-01** One again.`n"
            CoreText = "# Core`n"
            Message = '*defined more than once*'
        }
        @{
            Problem = 'a rule uses another file''s prefix'
            RuleText = "# Sample rules`n`n- **ERR-01** Wrong prefix.`n"
            CoreText = "# Core`n"
            Message = "*must start with 'SMP-'*"
        }
        @{
            Problem = 'the core lists a rule that does not exist'
            RuleText = "# Sample rules`n`n- **SMP-01** One.`n"
            CoreText = "# Core`n`n<!-- rules: SMP-09 -->`n"
            Message = '*which no rule file defines*'
        }
        @{
            Problem = 'a rule file does not start with a heading'
            RuleText = "- **SMP-01** One.`n"
            CoreText = "# Core`n"
            Message = '*must start with a level-one heading*'
        }
        @{
            Problem = 'the core does not start with a heading'
            RuleText = "# Sample rules`n`n- **SMP-01** One.`n"
            CoreText = "Core without a heading`n"
            Message = '*must start with a level-one heading*'
        }
    ) {
        & $newFixtureRepository -Root $fixtureRoot -RuleText $RuleText -CoreText $CoreText

        { & $buildScript -RepositoryRoot $fixtureRoot } | Should-Throw -ExceptionMessage $Message
    }
}
