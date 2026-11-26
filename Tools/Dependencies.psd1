# The versions that this repository pins, and the text that holds each pin. Find-DependencyUpdate.ps1
# compares them with the latest releases, and a test checks that every file still holds the text of
# its pin, with {0} replaced by the version. Move a pin here and in each file in the same change.
#
# GitHub Actions in .github/workflows are left to Dependabot. The actions that the templates pin
# are listed here, because Dependabot reads only .github/workflows.
@{
    Dependencies = @(
        @{
            Name = 'Pester'
            Source = 'PSGallery'
            Version = '6.2.0'
            PinnedIn = @{
                '.github/workflows/quality-gates-pr.yml' = 'Install-PSResource -Name Pester -Version {0}'
                'standards/rules/powershell-version.md' = '| Pester | {0} |'
            }
        }
        @{
            Name = 'PSScriptAnalyzer'
            Source = 'PSGallery'
            Version = '1.25.0'
            PinnedIn = @{
                '.github/workflows/quality-gates-pr.yml' = 'Install-PSResource -Name PSScriptAnalyzer -Version {0}'
                'standards/rules/powershell-version.md' = '| PSScriptAnalyzer | {0} |'
            }
        }
        @{
            Name = 'Microsoft.PowerShell.PlatyPS'
            Source = 'PSGallery'
            Version = '1.0.3'
            PinnedIn = @{
                'standards/rules/powershell-version.md' = '| Microsoft.PowerShell.PlatyPS | {0} |'
            }
        }
        @{
            Name = 'PSFramework'
            Source = 'PSGallery'
            Version = '1.15.479'
            PinnedIn = @{
                '.github/workflows/quality-gates-pr.yml' = 'Install-PSResource -Name PSFramework -Version {0}'
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
    )
}
