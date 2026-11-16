# Security Test Template

A test file for functions that handle untrusted input, paths, or credentials. Write one only for a
function that has such a requirement (TST-43). The security rules that these tests check are in the
[security rules](../powershell-security.instructions.md), and the testing rules are in the
[Pester rules](../powershell-pester.instructions.md). The file below passes on Pester 6.2.0 under
PowerShell 7.6 and Windows PowerShell 5.1, and each of its tests fails against a copy of the module
that has the defect it looks for.

## The Code Under Test

The template tests the module `ModuleName` from the [unit test template](./unit-test-template.md).

- `Get-Thing -Name <string[]>` puts each name into the address of a web request. It restricts names
  with an anchored `ValidatePattern` (SEC-11).
- `Read-ThingFile -Root <string> -ChildPath <string>` reads a file below a root folder. It resolves
  the path and refuses one that leaves the root, with the error ID `PathOutsideRoot` (SEC-12).
- `Connect-ThingService -Credential <PSCredential>` signs in to the service. Without a credential it
  fails with the error ID `CredentialRequired`; it does not prompt (SEC-05). It writes a verbose
  message, and a failed sign-in has the error ID `SignInFailed`.

## The Test File

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    $injectionCases = @(
        @{ Description = 'a command separator'; Text = 'alpha; Remove-Item -Path *' }
        @{ Description = 'a subexpression'; Text = '$(Get-Process)' }
        @{ Description = 'a pipe'; Text = 'alpha | Out-File -FilePath x' }
        @{ Description = 'a relative path'; Text = '../../etc/passwd' }
        @{ Description = 'a quote'; Text = "alpha' OR '1'='1" }
    )

    $traversalCases = @(
        @{ ChildPath = '../outside.txt' }
        @{ ChildPath = 'reports/../../outside.txt' }
        @{ ChildPath = '../root-other/outside.txt' }
    )
}

BeforeAll {
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ModuleName.psd1')
    }
}

Describe 'Get-Thing input validation' -Tag 'Security' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith { }
    }

    It 'Rejects a name that contains <Description>' -ForEach $injectionCases {
        { Get-Thing -Name $Text } |
            Should-Throw -FullyQualifiedErrorId 'ParameterArgumentValidationError,Get-Thing'

        Should-NotInvoke -CommandName Invoke-RestMethod -ModuleName ModuleName
    }
}

Describe 'Read-ThingFile path handling' -Tag 'Security' {
    BeforeAll {
        $root = Join-Path -Path $TestDrive -ChildPath 'root'
        $sibling = Join-Path -Path $TestDrive -ChildPath 'root-other'
        $null = New-Item -Path $root -ItemType Directory
        $null = New-Item -Path $sibling -ItemType Directory

        # The files outside the root exist, so a function that followed the path would return them.
        $insidePath = Join-Path -Path $root -ChildPath 'inside.txt'
        $outsidePath = Join-Path -Path $TestDrive -ChildPath 'outside.txt'
        $siblingPath = Join-Path -Path $sibling -ChildPath 'outside.txt'
        Set-Content -LiteralPath $insidePath -Value 'inside' -Encoding ascii
        Set-Content -LiteralPath $outsidePath -Value 'outside' -Encoding ascii
        Set-Content -LiteralPath $siblingPath -Value 'outside' -Encoding ascii
    }

    It 'Reads a file inside the root' {
        Read-ThingFile -Root $root -ChildPath 'inside.txt' | Should-BeString 'inside' -TrimWhitespace
    }

    It 'Refuses <ChildPath>, which resolves outside the root' -ForEach $traversalCases {
        { Read-ThingFile -Root $root -ChildPath $ChildPath } |
            Should-Throw -FullyQualifiedErrorId 'PathOutsideRoot,Read-ThingFile'
    }

    It 'Refuses an absolute path outside the root' {
        { Read-ThingFile -Root $root -ChildPath $outsidePath } |
            Should-Throw -FullyQualifiedErrorId 'PathOutsideRoot,Read-ThingFile'
    }
}

