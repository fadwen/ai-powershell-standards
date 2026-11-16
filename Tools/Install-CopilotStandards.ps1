#requires -Version 5.1

<#
.SYNOPSIS
Installs the PowerShell standards into a project for GitHub Copilot, Claude Code, and Codex.

.DESCRIPTION
Copies the generated instruction files from this repository into the project at ProjectPath.
Run it again to update a project: files that the standards own are replaced, and files that the
standards no longer produce are removed.

Files the standards own are always replaced. They are the topic rules
(.github/instructions/powershell-*.instructions.md), the Pester guides beside them, the Claude Code
rules (.claude/rules/powershell-standards), and the skills whose names start with 'powershell-'.

Files a project may already have are never replaced unless they were installed by this script or
-Force is given. They are .github/copilot-instructions.md, AGENTS.md, PSScriptAnalyzerSettings.psd1,
and the sync workflow. When one is left alone, a warning says how to connect it to the standards.
The project's CLAUDE.md is never touched: Claude Code loads the standards from its rules folder.

The core rules are installed once, so that no agent loads them twice. They go into
.github/copilot-instructions.md, which GitHub Copilot reads and which a Claude Code rule imports.
GitHub Copilot also reads AGENTS.md, so AGENTS.md is then a short pointer to that file. When the
project uses only Codex, or has its own .github/copilot-instructions.md, AGENTS.md holds the core.

.PARAMETER ProjectPath
Root folder of the project to install into. It must exist.

.PARAMETER Agent
The coding agents the project uses. The default is all three. The topic rules under
.github/instructions are installed for every choice, because the core file points to them. Files
that an earlier installation wrote for an agent that is no longer listed are removed.

.PARAMETER IncludeAnalyzerSettings
Also installs PSScriptAnalyzerSettings.psd1, the settings that check the layout rules.

.PARAMETER IncludeSyncWorkflow
Also installs .github/workflows/sync-copilot-standards.yml, a scheduled workflow that reruns this
installation from the standards repository and opens a pull request when files change.

.PARAMETER RemoveLegacyFiles
Removes the files that versions before 2.0 installed or mirrored: the earlier instruction files, the
prompt files and their Claude Code commands, and the mirrored powershell-standards folder. Without
this switch they are reported in a warning and left in place.

.PARAMETER Force
Replaces a file the project already has even when this script did not install it.

.EXAMPLE
./Tools/Install-CopilotStandards.ps1 -ProjectPath 'C:\Projects\MyModule'

Installs the standards for all three agents.

.EXAMPLE
./Tools/Install-CopilotStandards.ps1 -ProjectPath . -Agent Copilot -IncludeSyncWorkflow -WhatIf

Shows what an installation for GitHub Copilot with the sync workflow would change.

.INPUTS
None.

.OUTPUTS
PowerShellStandards.InstalledFile. One object for each file considered, with Path and Status
properties. Status is Installed, Updated, Unchanged, Skipped, or Removed.
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType('PowerShellStandards.InstalledFile')]
param(
    [Parameter(Mandatory)]
    [string]$ProjectPath,

    [Parameter()]
    [ValidateSet('Copilot', 'ClaudeCode', 'Codex')]
    [string[]]$Agent = @('Copilot', 'ClaudeCode', 'Codex'),

    [Parameter()]
    [switch]$IncludeAnalyzerSettings,

    [Parameter()]
    [switch]$IncludeSyncWorkflow,

    [Parameter()]
    [switch]$RemoveLegacyFiles,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$standardsRoot = Split-Path -Path $PSScriptRoot -Parent
$projectRoot = Convert-Path -LiteralPath $ProjectPath
if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
    throw "ProjectPath '$ProjectPath' is not a folder."
}

