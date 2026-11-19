#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    $helpBlock = @'
    <#
    .SYNOPSIS
    Gets a thing.

    .DESCRIPTION
    Gets a thing.

    .EXAMPLE
    Get-Thing

    Gets a thing.

    .INPUTS
    None.

    .OUTPUTS
    System.String.
    #>
'@

    # Code that breaks exactly the named rule. Each fixture is otherwise written to the standards.
    $violationCases = @(
        @{
            RuleId = 'FUN-01'
            Reason = 'a function has no CmdletBinding attribute'
            FileName = 'Fixture.ps1'
            Code = "function Get-Thing {`n$helpBlock`n    param()`n`n    'thing'`n}"
        }
        @{
            RuleId = 'DOC-01'
            Reason = 'a function has no help'
            FileName = 'Fixture.ps1'
            Code = "function Get-Thing {`n    [CmdletBinding()]`n    param()`n`n    'thing'`n}"
        }
        @{
            RuleId = 'DOC-07'
            Reason = 'help carries a version stamp'
            FileName = 'Fixture.ps1'
            Code = @'
function Get-Thing {
    <#
    .SYNOPSIS
    Gets a thing.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    'thing'
}
'@
        }
        @{
            RuleId = 'FUN-10'
            Reason = 'the output type is PSCustomObject'
            FileName = 'Fixture.ps1'
            Code = @(
                'function Get-Thing {'
                $helpBlock
                '    [CmdletBinding()]'
                '    [OutputType([PSCustomObject])]'
                '    param()'
                ''
                "    'thing'"
                '}'
            ) -join "`n"
        }
        @{
            RuleId = 'ERR-11'
            Reason = 'an advanced function uses throw'
            FileName = 'Fixture.ps1'
            Code = "function Get-Thing {`n$helpBlock`n    [CmdletBinding()]`n    param()`n`n    throw 'failed'`n}"
        }
        @{
            RuleId = 'ERR-11'
            Reason = 'an advanced function uses Write-Error -ErrorAction Stop'
            FileName = 'Fixture.ps1'
            Code = @(
                'function Get-Thing {'
                $helpBlock
                '    [CmdletBinding()]'
                '    param()'
                ''
                "    Write-Error -Message 'failed' -ErrorAction Stop"
                '}'
            ) -join "`n"
        }
        @{
            RuleId = 'ERR-21'
            Reason = 'a catch block reads $Error[0]'
            FileName = 'Fixture.ps1'
            Code = @(
                'try {'
                '    Get-Item -LiteralPath $PSHOME -ErrorAction Stop'
                '} catch {'
                '    Write-Warning $Error[0].Exception.Message'
                '}'
            ) -join "`n"
        }
        @{
            RuleId = 'ERR-02'
            Reason = 'a root module sets $ErrorActionPreference'
            FileName = 'Fixture.psm1'
            Code = "Set-StrictMode -Version Latest`n`$ErrorActionPreference = 'Stop'"
        }
        @{
            RuleId = 'STY-40'
            Reason = 'an array is grown with += in a loop'
            FileName = 'Fixture.ps1'
            Code = "`$items = @()`nforeach (`$number in 1..3) {`n    `$items += `$number`n}`n`$items"
        }
        @{
            RuleId = 'STY-41'
            Reason = 'ArrayList is used'
            FileName = 'Fixture.ps1'
            Code = "`$items = [System.Collections.ArrayList]::new()`n`$items"
        }
        @{
            RuleId = 'VER-05'
            Reason = 'the script requires a version past its end of support'
            FileName = 'Fixture.ps1'
            Code = "#requires -Version 7.4`n`n'text'"
        }
        @{
            RuleId = 'VER-06'
            Reason = 'a Windows PowerShell command is used'
            FileName = 'Fixture.ps1'
            Code = "Get-EventLog -LogName Application -Newest 1"
        }
        @{
            RuleId = 'PLT-01'
            Reason = 'a retired platyPS command is used'
            FileName = 'Fixture.ps1'
            Code = "New-MarkdownHelp -Module Example -OutputFolder ./docs"
        }
        @{
            RuleId = 'SEC-01'
            Reason = 'a literal is assigned to a secret variable'
            FileName = 'Fixture.ps1'
            Code = "`$apiToken = 'abc123def456'`n`$apiToken"
        }
        @{
            RuleId = 'SEC-01'
            Reason = 'a literal is assigned to a secret key in a hashtable'
            FileName = 'Fixture.ps1'
            Code = "`$settings = @{`n    Password = 'hunter22'`n}`n`$settings"
        }
        @{
            RuleId = 'SEC-09'
            Reason = 'a request with a token lets a redirect be followed'
            FileName = 'Fixture.ps1'
            Code = "Invoke-RestMethod -Uri 'https://api.example.com/items' -Authentication Bearer -Token `$token"
        }
        @{
            RuleId = 'SEC-09'
            Reason = 'a request with a credential allows three redirects'
            FileName = 'Fixture.ps1'
            Code = "Invoke-WebRequest -Uri `$uri -Credential `$credential -MaximumRedirection 3"
        }
        @{
            RuleId = 'SEC-09'
            Reason = 'a request with a credential is paged with -FollowRelLink'
            FileName = 'Fixture.ps1'
            Code = "Invoke-RestMethod -Uri 'https://api.example.com' -Credential `$credential -FollowRelLink"
        }
        @{
            RuleId = 'SEC-09'
            Reason = 'the Authorization header is kept on a redirect'
            FileName = 'Fixture.ps1'
            Code = "Invoke-WebRequest -Uri `$uri -Headers `$headers -PreserveAuthorizationOnRedirect"
        }
        @{
            RuleId = 'SEC-09'
            Reason = 'a request with the credential of the current user lets a redirect be followed'
            FileName = 'Fixture.ps1'
            Code = "Invoke-RestMethod -Uri 'https://intranet.example.com/items' -UseDefaultCredentials"
        }
        @{
            RuleId = 'SEC-09'
            Reason = 'the redirect limit of a request with a token is only text inside its address'
            FileName = 'Fixture.ps1'
            Code = "Invoke-RestMethod -Uri 'https://api.example.com/?q=-MaximumRedirection 0' -Token `$token"
        }
        @{
            RuleId = 'SEC-09'
            Reason = 'a request with a token is made through the alias irm'
            FileName = 'Fixture.ps1'
            Code = "irm -Uri 'https://api.example.com/items' -Token `$token"
        }
        @{
            RuleId = 'MOD-03'
            Reason = 'a manifest still has the placeholder GUID'
            FileName = 'Fixture.psd1'
            Code = "@{`n    ModuleVersion = '1.0.0'`n    GUID = '00000000-0000-0000-0000-000000000000'`n}"
        }
        @{
            RuleId = 'STY-14'
            Reason = 'an alias is used'
            FileName = 'Fixture.ps1'
            Code = "gci -LiteralPath `$PSHOME"
        }
        @{
            RuleId = 'STY-20'
            Reason = '$null is on the right of a comparison'
            FileName = 'Fixture.ps1'
            Code = "`$value = Get-Item -LiteralPath `$PSHOME`nif (`$value -eq `$null) {`n    'none'`n}"
        }
        @{
            RuleId = 'STY-23'
            Reason = 'the format operator follows the parentheses of a command argument'
            FileName = 'Fixture.ps1'
            Code = "Write-Output ('{0} items' + ' found') -f 5"
        }
        @{
            RuleId = 'STY-07'
            Reason = 'one blank line separates a function from the code before it'
            FileName = 'Fixture.ps1'
            Code = "`$count = 1`n`nfunction Get-One {`n    1`n}"
        }
        @{
            RuleId = 'STY-07'
            Reason = 'one blank line separates two functions'
            FileName = 'Fixture.ps1'
            Code = "function Get-One {`n    1`n}`n`nfunction Get-Two {`n    2`n}"
        }
        @{
            RuleId = 'STY-07'
            Reason = 'one blank line separates a function from the code after it'
            FileName = 'Fixture.ps1'
            Code = "function Get-One {`n    1`n}`n`nGet-One"
        }
        @{
            RuleId = 'STY-07'
            Reason = 'two blank lines follow each other inside a function'
            FileName = 'Fixture.ps1'
            Code = "function Get-One {`n    `$value = 1`n`n`n    `$value`n}"
        }
    )

    # Code that looks close to a violation and is allowed.
    $allowedCases = @(
        @{
            RuleId = 'ERR-11'
            Reason = 'throw is at the top level of a script'
            FileName = 'Fixture.ps1'
            Code = "[CmdletBinding()]`nparam()`n`nthrow 'failed'"
        }
        @{
            RuleId = 'ERR-11'
            Reason = 'throw is inside a ValidateScript block'
            FileName = 'Fixture.ps1'
            Code = @(
                'function Get-Thing {'
                $helpBlock
                '    [CmdletBinding()]'
                '    param('
                "        [ValidateScript({ if (`$_ -gt 0) { `$true } else { throw 'Must be positive.' } })]"
                '        [int]$Count = 1'
                '    )'
                ''
                '    $Count'
                '}'
            ) -join "`n"
        }
        @{
            RuleId = 'ERR-11'
            Reason = 'throw is inside a class method'
            FileName = 'Fixture.ps1'
            Code = "class Thing {`n    [string] GetName() {`n        throw 'Not implemented.'`n    }`n}"
        }
        @{
            RuleId = 'FUN-01'
            Reason = 'a class method is not a function'
            FileName = 'Fixture.ps1'
            Code = "class Thing {`n    [string] GetName() {`n        return 'thing'`n    }`n}"
        }
        @{
            RuleId = 'STY-40'
            Reason = 'a number is increased with += in a loop'
            FileName = 'Fixture.ps1'
            Code = "`$total = 0`nforeach (`$number in 1..3) {`n    `$total += `$number`n}`n`$total"
        }
        @{
            RuleId = 'VER-05'
            Reason = 'the script requires Windows PowerShell 5.1'
            FileName = 'Fixture.ps1'
            Code = "#requires -Version 5.1`n`n'text'"
        }
        @{
            RuleId = 'VER-05'
            Reason = 'the script requires PowerShell 7.6'
            FileName = 'Fixture.ps1'
            Code = "#requires -Version 7.6`n`n'text'"
        }
        @{
            RuleId = 'SEC-01'
            Reason = 'the variable name only starts with a secret word'
            FileName = 'Fixture.ps1'
            Code = "`$passwordPrompt = 'Enter the password'`n`$passwordPrompt"
        }
        @{
            RuleId = 'SEC-01'
            Reason = 'the secret comes from the environment'
            FileName = 'Fixture.ps1'
            Code = "`$apiToken = `$env:API_TOKEN`n`$apiToken"
        }
        @{
            RuleId = 'SEC-09'
            Reason = 'a request with a token refuses redirects'
            FileName = 'Fixture.ps1'
            Code = "Invoke-RestMethod -Uri 'https://api.example.com' -Token `$token -MaximumRedirection 0"
        }
        @{
            RuleId = 'SEC-09'
            Reason = 'the redirect limit of a request with a token is written with a colon'
            FileName = 'Fixture.ps1'
            Code = "Invoke-RestMethod -Uri 'https://api.example.com' -Token `$token -MaximumRedirection:0"
        }
        @{
            RuleId = 'SEC-09'
            Reason = 'a request with the credential of the current user refuses redirects'
            FileName = 'Fixture.ps1'
            Code = "Invoke-WebRequest -Uri `$uri -UseDefaultCredentials -MaximumRedirection 0"
        }
        @{
            RuleId = 'SEC-09'
            Reason = 'a request without a credential is paged with -FollowRelLink'
            FileName = 'Fixture.ps1'
            Code = "Invoke-RestMethod -Uri 'https://api.example.com/items' -FollowRelLink"
        }
        @{
            RuleId = 'ERR-02'
            Reason = 'a script, not a module, sets $ErrorActionPreference'
            FileName = 'Fixture.ps1'
            Code = "Set-StrictMode -Version Latest`n`$ErrorActionPreference = 'Stop'"
        }
        @{
            RuleId = 'STY-23'
            Reason = 'the format operator is inside the parentheses'
            FileName = 'Fixture.ps1'
            Code = "Write-Output (('{0} items' + ' found') -f 5)"
        }
        @{
            RuleId = 'STY-07'
            Reason = 'two blank lines surround each function'
            FileName = 'Fixture.ps1'
            Code = "`$count = 1`n`n`nfunction Get-One {`n    1`n}`n`n`nfunction Get-Two {`n    2`n}`n`n`n`$count"
        }
        @{
            RuleId = 'STY-07'
            Reason = 'the file holds one function and nothing else'
            FileName = 'Fixture.ps1'
            Code = "function Get-One {`n    `$value = 1`n`n    `$value`n}"
        }
        @{
            RuleId = 'STY-07'
            Reason = 'a comment sits directly above the function, after two blank lines'
            FileName = 'Fixture.ps1'
            Code = "`$count = 1`n`n`n# Gets one.`nfunction Get-One {`n    1`n}"
        }
        @{
            RuleId = 'STY-07'
            Reason = 'the blank lines are inside a here-string'
            FileName = 'Fixture.ps1'
            Code = "function Get-Text {`n    @'`none`n`n`ntwo`n'@`n}"
        }
    )
}