Describe 'Connect-ThingService credential handling' -Tag 'Security' {
    BeforeAll {
        # The password is generated for each run, so the test file stores no secret.
        $secretText = [guid]::NewGuid().ToString('N')
        $password = ConvertTo-SecureString -String $secretText -AsPlainText -Force
        $credential = [System.Management.Automation.PSCredential]::new('svc-test', $password)
        $secretPattern = [regex]::Escape($secretText)
    }

    It 'Declares Credential as a PSCredential' {
        Get-Command -Name Connect-ThingService |
            Should-HaveParameter -ParameterName Credential -Type ([System.Management.Automation.PSCredential])
    }

    It 'Fails without prompting when no credential is passed' {
        Mock -CommandName Get-Credential -ModuleName ModuleName -MockWith { }
        Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith { }

        { Connect-ThingService } |
            Should-Throw -FullyQualifiedErrorId 'CredentialRequired,Connect-ThingService'

        Should-NotInvoke -CommandName Get-Credential -ModuleName ModuleName
        Should-NotInvoke -CommandName Invoke-RestMethod -ModuleName ModuleName
    }

    It 'Does not write the password to any stream' {
        Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith {
            [PSCustomObject]@{ sessionId = 'session-1' }
        }

        $output = Connect-ThingService -Credential $credential -Verbose -InformationAction Continue *>&1
        $text = $output | Out-String

        # The first assertion proves that the verbose stream was captured.
        $text | Should-MatchString 'Signing in'
        $text | Should-NotMatchString $secretPattern
    }

    It 'Does not put the password in the error when sign-in fails' {
        Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith {
            throw [System.UnauthorizedAccessException]::new('The service refused the credential.')
        }

        $failure = { Connect-ThingService -Credential $credential } |
            Should-Throw -FullyQualifiedErrorId 'SignInFailed,Connect-ThingService'

        $failure.Exception.Message | Should-NotMatchString $secretPattern
        ($failure | Out-String) | Should-NotMatchString $secretPattern
    }
}
```

## What The Template Shows

### Attack Data Is Built During Discovery

The lists that drive `-ForEach` must exist during discovery, so they are built in `BeforeDiscovery`
(TST-02). A list built in `BeforeAll` is `$null` at that point, and the outcome depends on how the
cases are derived from it:

| Cases derived from a `$null` list with | Result |
| --- | --- |
| `$list \| ForEach-Object { @{ Text = $_ } }` | One test with `$null` as its value. It can pass, and the run looks complete. |
| `foreach ($item in $list) { @{ Text = $item } }` | No cases. Discovery of the file fails. |
| `$list.ForEach({ @{ Text = $_ } })` | No cases. Discovery of the file fails. |

Do not build cases with `ForEach-Object`. Do not add `-AllowNullOrEmptyForEach` in a security test
file either: an empty list of attacks must stop the run.

To see how many tests a file produces without running them:

```powershell
$configuration = New-PesterConfiguration
$configuration.Run.Path = './Tests'
$configuration.Run.SkipRun = $true
$configuration.Run.PassThru = $true
$discovered = Invoke-Pester -Configuration $configuration
$discovered.TotalCount
```

### Attack Strings Are Quoted Literally

Write a pattern that contains `$` in single quotes. In double quotes PowerShell expands it before
the test runs, and the function receives the output of the command instead of the attack:

```powershell
# Compliant: the function receives the text
@{ Description = 'a subexpression'; Text = '$(Get-Process)' }

# Non-compliant: the function receives a list of processes
@{ Description = 'a subexpression'; Text = "$(Get-Process)" }
```

Write path separators as `/`. A backslash is a separator on Windows only, so `..\outside.txt` names
an ordinary file inside the root on Linux and macOS.

### The Unsafe Outcome Must Be Possible

A test proves a control only if it fails when the control is missing:

- The files outside the root exist. Without the check, `Read-ThingFile` would return their content
  and `Should-Throw` would fail.
- The mock of `Invoke-RestMethod` lets `Should-NotInvoke` show that a rejected name never reached
  the service. An error ID alone would not show that.
- The first assertion on the captured text shows that the verbose stream is in it. An empty capture
  would pass the second assertion without proving anything.

### No Secret Is Stored In The Test File

SEC-01 and SEC-04 apply to test files. The password is a value generated at run time, converted
with `ConvertTo-SecureString -AsPlainText` only because it is not a literal and is not stored in
source. A random value is also a better marker than a fixed one: it cannot appear in the output by
coincidence.

### Every Stream Is Captured

`*>&1` merges the error, warning, verbose, debug, and information streams into the output. The call
passes `-Verbose` and `-InformationAction Continue` so that those streams are written at all.

Do not add `-Debug` in a test that must run on Windows PowerShell 5.1. There it makes `Write-Debug`
ask for confirmation, which fails in a non-interactive session. On PowerShell 7 `-Debug` only turns
the stream on.

### A Value Used As A Pattern Is Escaped

`Should-MatchString` and `Should-NotMatchString` take a regular expression. A password or a
connection string can contain characters such as `.`, `$`, and `(`, so pass it through
`[regex]::Escape()`. An invalid pattern stops the test with an error, and a valid but unintended one
can fail to match the text it was meant to find.

### The Error Is Asserted, Not Only Caught

`Should-Throw` returns the error record, and the test asserts on its message. Do not write the
assertions in the `catch` block of a `try` statement: when the function does not throw, the block
does not run and the test passes.

### What The Function Must Not Do

For a refusal, `Should-NotInvoke` on the protected action is stronger evidence than `Should-Throw`,
because a function can throw after it has done the damage. For SEC-05, mock `Get-Credential` and
`Read-Host` in the module and assert that neither was called; the mock also keeps a defective
function from waiting for input.