if ($projectRoot.TrimEnd('\', '/') -eq $standardsRoot.TrimEnd('\', '/')) {
    throw 'ProjectPath is the standards repository itself. Its files are built by Build-AgentInstructions.ps1.'
}

$manifestPath = Join-Path -Path (Join-Path -Path $standardsRoot -ChildPath 'standards') -ChildPath 'manifest.psd1'
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$generatedMarker = "Generated from $($manifest.Name)"

# Each entry is a file to install: where it comes from, where it goes, and who owns the destination.
# 'Standards' files are always replaced. 'Project' files are replaced only if this script wrote them.
$plan = [System.Collections.Generic.List[hashtable]]::new()

foreach ($rule in $manifest.Rules) {
    $relativePath = ".github/instructions/$($rule.Id).instructions.md"
    $plan.Add(@{ Source = $relativePath; Destination = $relativePath; Owner = 'Standards' })
}

foreach ($reference in $manifest.Reference) {
    $referencePath = Join-Path -Path $standardsRoot -ChildPath $reference
    if (-not (Test-Path -LiteralPath $referencePath -PathType Container)) {
        continue
    }
    foreach ($file in Get-ChildItem -LiteralPath $referencePath -File -Recurse) {
        $relativePath = $file.FullName.Substring($standardsRoot.Length).TrimStart('\', '/').Replace('\', '/')
        $plan.Add(@{ Source = $relativePath; Destination = $relativePath; Owner = 'Standards' })
    }
}

# True when the text of an always-loaded file shows that this script wrote it.
$coreFile = '.github/copilot-instructions.md'
$claudeRuleFolder = '.claude/rules/powershell-standards'
$testInstalledText = {
    param([string]$Text)

    $Text.Contains($generatedMarker)
}

# The core is installed once. GitHub Copilot reads its own file and AGENTS.md, and the Claude Code
# rules import the Copilot file, so that file holds the core whenever either agent is selected and
# AGENTS.md then only points to it. The Copilot file cannot hold the core when the project wrote
# that file itself, or uses neither agent; AGENTS.md holds it then.
$copilotHoldsCore = $false
$skillFolders = [System.Collections.Generic.List[string]]::new()
if ($Agent -contains 'Copilot' -or $Agent -contains 'ClaudeCode') {
    $coreDestination = Join-Path -Path $projectRoot -ChildPath $coreFile
    $copilotHoldsCore = $true
    if (-not $Force -and (Test-Path -LiteralPath $coreDestination)) {
        $copilotHoldsCore = & $testInstalledText -Text ([System.IO.File]::ReadAllText($coreDestination))
    }
    $plan.Add(@{ Source = $coreFile; Destination = $coreFile; Owner = 'Project' })
}
if ($Agent -contains 'Copilot') {
    $skillFolders.Add('.github/skills')
}
if ($Agent -contains 'ClaudeCode') {
    foreach ($rule in $manifest.Rules) {
        $relativePath = "$claudeRuleFolder/$($rule.Id).md"
        $plan.Add(@{ Source = $relativePath; Destination = $relativePath; Owner = 'Standards' })
    }

    # The rule that loads the core at launch imports whichever file holds it.
    $coreRule = "$claudeRuleFolder/copilot-instructions.md"
    if ($copilotHoldsCore) {
        $plan.Add(@{ Source = $coreRule; Destination = $coreRule; Owner = 'Standards' })
    } else {
        $importLines = @(
            '@../../../AGENTS.md'
            ''
            'Source of this rule: `AGENTS.md`, which holds the core rules in this project.'
            ''
        )
        $plan.Add(@{ Text = ($importLines -join "`n"); Destination = $coreRule; Owner = 'Standards' })
    }
    $skillFolders.Add('.claude/skills')
}
if ($Agent -contains 'Codex') {
    $skillFolders.Add('.agents/skills')
}
if ($Agent -contains 'Codex' -or ($Agent -contains 'ClaudeCode' -and -not $copilotHoldsCore)) {
    # In the standards repository AGENTS.md is the pointer and the Copilot file is the core.
    $agentsSource = if ($copilotHoldsCore) { 'AGENTS.md' } else { $coreFile }
    $plan.Add(@{ Source = $agentsSource; Destination = 'AGENTS.md'; Owner = 'Project' })
}

foreach ($skillFolder in $skillFolders) {
    foreach ($skill in $manifest.Skills) {
        $relativePath = "$skillFolder/$skill/SKILL.md"
        $plan.Add(@{ Source = $relativePath; Destination = $relativePath; Owner = 'Standards' })
    }
}

if ($IncludeAnalyzerSettings) {
    $plan.Add(@{
            Source = 'PSScriptAnalyzerSettings.psd1'
            Destination = 'PSScriptAnalyzerSettings.psd1'
            Owner = 'Project'
        })
}
if ($IncludeSyncWorkflow) {
    $plan.Add(@{
            Source = 'Templates/Workflows/sync-copilot-standards.yml'
            Destination = '.github/workflows/sync-copilot-standards.yml'
            Owner = 'Project'
        })
}

$plannedDestinations = @($plan | ForEach-Object { $_.Destination })

foreach ($entry in $plan) {
    $destinationPath = Join-Path -Path $projectRoot -ChildPath $entry.Destination
    $hasText = $entry.ContainsKey('Text')
    if ($hasText) {
        $sourceText = $entry.Text
    } else {
        $sourcePath = Join-Path -Path $standardsRoot -ChildPath $entry.Source
        $sourceText = [System.IO.File]::ReadAllText($sourcePath).Replace("`r`n", "`n")
    }

    $status = 'Installed'
    if (Test-Path -LiteralPath $destinationPath) {
        $destinationText = [System.IO.File]::ReadAllText($destinationPath).Replace("`r`n", "`n")
        $installedByThisScript = & $testInstalledText -Text $destinationText

        if ($destinationText -ceq $sourceText) {
            $status = 'Unchanged'
        } elseif ($entry.Owner -eq 'Standards' -or $installedByThisScript -or $Force) {
            $status = 'Updated'
        } else {
            $status = 'Skipped'
        }
    }

    if ($status -eq 'Skipped') {
        $advice = switch ($entry.Destination) {
            'AGENTS.md' {
                if ($copilotHoldsCore) {
                    "Add a line to it that tells agents to read $coreFile before they work on PowerShell files."
                } else {
                    'Add a line to it that tells agents to read the files under .github/instructions first.'
                }
            }
            '.github/copilot-instructions.md' {
                'The topic rules under .github/instructions still load for matching files.'
            }
            default {
                'Compare it with the version in the standards repository.'
            }
        }
        $reason = "'$($entry.Destination)' already exists and was not installed by this script."
        Write-Warning "$reason It was left unchanged. $advice Use -Force to replace it."
    }

    if ($status -in 'Installed', 'Updated') {
        if ($PSCmdlet.ShouldProcess($destinationPath, "Write file from $($manifest.Name) $($manifest.Version)")) {
            $destinationFolder = Split-Path -Path $destinationPath -Parent
            if (-not (Test-Path -LiteralPath $destinationFolder)) {
                $null = New-Item -Path $destinationFolder -ItemType Directory -Force
            }
            if ($hasText) {
                $utf8 = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllText($destinationPath, $sourceText, $utf8)
            } else {
                Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
            }
        }
    }

    [PSCustomObject]@{
        PSTypeName = 'PowerShellStandards.InstalledFile'
        Path = $entry.Destination
        Status = $status
    }
}

# Files in the locations the standards own that this installation no longer includes.
$ownedPatterns = [System.Collections.Generic.List[string]]::new()
$ownedPatterns.Add('.github/instructions/powershell-*.instructions.md')
$ownedPatterns.Add("$claudeRuleFolder/*.md")
foreach ($skillFolder in '.github/skills', '.claude/skills', '.agents/skills') {
    $ownedPatterns.Add("$skillFolder/powershell-*/SKILL.md")
}
foreach ($reference in $manifest.Reference) {
    if (Test-Path -LiteralPath (Join-Path -Path $standardsRoot -ChildPath $reference) -PathType Container) {
        $ownedPatterns.Add("$reference/*")
    }
}

$legacyInstructionNames = @(
    'analyze', 'architecturedesign', 'cicd', 'comments', 'community-standards', 'errorsandlogs'
    'module', 'pester', 'platyps', 'readme', 'securitycompliance', 'style-enforcement'
)
$legacyPromptNames = @(
    'code-analysis', 'create-module', 'create-test', 'create-workflow', 'new-function'
    'optimize-performance', 'performance-analysis', 'scaffold-project', 'security-review'
    'validate-standards'
)
$legacyPaths = @(
    foreach ($name in $legacyInstructionNames) {
        ".github/instructions/$name.instructions.md"
    }
    '.github/instructions/futureTODO.md'
    '.github/instructions/pull-requests.instructions.md'
    foreach ($name in $legacyPromptNames) {
        ".github/prompts/$name.prompt.md"
        ".claude/commands/powershell-standards/$name.md"
    }
    # Earlier versions mirrored the worked examples into this folder and replaced it on every sync.
    $mirroredExamples = Join-Path -Path $projectRoot -ChildPath 'powershell-standards'
    if (Test-Path -LiteralPath $mirroredExamples -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $mirroredExamples -File -Recurse) {
            $file.FullName.Substring($projectRoot.Length).TrimStart('\', '/').Replace('\', '/')
        }
    }
)

$obsoletePaths = [System.Collections.Generic.List[string]]::new()
foreach ($pattern in $ownedPatterns) {
    $patternPath = Join-Path -Path $projectRoot -ChildPath $pattern
    foreach ($file in Get-ChildItem -Path $patternPath -File -ErrorAction SilentlyContinue) {
        $relativePath = $file.FullName.Substring($projectRoot.Length).TrimStart('\', '/').Replace('\', '/')
        if ($plannedDestinations -notcontains $relativePath) {
            $obsoletePaths.Add($relativePath)
        }
    }
}

# An always-loaded file that an earlier installation wrote and this one does not include. Leaving
# it in place would make an agent load the core twice, or load rules for an agent no longer used.
foreach ($relativePath in $coreFile, 'AGENTS.md') {
    $fullPath = Join-Path -Path $projectRoot -ChildPath $relativePath
    if ($plannedDestinations -contains $relativePath -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        continue
    }
    $existingText = [System.IO.File]::ReadAllText($fullPath).Replace("`r`n", "`n")
    if (& $testInstalledText -Text $existingText) {
        $obsoletePaths.Add($relativePath)
    }
}

$legacyFound = @(
    foreach ($legacyPath in $legacyPaths) {
        if (Test-Path -LiteralPath (Join-Path -Path $projectRoot -ChildPath $legacyPath)) {
            $legacyPath
        }
    }
)
if ($RemoveLegacyFiles) {
    foreach ($legacyPath in $legacyFound) {
        $obsoletePaths.Add($legacyPath)
    }
} elseif ($legacyFound.Count -gt 0) {
    $legacyList = $legacyFound -join ', '
    $legacyAdvice = 'They contradict the current rules. Run again with -RemoveLegacyFiles to remove them.'
    Write-Warning "Files from a version before 2.0 are still present: $legacyList. $legacyAdvice"
}

foreach ($obsoletePath in $obsoletePaths) {
    $fullPath = Join-Path -Path $projectRoot -ChildPath $obsoletePath
    if ($PSCmdlet.ShouldProcess($fullPath, 'Remove file that the standards no longer install')) {
        Remove-Item -LiteralPath $fullPath
    }

    [PSCustomObject]@{
        PSTypeName = 'PowerShellStandards.InstalledFile'
        Path = $obsoletePath
        Status = 'Removed'
    }
}
