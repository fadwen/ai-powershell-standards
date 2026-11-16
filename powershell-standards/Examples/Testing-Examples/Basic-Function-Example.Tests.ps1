#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    $examplesRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path -Path $examplesRoot -ChildPath 'Basic-Function-Example.ps1')
}

Describe 'Get-BasicServerInfo' -Tag 'Unit' {
    BeforeAll {
        # The CIM commands reach the network and the clock decides the uptime, so every test replaces
        # them. The stand-in session is not a CimSession. The two commands that receive it are
        # therefore mocked with -RemoveParameterType, because parameter binding would otherwise
        # reject the stand-in before the mock ran.
        Mock -CommandName Get-Date -MockWith { [datetime]'2026-03-06T12:00:00' }

        Mock -CommandName New-CimSession -MockWith {
            [PSCustomObject]@{ ComputerName = $ComputerName }
        }

        Mock -CommandName Remove-CimSession -RemoveParameterType CimSession -MockWith { }

        Mock -CommandName Get-CimInstance -RemoveParameterType CimSession -MockWith {
            switch ($ClassName) {
                'Win32_OperatingSystem' {
                    [PSCustomObject]@{
                        Caption = 'Microsoft Windows Server 2022 Standard'
                        Version = '10.0.20348'
                        OSArchitecture = '64-bit'
                        LastBootUpTime = [datetime]'2026-03-01T00:00:00'
                    }
                }
                'Win32_ComputerSystem' {
                    [PSCustomObject]@{
                        Manufacturer = 'Contoso'
                        Model = 'Rack Server 1'
                        Domain = 'contoso.com'
                        TotalPhysicalMemory = 16GB
                        NumberOfLogicalProcessors = 8
                    }
                }
                'Win32_Service' {
                    [PSCustomObject]@{ Name = 'Spooler'; DisplayName = 'Print Spooler'; StartMode = 'Auto' }
                    [PSCustomObject]@{ Name = 'Themes'; DisplayName = 'Themes'; StartMode = 'Auto' }
                }
                default {
                    throw "The test does not expect a query for the class '$ClassName'."
                }
            }
        }
    }

    Context 'When the computers answer' {
        It 'Returns one object with the values read from the computer' {
            $result = @(Get-BasicServerInfo -ComputerName 'SERVER01')

            $result | Should-BeCollection -Count 1
            $result[0] | Should-HaveType 'Example.ServerInfo'
            $result[0].ComputerName | Should-Be 'SERVER01'
            $result[0].OperatingSystem | Should-Be 'Microsoft Windows Server 2022 Standard'
            $result[0].Version | Should-Be '10.0.20348'
            $result[0].Architecture | Should-Be '64-bit'
            $result[0].Manufacturer | Should-Be 'Contoso'
            $result[0].Model | Should-Be 'Rack Server 1'
            $result[0].Domain | Should-Be 'contoso.com'
            $result[0].TotalMemoryGB | Should-Be 16
            $result[0].LogicalProcessors | Should-Be 8
        }

        It 'Calculates the uptime from the last boot time' {
            $result = Get-BasicServerInfo -ComputerName 'SERVER01'

            $result.LastBootTime | Should-Be ([datetime]'2026-03-01T00:00:00')
            $result.UptimeDays | Should-Be 5.5
        }

        It 'Accepts the computer name <ValidName>' -ForEach @(
            @{ ValidName = 'SERVER01' }
            @{ ValidName = 'web01.contoso.com' }
            @{ ValidName = 'DB-SERVER-01' }
        ) {
            $result = Get-BasicServerInfo -ComputerName $ValidName

            $result.ComputerName | Should-Be $ValidName
        }

        It 'Emits one object for each computer name received from the pipeline, in order' {
            $result = @('WEB01', 'WEB02' | Get-BasicServerInfo)

            $result | Should-BeCollection -Count 2
            $result[0].ComputerName | Should-Be 'WEB01'
            $result[1].ComputerName | Should-Be 'WEB02'
        }

        It 'Reads the computer name from the ComputerName property of a pipeline object' {
            $server = [PSCustomObject]@{ ComputerName = 'APP01' }

            $result = @($server | Get-BasicServerInfo)

            $result | Should-BeCollection -Count 1
            $result[0].ComputerName | Should-Be 'APP01'
        }

        It 'Closes the session of every computer' {
            $null = Get-BasicServerInfo -ComputerName 'WEB01', 'WEB02'

            Should-Invoke -CommandName New-CimSession -Times 2 -Exactly
            Should-Invoke -CommandName Remove-CimSession -Times 2 -Exactly
        }
    }

    Context 'When the running services are requested' {
        It 'Leaves RunningServices empty and does not query the services by default' {
            $result = Get-BasicServerInfo -ComputerName 'SERVER01'

            $result | Should-HaveType 'Example.ServerInfo'
            $result.RunningServices | Should-BeCollection -Count 0
            Should-Invoke -CommandName Get-CimInstance -Times 0 -Exactly -ParameterFilter {
                $ClassName -eq 'Win32_Service'
            }
        }

        It 'Adds the running services, in the order the computer returned them' {
            $result = Get-BasicServerInfo -ComputerName 'SERVER01' -IncludeServices

            $result.RunningServices | Should-BeCollection -Count 2
            $result.RunningServices[0].Name | Should-Be 'Spooler'
            $result.RunningServices[0].DisplayName | Should-Be 'Print Spooler'
            $result.RunningServices[1].Name | Should-Be 'Themes'
        }

        It 'Asks the computer for running services only' {
            $null = Get-BasicServerInfo -ComputerName 'SERVER01' -IncludeServices

            Should-Invoke -CommandName Get-CimInstance -Times 1 -Exactly -ParameterFilter {
                $ClassName -eq 'Win32_Service' -and $Filter -eq 'State = "Running"'
            }
        }
    }

    Context 'When a credential is supplied' {
        It 'Opens the session with that credential' {
            # An empty SecureString keeps a password out of the test file.
            $operatorCredential = [System.Management.Automation.PSCredential]::new(
                'CONTOSO\operator', [System.Security.SecureString]::new())

            $null = Get-BasicServerInfo -ComputerName 'SERVER01' -Credential $operatorCredential

            Should-Invoke -CommandName New-CimSession -Times 1 -Exactly -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Credential') -and
                $Credential.UserName -eq 'CONTOSO\operator'
            }
        }

        It 'Opens the session as the current user when no credential is supplied' {
            $null = Get-BasicServerInfo -ComputerName 'SERVER01'

            Should-Invoke -CommandName New-CimSession -Times 1 -Exactly -ParameterFilter {
                -not $PesterBoundParameters.ContainsKey('Credential')
            }
        }
    }

    Context 'When a computer name is not valid' {
        It 'Rejects a name that <Reason>' -ForEach @(
            @{ InvalidName = 'SERVER_01'; Reason = 'contains an underscore' }
            @{ InvalidName = 'SERVER 01'; Reason = 'contains a space' }
            @{ InvalidName = '-SERVER01'; Reason = 'starts with a hyphen' }
            @{ InvalidName = ''; Reason = 'is empty' }
        ) {
            { Get-BasicServerInfo -ComputerName $InvalidName } |
                Should-Throw -FullyQualifiedErrorId 'ParameterArgumentValidationError,Get-BasicServerInfo'

            Should-Invoke -CommandName New-CimSession -Times 0 -Exactly
        }
    }

    Context 'When a computer cannot be reached' {
        BeforeAll {
            Mock -CommandName New-CimSession -ParameterFilter { $ComputerName -contains 'OFFLINE01' } -MockWith {
                throw 'The WinRM client cannot complete the operation.'
            }
        }

        It 'Writes one non-terminating error and still returns the computers that answer' {
            $output = Get-BasicServerInfo -ComputerName 'OFFLINE01', 'SERVER01' -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $values = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].FullyQualifiedErrorId | Should-BeLikeString 'ServerInfoQueryFailed*'
            $errors[0].TargetObject | Should-Be 'OFFLINE01'
            $values | Should-BeCollection -Count 1
            $values[0].ComputerName | Should-Be 'SERVER01'
        }

        It 'Keeps the original failure as the inner exception' {
            $output = Get-BasicServerInfo -ComputerName 'OFFLINE01' -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].Exception | Should-HaveType ([System.InvalidOperationException])
            $errors[0].Exception.InnerException.Message |
                Should-Be 'The WinRM client cannot complete the operation.'
        }

        It 'Does not close a session that never opened' {
            $null = Get-BasicServerInfo -ComputerName 'OFFLINE01' -ErrorAction Continue 2>&1

            Should-Invoke -CommandName Remove-CimSession -Times 0 -Exactly
        }

        It 'Stops at the failed computer when the caller passes -ErrorAction Stop' {
            { Get-BasicServerInfo -ComputerName 'OFFLINE01', 'SERVER01' -ErrorAction Stop } |
                Should-Throw -FullyQualifiedErrorId 'ServerInfoQueryFailed,Get-BasicServerInfo'

            Should-Invoke -CommandName New-CimSession -Times 1 -Exactly
        }
    }

    Context 'When a query fails after the session opened' {
        BeforeAll {
            Mock -CommandName Get-CimInstance -RemoveParameterType CimSession -ParameterFilter {
                $ClassName -eq 'Win32_ComputerSystem'
            } -MockWith {
                throw 'Access is denied.'
            }
        }

        It 'Reports the failure, returns nothing for that computer, and closes the session' {
            $output = @(Get-BasicServerInfo -ComputerName 'SERVER01' -ErrorAction Continue 2>&1)

            $output | Should-BeCollection -Count 1
            $output[0] | Should-HaveType ([System.Management.Automation.ErrorRecord])
            $output[0].FullyQualifiedErrorId | Should-BeLikeString 'ServerInfoQueryFailed*'
            Should-Invoke -CommandName Remove-CimSession -Times 1 -Exactly
        }
    }
}
