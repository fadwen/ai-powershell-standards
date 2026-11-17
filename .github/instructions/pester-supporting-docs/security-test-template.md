# Security Test Template

Use this template for validating security controls and input sanitization: test files for functions
that handle untrusted input, paths, credentials, access rights, or protected data. TST-43 requires
security tests for credential handling and input validation. The security rules that these tests
check are in the [security rules](../powershell-security.instructions.md), and the testing rules
are in the [Pester rules](../powershell-pester.instructions.md). The files below pass on Pester
6.2.0 under PowerShell 7.6 and Windows PowerShell 5.1, and each of their tests fails against a copy
of the code that has the defect it looks for.

Do not use emoji in generated code, documentation, or test output. Use plain text and standard
ASCII characters only (STY-06, TST-07).

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
        @{ ChildPath = '../../../../etc/shadow' }
    )

    # A backslash is a separator on Windows only, so these patterns are attacks there only.
    $onWindows = $PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows
    $windowsTraversalPatterns = @(
        '..\outside.txt'
        '..\..\Windows\System32\config'
        '..\..\..\secrets\passwords.txt'
        'C:\Windows\System32\SAM'
    )
    $windowsTraversalCases = $windowsTraversalPatterns.ForEach({ @{ ChildPath = $_ } })
}

BeforeAll {
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ModuleName.psd1')
    }
}

Describe 'Get-Thing input validation' -Tag 'Security', 'InputValidation' {
    BeforeEach {
        Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith { }
    }

    It 'Should reject a name that contains <Description>' -ForEach $injectionCases {
        { Get-Thing -Name $Text } |
            Should-Throw -FullyQualifiedErrorId 'ParameterArgumentValidationError,Get-Thing'

        Should-NotInvoke -CommandName Invoke-RestMethod -ModuleName ModuleName
    }
}

Describe 'Read-ThingFile path handling' -Tag 'Security', 'InputValidation' {
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

    It 'Should read a file inside the root' {
        Read-ThingFile -Root $root -ChildPath 'inside.txt' | Should-BeString 'inside' -TrimWhitespace
    }

    It 'Should refuse <ChildPath>, which resolves outside the root' -ForEach $traversalCases {
        { Read-ThingFile -Root $root -ChildPath $ChildPath } |
            Should-Throw -FullyQualifiedErrorId 'PathOutsideRoot,Read-ThingFile'
    }

    It 'Should refuse the Windows path <ChildPath>' -ForEach $windowsTraversalCases -Skip:(-not $onWindows) {
        { Read-ThingFile -Root $root -ChildPath $ChildPath } |
            Should-Throw -FullyQualifiedErrorId 'PathOutsideRoot,Read-ThingFile'
    }

    It 'Should refuse an absolute path outside the root' {
        { Read-ThingFile -Root $root -ChildPath $outsidePath } |
            Should-Throw -FullyQualifiedErrorId 'PathOutsideRoot,Read-ThingFile'
    }
}

