#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    # These tests write through the real PSFramework module. Its assembly is not signed, so an
    # application control policy such as Windows Smart App Control refuses to load it. The tests
    # are skipped where that happens, and those of the script also where PowerShell is older than
    # the 7.6 that the script requires.
    $frameworkLoads = $true
    try {
        $importParameters = @{
            Name = 'PSFramework'
            MinimumVersion = '1.15.479'
            ErrorAction = 'Stop'
            WarningAction = 'SilentlyContinue'
        }
        Import-Module @importParameters
    } catch {
        $frameworkLoads = $false
    }
    $canRun = $frameworkLoads -and $PSVersionTable.PSVersion -ge [version]'7.6'
}

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-FolderSizeReport.ps1'

    # Returns the lines of the one log file in a folder, without empty lines.
    $readLogLine = {
        param([string]$Folder)
        $logFiles = @(Get-ChildItem -LiteralPath $Folder -Filter 'FolderSizeReport-*.jsonl' -File)
        if ($logFiles.Count -ne 1) {
            throw "Expected one log file in '$Folder' and found $($logFiles.Count)."
        }
        Get-Content -LiteralPath $logFiles[0].FullName | Where-Object { $_.Trim() }
    }
}

Describe 'Get-FolderSize with the PSFramework module' -Tag 'Integration' -Skip:(-not $frameworkLoads) {
    BeforeAll {
        # A message written here would otherwise go to PSFramework's own log, in the profile of the
        # account that runs the tests.
        Set-PSFLoggingProvider -Name filesystem -Enabled $false -Wait

        . (Join-Path -Path $PSScriptRoot -ChildPath 'Get-FolderSize.ps1')

        $reportFolder = Join-Path -Path $TestDrive -ChildPath 'reports'
        $missingFolder = Join-Path -Path $TestDrive -ChildPath 'absent'
        $null = New-Item -Path $reportFolder -ItemType Directory
        $firstFile = Join-Path -Path $reportFolder -ChildPath 'first.txt'
        Set-Content -LiteralPath $firstFile -Value 'abc' -NoNewline -Encoding ascii
    }

    It 'Gives the caller nothing for a failure under -ErrorAction SilentlyContinue' {
        $output = @(Get-FolderSize -LiteralPath $missingFolder -ErrorAction SilentlyContinue *>&1)

        $output.Count | Should-Be 0
    }

    It 'Gives the caller one error and no warning for a failure' {
        $output = @(Get-FolderSize -LiteralPath $missingFolder -ErrorAction Continue *>&1)

        $output | Should-BeCollection -Count 1
        $output[0] | Should-HaveType ([System.Management.Automation.ErrorRecord])
    }

    It 'Shows a verbose message when the caller passes -Verbose' {
        $output = @(Get-FolderSize -LiteralPath $reportFolder -Verbose 4>&1)
        $messages = @($output | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })

        $messages | Should-BeCollection -Count 1
        $messages[0].Message | Should-BeLikeString "*Measuring '*'."
    }
}

