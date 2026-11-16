#requires -Version 7.6
#requires -Modules PSScriptAnalyzer

<#
.SYNOPSIS
Checks PowerShell files against the rules of the PowerShell standards that a tool can check.

.DESCRIPTION
Runs PSScriptAnalyzer with the standards' settings file, then applies checks for rules that
PSScriptAnalyzer does not cover, by reading the parsed code. Every finding carries the ID of the
rule it breaks, such as ERR-11, so that it can be looked up in the rule files.

The additional checks cover: functions without [CmdletBinding()] or without help (FUN-01, DOC-01),
version stamps in help (DOC-07), [OutputType([PSCustomObject])] (FUN-10), throw and
Write-Error -ErrorAction Stop in advanced functions (ERR-11), $Error[0] in catch (ERR-21),
$ErrorActionPreference set in a root module (ERR-02), arrays grown with += in a loop (STY-40),
ArrayList (STY-41), non-ASCII characters outside strings (STY-06), #requires for a version past its
end of support (VER-05), commands that exist only in Windows PowerShell (VER-06), retired platyPS
commands (PLT-01), literal secrets (SEC-01), and a manifest that still has the placeholder GUID
(MOD-03).

A clean result does not prove that code follows every rule. Many rules need a reader.

.PARAMETER Path
File or folder to check. A folder is searched recursively for .ps1, .psm1, and .psd1 files.

.PARAMETER SettingsPath
PSScriptAnalyzer settings file. The default is PSScriptAnalyzerSettings.psd1 in the repository
that contains this script.

.PARAMETER ExcludeTests
Leaves out files named *.Tests.ps1 and files under a folder named Tests.

.PARAMETER PassThru
Returns the findings without failing. Without this switch the script fails, after writing the
findings, when any finding has the severity Error or Warning.

.EXAMPLE
./Tools/Test-StandardsCompliance.ps1 -Path ./src

Checks every PowerShell file under src and fails if anything is found.

.EXAMPLE
./Tools/Test-StandardsCompliance.ps1 -Path ./src -PassThru | Group-Object -Property RuleId

Counts the findings for each rule without failing.

.INPUTS
None.

.OUTPUTS
PowerShellStandards.Finding. One object for each finding, with RuleId, Severity, File, Line,
Message, and Source properties. Source is PSScriptAnalyzer or Standards.
#>
using namespace System.Management.Automation.Language

[CmdletBinding()]
[OutputType('PowerShellStandards.Finding')]
param(
    [Parameter()]
    [string]$Path = '.',

    [Parameter()]
    [string]$SettingsPath,

    [Parameter()]
    [switch]$ExcludeTests,

    [Parameter()]
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $SettingsPath) {
    $repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $SettingsPath = Join-Path -Path $repositoryRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
}
if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
    throw "The PSScriptAnalyzer settings file '$SettingsPath' does not exist."
}

# Rules in the standards, and the PSScriptAnalyzer rules that enforce each of them.
$analyzerRulesByRuleId = @{
    'STY-01' = @('PSUseConsistentIndentation')
    'STY-02' = @('PSPlaceOpenBrace', 'PSPlaceCloseBrace')
    'STY-03' = @('PSAvoidLongLines')
    'STY-04' = @('PSUseConsistentWhitespace')
    'STY-05' = @('PSAvoidTrailingWhitespace')
    'STY-06' = @('PSUseBOMForUnicodeEncodedFile')
    'STY-10' = @('PSUseApprovedVerbs', 'PSUseSingularNouns')
    'STY-13' = @('PSAvoidAssignmentToAutomaticVariable')
    'STY-14' = @('PSAvoidUsingCmdletAliases', 'PSAvoidUsingPositionalParameters')
    'STY-15' = @('PSUseCorrectCasing')
    'STY-20' = @('PSPossibleIncorrectComparisonWithNull')
    'FUN-03' = @('PSAvoidGlobalVars')
    'FUN-30' = @('PSUseShouldProcessForStateChangingFunctions', 'PSShouldProcess')
    'ERR-20' = @('PSAvoidUsingEmptyCatchBlock')
    'ERR-31' = @('PSAvoidUsingWriteHost')
    'SEC-03' = @('PSAvoidUsingPlainTextForPassword', 'PSAvoidUsingUsernameAndPasswordParams')
    'SEC-04' = @('PSAvoidUsingConvertToSecureStringWithPlainText')
    'SEC-10' = @('PSAvoidUsingInvokeExpression')
    'VER-06' = @('PSAvoidUsingWMICmdlet')
}
$ruleIdByAnalyzerRule = @{}
foreach ($mappedRuleId in $analyzerRulesByRuleId.Keys) {
    foreach ($analyzerRule in $analyzerRulesByRuleId[$mappedRuleId]) {
        $ruleIdByAnalyzerRule[$analyzerRule] = $mappedRuleId
    }
}

