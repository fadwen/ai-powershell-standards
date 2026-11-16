#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    # This file holds the module's contract tests, so it is the one file that imports with -Force:
    # it asserts what a newly imported module looks like. No file removes the module afterwards.
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ModuleExample.psd1') -Force
}

Describe 'ModuleExample' -Tag 'Unit' {
    Context 'The export list' {
        It 'Exports Get-ExampleData and nothing else' {
            $commands = @(Get-Command -Module ModuleExample)

            $commands | Should-BeCollection -Count 1
            $commands[0].Name | Should-Be 'Get-ExampleData'
        }

        It 'Keeps <CommandName> private' -ForEach @(
            @{ CommandName = 'Connect-ExampleService' }
            @{ CommandName = 'Get-ExampleServiceStatus' }
        ) {
            $module = Get-Module -Name ModuleExample

            $module.ExportedCommands.ContainsKey($CommandName) | Should-BeFalse
            InModuleScope ModuleExample -Parameters @{ CommandName = $CommandName } {
                (Get-Command -Name $CommandName).CommandType | Should-Be 'Function'
            }
        }

        It 'Declares ExampleServiceResult as the output type of Get-ExampleData' {
            $outputTypes = @((Get-Command -Name Get-ExampleData).OutputType)

            $outputTypes | Should-BeCollection -Count 1
            $outputTypes[0].Name | Should-Be 'ExampleServiceResult'
        }
    }

    Context 'The root module' {
        It 'Fails the import when a function file does not load' {
            $brokenRoot = Join-Path -Path $TestDrive -ChildPath 'BrokenModule'
            $publicPath = Join-Path -Path $brokenRoot -ChildPath 'Public'
            $null = New-Item -Path $publicPath -ItemType Directory -Force
            $sourcePath = Join-Path -Path $moduleRoot -ChildPath 'ModuleExample.psm1'
            $rootModulePath = Join-Path -Path $brokenRoot -ChildPath 'BrokenModule.psm1'
            Copy-Item -LiteralPath $sourcePath -Destination $rootModulePath
            $brokenFilePath = Join-Path -Path $publicPath -ChildPath 'Get-Broken.ps1'
            Set-Content -LiteralPath $brokenFilePath -Value 'function Get-Broken {' -Encoding ascii
            $expectedErrorId = 'MissingEndCurlyBrace,Microsoft.PowerShell.Commands.ImportModuleCommand'

            { Import-Module -Name $rootModulePath -Force } |
                Should-Throw -FullyQualifiedErrorId $expectedErrorId
            Get-Module -Name BrokenModule | Should-BeNull
        }
    }
}

Describe 'Get-ExampleData' -Tag 'Unit' {
    Context 'When the services exist' {
        It 'Returns the status <Expected> for <ServiceName>' -ForEach @(
            @{ ServiceName = 'Billing'; Expected = 'Healthy' }
            @{ ServiceName = 'Identity'; Expected = 'Degraded' }
            @{ ServiceName = 'Reporting'; Expected = 'Unavailable' }
        ) {
            $result = Get-ExampleData -ServiceName $ServiceName

            $result | Should-HaveType 'ExampleServiceResult'
            $result.ServiceName | Should-Be $ServiceName
            $result.Status | Should-Be $Expected
        }

        It 'Queries the Development environment by default' {
            $result = Get-ExampleData -ServiceName 'Billing'

            $result.Environment | Should-Be 'Development'
        }

        It 'Records the environment <Environment> on the result' -ForEach @(
            @{ Environment = 'Test' }
            @{ Environment = 'Production' }
        ) {
            $result = Get-ExampleData -ServiceName 'Billing' -Environment $Environment

            $result.Environment | Should-Be $Environment
        }

        It 'Emits one result for each name received from the pipeline, in order' {
            $result = @('Reporting', 'Billing', 'Identity' | Get-ExampleData)

            $result | Should-BeCollection -Count 3
            $result[0].ServiceName | Should-Be 'Reporting'
            $result[1].ServiceName | Should-Be 'Billing'
            $result[2].ServiceName | Should-Be 'Identity'
        }

        It 'Emits one result for each name in an array argument, in order' {
            $result = @(Get-ExampleData -ServiceName 'Identity', 'Billing')

            $result | Should-BeCollection -Count 2
            $result[0].ServiceName | Should-Be 'Identity'
            $result[1].ServiceName | Should-Be 'Billing'
        }

        It 'Takes the name from the ServiceName property of a piped object' {
            $result = @([PSCustomObject]@{ ServiceName = 'Identity' } | Get-ExampleData)

            $result | Should-BeCollection -Count 1
            $result[0].ServiceName | Should-Be 'Identity'
        }

        It 'Records the time of the check on the result' {
            $checkedAt = [datetime]::new(2001, 2, 3, 4, 5, 6)
            Mock -CommandName Get-Date -ModuleName ModuleExample -MockWith { $checkedAt }

            $result = Get-ExampleData -ServiceName 'Billing'

            $result.CheckedAt | Should-Be $checkedAt
            Should-Invoke -CommandName Get-Date -ModuleName ModuleExample -Times 1 -Exactly
        }
    }

    Context 'When a service cannot be queried' {
        # A module function reads $ErrorActionPreference from the global scope, which a CI runner
        # sets to Stop. Each call below passes -ErrorAction Continue, so the outcome does not depend
        # on where the tests run.
        It 'Writes one non-terminating error and still returns the other services' {
            $serviceNames = 'Billing', 'Missing', 'Reporting'
            $output = Get-ExampleData -ServiceName $serviceNames -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $results = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].FullyQualifiedErrorId | Should-Be 'ServiceNotFound,Get-ExampleData'
            $errors[0].TargetObject | Should-Be 'Missing'
            $results | Should-BeCollection -Count 2
            $results[0].ServiceName | Should-Be 'Billing'
            $results[1].ServiceName | Should-Be 'Reporting'
        }

        It 'Writes one error for each service when every service fails' {
            $output = 'Missing', 'Absent' | Get-ExampleData -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            $output | Should-BeCollection -Count 2
            $errors | Should-BeCollection -Count 2
            $errors[0].TargetObject | Should-Be 'Missing'
            $errors[1].TargetObject | Should-Be 'Absent'
        }

        It 'Throws when the caller passes -ErrorAction Stop' {
            { Get-ExampleData -ServiceName 'Missing', 'Billing' -ErrorAction Stop } |
                Should-Throw -FullyQualifiedErrorId 'ServiceNotFound,Get-ExampleData'
        }
    }

    Context 'When an argument is not valid' {
        It 'Rejects an environment that is not in the allowed set' {
            { Get-ExampleData -ServiceName 'Billing' -Environment 'Staging' } |
                Should-Throw -FullyQualifiedErrorId 'ParameterArgumentValidationError,Get-ExampleData'
        }

        It 'Rejects an empty service name' {
            $expectedErrorId = 'ParameterArgumentValidationErrorEmptyStringNotAllowed,Get-ExampleData'

            { Get-ExampleData -ServiceName '' } | Should-Throw -FullyQualifiedErrorId $expectedErrorId
        }
    }
}