Describe 'Connect-ThingService credential handling' -Tag 'Security', 'CredentialHandling' {
    BeforeAll {
        # The password is generated for each run, so the test file stores no secret.
        $secretText = [guid]::NewGuid().ToString('N')
        $password = ConvertTo-SecureString -String $secretText -AsPlainText -Force
        $credential = [System.Management.Automation.PSCredential]::new('svc-test', $password)
        $secretPattern = [regex]::Escape($secretText)
    }

    It 'Should declare Credential as a PSCredential' {
        Get-Command -Name Connect-ThingService |
            Should-HaveParameter -ParameterName Credential -Type ([System.Management.Automation.PSCredential])
    }

    It 'Should fail without prompting when no credential is passed' {
        Mock -CommandName Get-Credential -ModuleName ModuleName -MockWith { }
        Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith { }

        { Connect-ThingService } |
            Should-Throw -FullyQualifiedErrorId 'CredentialRequired,Connect-ThingService'

        Should-NotInvoke -CommandName Get-Credential -ModuleName ModuleName
        Should-NotInvoke -CommandName Invoke-RestMethod -ModuleName ModuleName
    }

    It 'Should validate credential authentication' {
        Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith {
            throw [System.UnauthorizedAccessException]::new('The service refused the credential.')
        }
        $validSignIn = @{
            CommandName = 'Invoke-RestMethod'
            ModuleName = 'ModuleName'
            ParameterFilter = { $Credential.UserName -eq 'svc-test' }
        }
        Mock @validSignIn -MockWith { [PSCustomObject]@{ sessionId = 'session-1' } }
        $invalidCredential = [System.Management.Automation.PSCredential]::new('svc-unknown', $password)
        $refused = @{
            FullyQualifiedErrorId = 'SignInFailed,Connect-ThingService'
            ExceptionMessage = '*Sign-in*failed*'
        }

        # The valid credential must work. With -ErrorAction Stop, any error fails the test.
        $session = Connect-ThingService -Credential $credential -ErrorAction Stop
        $session.SessionId | Should-Be 'session-1'

        # The invalid credential must fail.
        { Connect-ThingService -Credential $invalidCredential } | Should-Throw @refused
    }

    It 'Should not expose credentials in logs or output' {
        Mock -CommandName Invoke-RestMethod -ModuleName ModuleName -MockWith {
            [PSCustomObject]@{ sessionId = 'session-1' }
        }

        $output = Connect-ThingService -Credential $credential -Verbose -InformationAction Continue *>&1
        $text = $output | Out-String

        # The first assertion proves that the verbose stream was captured.
        $text | Should-MatchString 'Signing in'
        $text | Should-NotMatchString ([regex]::Escape($credential.UserName))
        $text | Should-NotMatchString $secretPattern
    }

    It 'Should not expose the password in the error when sign-in fails' {
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

## Tests Against Stand-In Functions

The example module has no e-mail parameter, credential cache, role check, encryption, or password
hashing. The tests for those controls therefore run against a small stand-in module that the
template defines itself. In a project, the functions under test are the project's own.
Comment-based help is omitted here to keep the example short.

```powershell
# Tests/TestHelpers/SecuritySample.psm1
Set-StrictMode -Version Latest

$script:credentialCache = @{}


function ConvertTo-ThingOwner {
    [CmdletBinding()]
    [OutputType('SecuritySample.Owner')]
    param(
        [Parameter(Mandatory)]
        [ValidateLength(3, 254)]
        [ValidatePattern('^[^@\s.]+(\.[^@\s.]+)*@[^@\s.]+(\.[^@\s.]+)+$')]
        [string]$EmailAddress,

        [Parameter(Mandatory)]
        [ValidateLength(1, 256)]
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
        [string]$DisplayName
    )

    [PSCustomObject]@{
        PSTypeName = 'SecuritySample.Owner'
        EmailAddress = $EmailAddress
        DisplayName = $DisplayName
    }
}


function Add-CachedCredential {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    # The cache keeps the PSCredential object, so the password stays a SecureString.
    if ($PSCmdlet.ShouldProcess($Credential.UserName, 'Cache credential')) {
        $script:credentialCache[$Credential.UserName] = $Credential
    }
}


function Get-CredentialCache {
    [CmdletBinding()]
    [OutputType('SecuritySample.CacheEntry')]
    param()

    foreach ($cachedCredential in $script:credentialCache.Values) {
        [PSCustomObject]@{
            PSTypeName = 'SecuritySample.CacheEntry'
            Credential = $cachedCredential
        }
    }
}


function Get-CurrentUserRole {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    'User'
}


function Get-CurrentSession {
    [CmdletBinding()]
    [OutputType('SecuritySample.Session')]
    param()

    # There is no session until a test supplies one.
}


function Test-PathAccess {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Test-Path -LiteralPath $Path
}


function Invoke-PrivilegedAction {
    [CmdletBinding()]
    param(
        [string]$Path = ''
    )

    Write-Verbose "The privileged action ran for '$Path'."
}


function Invoke-AdminTask {
    [CmdletBinding()]
    param(
        [ValidateSet('User', 'Administrator')]
        [string]$RequiredRole = 'Administrator',

        [string]$Path = '',

        [switch]$RequireValidSession
    )

    $denial = $null
    if ($RequireValidSession) {
        $session = Get-CurrentSession
        if ($null -eq $session -or -not $session.Valid) {
            $denial = 'InvalidSession', 'Access denied: invalid session.'
        }
    }

    if ($null -eq $denial -and (Get-CurrentUserRole) -ne $RequiredRole) {
        $denial = 'InsufficientPrivileges', 'Access denied: insufficient privileges.'
    }

    if ($null -eq $denial -and $Path -and -not (Test-PathAccess -Path $Path)) {
        $denial = 'PathAccessDenied', 'Access denied to the path.'
    }

    if ($null -ne $denial) {
        $exception = [System.UnauthorizedAccessException]::new($denial[1])
        $category = [System.Management.Automation.ErrorCategory]::PermissionDenied
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, $denial[0], $category, $Path)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    Invoke-PrivilegedAction -Path $Path
}


function Protect-ThingData {
    [CmdletBinding()]
    [OutputType('SecuritySample.ProtectedData')]
    param(
        [Parameter(Mandatory)]
        [string]$Data,

        [Parameter(Mandatory)]
        [ValidateCount(32, 32)]
        [byte[]]$Key
    )

    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.Key = $Key
        $aes.GenerateIV()
        $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($Data)
        $cipherBytes = $aes.CreateEncryptor().TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
        $initializationVector = $aes.IV
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    } finally {
        $aes.Dispose()
    }

    [PSCustomObject]@{
        PSTypeName = 'SecuritySample.ProtectedData'
        EncryptedData = [System.Convert]::ToBase64String($cipherBytes)
        EncryptionAlgorithm = 'AES-256-CBC'
        IV = [System.Convert]::ToBase64String($initializationVector)
    }
}


function Invoke-SecureTransmission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Payload,

        [Parameter(Mandatory)]
        [uri]$Endpoint
    )

    try {
        $null = Invoke-RestMethod -Uri $Endpoint -Method Post -Body $Payload -ErrorAction Stop
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}


function Send-ThingData {
    [CmdletBinding()]
    [OutputType('SecuritySample.TransmissionResult')]
    param(
        [Parameter(Mandatory)]
        [string]$Data,

        [Parameter(Mandatory)]
        [ValidateCount(32, 32)]
        [byte[]]$Key,

        [Parameter(Mandatory)]
        [uri]$Endpoint
    )

    $protectedData = Protect-ThingData -Data $Data -Key $Key
    Invoke-SecureTransmission -Payload $protectedData.EncryptedData -Endpoint $Endpoint

    [PSCustomObject]@{
        PSTypeName = 'SecuritySample.TransmissionResult'
        Success = $true
        Encrypted = $true
    }
}


function ConvertTo-PasswordHash {
    [CmdletBinding()]
    [OutputType('SecuritySample.PasswordHash')]
    param(
        [Parameter(Mandatory)]
        [System.Security.SecureString]$Password
    )

    $salt = [byte[]]::new(16)
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($salt)
        $plainText = [System.Net.NetworkCredential]::new('', $Password).Password
        $deriveBytes = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
            $plainText, $salt, 100000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
        $hash = $deriveBytes.GetBytes(32)
        $deriveBytes.Dispose()
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    } finally {
        $generator.Dispose()
    }

    [PSCustomObject]@{
        PSTypeName = 'SecuritySample.PasswordHash'
        HashedPassword = [System.Convert]::ToBase64String($hash)
        Salt = [System.Convert]::ToBase64String($salt)
        Algorithm = 'PBKDF2'
    }
}
```

The test file for these functions:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    $invalidEmailPatterns = @(
        'notanemail'
        '@domain.com'
        'user@'
        'user..name@domain.com'
        'user@domain'
    )
    $invalidEmailCases = $invalidEmailPatterns.ForEach({ @{ InvalidEmail = $_ } })
}

BeforeAll {
    $helperPath = Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers'
    if (-not (Get-Module -Name SecuritySample)) {
        Import-Module -Name (Join-Path -Path $helperPath -ChildPath 'SecuritySample.psm1')
    }

    # The password is generated for each run, so the test file stores no secret.
    $secretText = [guid]::NewGuid().ToString('N')
    $password = ConvertTo-SecureString -String $secretText -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new('cache-test', $password)
    $secretPattern = [regex]::Escape($secretText)
}

Describe 'ConvertTo-ThingOwner input validation' -Tag 'Security', 'InputValidation' {
    BeforeAll {
        $rejectedAddress = @{
            FullyQualifiedErrorId = 'ParameterArgumentValidationError,ConvertTo-ThingOwner'
            ExceptionMessage = '*EmailAddress*'
        }
        $rejectedName = @{
            FullyQualifiedErrorId = 'ParameterArgumentValidationError*,ConvertTo-ThingOwner'
            ExceptionMessage = '*DisplayName*'
        }
    }

    It 'Should accept a valid address and name' {
        $owner = ConvertTo-ThingOwner -EmailAddress 'ann@example.com' -DisplayName 'Ann'

        $owner.EmailAddress | Should-Be 'ann@example.com'
    }

    It 'Should reject invalid email format: <InvalidEmail>' -ForEach $invalidEmailCases {
        { ConvertTo-ThingOwner -EmailAddress $InvalidEmail -DisplayName 'Ann' } |
            Should-Throw @rejectedAddress
    }

    It 'Should validate parameter length limits' {
        $oversizedInput = 'x' * 10000

        { ConvertTo-ThingOwner -EmailAddress 'ann@example.com' -DisplayName $oversizedInput } |
            Should-Throw @rejectedName
    }

    It 'Should reject <Description> input' -ForEach @(
        @{ Description = 'null'; Value = $null }
        @{ Description = 'empty'; Value = '' }
        @{ Description = 'whitespace-only'; Value = '   ' }
    ) {
        { ConvertTo-ThingOwner -EmailAddress 'ann@example.com' -DisplayName $Value } |
            Should-Throw @rejectedName
    }
}

Describe 'Credential caching' -Tag 'Security', 'CredentialHandling' {
    It 'Should implement secure credential caching' {
        Add-CachedCredential -Credential $credential

        $cacheContent = @(Get-CredentialCache)
        if ($cacheContent.Count -eq 0) {
            Set-ItResult -Inconclusive -Because 'no credential cache was produced to inspect'
        }

        $cacheText = $cacheContent | Format-List -Property * | Out-String
        $cacheText | Should-MatchString 'Credential'
        $cacheText | Should-NotMatchString $secretPattern
        $cacheText | Should-NotMatchString ([regex]::Escape($credential.UserName))
    }
}

Describe 'Invoke-AdminTask access control' -Tag 'Security', 'AccessControl' {
    BeforeEach {
        Mock -CommandName Get-CurrentUserRole -ModuleName SecuritySample -MockWith { 'Administrator' }
        Mock -CommandName Invoke-PrivilegedAction -ModuleName SecuritySample -MockWith { }
    }

    It 'Should deny access when the role is insufficient' {
        Mock -CommandName Get-CurrentUserRole -ModuleName SecuritySample -MockWith { 'User' }
        $denied = @{
            FullyQualifiedErrorId = 'InsufficientPrivileges,Invoke-AdminTask'
            ExceptionMessage = '*insufficient privileges*'
        }

        { Invoke-AdminTask -RequiredRole 'Administrator' } | Should-Throw @denied

        # The assertion that matters: the action never ran.
        Should-NotInvoke -CommandName Invoke-PrivilegedAction -ModuleName SecuritySample
    }

    It 'Should allow access when the role is sufficient' {
        Invoke-AdminTask -RequiredRole 'Administrator' -ErrorAction Stop

        Should-Invoke -CommandName Invoke-PrivilegedAction -ModuleName SecuritySample -Times 1 -Exactly
    }

    It 'Should validate file system permissions' {
        Mock -CommandName Test-PathAccess -ModuleName SecuritySample -MockWith { $false }
        $restrictedPath = Join-Path -Path $TestDrive -ChildPath 'restricted'
        $denied = @{
            FullyQualifiedErrorId = 'PathAccessDenied,Invoke-AdminTask'
            ExceptionMessage = '*access denied*'
        }

        { Invoke-AdminTask -Path $restrictedPath } | Should-Throw @denied

        Should-NotInvoke -CommandName Invoke-PrivilegedAction -ModuleName SecuritySample
    }

    It 'Should reject an invalid session' {
        Mock -CommandName Get-CurrentSession -ModuleName SecuritySample -MockWith { }
        $denied = @{
            FullyQualifiedErrorId = 'InvalidSession,Invoke-AdminTask'
            ExceptionMessage = '*invalid session*'
        }

        { Invoke-AdminTask -RequireValidSession } | Should-Throw @denied

        Should-NotInvoke -CommandName Invoke-PrivilegedAction -ModuleName SecuritySample
    }

    It 'Should accept a valid session' {
        Mock -CommandName Get-CurrentSession -ModuleName SecuritySample -MockWith {
            [PSCustomObject]@{ Valid = $true; UserId = 'test-user' }
        }

        Invoke-AdminTask -RequireValidSession -ErrorAction Stop

        Should-Invoke -CommandName Invoke-PrivilegedAction -ModuleName SecuritySample -Times 1 -Exactly
    }
}

Describe 'Data protection' -Tag 'Security', 'DataProtection' {
    BeforeAll {
        # The key is generated for each run as well.
        $key = [byte[]]::new(32)
        $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $generator.GetBytes($key)
        $generator.Dispose()
    }

    It 'Should encrypt sensitive data at rest' {
        $sensitiveData = 'Confidential Information 12345'

        $result = Protect-ThingData -Data $sensitiveData -Key $key

        # The data is encrypted: it is not plain text, and not plain text in another encoding.
        $result.EncryptedData | Should-NotBeEmptyString
        $result.EncryptedData | Should-NotMatchString 'Confidential Information'
        $storedBytes = [System.Convert]::FromBase64String($result.EncryptedData)
        [System.Text.Encoding]::UTF8.GetString($storedBytes) | Should-NotMatchString 'Confidential Information'

        # The encryption metadata is present.
        $result.EncryptionAlgorithm | Should-Be 'AES-256-CBC'
        $result.IV | Should-NotBeEmptyString
    }

    It 'Should implement secure data transmission' {
        Mock -CommandName Invoke-SecureTransmission -ModuleName SecuritySample -MockWith { }
        $serviceEndpoint = 'https://api.example.test/'

        $result = Send-ThingData -Data 'Sensitive transmission data' -Key $key -Endpoint $serviceEndpoint

        $result.Success | Should-BeTrue
        $result.Encrypted | Should-BeTrue
        $encryptedTransmission = @{
            CommandName = 'Invoke-SecureTransmission'
            ModuleName = 'SecuritySample'
            ParameterFilter = { $Payload -and $Payload -notmatch 'Sensitive transmission data' }
        }
        Should-Invoke @encryptedTransmission -Times 1 -Exactly
    }

    It 'Should securely hash passwords' {
        $result = ConvertTo-PasswordHash -Password $password
        $second = ConvertTo-PasswordHash -Password $password

        # The password is hashed, not stored as plain text.
        $result.HashedPassword | Should-NotBeEmptyString
        $result.HashedPassword | Should-NotMatchString $secretPattern

        # A salt is used, so the same password gives a different hash each time.
        $result.Salt | Should-NotBeEmptyString
        $second.HashedPassword | Should-NotBe $result.HashedPassword

        # The algorithm is an accepted one. There is no Should-BeIn; Should-Any over the list
        # states the same thing.
        'SHA256', 'SHA512', 'bcrypt', 'scrypt', 'PBKDF2' | Should-Any { $_ -eq $result.Algorithm }
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

Turn a list of patterns into cases with the `.ForEach()` method, as the Windows paths and the
e-mail addresses do. Write the hashtables directly, as the injection cases do, when a case needs a
description beside its value. Do not build cases with `ForEach-Object`. Do not add
`-AllowNullOrEmptyForEach` in a security test file either: an empty list of attacks must stop the
run.

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

### Both Kinds Of Path Separator Are Tested

A pattern written with `/` is an attack on every platform. A pattern written with `\`, and a
Windows absolute path such as `C:\Windows\System32\SAM`, is an attack on Windows only: a backslash
is a separator there and an ordinary character on Linux and macOS, where `..\outside.txt` names a
file inside the root. The template therefore keeps the two lists apart and skips the Windows list
on other platforms. A function that is tested with one kind of separator only can still be open to
the other.

### The Unsafe Outcome Must Be Possible

A test proves a control only if it fails when the control is missing:

- The files outside the root exist. Without the check, `Read-ThingFile` would return their content
  and `Should-Throw` would fail.
- The mock of `Invoke-RestMethod` lets `Should-NotInvoke` show that a rejected name never reached
  the service. An error ID alone would not show that.
- The first assertion on the captured text shows that the verbose stream is in it. An empty capture
  would pass the second assertion without proving anything.
- A valid address and name are accepted, so the rejections are not the work of a function that
  rejects everything.
- The encryption test also decodes the stored value. A function that only encoded the text as
  Base64 passed the test without that assertion.

### No Secret Is Stored In The Test File

SEC-01 and SEC-04 apply to test files. The password is a value generated at run time, converted
with `ConvertTo-SecureString -AsPlainText` only because it is not a literal and is not stored in
source. A random value is also a better marker than a fixed one: it cannot appear in the output by
coincidence. The encryption key is generated the same way.

### Every Stream Is Captured

`*>&1` merges the error, warning, verbose, debug, and information streams into the output. The call
passes `-Verbose` and `-InformationAction Continue` so that those streams are written at all. The
test then asserts that neither the user name nor the password is in the captured text.

Do not add `-Debug` in a test that must run on Windows PowerShell 5.1. There it makes `Write-Debug`
ask for confirmation, which fails in a non-interactive session. On PowerShell 7 `-Debug` only turns
the stream on.

### A Value Used As A Pattern Is Escaped

`Should-MatchString` and `Should-NotMatchString` take a regular expression. A password or a
connection string can contain characters such as `.`, `$`, `(`, and `\`, so pass it through
`[regex]::Escape()`. Measured on Pester 6.2.0 with `Should-NotMatchString`:

| Unescaped value | What happens |
| --- | --- |
| `Pa$$w0rd`, in a text that contains it | The assertion passes. `$` anchors the pattern, so the leak is not found. |
| `db.example`, in a text that contains `dbXexample` | The assertion fails. `.` matches any character, so other text is reported as the secret. |
| `abc(def` | The test stops with an error about an invalid pattern. |

### The Error Is Asserted, Not Only Caught

`Should-Throw` returns the error record, and the test asserts on its message. Do not write the
assertions in the `catch` block of a `try` statement: when the function does not throw, the block
does not run and the test passes.

A rejection is asserted by its error ID. Where the message is part of what the caller sees, the
same call adds a message pattern, which needs wildcards: `-ExceptionMessage '*access denied*'`.
For a parameter that a validation attribute rejects, the pattern names the parameter, because
several parameters share the error ID `ParameterArgumentValidationError`.

### Both Outcomes Of A Sign-In

The sign-in test proves that a valid credential works and that an invalid one fails. There is no
`Should-NotThrow`: the valid call is made directly with `-ErrorAction Stop`, and any error fails
the test (TST-16).

### What The Function Must Not Do

For a refusal, `Should-NotInvoke` on the protected action is stronger evidence than `Should-Throw`,
because a function can throw after it has done the damage. The access-control tests assert both for
a role, a path, and a session. For SEC-05, mock `Get-Credential` and `Read-Host` in the module and
assert that neither was called; the mock also keeps a defective function from waiting for input.

### The Shape Of An Object

There is no `Should -HaveProperty` operator in Pester, and no `Should-HaveProperty` assertion.
Assert the shape instead: the count, and then the properties of every item.

```powershell
$records | Should-BeCollection -Count 5
$records | Should-All { $null -ne $_.UserId -and $null -ne $_.Action -and $null -ne $_.Timestamp }
```

### A Test That Has Nothing To Inspect

The caching test calls `Set-ItResult -Inconclusive` when no cache was produced. The test is then
reported as inconclusive, not as passed, so a missing cache cannot look like a safe one.

## Security Test Guidelines

### Input Validation Testing

- Test all forms of malicious input.
- Validate parameter length limits.
- Test encoding and special characters.
- Verify path traversal prevention.
- Test command injection attempts.

### Credential Security Testing

- Verify that credentials are never exposed in logs or output.
- Test `SecureString` handling.
- Validate authentication mechanisms.
- Test the security of credential caching.
- Verify secure transmission of credentials.

### Access Control Testing

- Test role-based access control.
- Validate file system permissions.
- Test session management.
- Verify that authorization is enforced.
- Test the prevention of privilege escalation.

### Data Protection Testing

- Test encryption at rest and in transit.
- Validate secure data handling.
- Test password hashing algorithms.
- Verify secure deletion methods.
- Test data anonymization features.

### Error Handling Security

- Ensure that error messages hold no sensitive data.
- Test what information an error discloses.
- Test error handling under attack conditions.
- Verify graceful failure modes.