# Pester assigns variables in one block and reads them in another, and test data often names
# computers, so these rules report false findings in test files.
$rulesExcludedInTests = @(
    'PSAvoidUsingComputerNameHardcoded'
    'PSReviewUnusedParameter'
    'PSUseDeclaredVarsMoreThanAssignments'
)

$windowsOnlyCommands = @(
    'Get-EventLog', 'Write-EventLog', 'New-EventLog', 'Clear-EventLog', 'Limit-EventLog'
    'Remove-EventLog', 'Show-EventLog', 'New-WebServiceProxy', 'Add-PSSnapin', 'Send-MailMessage'
)
$retiredPlatyPSCommands = @(
    'New-MarkdownHelp', 'Update-MarkdownHelp', 'Update-MarkdownHelpModule', 'New-ExternalHelp'
    'New-ExternalHelpCab', 'Get-HelpPreview'
)
$secretNamePattern = '(?i)(password|passwd|pwd|secret|apikey|api_key|token|connectionstring)$'
# A quoted string of three or more characters with no variable in it.
$literalStringPattern = '^(''[^'']{3,}''|"[^"$]{3,}")$'
$stringTokenKinds = @('StringLiteral', 'StringExpandable', 'HereStringLiteral', 'HereStringExpandable')
$terminatingAdvice = 'Use $PSCmdlet.ThrowTerminatingError().'
$listAdvice = 'ArrayList is used. Use [System.Collections.Generic.List[T]].'

$resolvedPath = Convert-Path -LiteralPath $Path
$separator = [System.IO.Path]::DirectorySeparatorChar
$files = @(
    if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
        Get-Item -LiteralPath $resolvedPath
    } else {
        Get-ChildItem -LiteralPath $resolvedPath -Include '*.ps1', '*.psm1', '*.psd1' -File -Recurse |
            Where-Object { $_.FullName -notlike "*${separator}.git${separator}*" }
    }
)

$isTestFile = {
    param([System.IO.FileInfo]$File)
    $File.Name -like '*.Tests.ps1' -or $File.FullName -like "*${separator}Tests${separator}*"
}

if ($ExcludeTests) {
    $files = @($files | Where-Object { -not (& $isTestFile -File $_) })
}

if ($files.Count -eq 0) {
    throw "No PowerShell files were found under '$resolvedPath'. Nothing was checked."
}

$blockingFindingCount = 0

