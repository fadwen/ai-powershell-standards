#requires -Version 7.6

<#
.SYNOPSIS
Builds the agent instruction files from the sources in the standards folder.

.DESCRIPTION
Reads standards/manifest.psd1, standards/core.md, the rule files under standards/rules, and the
skills under standards/skills. From them it writes the files that each coding agent reads:

- .github/copilot-instructions.md holds the core.
- AGENTS.md points to that file. GitHub Copilot loads AGENTS.md as well as its own file, so the
  core is written once. Install-CopilotStandards.ps1 writes the core to AGENTS.md for a project
  that does not use GitHub Copilot.
- .github/instructions/<Id>.instructions.md holds each topic for GitHub Copilot.
- .claude/rules/powershell-standards/<Id>.md is the Claude Code rule for each topic. It carries the
  same globs and imports the Copilot file, so no rule text is written twice. The rule named
  copilot-instructions.md in that folder imports the core.
- .github/skills, .claude/skills, and .agents/skills each receive a copy of every skill.

A file that is no longer produced is removed from those locations when its name starts with
'powershell-'.

With -Check nothing is written or removed. The script compares what it would write with the files
on disk and fails when any file is out of date or stale.

.PARAMETER RepositoryRoot
Root folder of the repository. The default is the parent of the folder that contains this script.

.PARAMETER Check
Compares instead of writing, and fails when the generated files do not match their sources.

.EXAMPLE
./Tools/Build-AgentInstructions.ps1

Rebuilds every generated file.

.EXAMPLE
./Tools/Build-AgentInstructions.ps1 -Check

Fails when a generated file differs from what the sources produce. Use this in CI.

.INPUTS
None.

