#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Get-ConfigValue.ps1')
}

Describe 'Get-ConfigValue' -Tag 'Unit' {
    BeforeAll {
        $configPath = Join-Path -Path $TestDrive -ChildPath 'settings.json'
        $json = '{ "Region": "westeurope", "Tier": "standard" }'
        Set-Content -LiteralPath $configPath -Value $json -Encoding ascii
    }

    Context 'When the requested values exist' {
        It 'Returns <ValueName> with the value <Expected>' -ForEach @(
            @{ ValueName = 'Region'; Expected = 'westeurope' }
            @{ ValueName = 'Tier'; Expected = 'standard' }
        ) {
            $result = Get-ConfigValue -Path $configPath -Name $ValueName

            $result | Should-HaveType 'Example.ConfigValue'
            $result.Name | Should-Be $ValueName
            $result.Value | Should-Be $Expected
        }

        It 'Emits one object for each name received from the pipeline, in order' {
            $result = @('Tier', 'Region' | Get-ConfigValue -Path $configPath)

            $result | Should-BeCollection -Count 2
            $result[0].Name | Should-Be 'Tier'
            $result[1].Name | Should-Be 'Region'
        }
    }

    Context 'When a requested value is missing' {
        It 'Writes one non-terminating error and still returns the values that exist' {
            $output = Get-ConfigValue -Path $configPath -Name 'Missing', 'Region' -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $values = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].FullyQualifiedErrorId | Should-BeLikeString 'ConfigValueNotFound*'
            $values | Should-BeCollection -Count 1
            $values[0].Name | Should-Be 'Region'
        }
    }

    Context 'When the file cannot be used' {
        It 'Throws when the file does not exist' {
            $missingPath = Join-Path -Path $TestDrive -ChildPath 'absent.json'

            { Get-ConfigValue -Path $missingPath -Name 'Region' } |
                Should-Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
        }

        It 'Throws when the file does not contain a JSON object' {
            $arrayPath = Join-Path -Path $TestDrive -ChildPath 'array.json'
            Set-Content -LiteralPath $arrayPath -Value '[1, 2]' -Encoding ascii

            { Get-ConfigValue -Path $arrayPath -Name 'Region' } |
                Should-Throw -ExceptionType ([System.IO.InvalidDataException])
        }
    }
}