Describe 'ExampleServiceResult' -Tag 'Unit' {
    It 'Reports the status <Status> as usable: <Expected>' -ForEach @(
        @{ Status = 'Healthy'; Expected = $true }
        @{ Status = 'Degraded'; Expected = $true }
        @{ Status = 'Unavailable'; Expected = $false }
    ) {
        InModuleScope ModuleExample -Parameters @{ Status = $Status; Expected = $Expected } {
            $result = [ExampleServiceResult]::new('Billing', 'Test', $Status)

            $result.IsUsable() | Should-Be $Expected
        }
    }

    It 'Converts to a string that names the service, the environment, and the status' {
        InModuleScope ModuleExample {
            $result = [ExampleServiceResult]::new('Billing', 'Test', 'Healthy')

            $result.ToString() | Should-Be 'Billing [Test]: Healthy'
        }
    }

    It 'Rejects a status that is not in the allowed set' {
        InModuleScope ModuleExample {
            { [ExampleServiceResult]::new('Billing', 'Test', 'Exploded') } |
                Should-Throw -ExceptionType ([System.Management.Automation.SetValueInvocationException])
        }
    }
}

Describe 'Connect-ExampleService' -Tag 'Unit' {
    It 'Returns a session for the <Environment> environment' -ForEach @(
        @{ Environment = 'Development'; Endpoint = 'https://service.example.com/development' }
        @{ Environment = 'Test'; Endpoint = 'https://service.example.com/test' }
        @{ Environment = 'Production'; Endpoint = 'https://service.example.com/production' }
    ) {
        InModuleScope ModuleExample -Parameters @{ Environment = $Environment; Endpoint = $Endpoint } {
            $session = Connect-ExampleService -Environment $Environment

            $session | Should-HaveType ([hashtable])
            $session['Environment'] | Should-Be $Environment
            $session['Endpoint'] | Should-Be $Endpoint
        }
    }

    It 'Rejects an environment that is not in the allowed set' {
        InModuleScope ModuleExample {
            { Connect-ExampleService -Environment 'Staging' } |
                Should-Throw -FullyQualifiedErrorId 'ParameterArgumentValidationError,Connect-ExampleService'
        }
    }
}

Describe 'Get-ExampleServiceStatus' -Tag 'Unit' {
    It 'Returns the status of a service that exists' {
        InModuleScope ModuleExample {
            $session = Connect-ExampleService -Environment 'Test'

            Get-ExampleServiceStatus -ServiceName 'Identity' -Session $session | Should-Be 'Degraded'
        }
    }

    It 'Throws ServiceNotFound for a service that does not exist' {
        InModuleScope ModuleExample {
            $session = Connect-ExampleService -Environment 'Test'

            { Get-ExampleServiceStatus -ServiceName 'Missing' -Session $session } |
                Should-Throw -FullyQualifiedErrorId 'ServiceNotFound,Get-ExampleServiceStatus'
        }
    }
}