foreach ($file in $files) {
    $filePath = $file.FullName

    # Each entry is the rule ID, the severity, the line, the message, and the source of a finding.
    $issues = [System.Collections.Generic.List[object[]]]::new()

    $analyzerParameters = @{
        Path = $filePath
        Settings = $SettingsPath
    }
    if (& $isTestFile -File $file) {
        $analyzerParameters['ExcludeRule'] = $rulesExcludedInTests
    }
    foreach ($record in Invoke-ScriptAnalyzer @analyzerParameters) {
        $ruleName = [string]$record.RuleName
        $ruleId = $ruleName
        if ($ruleIdByAnalyzerRule.ContainsKey($ruleName)) {
            $ruleId = $ruleIdByAnalyzerRule[$ruleName]
        }
        $severity = [string]$record.Severity
        if ($severity -eq 'ParseError') {
            $severity = 'Error'
        }
        $line = 0
        if ($null -ne $record.Line) {
            $line = [int]$record.Line
        }
        $issues.Add(@($ruleId, $severity, $line, "${ruleName}: $($record.Message)", 'PSScriptAnalyzer'))
    }

    $tokens = $null
    $parseErrors = $null
    $ast = [Parser]::ParseFile($filePath, [ref]$tokens, [ref]$parseErrors)

    # Functions, leaving out class methods, which cannot be advanced functions.
    $functions = $ast.FindAll(
        { param($node) $node -is [FunctionDefinitionAst] -and $node.Parent -isnot [FunctionMemberAst] },
        $true)

    $advancedFunctionBodies = [System.Collections.Generic.List[object]]::new()
    foreach ($function in $functions) {
        $name = $function.Name
        $line = $function.Extent.StartLineNumber
        $paramBlock = $function.Body.ParamBlock

        $isAdvanced = $false
        if ($null -ne $paramBlock) {
            foreach ($attribute in $paramBlock.Attributes) {
                if ($attribute.TypeName.Name -eq 'CmdletBinding') {
                    $isAdvanced = $true
                }
                if ($attribute.TypeName.Name -ne 'OutputType') {
                    continue
                }
                $typeNames = foreach ($argument in $attribute.PositionalArguments) {
                    if ($argument -is [TypeExpressionAst]) {
                        $argument.TypeName.Name
                    }
                }
                if (@($typeNames) -contains 'PSCustomObject') {
                    $message = "'$name' declares [OutputType([PSCustomObject])]. Name the type instead."
                    $issues.Add(@('FUN-10', 'Error', $attribute.Extent.StartLineNumber, $message, 'Standards'))
                }
            }
        }

        if ($isAdvanced) {
            $advancedFunctionBodies.Add($function.Body)
        } else {
            $message = "Function '$name' has no [CmdletBinding()] attribute."
            $issues.Add(@('FUN-01', 'Error', $line, $message, 'Standards'))
        }

        $help = $function.GetHelpContent()
        if ($null -eq $help) {
            $message = "Function '$name' has no comment-based help that Get-Help can find."
            $issues.Add(@('DOC-01', 'Error', $line, $message, 'Standards'))
        } elseif ($help.Notes -match '(?im)^\s*(version|last\s+updated|date)\s*:') {
            $message = "The help of '$name' contains a version or date stamp."
            $issues.Add(@('DOC-07', 'Error', $line, $message, 'Standards'))
        }
    }

    # A statement belongs to an advanced function when the nearest script block around it is the
    # function's body. A nested script block, such as a ValidateScript argument, is not the function.
    $isInAdvancedFunction = {
        param($Node)
        $current = $Node.Parent
        while ($null -ne $current -and $current -isnot [ScriptBlockAst]) {
            $current = $current.Parent
        }
        $null -ne $current -and $advancedFunctionBodies.Contains($current)
    }

    foreach ($throwStatement in $ast.FindAll({ param($node) $node -is [ThrowStatementAst] }, $true)) {
        if (& $isInAdvancedFunction -Node $throwStatement) {
            $message = "throw is used in an advanced function. $terminatingAdvice"
            $issues.Add(@('ERR-11', 'Error', $throwStatement.Extent.StartLineNumber, $message, 'Standards'))
        }
    }

    foreach ($command in $ast.FindAll({ param($node) $node -is [CommandAst] }, $true)) {
        $commandName = $command.GetCommandName()
        if ($null -eq $commandName) {
            continue
        }
        $line = $command.Extent.StartLineNumber

        if ($windowsOnlyCommands -contains $commandName) {
            $message = "$commandName is not part of PowerShell 7, or is obsolete there."
            $issues.Add(@('VER-06', 'Error', $line, $message, 'Standards'))
        }
        if ($retiredPlatyPSCommands -contains $commandName) {
            $message = "$commandName belongs to the retired platyPS module. Use Microsoft.PowerShell.PlatyPS."
            $issues.Add(@('PLT-01', 'Error', $line, $message, 'Standards'))
        }
        if ($commandName -eq 'New-Object' -and $command.Extent.Text -match '(?i)Collections\.ArrayList') {
            $issues.Add(@('STY-41', 'Error', $line, $listAdvice, 'Standards'))
        }
        $formatArguments = @($command.CommandElements |
                Where-Object { $_ -is [CommandParameterAst] -and $_.ParameterName -eq 'f' })
        if ($formatArguments.Count -gt 0) {
            $advice = 'Put the format operator inside the parentheses.'
            $message = "'-f' is passed to $commandName as an argument. $advice"
            $issues.Add(@('STY-23', 'Error', $line, $message, 'Standards'))
        }
        if ($commandName -ne 'Write-Error' -or -not (& $isInAdvancedFunction -Node $command)) {
            continue
        }

        $elements = $command.CommandElements
        for ($index = 0; $index -lt $elements.Count; $index++) {
            $element = $elements[$index]
            if ($element -isnot [CommandParameterAst] -or $element.ParameterName -notmatch '^(ErrorAction|EA)$') {
                continue
            }
            $valueAst = $element.Argument
            if ($null -eq $valueAst -and $index + 1 -lt $elements.Count) {
                $valueAst = $elements[$index + 1]
            }
            if ($null -ne $valueAst -and $valueAst.Extent.Text.Trim('''"') -eq 'Stop') {
                $message = "Write-Error -ErrorAction Stop is used in an advanced function. $terminatingAdvice"
                $issues.Add(@('ERR-11', 'Error', $line, $message, 'Standards'))
            }
        }
    }

    $typeNodes = $ast.FindAll(
        { param($node) $node -is [TypeExpressionAst] -or $node -is [TypeConstraintAst] },
        $true)
    foreach ($typeNode in $typeNodes) {
        if ($typeNode.TypeName.FullName -match '(?i)(^|\.)ArrayList$') {
            $issues.Add(@('STY-41', 'Error', $typeNode.Extent.StartLineNumber, $listAdvice, 'Standards'))
        }
    }

    foreach ($catchClause in $ast.FindAll({ param($node) $node -is [CatchClauseAst] }, $true)) {
        $errorIndexes = $catchClause.FindAll(
            {
                param($node)
                $node -is [IndexExpressionAst] -and
                $node.Target -is [VariableExpressionAst] -and
                $node.Target.VariablePath.UserPath -eq 'Error'
            },
            $true)
        foreach ($errorIndex in $errorIndexes) {
            $message = '$Error is indexed inside a catch block. Read the error from $_.'
            $issues.Add(@('ERR-21', 'Error', $errorIndex.Extent.StartLineNumber, $message, 'Standards'))
        }
    }

    # The variable on the left of an assignment, with or without a type constraint in front of it.
    $getAssignedVariableName = {
        param($Assignment)
        $target = $Assignment.Left
        if ($target -is [ConvertExpressionAst]) {
            $target = $target.Child
        }
        if ($target -is [VariableExpressionAst]) {
            $target.VariablePath.UserPath
        }
    }

    $assignments = $ast.FindAll({ param($node) $node -is [AssignmentStatementAst] }, $true)
    $emptyArrayVariables = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    foreach ($assignment in $assignments) {
        $variableName = & $getAssignedVariableName -Assignment $assignment
        if ($null -eq $variableName) {
            continue
        }
        $line = $assignment.Extent.StartLineNumber
        $isPlainAssignment = $assignment.Operator -eq [TokenKind]::Equals
        $rightText = $assignment.Right.Extent.Text.Trim()

        if ($isPlainAssignment -and $rightText -match '^@\(\s*\)$') {
            $null = $emptyArrayVariables.Add($variableName)
        }
        if ($file.Extension -eq '.psm1' -and $variableName -eq 'ErrorActionPreference') {
            $issues.Add(@('ERR-02', 'Error', $line, 'A root module sets $ErrorActionPreference.', 'Standards'))
        }
        $isSecretName = $variableName -match $secretNamePattern
        if ($isPlainAssignment -and $isSecretName -and $rightText -match $literalStringPattern) {
            $message = "A literal value is assigned to `$$variableName."
            $issues.Add(@('SEC-01', 'Error', $line, $message, 'Standards'))
        }
    }

    foreach ($assignment in $assignments) {
        if ($assignment.Operator -ne [TokenKind]::PlusEquals) {
            continue
        }
        $variableName = & $getAssignedVariableName -Assignment $assignment
        if ($null -eq $variableName -or -not $emptyArrayVariables.Contains($variableName)) {
            continue
        }
        $current = $assignment.Parent
        while ($null -ne $current -and $current -isnot [LoopStatementAst]) {
            $current = $current.Parent
        }
        if ($null -ne $current) {
            $message = "The array `$$variableName is grown with += inside a loop."
            $issues.Add(@('STY-40', 'Error', $assignment.Extent.StartLineNumber, $message, 'Standards'))
        }
    }

    foreach ($hashtable in $ast.FindAll({ param($node) $node -is [HashtableAst] }, $true)) {
        foreach ($pair in $hashtable.KeyValuePairs) {
            $keyText = $pair.Item1.Extent.Text.Trim('''"')
            $valueText = $pair.Item2.Extent.Text.Trim()
            if ($keyText -match $secretNamePattern -and $valueText -match $literalStringPattern) {
                $message = "A literal value is assigned to the key '$keyText'."
                $issues.Add(@('SEC-01', 'Error', $pair.Item1.Extent.StartLineNumber, $message, 'Standards'))
            }
        }
    }

    foreach ($token in $tokens) {
        if ($stringTokenKinds -notcontains [string]$token.Kind -and $token.Text -match '[^\x00-\x7F]') {
            $message = 'A non-ASCII character appears outside a string literal.'
            $issues.Add(@('STY-06', 'Error', $token.Extent.StartLineNumber, $message, 'Standards'))
        }
    }

    # STY-07: two blank lines around a top-level function, and no run of blank lines inside one.
    # Lines inside a multi-line string are data, not layout, so they are left out.
    $sourceLines = [System.IO.File]::ReadAllLines($filePath)
    $stringLines = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($token in $tokens) {
        if ($stringTokenKinds -contains [string]$token.Kind) {
            for ($number = $token.Extent.StartLineNumber; $number -le $token.Extent.EndLineNumber; $number++) {
                $null = $stringLines.Add($number)
            }
        }
    }
    $isBlank = { param([int]$Number) [string]::IsNullOrWhiteSpace($sourceLines[$Number - 1]) }

    $topLevelFunctions = @($functions | Where-Object {
            $_.Parent -is [NamedBlockAst] -and $null -eq $_.Parent.Parent.Parent
        })
    # A comment directly above a function belongs to it, so the function starts at that comment.
    $functionStarts = @{}
    foreach ($function in $topLevelFunctions) {
        $start = $function.Extent.StartLineNumber
        while ($start -gt 1 -and $sourceLines[$start - 2] -match '^\s*#') {
            $start--
        }
        $functionStarts[$start] = $function
    }

    foreach ($start in $functionStarts.Keys) {
        $function = $functionStarts[$start]
        $blankBefore = 0
        while ($start - $blankBefore -gt 1 -and (& $isBlank -Number ($start - $blankBefore - 1))) {
            $blankBefore++
        }
        if ($start - $blankBefore -gt 1 -and $blankBefore -ne 2) {
            $message = "Put two blank lines before the function $($function.Name)."
            $issues.Add(@('STY-07', 'Warning', $start, $message, 'Standards'))
        }

        $end = $function.Extent.EndLineNumber
        $next = $end + 1
        while ($next -le $sourceLines.Count -and (& $isBlank -Number $next)) {
            $next++
        }
        $followedByCode = $next -le $sourceLines.Count -and -not $functionStarts.ContainsKey($next)
        if ($followedByCode -and $next - $end - 1 -ne 2) {
            $message = "Put two blank lines after the function $($function.Name)."
            $issues.Add(@('STY-07', 'Warning', $end, $message, 'Standards'))
        }

        for ($number = $function.Extent.StartLineNumber + 1; $number -lt $end; $number++) {
            $isRun = (& $isBlank -Number $number) -and (& $isBlank -Number ($number + 1))
            if ($isRun -and -not $stringLines.Contains($number) -and -not $stringLines.Contains($number + 1)) {
                $message = "Use at most one blank line between statements inside $($function.Name)."
                $issues.Add(@('STY-07', 'Warning', $number, $message, 'Standards'))
                break
            }
        }
    }

    if ($file.Extension -eq '.psd1') {
        foreach ($hashtable in $ast.FindAll({ param($node) $node -is [HashtableAst] }, $true)) {
            foreach ($pair in $hashtable.KeyValuePairs) {
                $isGuidKey = $pair.Item1.Extent.Text.Trim('''"') -eq 'GUID'
                if ($isGuidKey -and $pair.Item2.Extent.Text -match '0{8}-0{4}-0{4}-0{4}-0{12}') {
                    $message = 'The manifest GUID is the all-zero placeholder. Generate one with New-Guid.'
                    $issues.Add(@('MOD-03', 'Error', $pair.Item1.Extent.StartLineNumber, $message, 'Standards'))
                }
            }
        }
    }

    $requiredVersion = $ast.ScriptRequirements?.RequiredPSVersion
    if ($null -ne $requiredVersion) {
        $isSeven = $requiredVersion.Major -eq 7
        if ($requiredVersion.Major -eq 6 -or ($isSeven -and $requiredVersion.Minor -lt 6)) {
            $message = "#requires -Version $requiredVersion names a version that is past its end of support."
            $issues.Add(@('VER-05', 'Error', 1, $message, 'Standards'))
        }
    }

    foreach ($issue in $issues | Sort-Object -Property { $_[2] }, { $_[0] }) {
        if ($issue[1] -in 'Error', 'Warning') {
            $blockingFindingCount++
        }

        [PSCustomObject]@{
            PSTypeName = 'PowerShellStandards.Finding'
            RuleId = $issue[0]
            Severity = $issue[1]
            File = $filePath
            Line = $issue[2]
            Message = $issue[3]
            Source = $issue[4]
        }
    }
}

if ($blockingFindingCount -gt 0 -and -not $PassThru) {
    throw "$blockingFindingCount finding(s) with severity Error or Warning in $($files.Count) file(s)."
}
