# The versions that this repository pins, and the text that holds each pin. Find-DependencyUpdate.ps1
# compares them with the latest releases, and a test checks that every file still holds the text of
# its pin, with {0} replaced by the version and {1} by the commit. Move a pin here and in each file
# in the same change.
#
# PinnedIn names the places that install or require a version: a workflow, a #requires line, an
# install command in a rule, a manifest entry in a skill. Other files name the version as well,
# above all as the version that a statement was measured on, and the test lines of every test file
# require Pester. Those are found by searching for the old version, and a measurement moves only
# once it has been repeated on the new one.
#
# GitHub Actions in .github/workflows are left to Dependabot. The actions that the templates pin,
# and the ones that the examples in the rules name by their major version, are listed here,
# because Dependabot reads only .github/workflows.
@{
    Dependencies = @(
        @{
            Name = 'Pester'
            Source = 'PSGallery'
            Version = '6.2.0'
            PinnedIn = @{
                '.github/workflows/quality-gates-pr.yml' = 'Install-PSResource -Name Pester -Version {0}'
                'standards/rules/powershell-cicd.md' = 'Install-PSResource -Name Pester -Version {0}'
                'standards/rules/powershell-version.md' = '| Pester | {0} |'
                'Tools/Invoke-QualityGate.ps1' = "ModuleName = 'Pester'; ModuleVersion = '{0}'"
            }
        }
        @{
            Name = 'PSScriptAnalyzer'
            Source = 'PSGallery'
            Version = '1.25.0'
            PinnedIn = @{
                '.github/workflows/quality-gates-pr.yml' = 'Install-PSResource -Name PSScriptAnalyzer -Version {0}'
                'standards/rules/powershell-cicd.md' = 'Install-PSResource -Name PSScriptAnalyzer -Version {0}'
                'standards/rules/powershell-version.md' = '| PSScriptAnalyzer | {0} |'
            }
        }
        @{
            Name = 'Microsoft.PowerShell.PlatyPS'
            Source = 'PSGallery'
            Version = '1.0.3'
            PinnedIn = @{
                'standards/rules/powershell-version.md' = '| Microsoft.PowerShell.PlatyPS | {0} |'
                'standards/rules/powershell-platyps.md' = "PlatyPS'; ModuleVersion = '{0}'"
            }
        }
        @{
            Name = 'PSFramework'
            Source = 'PSGallery'
            Version = '1.15.479'
            PinnedIn = @{
                '.github/workflows/quality-gates-pr.yml' = 'Install-PSResource -Name PSFramework -Version {0}'
                'standards/examples/Invoke-FolderSizeReport.ps1' = "'PSFramework'; ModuleVersion = '{0}'"
                'standards/skills/powershell-logging/SKILL.md' = "'PSFramework'; ModuleVersion = '{0}'"
            }
        }
        @{
            Name = 'PowerShell 7.6'
            Source = 'GitHub'
            Repository = 'PowerShell/PowerShell'
            # Only the releases of the LTS line count for this pin.
            Track = '7.6'
            Version = '7.6.10'
            PinnedIn = @{
                'standards/rules/powershell-version.md' = 'PowerShell {0}'
            }
        }
        @{
            Name = 'PowerShell'
            Source = 'GitHub'
            Repository = 'PowerShell/PowerShell'
            Version = '7.7.0'
            PinnedIn = @{
                'standards/rules/powershell-version.md' = 'PowerShell {0}'
            }
        }
        @{
            Name = 'betterleaks'
            Source = 'GitHub'
            Repository = 'betterleaks/betterleaks'
            Version = '1.10.1'
            PinnedIn = @{
                'Tools/Invoke-CredentialScan.ps1' = "Version = '{0}'"
                '.github/workflows/credential-scan.yml' = "SCANNER_VERSION: '{0}'"
            }
        }
        @{
            Name = 'gitleaks'
            Source = 'GitHub'
            Repository = 'gitleaks/gitleaks'
            Version = '8.30.1'
            PinnedIn = @{
                'Tools/Invoke-CredentialScan.ps1' = "Version = '{0}'"
            }
        }
        @{
            Name = 'trufflehog'
            Source = 'GitHub'
            Repository = 'trufflesecurity/trufflehog'
            Version = '3.99.9'
            PinnedIn = @{
                'Tools/Invoke-CredentialScan.ps1' = "Version = '{0}'"
                '.github/workflows/credential-scan-monthly.yml' = "SCANNER_VERSION: '{0}'"
            }
        }
        @{
            Name = 'actions/checkout'
            Source = 'GitHub'
            Repository = 'actions/checkout'
            Version = '7.0.1'
            PinnedIn = @{
                'Templates/Workflows/credential-scan.yml' = 'actions/checkout@{1} # v{0}'
                'Templates/Workflows/sync-copilot-standards.yml' = 'actions/checkout@{1} # v{0}'
            }
            Commit = '3d3c42e5aac5ba805825da76410c181273ba90b1'
        }
        @{
            Name = 'peter-evans/create-pull-request'
            Source = 'GitHub'
            Repository = 'peter-evans/create-pull-request'
            Version = '8.1.3'
            PinnedIn = @{
                'Templates/Workflows/sync-copilot-standards.yml' = 'peter-evans/create-pull-request@{1} # v{0}'
            }
            Commit = '3ffccacd46053766916f087ce41d627c0b8cf2d1'
        }
        @{
            Name = 'actions/checkout in the rules'
            Source = 'GitHub'
            Repository = 'actions/checkout'
            Version = '7'
            PinnedIn = @{
                'standards/rules/powershell-cicd.md' = 'actions/checkout@v{0}'
            }
        }
        @{
            Name = 'actions/upload-artifact in the rules'
            Source = 'GitHub'
            Repository = 'actions/upload-artifact'
            Version = '7'
            PinnedIn = @{
                'standards/rules/powershell-cicd.md' = 'actions/upload-artifact@v{0}'
            }
        }
        @{
            Name = 'actions/download-artifact in the rules'
            Source = 'GitHub'
            Repository = 'actions/download-artifact'
            Version = '8'
            PinnedIn = @{
                'standards/rules/powershell-cicd.md' = 'actions/download-artifact@v{0}'
            }
        }
        @{
            Name = 'DavidAnson/markdownlint-cli2-action in the rules'
            Source = 'GitHub'
            Repository = 'DavidAnson/markdownlint-cli2-action'
            Version = '25'
            PinnedIn = @{
                'standards/rules/powershell-platyps.md' = 'DavidAnson/markdownlint-cli2-action@v{0}'
            }
        }
    )
}
