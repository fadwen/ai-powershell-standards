#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    # The tests replace Write-PSFMessage with a mock, and a mock needs the command to exist, not
    # the module. This stand-in lets them run where PSFramework is not installed or is not allowed
    # to load.
    $realCommand = Get-Command -Name Write-PSFMessage -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    if ($null -eq $realCommand) {
        function Write-PSFMessage {
            <#
            .SYNOPSIS
            Stands in for the PSFramework command of the same name, so that it can be mocked.

            .DESCRIPTION
            Does nothing. It declares the parameters that Get-FolderSize passes, so that a mock of
            it can filter on them.

            .PARAMETER Level
            Level of the message.

            .PARAMETER Message
            Text of the message.

            .PARAMETER Target
            The item that the message is about.

            .PARAMETER Tag
            Tags of the message.

            .PARAMETER ErrorRecord
            The error that the message reports.

            .EXAMPLE
            Write-PSFMessage -Level Verbose -Message 'Measuring.'

            Does nothing.

            .INPUTS
            None.

            .OUTPUTS
            None.
            #>
            [CmdletBinding()]
            param(
                [string]$Level,

                [string]$Message,

                [object]$Target,

                [string[]]$Tag,

                [System.Management.Automation.ErrorRecord[]]$ErrorRecord
            )
        }
    }

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Get-FolderSize.ps1')
}

Describe 'Get-FolderSize' -Tag 'Unit', 'Public' {
    BeforeAll {
        Mock -CommandName Write-PSFMessage

        $reportFolder = Join-Path -Path $TestDrive -ChildPath 'reports'
        $emptyFolder = Join-Path -Path $TestDrive -ChildPath 'empty'
        $missingFolder = Join-Path -Path $TestDrive -ChildPath 'absent'
        $null = New-Item -Path $reportFolder, $emptyFolder -ItemType Directory
        $firstFile = Join-Path -Path $reportFolder -ChildPath 'first.txt'
        $secondFile = Join-Path -Path $reportFolder -ChildPath 'second.txt'
        Set-Content -LiteralPath $firstFile -Value 'abc' -NoNewline -Encoding ascii
        Set-Content -LiteralPath $secondFile -Value 'defgh' -NoNewline -Encoding ascii
    }

    Context 'Parameter Validation' {
        It 'Declares LiteralPath as a mandatory parameter' {
            Get-Command -Name Get-FolderSize |
                Should-HaveParameter -ParameterName 'LiteralPath' -Type ([string[]]) -Mandatory
        }

        It 'Gives the same result for piped input and for an array argument' {
            $piped = @($reportFolder, $emptyFolder | Get-FolderSize)
            $byParameter = @(Get-FolderSize -LiteralPath $reportFolder, $emptyFolder)

            $piped | Should-BeCollection -Count 2
            $byParameter | Should-BeCollection -Count 2
            $piped[0].TotalBytes | Should-Be $byParameter[0].TotalBytes
            $piped[1].Path | Should-Be $byParameter[1].Path
        }
    }

    Context 'Core Functionality' {
        It 'Returns the file count and the total size of a folder' {
            $result = @(Get-FolderSize -LiteralPath $reportFolder)

            $result | Should-BeCollection -Count 1
            $result[0] | Should-HaveType 'Example.FolderSize'
            $result[0].Path | Should-Be (Convert-Path -LiteralPath $reportFolder)
            $result[0].FileCount | Should-Be 2
            $result[0].TotalBytes | Should-Be 8
        }

        It 'Returns zero for a folder without files' {
            $result = @(Get-FolderSize -LiteralPath $emptyFolder)

            $result | Should-BeCollection -Count 1
            $result[0].FileCount | Should-Be 0
            $result[0].TotalBytes | Should-Be 0
        }
    }

    Context 'Logging' {
        It 'Writes one verbose message for a folder, with the folder as the target' {
            $null = Get-FolderSize -LiteralPath $reportFolder

            Should-Invoke -CommandName Write-PSFMessage -Times 1 -Exactly
            Should-Invoke -CommandName Write-PSFMessage -Times 1 -Exactly -ParameterFilter {
                $Level -eq 'Verbose' -and $Target -eq $reportFolder -and $Tag -contains 'measure'
            }
        }

        It 'Writes a warning message for a folder without files' {
            $null = Get-FolderSize -LiteralPath $emptyFolder

            Should-Invoke -CommandName Write-PSFMessage -Times 1 -Exactly -ParameterFilter {
                $Level -eq 'Warning' -and $Message -like '*contains no files*'
            }
        }

        It 'Names the folder in the warning as the caller gave it, not as a resolved path' {
            Push-Location -LiteralPath $TestDrive
            try {
                $null = Get-FolderSize -LiteralPath './empty'
            } finally {
                Pop-Location
            }

            Should-Invoke -CommandName Write-PSFMessage -Times 1 -Exactly -ParameterFilter {
                $Level -eq 'Warning' -and $Message -eq "'./empty' contains no files."
            }
        }

        It 'Uses no level that PSFramework writes straight to the console' {
            $folders = $reportFolder, $emptyFolder, $missingFolder

            $null = Get-FolderSize -LiteralPath $folders -ErrorAction SilentlyContinue

            Should-Invoke -CommandName Write-PSFMessage -Times 0 -Exactly -ParameterFilter {
                $Level -in 'Critical', 'Important', 'Host', 'Output', 'Significant'
            }
        }
    }

    Context 'Error Handling' {
        It 'Logs the failure, writes one non-terminating error, and still measures the next folder' {
            $output = Get-FolderSize -LiteralPath $missingFolder, $reportFolder -ErrorAction Continue 2>&1
            $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $sizes = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })

            $errors | Should-BeCollection -Count 1
            $errors[0].Exception | Should-HaveType ([System.Management.Automation.ItemNotFoundException])
            $sizes | Should-BeCollection -Count 1
            $sizes[0].FileCount | Should-Be 2
            Should-Invoke -CommandName Write-PSFMessage -Times 1 -Exactly -ParameterFilter {
                $Level -eq 'Error' -and $Target -eq $missingFolder -and $null -ne $ErrorRecord
            }
        }
    }

    Context 'Performance Requirements' {
        It 'Measures 50 folders in less than five seconds' {
            $folders = @($reportFolder) * 50

            { Get-FolderSize -LiteralPath $folders } | Should-BeFasterThan '5s'
        }
    }
}
