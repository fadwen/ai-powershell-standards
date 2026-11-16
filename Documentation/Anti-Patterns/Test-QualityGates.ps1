# NEGATIVE EXAMPLE. DO NOT COPY CODE FROM THIS FILE.
#
# The two functions below break the PowerShell standards on purpose, so that the quality gates have
# something to catch. Each deliberate violation is marked where it occurs with the word VIOLATION and
# the rule it breaks. For code to copy, use Basic-Function-Example.ps1.
#
# Reported by PSScriptAnalyzer when it runs with PSScriptAnalyzerSettings.psd1 from the repository
# root:
#
#   STY-02     PSPlaceCloseBrace            catch starts on its own line
#   STY-04     PSUseConsistentWhitespace    a hashtable padded so that its equals signs line up
#   STY-10     PSUseSingularNouns           the noun QualityGates is plural
#   STY-10     PSUseApprovedVerbs           Process is not an approved verb
#   ERR-31     PSAvoidUsingWriteHost        Write-Host in a function
#   no rule    PSReviewUnusedParameter      a parameter that the function never reads
#
# Not reported by PSScriptAnalyzer. Finding them takes a check that reads the parsed code, or a
# reviewer:
#
#   FUN-10     [OutputType([PSCustomObject])]
#   FUN-23     ValidateNotNullOrEmpty on a mandatory string, and whitespace rejected in the body
#   STY-22     a string extended with += in a loop
#   STY-40     an array grown with += in a loop
#   ERR-11     throw in an advanced function
#   ERR-14     an error rethrown as a string
#   ERR-21     $Error[0] in a catch block
#
# The file has no security violations: no secrets, no credentials, and no command built from input.
# It has to stay that way, because it is kept in the repository.
#
# An analysis run that has to pass must leave this file out by name. Test-QualityGates.Tests.ps1 pins
# both lists, so adding or removing a violation fails a test until the lists are brought up to date.

# VIOLATION STY-10: the noun is plural. PSScriptAnalyzer reports PSUseSingularNouns.
function Test-QualityGates {
    <#
    .SYNOPSIS
    Negative example. Summarizes a list of servers while breaking the standards on purpose.

    .DESCRIPTION
    Do not copy this function. It counts the servers it is given and builds one line of log text
    for each of them. The header of this file lists the rules it breaks.

    .PARAMETER UserName
    Name of the user the summary is for. A blank name ends the function with an error.

    .PARAMETER ServerList
    Names of the servers to summarize.

    .PARAMETER UnusedParameter
    Never read by the function. Declaring it is one of the violations.

    .EXAMPLE
    Test-QualityGates -UserName 'operator' -ServerList 'server1', 'server2'

    Returns a summary of two servers.

    .INPUTS
    None.

    .OUTPUTS
    System.Management.Automation.PSCustomObject. An object with UserName, ServersProcessed, and
    LogSize properties.
    #>
    [CmdletBinding()]
    # VIOLATION FUN-10: the type says nothing about the object. Name the type as a string and set
    # PSTypeName on the object.
    [OutputType([PSCustomObject])]
    param(
        # VIOLATION FUN-23: mandatory binding already rejects $null and an empty string.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UserName,

        [Parameter()]
        [string[]]$ServerList,

        # VIOLATION: the function never reads this parameter. PSScriptAnalyzer reports
        # PSReviewUnusedParameter.
        [Parameter()]
        [string]$UnusedParameter
    )

    begin {
        # VIOLATION ERR-31: Write-Host in a function. PSScriptAnalyzer reports PSAvoidUsingWriteHost.
        Write-Host 'Starting quality gate test...'
        $results = @()
    }

    process {
        try {
            # VIOLATION FUN-23: whitespace is rejected here and not by a validation attribute.
            # VIOLATION ERR-11: throw in an advanced function.
            if ($UserName.Trim().Length -eq 0) {
                throw 'UserName cannot be blank.'
            }

            # VIOLATION STY-40: += copies the whole array on every pass.
            foreach ($server in $ServerList) {
                $results += $server
            }

            # VIOLATION STY-22: += copies the whole string on every pass.
            $logOutput = ''
            foreach ($server in $results) {
                $logOutput += "Processing $server`n"
            }

            # VIOLATION STY-04: padding lines up the equals signs. PSScriptAnalyzer reports
            # PSUseConsistentWhitespace.
            $result = [PSCustomObject]@{
                UserName         = $UserName
                ServersProcessed = $results.Count
                LogSize          = $logOutput.Length
            }

            return $result
        }
        catch {
            # VIOLATION STY-02: catch starts on its own line. PSScriptAnalyzer reports
            # PSPlaceCloseBrace.
            # VIOLATION ERR-21: $Error is shared by the whole session, so its first entry can be an
            # unrelated error. The error that was caught is $_.
            # VIOLATION ERR-14 and ERR-11: the error is rethrown as a string, which discards its type
            # and its original record.
            $currentError = $Error[0]
            throw "Processing failed: $($currentError.Exception.Message)"
        }
    }

    end {
        # VIOLATION ERR-31: Write-Host in a function. PSScriptAnalyzer reports PSAvoidUsingWriteHost.
        Write-Host 'Quality gate test completed'
    }
}

# VIOLATION STY-10: Process is not an approved verb. PSScriptAnalyzer reports PSUseApprovedVerbs.
function Process-TestData {
    <#
    .SYNOPSIS
    Negative example. Adds a prefix to a string, under a verb that PowerShell does not approve.

    .DESCRIPTION
    Do not copy this function. Its name is the violation: Get-Verb does not list Process.

    .PARAMETER Data
    Text to add the prefix to.

    .EXAMPLE
    Process-TestData -Data 'sample'

    Returns the text "Processed: sample".

    .INPUTS
    None.

    .OUTPUTS
    System.String. The text with its prefix.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Data
    )

    "Processed: $Data"
}
