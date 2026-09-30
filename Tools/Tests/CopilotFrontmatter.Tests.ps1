#Requires -Module Pester

# VS Code checks the YAML header of prompt and instruction files against a fixed set of fields and
# flags anything else in the editor. These tests hold the shipped files to that set, so a field that
# was renamed upstream (mode became agent) or never belonged (tools in an instructions file) fails
# here rather than surfacing as a warning in every consuming project.
#
# Supported fields, from the VS Code customization docs:
#   *.prompt.md        description, name, argument-hint, agent, model, tools
#   *.instructions.md  name, description, applyTo

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    $promptCases = Get-ChildItem (Join-Path $repoRoot '.github/prompts') -Filter '*.prompt.md' |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }

    $instructionCases = Get-ChildItem (Join-Path $repoRoot '.github/instructions') -Filter '*.instructions.md' |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
}

BeforeAll {
    function Get-FrontMatter {
        param([string]$Path)

        $lines = @(Get-Content -Path $Path)
        if ($lines.Count -lt 2 -or $lines[0] -ne '---') { return @() }

        $end = [array]::IndexOf($lines, '---', 1)
        if ($end -lt 2) { return @() }

        $lines[1..($end - 1)]
    }

    function Get-FrontMatterKey {
        param([string]$Path)

        Get-FrontMatter -Path $Path |
            Where-Object { $_ -match '^[A-Za-z][A-Za-z-]*:' } |
            ForEach-Object { ($_ -split ':', 2)[0] }
    }

    function Get-FrontMatterValue {
        param([string]$Path, [string]$Key)

        $line = Get-FrontMatter -Path $Path | Where-Object { $_ -match "^${Key}:" } | Select-Object -First 1
        if (-not $line) { return '' }

        ($line -replace "^${Key}:\s*", '').Trim()
    }
}

Describe 'Copilot prompt file headers' -Tag 'Unit', 'Frontmatter' {

    It 'Uses only supported header fields in <Name>' -ForEach $promptCases {
        $supported = 'description', 'name', 'argument-hint', 'agent', 'model', 'tools'
        $unsupported = Get-FrontMatterKey -Path $Path | Where-Object { $_ -notin $supported }

        # mode was renamed to agent; anything listed here is flagged by VS Code
        ($unsupported -join ', ') | Should-Be ''
    }

    It 'Names an agent VS Code still has in <Name>' -ForEach $promptCases {
        $agent = (Get-FrontMatterValue -Path $Path -Key 'agent').Trim('"', "'")

        # edit was a mode; it is not an agent. ask, agent, plan or a custom agent name are valid.
        ($agent -eq 'edit') | Should-BeFalse
    }

    It 'Writes search/codebase with its tool set prefix in <Name>' -ForEach $promptCases {
        $tools = Get-FrontMatterValue -Path $Path -Key 'tools'

        ($tools -match "['""]codebase['""]") | Should-BeFalse
    }
}

Describe 'Copilot instruction file headers' -Tag 'Unit', 'Frontmatter' {

    It 'Uses only name, description and applyTo in <Name>' -ForEach $instructionCases {
        $supported = 'name', 'description', 'applyTo'
        $unsupported = Get-FrontMatterKey -Path $Path | Where-Object { $_ -notin $supported }

        ($unsupported -join ', ') | Should-Be ''
    }

    It 'Declares an applyTo glob in <Name>' -ForEach $instructionCases {
        # Without applyTo the file is never applied automatically, and its Claude rule has no paths
        Get-FrontMatterValue -Path $Path -Key 'applyTo' | Should-NotBeNull
        ((Get-FrontMatterValue -Path $Path -Key 'applyTo').Length -gt 0) | Should-BeTrue
    }
}