.OUTPUTS
PowerShellStandards.GeneratedFile. One object for each generated file, with Path and Status
properties. Status is Current, Written, Removed, OutOfDate, or Stale.
#>
[CmdletBinding()]
[OutputType('PowerShellStandards.GeneratedFile')]
param(
    [Parameter()]
    [string]$RepositoryRoot = (Split-Path -Path $PSScriptRoot -Parent),

    [Parameter()]
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


function ConvertTo-LfText {
    <#
    .SYNOPSIS
    Converts text to LF line endings with exactly one trailing newline.

    .DESCRIPTION
    Generated files are compared as text, so line endings are made uniform first. This keeps the
    comparison independent of how Git checked the files out.

    .PARAMETER Text
    The text to convert.

    .EXAMPLE
    ConvertTo-LfText -Text "one`r`ntwo"

    Returns the two lines separated by LF and followed by one LF.

    .INPUTS
    None.

    .OUTPUTS
    System.String.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $lfText = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $lfText.TrimEnd("`n") + "`n"
}


function Expand-IncludeDirective {
    <#
    .SYNOPSIS
    Replaces each include directive in Markdown text with the named file in a code fence.

    .DESCRIPTION
    A directive is a line of the form '<!-- include: relative/path -->'. The path is relative to
    the repository root. Including a real file keeps a sample in the instructions identical to
    code that the test suite runs.

    .PARAMETER Text
    Markdown text with LF line endings.

    .PARAMETER RootPath
    Absolute path of the repository root.

    .EXAMPLE
    Expand-IncludeDirective -Text $markdown -RootPath $RepositoryRoot

    Returns the Markdown with every include directive replaced.

    .INPUTS
    None.

    .OUTPUTS
    System.String.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $languageByExtension = @{
        '.ps1' = 'powershell'
        '.psm1' = 'powershell'
        '.psd1' = 'powershell'
        '.yml' = 'yaml'
        '.yaml' = 'yaml'
    }

    $expanded = $Text
    foreach ($directive in [regex]::Matches($Text, '(?m)^<!-- include: (?<path>\S+) -->[ \t]*$')) {
        $includePath = Join-Path -Path $RootPath -ChildPath $directive.Groups['path'].Value
        try {
            $content = [System.IO.File]::ReadAllText($includePath)
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }

        $extension = [System.IO.Path]::GetExtension($includePath).ToLowerInvariant()
        $language = if ($languageByExtension.ContainsKey($extension)) {
            $languageByExtension[$extension]
        } else {
            'text'
        }
        $fence = if ($content.Contains('```')) { '````' } else { '```' }
        $block = $fence + $language + "`n" + (ConvertTo-LfText -Text $content) + $fence
        $expanded = $expanded.Replace($directive.Value, $block)
    }

    $expanded
}


function Get-RuleEntry {
    <#
    .SYNOPSIS
    Gets the numbered rules from the text of a rule file.

    .DESCRIPTION
    A rule is a list item that starts with an ID in bold, such as '- **ERR-10** ...'. Lines that
    follow it and are indented by two spaces belong to the same rule.

    .PARAMETER Text
    Markdown text of a rule file, with LF line endings.

    .EXAMPLE
    Get-RuleEntry -Text $ruleFileText

    Returns one object for each rule in the file.

    .INPUTS
    None.

    .OUTPUTS
    PowerShellStandards.RuleEntry. An object with Id and Text properties.
    #>
    [CmdletBinding()]
    [OutputType('PowerShellStandards.RuleEntry')]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $ruleId = $null
    $ruleLines = [System.Collections.Generic.List[string]]::new()

    # The extra empty line at the end closes a rule that is the last line of the text.
    foreach ($line in @($Text -split "`n") + '') {
        $startsRule = $line -match '^- \*\*(?<id>[A-Z]{3}-\d{2})\*\* '
        $continuesRule = $null -ne $ruleId -and -not $startsRule -and $line -match '^  \S'

        if ($continuesRule) {
            $ruleLines.Add($line)
            continue
        }

        if ($null -ne $ruleId) {
            [PSCustomObject]@{
                PSTypeName = 'PowerShellStandards.RuleEntry'
                Id = $ruleId
                Text = $ruleLines -join "`n"
            }
            $ruleId = $null
            $ruleLines.Clear()
        }

        if ($startsRule) {
            $ruleId = $Matches['id']
            $ruleLines.Add($line)
        }
    }
}


$manifestPath = Join-Path -Path $RepositoryRoot -ChildPath 'standards/manifest.psd1'
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$notice = @(
    "> Generated from $($manifest.Name) $($manifest.Version). Do not edit this file."
    '> Its source is the `standards` folder of that repository; `Tools/Build-AgentInstructions.ps1` rebuilds it.'
) -join "`n"

$claudeRuleFolder = '.claude/rules/powershell-standards'

# The body of a Claude Code rule that imports a file under .github instead of repeating it. The
# import path is relative to the rule file, which sits three folders below the repository root.
$newClaudeImport = {
    param([string]$Source)

    $lines = @(
        "@../../../$Source"
        ''
        ('Source of this rule: `{0}`, which GitHub Copilot reads as well.' -f $Source)
        'This file is generated by `Tools/Build-AgentInstructions.ps1`. Change the source under'
        '`standards/` instead of editing it.'
        ''
    )
    $lines -join "`n"
}

# Relative path of each generated file, mapped to its content.
$generated = [ordered]@{}
$ruleTextById = @{}

foreach ($rule in $manifest.Rules) {
    if ($rule.Id -notlike 'powershell-*') {
        throw "Rule ID '$($rule.Id)' must start with 'powershell-'."
    }
    if ($rule.Description.Contains('"')) {
        throw "The description of rule '$($rule.Id)' must not contain a double quote."
    }

    $sourcePath = Join-Path -Path $RepositoryRoot -ChildPath "standards/rules/$($rule.Id).md"
    $source = ConvertTo-LfText -Text ([System.IO.File]::ReadAllText($sourcePath))
    if (-not $source.StartsWith('# ')) {
        throw "'$sourcePath' must start with a level-one heading."
    }

    foreach ($entry in Get-RuleEntry -Text $source) {
        if ($entry.Id -notlike "$($rule.Prefix)-*") {
            throw "Rule $($entry.Id) is in '$($rule.Id)', whose rules must start with '$($rule.Prefix)-'."
        }
        if ($ruleTextById.ContainsKey($entry.Id)) {
            throw "Rule $($entry.Id) is defined more than once."
        }
        $ruleTextById[$entry.Id] = $entry.Text
    }

    $firstLineEnd = $source.IndexOf("`n")
    $body = $source.Substring(0, $firstLineEnd + 1) + "`n" + $notice + "`n" + $source.Substring($firstLineEnd + 1)
    $body = Expand-IncludeDirective -Text $body -RootPath $RepositoryRoot

    $applyTo = $rule.Globs -join ','
    $copilotHeader = "---`napplyTo: `"$applyTo`"`ndescription: `"$($rule.Description)`"`n---`n`n"
    $copilotFile = ".github/instructions/$($rule.Id).instructions.md"
    $generated[$copilotFile] = $copilotHeader + $body

    # A rule whose only glob is '**' gets no paths, so that Claude Code loads it when the session
    # starts instead of when a file is read.
    $claudeHeader = ''
    if ($applyTo -ne '**') {
        $pathLines = ($rule.Globs | ForEach-Object { "  - `"$_`"" }) -join "`n"
        $claudeHeader = "---`npaths:`n$pathLines`n---`n`n"
    }
    $generated["$claudeRuleFolder/$($rule.Id).md"] = $claudeHeader + (& $newClaudeImport -Source $copilotFile)
}

$corePath = Join-Path -Path $RepositoryRoot -ChildPath $manifest.Core
$core = ConvertTo-LfText -Text ([System.IO.File]::ReadAllText($corePath))
if (-not $core.StartsWith('# ')) {
    throw "'$corePath' must start with a level-one heading."
}

foreach ($directive in [regex]::Matches($core, '(?m)^<!-- rules: (?<ids>[A-Z0-9, -]+) -->[ \t]*$')) {
    $ruleIds = @($directive.Groups['ids'].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $ruleLines = foreach ($ruleId in $ruleIds) {
        if (-not $ruleTextById.ContainsKey($ruleId)) {
            throw "'$corePath' lists rule $ruleId, which no rule file defines."
        }
        $ruleTextById[$ruleId]
    }
    $core = $core.Replace($directive.Value, ($ruleLines -join "`n"))
}

$firstLineEnd = $core.IndexOf("`n")
$core = $core.Substring(0, $firstLineEnd + 1) + "`n" + $notice + "`n" + $core.Substring($firstLineEnd + 1)
$core = Expand-IncludeDirective -Text $core -RootPath $RepositoryRoot

$generated['.github/copilot-instructions.md'] = $core

$pointerPath = Join-Path -Path $RepositoryRoot -ChildPath $manifest.Pointer
$pointer = ConvertTo-LfText -Text ([System.IO.File]::ReadAllText($pointerPath))
if (-not $pointer.StartsWith('# ')) {
    throw "'$pointerPath' must start with a level-one heading."
}
$firstLineEnd = $pointer.IndexOf("`n")
$pointer = $pointer.Substring(0, $firstLineEnd + 1) + "`n" + $notice + "`n" + $pointer.Substring($firstLineEnd + 1)

$generated['AGENTS.md'] = $pointer
$coreRule = "$claudeRuleFolder/copilot-instructions.md"
$generated[$coreRule] = & $newClaudeImport -Source '.github/copilot-instructions.md'

$skillFolders = '.github/skills', '.claude/skills', '.agents/skills'
foreach ($skill in $manifest.Skills) {
    if ($skill -cnotmatch '^powershell-[a-z0-9-]{1,53}$') {
        throw "Skill name '$skill' must be 'powershell-' followed by lowercase letters, digits, or hyphens."
    }

    $skillPath = Join-Path -Path $RepositoryRoot -ChildPath "standards/skills/$skill/SKILL.md"
    $skillText = ConvertTo-LfText -Text ([System.IO.File]::ReadAllText($skillPath))
    foreach ($skillFolder in $skillFolders) {
        $generated["$skillFolder/$skill/SKILL.md"] = $skillText
    }
}

# Files under the managed locations that the sources no longer produce.
$managedPatterns = @(
    '.github/instructions/powershell-*.instructions.md'
    "$claudeRuleFolder/*.md"
    # Rules that an earlier layout wrote beside the folder
    '.claude/rules/powershell-*.md'
) + ($skillFolders | ForEach-Object { "$_/powershell-*/SKILL.md" })

$staleFiles = foreach ($pattern in $managedPatterns) {
    $patternPath = Join-Path -Path $RepositoryRoot -ChildPath $pattern
    foreach ($file in Get-ChildItem -Path $patternPath -File -ErrorAction SilentlyContinue) {
        $relativePath = [System.IO.Path]::GetRelativePath($RepositoryRoot, $file.FullName).Replace('\', '/')
        if (-not $generated.Contains($relativePath)) {
            $relativePath
        }
    }
}

$problemCount = 0
$utf8 = [System.Text.UTF8Encoding]::new($false)

foreach ($relativePath in $generated.Keys) {
    $fullPath = Join-Path -Path $RepositoryRoot -ChildPath $relativePath
    $expected = $generated[$relativePath]
    $actual = if (Test-Path -LiteralPath $fullPath) {
        ConvertTo-LfText -Text ([System.IO.File]::ReadAllText($fullPath))
    } else {
        $null
    }

    $status = 'Current'
    if ($actual -cne $expected) {
        if ($Check) {
            $status = 'OutOfDate'
            $problemCount++
        } else {
            $status = 'Written'
            $null = New-Item -Path (Split-Path -Path $fullPath -Parent) -ItemType Directory -Force
            [System.IO.File]::WriteAllText($fullPath, $expected, $utf8)
        }
    }

    [PSCustomObject]@{
        PSTypeName = 'PowerShellStandards.GeneratedFile'
        Path = $relativePath
        Status = $status
    }
}

foreach ($relativePath in $staleFiles) {
    $status = 'Removed'
    if ($Check) {
        $status = 'Stale'
        $problemCount++
    } else {
        Remove-Item -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath $relativePath)
    }

    [PSCustomObject]@{
        PSTypeName = 'PowerShellStandards.GeneratedFile'
        Path = $relativePath
        Status = $status
    }
}

if ($problemCount -gt 0) {
    throw "$problemCount generated file(s) do not match their sources. Run Tools/Build-AgentInstructions.ps1."
}
