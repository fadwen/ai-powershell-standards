@{
    # Name and version of the standards bundle. The version is written into every generated file.
    Name = 'ai-powershell-standards'
    Version = '2.0.0'

    # The always-loaded core. It is written to .github/copilot-instructions.md.
    Core = 'standards/core.md'

    # The text of AGENTS.md where the Copilot file holds the core. GitHub Copilot loads both files,
    # so AGENTS.md points to the core instead of repeating it.
    Pointer = 'standards/pointer.md'

    # Topic rules. Each entry becomes:
    #   .github/instructions/<Id>.instructions.md   (GitHub Copilot, scoped by applyTo)
    #   .claude/rules/<Id>.md                       (Claude Code, scoped by paths)
    # Prefix is the rule ID prefix that the file owns.
    Rules = @(
        @{
            Id = 'powershell-style'
            Prefix = 'STY'
            Description = 'PowerShell layout, naming, strings, paths, collections, and preferred constructs.'
            Globs = @('**/*.ps1', '**/*.psm1', '**/*.psd1')
        }
        @{
            Id = 'powershell-functions'
            Prefix = 'FUN'
            Description = 'PowerShell function structure, parameter, and output rules.'
            Globs = @('**/*.ps1', '**/*.psm1')
        }
        @{
            Id = 'powershell-error-handling'
            Prefix = 'ERR'
            Description = 'PowerShell error handling, strict mode, and output stream rules.'
            Globs = @('**/*.ps1', '**/*.psm1')
        }
        @{
            Id = 'powershell-security'
            Prefix = 'SEC'
            Description = 'PowerShell rules for secrets, credentials, untrusted input, and command execution.'
            Globs = @('**/*.ps1', '**/*.psm1')
        }
        @{
            Id = 'powershell-help'
            Prefix = 'DOC'
            Description = 'PowerShell comment-based help and code comment rules.'
            Globs = @('**/*.ps1', '**/*.psm1')
        }
        @{
            Id = 'powershell-version'
            Prefix = 'VER'
            Description = 'PowerShell target version, support lifecycle, and version-dependent features.'
            Globs = @('**/*.ps1', '**/*.psm1', '**/*.psd1')
        }
        @{
            Id = 'powershell-modules'
            Prefix = 'MOD'
            Description = 'PowerShell module layout, manifest, and root module rules.'
            Globs = @('**/*.psm1', '**/*.psd1')
        }
        @{
            Id = 'powershell-pester'
            Prefix = 'TST'
            Description = 'Pester 6 testing rules for PowerShell code.'
            Globs = @('**/*.Tests.ps1', '**/Tests/**/*.ps1')
        }
        @{
            Id = 'powershell-platyps'
            Prefix = 'PLT'
            Description = 'Rules for PowerShell module help built with Microsoft.PowerShell.PlatyPS.'
            Globs = @('**/docs/**/*.md')
        }
        @{
            Id = 'powershell-cicd'
            Prefix = 'CIC'
            Description = 'CI pipeline rules for repositories that contain PowerShell code.'
            Globs = @('**/.github/workflows/*.yml', '**/.github/workflows/*.yaml', '**/azure-pipelines.yml')
        }
        @{
            Id = 'powershell-readme'
            Prefix = 'RDM'
            Description = 'README rules for PowerShell projects.'
            Globs = @('**/README.md')
        }
        @{
            # Loads in every session: opening a pull request does not always involve reading a file.
            Id = 'powershell-pull-requests'
            Prefix = 'PRQ'
            Description = 'Branch, commit, and pull request conventions.'
            Globs = @('**')
        }
    )

    # Skills. The SKILL.md of each folder under standards/skills is written to .github/skills,
    # .claude/skills, and .agents/skills, the folders that GitHub Copilot, Claude Code, and Codex
    # read. An include directive in it is replaced by the file that it names.
    Skills = @(
        'powershell-new-function'
        'powershell-new-module'
        'powershell-write-tests'
        'powershell-review'
        'powershell-security-review'
        'powershell-performance-review'
        'powershell-ci-pipeline'
        'powershell-module-help'
        'powershell-logging'
        'powershell-credential-scan'
    )

    # Files that ship unchanged because rule files refer to them.
    Reference = @(
        '.github/instructions/pester-supporting-docs'
        'PSScriptAnalyzerSettings.psd1'
    )
}
