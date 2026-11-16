#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ModuleName.psd1')
    }
}

Describe 'Get-TemplateFunction' -Tag 'Unit' {
    BeforeAll {
        # The settings file is the boundary, so the command that reads it is replaced. The mock names
        # the module because the call is made inside the module.
        Mock -CommandName Import-PowerShellDataFile -ModuleName ModuleName -MockWith {
            @{
                Environments = @{
                    Development = @{ LogLevel = 'Verbose'; TimeoutSeconds = 30; RetryCount = 3 }
                    Production = @{ LogLevel = 'Warning'; TimeoutSeconds = 10; RetryCount = 1 }
                }
            }
        }
    }

    Context 'When the settings define the environment' {
        It 'Returns the settings of <EnvironmentName>' -ForEach @(
            @{ EnvironmentName = 'Development'; LogLevel = 'Verbose'; TimeoutSeconds = 30; RetryCount = 3 }
            @{ EnvironmentName = 'Production'; LogLevel = 'Warning'; TimeoutSeconds = 10; RetryCount = 1 }
        ) {
            $result = Get-TemplateFunction -Name $EnvironmentName

            $result | Should-HaveType 'ModuleName.EnvironmentSetting'
            $result.Name | Should-Be $EnvironmentName
            $result.LogLevel | Should-Be $LogLevel
            $result.TimeoutSeconds | Should-Be $TimeoutSeconds
            $result.RetryCount | Should-Be $RetryCount
        }

        It 'Emits one object for each name received from the pipeline, in order' {
            $result = @('Production', 'Development' | Get-TemplateFunction)

            $result | Should-BeCollection -Count 2
            $result[0].Name | Should-Be 'Production'
            $result[1].Name | Should-Be 'Development'
        }

        It 'Reads the settings file once for any number of names' {
            $null = 'Production', 'Development' | Get-TemplateFunction

            Should-Invoke -CommandName Import-PowerShellDataFile -ModuleName ModuleName -Times 1 -Exactly
        }
    }

    Context 'When the settings do not define the environment' {
        It 'Writes one non-terminating error and still returns the environments that exist' {
            $output = Get-TemplateFunction -Name 'Staging', 'Production' -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $values = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].FullyQualifiedErrorId | Should-BeLikeString 'EnvironmentNotFound*'
            $errors[0].TargetObject | Should-Be 'Staging'
            $values | Should-BeCollection -Count 1
            $values[0].Name | Should-Be 'Production'
        }
    }

    Context 'When the settings file cannot be used' {
        It 'Throws the error that reading the file raised' {
            Mock -CommandName Import-PowerShellDataFile -ModuleName ModuleName -MockWith {
                throw [System.IO.FileNotFoundException]::new('The settings file was not found.')
            }

            { Get-TemplateFunction -Name 'Production' } |
                Should-Throw -ExceptionType ([System.IO.FileNotFoundException])
        }

        It 'Throws when the file has no Environments table' {
            Mock -CommandName Import-PowerShellDataFile -ModuleName ModuleName -MockWith {
                @{ Unrelated = 'value' }
            }

            { Get-TemplateFunction -Name 'Production' } |
                Should-Throw -FullyQualifiedErrorId 'EnvironmentsNotDefined,Get-TemplateFunction'
        }
    }
}
