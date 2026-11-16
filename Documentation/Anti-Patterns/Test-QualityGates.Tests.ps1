#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }
#Requires -Modules @{ ModuleName = 'PSScriptAnalyzer'; ModuleVersion = '1.25.0' }

BeforeAll {
    $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath 'Test-QualityGates.ps1'
    . $sourcePath
}

# Test-QualityGates.ps1 is a negative example. The first two Describe blocks record what its functions
# do; they do not endorse how the functions do it. Write-Host output is discarded with 6>$null.

Describe 'Test-QualityGates' -Tag 'Unit' {
    Context 'When the user name is not blank' {
        It 'Returns one summary that counts the servers' {
            $result = @(Test-QualityGates -UserName 'operator' -ServerList 'server1', 'server2' 6>$null)

            $result | Should-BeCollection -Count 1
            $result[0].UserName | Should-Be 'operator'
            $result[0].ServersProcessed | Should-Be 2
            $result[0].LogSize | Should-Be "Processing server1`nProcessing server2`n".Length
        }

        It 'Returns a summary of no servers when ServerList is omitted' {
            $result = @(Test-QualityGates -UserName 'operator' 6>$null)

            $result | Should-BeCollection -Count 1
            $result[0].ServersProcessed | Should-Be 0
            $result[0].LogSize | Should-Be 0
        }

        It 'Writes a status message with Write-Host before and after the work' {
            $output = Test-QualityGates -UserName 'operator' 6>&1
            $messages = @(
                $output | Where-Object { $_ -is [System.Management.Automation.InformationRecord] }
            )

            $messages | Should-BeCollection -Count 2
            $messages[0].MessageData.ToString() | Should-Be 'Starting quality gate test...'
            $messages[1].MessageData.ToString() | Should-Be 'Quality gate test completed'
        }
    }

    Context 'When the user name is blank' {
        It 'Throws a string that carries the message of the original error' {
            { Test-QualityGates -UserName '   ' 6>$null } |
                Should-Throw -ExceptionMessage 'Processing failed: UserName cannot be blank.'
        }

        It 'Rejects an empty user name when the parameter is bound' {
            { Test-QualityGates -UserName '' 6>$null } |
                Should-Throw -FullyQualifiedErrorId 'ParameterArgumentValidationError,Test-QualityGates'
        }
    }
}

Describe 'Process-TestData' -Tag 'Unit' {
    It 'Adds the prefix to the text' {
        Process-TestData -Data 'sample' | Should-Be 'Processed: sample'
    }
}

Describe 'Deliberate violations in Test-QualityGates.ps1' -Tag 'Integration' {
    BeforeAll {
        $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $settingsPath = Join-Path -Path $repositoryRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
        $findings = @(Invoke-ScriptAnalyzer -Path $sourcePath -Settings $settingsPath)

        # The checks below read the syntax tree and not the text, because the comments in the file
        # name every construct that the checks look for.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $sourcePath, [ref]$null, [ref]$null)
    }

    Context 'The label' {
        It 'Starts the file with the warning not to copy from it' {
            $firstLine = Get-Content -LiteralPath $sourcePath -TotalCount 1

            $firstLine | Should-Be '# NEGATIVE EXAMPLE. DO NOT COPY CODE FROM THIS FILE.'
        }
    }

    Context 'Violations that PSScriptAnalyzer reports' {
        It 'Reports the rules that the file header lists, and no others' {
            $reported = $findings |
                Group-Object -Property RuleName |
                Sort-Object -Property Name |
                ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count }
            $expected = @(
                'PSAvoidUsingWriteHost x2'
                'PSPlaceCloseBrace x1'
                'PSReviewUnusedParameter x1'
                'PSUseApprovedVerbs x1'
                'PSUseConsistentWhitespace x2'
                'PSUseSingularNouns x1'
            )

            ($reported -join '; ') | Should-Be ($expected -join '; ')
        }

        It 'Names every reported rule in the file header' {
            $isFunction = {
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }
            $functions = @($ast.FindAll($isFunction, $true))
            $functions | Should-BeCollection -Count 2
            $header = $ast.Extent.Text.Substring(0, $functions[0].Extent.StartOffset)

            $ruleNames = @($findings.RuleName | Sort-Object -Unique)
            $missingFromHeader = @($ruleNames | Where-Object { -not $header.Contains($_) })

            $ruleNames | Should-BeCollection -Count 6
            $missingFromHeader | Should-BeCollection -Count 0
        }
    }

    Context 'Violations that PSScriptAnalyzer does not report' {
        It 'Declares PSCustomObject as the output type (FUN-10)' {
            $outputTypes = @((Get-Command -Name Test-QualityGates).OutputType)

            # [PSCustomObject] is an accelerator for PSObject, which is the name the attribute keeps.
            $outputTypes | Should-BeCollection -Count 1
            $outputTypes[0].Name | Should-Be 'System.Management.Automation.PSObject'
        }

        It 'Adds ValidateNotNullOrEmpty to a mandatory string parameter (FUN-23)' {
            $parameter = (Get-Command -Name Test-QualityGates).Parameters['UserName']
            $mandatory = @(
                $parameter.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }
            )
            $validators = @(
                $parameter.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] }
            )

            $parameter.ParameterType | Should-Be ([string])
            $mandatory | Should-BeCollection -Count 1
            $validators | Should-BeCollection -Count 1
        }

        It 'Extends an array and then a string with += (STY-40, STY-22)' {
            $isAddition = {
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Operator -eq [System.Management.Automation.Language.TokenKind]::PlusEquals
            }
            $additions = @($ast.FindAll($isAddition, $true))
            $loopType = [System.Management.Automation.Language.ForEachStatementAst]

            $additions | Should-BeCollection -Count 2
            $additions[0].Left.Extent.Text | Should-Be '$results'
            $additions[0].Parent.Parent | Should-HaveType $loopType
            $additions[1].Left.Extent.Text | Should-Be '$logOutput'
            $additions[1].Parent.Parent | Should-HaveType $loopType
        }

        It 'Throws strings in an advanced function (ERR-11, ERR-14)' {
            $isThrow = {
                param($node)
                $node -is [System.Management.Automation.Language.ThrowStatementAst]
            }
            $throwStatements = @($ast.FindAll($isThrow, $true))

            $throwStatements | Should-BeCollection -Count 2
            $throwStatements[0].Pipeline.Extent.Text | Should-BeLikeString '*UserName cannot be blank.*'
            $throwStatements[1].Pipeline.Extent.Text | Should-BeLikeString '"Processing failed: *"'
        }

        It 'Reads $Error[0] in the catch block (ERR-21)' {
            $isErrorIndex = {
                param($node)
                $node -is [System.Management.Automation.Language.IndexExpressionAst] -and
                $node.Target.Extent.Text -eq '$Error'
            }
            $errorIndexes = @($ast.FindAll($isErrorIndex, $true))

            $errorIndexes | Should-BeCollection -Count 1
            $errorIndexes[0].Parent.Parent.Parent.Parent |
                Should-HaveType ([System.Management.Automation.Language.CatchClauseAst])
        }
    }
}