BeforeAll {
    $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $complianceScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools/Test-StandardsCompliance.ps1'

    # Writes code to a new file in its own folder under TestDrive and returns the file's path.
    $newFixtureFile = {
        param([string]$Code, [string]$FileName)
        $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $folder -ItemType Directory
        $filePath = Join-Path -Path $folder -ChildPath $FileName
        [System.IO.File]::WriteAllText($filePath, $Code + "`n", [System.Text.UTF8Encoding]::new($false))
        $filePath
    }

    # A line that breaks VER-06, for tests that only need some finding.
    $eventLogCode = 'Get-EventLog -LogName Application -Newest 1'

    # Returns the code of a function that breaks ERR-11 in its catch block and nothing else. The
    # lines given are written directly above the statement that breaks the rule, and the suffix
    # at the end of that statement's line.
    $newExceptionCode = {
        param([string[]]$LinesAbove = @(), [string]$Suffix = '')
        $before = @(
            'function Get-Thing {'
            '    <#'
            '    .SYNOPSIS'
            '    Gets the thing.'
            ''
            '    .DESCRIPTION'
            '    Gets the thing, and ends the calling script when that fails.'
            ''
            '    .EXAMPLE'
            '    Get-Thing'
            ''
            '    Gets the thing.'
            ''
            '    .INPUTS'
            '    None.'
            ''
            '    .OUTPUTS'
            '    System.IO.DirectoryInfo.'
            '    #>'
            '    [CmdletBinding()]'
            '    [OutputType([System.IO.DirectoryInfo])]'
            '    param()'
            ''
            '    try {'
            '        $item = Get-Item -LiteralPath $PSHOME -ErrorAction Stop'
            '    } catch {'
        )
        $after = @(
            "        Write-Error -ErrorRecord `$_ -ErrorAction Stop$Suffix"
            '    }'
            ''
            '    $item'
            '}'
        )
        @($before + $LinesAbove + $after) -join "`n"
    }
}

