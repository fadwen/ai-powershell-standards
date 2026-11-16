#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ModuleName.psd1')
    }
}

# Import-TemplateSetting is private, so the tests reach it with InModuleScope.

Describe 'Import-TemplateSetting' -Tag 'Integration' {
    It 'Returns the content of the settings file that ships with the module' {
        InModuleScope ModuleName {
            $settings = Import-TemplateSetting

            $settings | Should-HaveType ([hashtable])
            $settings['Environments'] | Should-HaveType ([hashtable])
            $settings['Environments'].ContainsKey('Production') | Should-BeTrue
        }
    }

    It 'Reads the file from the Configuration folder of the module' {
        $configurationFolder = Join-Path -Path $moduleRoot -ChildPath 'Configuration'
        $expectedPath = Join-Path -Path $configurationFolder -ChildPath 'DefaultConfiguration.psd1'

        InModuleScope ModuleName -Parameters @{ ExpectedPath = $expectedPath } {
            Mock -CommandName Import-PowerShellDataFile -MockWith { @{} }

            $null = Import-TemplateSetting

            Should-Invoke -CommandName Import-PowerShellDataFile -Times 1 -Exactly -ParameterFilter {
                $LiteralPath -eq $ExpectedPath
            }
        }
    }

    It 'Throws the error that reading the file raised' {
        InModuleScope ModuleName {
            Mock -CommandName Import-PowerShellDataFile -MockWith {
                throw [System.IO.FileNotFoundException]::new('The settings file was not found.')
            }

            { Import-TemplateSetting } | Should-Throw -ExceptionType ([System.IO.FileNotFoundException])
        }
    }
}