Describe 'Invoke-FolderSizeReport.ps1' -Tag 'Integration' -Skip:(-not $canRun) {
    BeforeAll {
        # A message written before the script has run would otherwise go to PSFramework's own log,
        # in the profile of the account that runs the tests.
        Set-PSFLoggingProvider -Name filesystem -Enabled $false -Wait

        $reportFolder = Join-Path -Path $TestDrive -ChildPath 'reports'
        $emptyFolder = Join-Path -Path $TestDrive -ChildPath 'empty'
        $missingFolder = Join-Path -Path $TestDrive -ChildPath 'absent'
        $null = New-Item -Path $reportFolder, $emptyFolder -ItemType Directory
        $firstFile = Join-Path -Path $reportFolder -ChildPath 'first.txt'
        Set-Content -LiteralPath $firstFile -Value 'abc' -NoNewline -Encoding ascii
    }

    Context 'When every folder can be measured' {
        BeforeAll {
            $logFolder = Join-Path -Path $TestDrive -ChildPath 'logs'
            $result = @(& $scriptPath -LiteralPath $reportFolder, $emptyFolder -LogDirectory $logFolder 3>$null)
            $lines = @(& $readLogLine -Folder $logFolder)
            $rows = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
        }

        It 'Returns one object for each folder' {
            $result | Should-BeCollection -Count 2
            $result[0] | Should-HaveType 'Example.FolderSize'
            $result[0].FileCount | Should-Be 1
        }

        It 'Names the log file after the script and the day' {
            $logFiles = @(Get-ChildItem -LiteralPath $logFolder -File)

            $logFiles | Should-BeCollection -Count 1
            $logFiles[0].Name | Should-MatchString '^FolderSizeReport-\d{4}-\d{2}-\d{2}\.jsonl$'
        }

        It 'Writes every message as one line that is a JSON object' {
            $lines | Should-BeCollection -Count 4
            $rows | Should-BeCollection -Count 4
        }

        It 'Writes only the chosen columns, without the computer name and the user name' {
            $names = $rows[0].PSObject.Properties.Name -join ','

            $names | Should-Be 'Timestamp,Level,ModuleName,FunctionName,Message,Tags,TargetObject'
        }

        It 'Writes the timestamp in UTC' {
            $lines | Should-All { $_ -match '"Timestamp":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z"' }
        }

        It 'Writes the level as a word and names the function that wrote the message' {
            $warnings = @($rows | Where-Object { $_.Level -eq 'Warning' })
            $verbose = @($rows | Where-Object { $_.Level -eq 'Verbose' })

            $warnings | Should-BeCollection -Count 1
            $warnings[0].FunctionName | Should-Be 'Get-FolderSize'
            $warnings[0].TargetObject | Should-Be $emptyFolder
            $verbose | Should-BeCollection -Count 3
        }

        It 'Names the script as the writer of its own message' {
            $own = @($rows | Where-Object { $_.Message -eq 'Measuring 2 folder(s).' })

            $own | Should-BeCollection -Count 1
            $own[0].FunctionName | Should-Be 'Invoke-FolderSizeReport.ps1'
            $own[0].Tags | Should-Be 'start'
        }

        It 'Turns its log file off when it ends' {
            Write-PSFMessage -Level Verbose -Message 'Written after the script ended.'
            Wait-PSFMessage

            $text = (& $readLogLine -Folder $logFolder) -join "`n"

            $text.Contains('Written after the script ended.') | Should-BeFalse
        }
    }

    Context 'When a folder cannot be measured' {
        BeforeAll {
            $failedLogFolder = Join-Path -Path $TestDrive -ChildPath 'failed-logs'
            $thrown = $null
            try {
                $null = & $scriptPath -LiteralPath $missingFolder, $reportFolder -LogDirectory $failedLogFolder
            } catch {
                # The test asserts the error, so it is kept here and not passed on.
                $thrown = $_
            }
            $failedRows = @(& $readLogLine -Folder $failedLogFolder | ForEach-Object { $_ | ConvertFrom-Json })
        }

        It 'Stops with the error of that folder' {
            $thrown | Should-NotBeNull
            $thrown.Exception | Should-HaveType ([System.Management.Automation.ItemNotFoundException])
        }

        It 'Has the failure in the log file, with the level Error and the folder as the target' {
            $failures = @($failedRows | Where-Object { $_.Level -eq 'Error' })

            $failures | Should-BeCollection -Count 1
            $failures[0].TargetObject | Should-Be $missingFolder
            $failures[0].Message | Should-BeLikeString "Could not measure '*'. | *"
            $failures[0].Tags | Should-Be 'measure,failure'
        }

        It 'Does not measure the folder after the one that failed' {
            $later = @($failedRows | Where-Object { $_.TargetObject -eq $reportFolder })

            $later.Count | Should-Be 0
        }
    }

    Context 'When the script runs in its own process' {
        It 'Has every message in the file after the process has ended' {
            $processLogFolder = Join-Path -Path $TestDrive -ChildPath 'process-logs'
            $shellPath = (Get-Process -Id $PID).Path
            $arguments = @(
                '-NoProfile', '-File', $scriptPath,
                '-LiteralPath', $reportFolder, '-LogDirectory', $processLogFolder
            )

            $null = & $shellPath @arguments
            $exitCode = $LASTEXITCODE
            $processRows = @(& $readLogLine -Folder $processLogFolder)

            $exitCode | Should-Be 0
            $processRows | Should-BeCollection -Count 2
        }
    }
}

Describe 'The logging examples in CI' -Tag 'Integration' {
    It 'Have PSFramework available, so that they are not skipped' -Skip:($env:GITHUB_ACTIONS -ne 'true') {
        @(Get-Module -Name PSFramework -ListAvailable) | Should-NotBeNull
    }
}