Describe 'Test-StandardsCompliance.ps1' -Tag 'Unit' {
    Context 'When code breaks a rule' {
        It 'Reports <RuleId> when <Reason>' -ForEach $violationCases {
            $filePath = & $newFixtureFile -Code $Code -FileName $FileName

            $ruleIds = @(& $complianceScript -Path $filePath -PassThru | ForEach-Object { $_.RuleId })

            $ruleIds -contains $RuleId | Should-BeTrue
        }

        It 'Reports STY-06 when a comment contains a non-ASCII character' {
            $code = "# Range 1$([char]0x2013)5`n'text'"
            $filePath = & $newFixtureFile -Code $code -FileName 'Fixture.ps1'

            $findings = @(& $complianceScript -Path $filePath -PassThru)

            @($findings | Where-Object { $_.RuleId -eq 'STY-06' -and $_.Source -eq 'Standards' }) |
                Should-BeCollection -Count 1
        }

        It 'Gives a finding the file, the line, a message, and its source' {
            $code = "`$first = 1`n`$items = [System.Collections.ArrayList]::new()`n`$first, `$items"
            $filePath = & $newFixtureFile -Code $code -FileName 'Fixture.ps1'

            $finding = @(& $complianceScript -Path $filePath -PassThru | Where-Object { $_.RuleId -eq 'STY-41' })

            $finding | Should-BeCollection -Count 1
            $finding[0] | Should-HaveType 'PowerShellStandards.Finding'
            $finding[0].File | Should-BeString $filePath
            $finding[0].Line | Should-Be 2
            $finding[0].Severity | Should-BeString 'Error'
            $finding[0].Source | Should-BeString 'Standards'
            $finding[0].Message | Should-MatchString 'ArrayList'
        }
    }

    Context 'When code is allowed' {
        It 'Does not report <RuleId> when <Reason>' -ForEach $allowedCases {
            $filePath = & $newFixtureFile -Code $Code -FileName $FileName

            $ruleIds = @(& $complianceScript -Path $filePath -PassThru | ForEach-Object { $_.RuleId })

            $ruleIds -contains $RuleId | Should-BeFalse
        }

        It 'Reports nothing for the function template' {
            $templatePath = Join-Path -Path $repositoryRoot -ChildPath 'standards/examples/Get-ConfigValue.ps1'

            $findings = @(& $complianceScript -Path $templatePath -PassThru)

            $findings.Count | Should-Be 0
        }
    }

    Context 'When a comment records an exception' {
        It 'Reports the finding as a recorded exception with its reason, and does not fail' {
            $comment = '        # Exception to ERR-11: a scheduled script must end here.'
            $code = & $newExceptionCode -LinesAbove $comment
            $filePath = & $newFixtureFile -Code $code -FileName 'Fixture.ps1'

            $findings = @(& $complianceScript -Path $filePath)

            $findings | Should-BeCollection -Count 1
            $findings[0].RuleId | Should-BeString 'ERR-11'
            $findings[0].Severity | Should-BeString 'Information'
            $findings[0].Message | Should-BeLikeString 'Recorded exception: a scheduled script must end here. | *'
        }

        It 'Reads a reason that runs over several comment lines' {
            $comments = @(
                '        # Exception to ERR-11: a scheduled script must end here,'
                '        # which the form of ERR-10 does not do.'
            )
            $code = & $newExceptionCode -LinesAbove $comments
            $filePath = & $newFixtureFile -Code $code -FileName 'Fixture.ps1'

            $findings = @(& $complianceScript -Path $filePath -PassThru)

            $findings | Should-BeCollection -Count 1
            $findings[0].Severity | Should-BeString 'Information'
            $findings[0].Message | Should-BeLikeString '*must end here, which the form of ERR-10 does not do. | *'
        }

        It 'Accepts the comment at the end of the line' {
            $code = & $newExceptionCode -Suffix ' # Exception to ERR-11: a scheduled script must end here.'
            $filePath = & $newFixtureFile -Code $code -FileName 'Fixture.ps1'

            $findings = @(& $complianceScript -Path $filePath -PassThru)

            $findings | Should-BeCollection -Count 1
            $findings[0].Severity | Should-BeString 'Information'
        }

        It 'Keeps the finding and reports DOC-22 when the comment gives no reason' {
            $code = & $newExceptionCode -LinesAbove '        # Exception to ERR-11:'
            $filePath = & $newFixtureFile -Code $code -FileName 'Fixture.ps1'

            $findings = @(& $complianceScript -Path $filePath -PassThru)
            $errors = @($findings | Where-Object { $_.Severity -eq 'Error' } | ForEach-Object { $_.RuleId })

            $errors | Should-BeCollection -Count 2
            $errors -contains 'ERR-11' | Should-BeTrue
            $errors -contains 'DOC-22' | Should-BeTrue
            { & $complianceScript -Path $filePath } | Should-Throw -ExceptionMessage '*finding(s) with severity*'
        }

        It 'Keeps the finding and reports DOC-22 when <Reason>' -ForEach @(
            @{
                Reason = 'a blank line separates the comment from the statement'
                LinesAbove = @('        # Exception to ERR-11: a scheduled script must end here.', '')
            }
            @{
                Reason = 'the comment names another rule that the script checks'
                LinesAbove = @('        # Exception to ERR-21: the reason does not matter here.')
            }
        ) {
            $code = & $newExceptionCode -LinesAbove $LinesAbove
            $filePath = & $newFixtureFile -Code $code -FileName 'Fixture.ps1'

            $findings = @(& $complianceScript -Path $filePath -PassThru)
            $kept = @($findings | Where-Object { $_.RuleId -eq 'ERR-11' })
            $unused = @($findings | Where-Object { $_.RuleId -eq 'DOC-22' })

            $kept | Should-BeCollection -Count 1
            $kept[0].Severity | Should-BeString 'Error'
            $unused | Should-BeCollection -Count 1
            $unused[0].Severity | Should-BeString 'Warning'
            $unused[0].Message | Should-BeLikeString '*excuses nothing*'
        }

        It 'Leaves a comment for a rule that the script cannot check to a reader' {
            $code = "# Exception to FUN-11: the caller needs the whole list at once.`n'text'"
            $filePath = & $newFixtureFile -Code $code -FileName 'Fixture.ps1'

            $findings = @(& $complianceScript -Path $filePath)

            $findings.Count | Should-Be 0
        }

        It 'Does not excuse a finding of PSScriptAnalyzer' {
            $code = "# Exception to VER-06: the report needs the old class.`nGet-WmiObject -Class Win32_Bios"
            $filePath = & $newFixtureFile -Code $code -FileName 'Fixture.ps1'

            $findings = @(& $complianceScript -Path $filePath -PassThru | Where-Object { $_.RuleId -eq 'VER-06' })

            $findings | Should-BeCollection -Count 1
            $findings[0].Source | Should-BeString 'PSScriptAnalyzer'
            $findings[0].Severity | Should-NotBe 'Information'
        }

        It 'Lists every rule that its own checks report as one whose exception it can check' {
            $scriptText = [System.IO.File]::ReadAllText($complianceScript)
            $reported = [regex]::Matches($scriptText, "issues\.Add\(@\('(?<id>[A-Z]{3}-\d{2})'") |
                ForEach-Object { $_.Groups['id'].Value } |
                Where-Object { $_ -ne 'DOC-22' } |
                Sort-Object -Unique
            $listPattern = '(?s)\$rulesThisScriptChecks = @\((?<list>.*?)\r?\n\)'
            $listText = [regex]::Match($scriptText, $listPattern).Groups['list'].Value
            $listed = [regex]::Matches($listText, "'(?<id>[A-Z]{3}-\d{2})'") |
                ForEach-Object { $_.Groups['id'].Value } |
                Sort-Object -Unique

            ($listed -join ',') | Should-BeString ($reported -join ',')
        }
    }

    Context 'Failing and passing' {
        It 'Fails after reporting when a finding is an error' {
            $filePath = & $newFixtureFile -Code $eventLogCode -FileName 'Fixture.ps1'

            { & $complianceScript -Path $filePath } | Should-Throw -ExceptionMessage '*finding(s) with severity*'
        }

        It 'Does not fail when nothing is found' {
            $filePath = & $newFixtureFile -Code "'text'" -FileName 'Fixture.ps1'

            $findings = @(& $complianceScript -Path $filePath)

            $findings.Count | Should-Be 0
        }

        It 'Reports SEC-09 without failing when the redirect limit of a request with a token is a variable' {
            $code = "Invoke-RestMethod -Uri 'https://api.example.com' -Token `$token -MaximumRedirection `$limit"
            $filePath = & $newFixtureFile -Code $code -FileName 'Fixture.ps1'

            $findings = @(& $complianceScript -Path $filePath | Where-Object { $_.RuleId -eq 'SEC-09' })

            $findings | Should-BeCollection -Count 1
            $findings[0].Severity | Should-BeString 'Information'
            $findings[0].Message | Should-MatchString 'not a number'
        }

        It 'Checks every PowerShell file under a folder' {
            $firstPath = & $newFixtureFile -Code $eventLogCode -FileName 'First.ps1'
            $folder = Split-Path -Path $firstPath -Parent
            $secondPath = Join-Path -Path $folder -ChildPath 'Second.psm1'
            Set-Content -LiteralPath $secondPath -Value "`$ErrorActionPreference = 'Stop'" -Encoding ascii

            $ruleIds = @(& $complianceScript -Path $folder -PassThru | ForEach-Object { $_.RuleId })

            $ruleIds -contains 'VER-06' | Should-BeTrue
            $ruleIds -contains 'ERR-02' | Should-BeTrue
        }

        It 'Leaves out test files when -ExcludeTests is given' {
            $testPath = & $newFixtureFile -Code $eventLogCode -FileName 'Sample.Tests.ps1'
            $cleanPath = Join-Path -Path (Split-Path -Path $testPath -Parent) -ChildPath 'Clean.ps1'
            $folder = Split-Path -Path $testPath -Parent
            Set-Content -LiteralPath $cleanPath -Value "'text'" -Encoding ascii

            $findings = @(& $complianceScript -Path $folder -ExcludeTests -PassThru)

            $findings.Count | Should-Be 0
        }

        It 'Fails when there is nothing to check' {
            $folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
            $null = New-Item -Path $folder -ItemType Directory

            { & $complianceScript -Path $folder } | Should-Throw -ExceptionMessage '*Nothing was checked*'
        }

        It 'Fails when the settings file does not exist' {
            $filePath = & $newFixtureFile -Code "'text'" -FileName 'Fixture.ps1'
            $missingSettings = Join-Path -Path $TestDrive -ChildPath 'absent.psd1'

            { & $complianceScript -Path $filePath -SettingsPath $missingSettings } |
                Should-Throw -ExceptionMessage '*does not exist*'
        }
    }
}

Describe 'The repository''s own PowerShell files' -Tag 'Integration' {
    It 'Pass the compliance check in <Folder>' -ForEach @(
        @{ Folder = 'Tools' }
        @{ Folder = 'standards' }
        @{ Folder = 'Templates' }
        @{ Folder = 'powershell-standards/Examples' }
    ) {
        $folderPath = Join-Path -Path $repositoryRoot -ChildPath $Folder

        # Test-QualityGates.ps1 breaks the rules on purpose, to give the quality gates something to catch.
        $findings = @(& $complianceScript -Path $folderPath -PassThru |
                Where-Object { (Split-Path -Path $_.File -Leaf) -ne 'Test-QualityGates.ps1' })
        $summary = $findings | ForEach-Object { "$(Split-Path -Path $_.File -Leaf):$($_.Line) $($_.RuleId)" }

        @($summary) -join '; ' | Should-BeString ''
    }
}
