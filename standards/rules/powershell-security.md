# PowerShell security: secrets, credentials, input, execution

These rules apply to every `.ps1` and `.psm1` file.

## Rules

### Secrets and credentials

- **SEC-01** Secrets MUST NOT appear in source: no passwords, tokens, keys, or connection strings in
  code, parameter defaults, comments, or example values.
- **SEC-02** Get a secret at run time from the caller or from a secret store: a `[PSCredential]`
  parameter, `Get-Secret` from Microsoft.PowerShell.SecretManagement, or a secret that the CI system
  injects.
- **SEC-03** Accept a credential as a `[PSCredential]` parameter carrying the
  `[System.Management.Automation.Credential()]` attribute. A password MUST NOT be accepted as a
  `[string]` parameter.
- **SEC-04** `ConvertTo-SecureString -AsPlainText` MUST NOT be applied to a literal or to a value
  stored in source.
- **SEC-05** A function or an unattended script MUST NOT fall back to an interactive prompt
  (`Get-Credential`, `Read-Host`) when a credential or value is missing. It fails with an error that
  names what is missing.
- **SEC-06** Secrets and personal data MUST NOT be written to any stream, log, error message, or
  file. This includes dumping `$PSBoundParameters` or a whole input object.
- **SEC-07** A `SecureString` MUST NOT be decrypted to plain text unless it is absolutely
  necessary. When it is, decrypt only during the method call that needs the value:
  `$connection.SetCredential($Credential.GetNetworkCredential())`.
- **SEC-08** Hold sensitive data in a `SecureString`. A script that a person runs interactively
  reads it with `Read-Host -AsSecureString`; a function or an unattended script does not prompt
  (SEC-05).
- **SEC-09** A web request that carries a credential MUST pass `-MaximumRedirection 0`, so that a
  redirect is an error, and MUST NOT be paged with `-FollowRelLink`. Follow a redirect or a link in
  the function, and send the credential again only when the address has the scheme, host, and port
  of the first request.

### Input and execution

- **SEC-10** Commands MUST NOT be built from strings: no `Invoke-Expression`, and no
  `[scriptblock]::Create()` on text that includes input. Pass arguments with splatting, or as an
  array for a native executable.
- **SEC-11** Treat input from outside the script as untrusted, and validate it at every entry
  point. Constrain it at the parameter with an allow-list (`ValidateSet`, or an anchored
  `ValidatePattern`), not by removing bad characters. Sanitize data that an allow-list cannot
  constrain before it reaches a path, a command, or a query (SEC-10, SEC-12, SEC-13).
- **SEC-12** Before using a path that comes from input, resolve it to a full path and confirm that it
  stays inside the folder it is allowed in.
- **SEC-13** Send values to SQL, LDAP, and similar query languages as parameters. Input MUST NOT be
  concatenated or interpolated into query text.
- **SEC-14** TLS certificate validation MUST NOT be disabled, whether with `-SkipCertificateCheck` or
  with a validation callback that always succeeds.
- **SEC-15** Access controls MUST follow the principle of least privilege. Code MUST NOT change the
  execution policy or require elevation that the task does not need. Declare a real need for
  elevation with `#requires -RunAsAdministrator`.
- **SEC-16** Limit the length of text input such as a name, a path, or an address. A value longer
  than 1000 characters MUST be rejected.
- **SEC-17** Check a file name that comes from input against
  `[System.IO.Path]::GetInvalidFileNameChars()`, and reject it when it contains one of them.
- **SEC-18** Check input for common injection tokens, and reject a value that contains one: `;`,
  `&`, `|`, `<`, `>`, a backtick, `$(`, `Invoke-`, `iex`, `Remove-`, or `Format-`. An allow-list
  (SEC-11) that admits none of them already makes this check. The check never replaces SEC-10.
- **SEC-19** Input that does not arrive through a parameter, such as a line of a file or a field of
  a reply, MUST be validated in the function body before it is used, by one helper function that
  applies these checks.

### Security assessment

- **SEC-20** Choose the security controls for code by the classification of what it handles:
  Public, Internal, Confidential, Restricted, or Top Secret.
- **SEC-21** Identify the threats to the code with the STRIDE model, and mitigate each threat that
  applies.

### Code signing

- **SEC-30** Sign only files that exist and have an approved extension: `.ps1`, `.psm1`, `.psd1`,
  or `.ps1xml`.
- **SEC-31** Before signing, confirm that the signing certificate exists at
  `Cert:\CurrentUser\My\<thumbprint>`, and fail when it does not.
- **SEC-32** Sign with `Set-AuthenticodeSignature`, passing the certificate with `-Certificate` and
  a timestamp server with `-TimestampServer`.
- **SEC-33** Count a file as signed only when the signature that is returned has the status `Valid`.
- **SEC-34** Run a security scan on a file before signing it. A file in which the scan finds a
  Critical or High issue MUST NOT be signed.
- **SEC-35** Take the certificate and the timestamp server from the code-signing configuration of
  the environment, and fail when the environment has none.

### Security scan

- **SEC-40** Scan source for credential leaks and injection risks with the patterns in the notes. A
  match is a candidate to read, not yet a finding.
- **SEC-41** Flag `Add-Type -TypeDefinition`, which compiles a type at run time, as a Medium risk.
- **SEC-42** Give each finding a risk tier, Critical, High, Medium, or Low, and report the overall
  risk as the highest tier found.

### Secret vault

- **SEC-50** Call `Get-Secret` with an explicit `-Vault`, and with `-AsPlainText:$false` or without
  `-AsPlainText`.
- **SEC-51** Rate-limit the retrieval of a credential to prevent brute force: count the attempts for
  its name in the last hour, and refuse the retrieval once the limit is exceeded.
- **SEC-52** Before storing a credential, validate its strength against the security level it is
  stored for: `Low`, `Medium`, `High`, or `Critical`. A credential that fails MUST NOT be stored.
- **SEC-53** Store a credential with `Set-Secret` in a named vault, and record with `-Metadata` who
  stored it, when, and at which security level.

## Notes and examples

**SEC-03.** The attribute lets a caller pass either a `PSCredential` or a user name, and the default
keeps the parameter optional:

```powershell
param(
    [Parameter()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty
)
```

**SEC-04.** A value that arrives at run time, such as a secret that the CI system injects (SEC-02),
is converted and wrapped in a credential like this:

```powershell
$securePassword = ConvertTo-SecureString -String $env:REPORTING_API_PASSWORD -AsPlainText -Force
$credential = [PSCredential]::new($userName, $securePassword)
```

**SEC-02, SEC-05, SEC-50.** Name the vault, and fail clearly when the secret is not available.
Without `-Vault`, `Get-Secret` searches every registered vault. `-AsPlainText:$false` states that a
string secret stays a `SecureString`:

```powershell
try {
    $apiCredential = Get-Secret -Name 'ReportingApi' -Vault $VaultName -AsPlainText:$false -ErrorAction Stop
} catch {
    $PSCmdlet.ThrowTerminatingError($_)
}
```

SEC-05 covers functions and unattended scripts. A script that a person runs at a console may fall
back to a prompt when the vault has no entry, after a warning:

```powershell
Write-Warning 'Credential not found in secure vault. Interactive prompt required.'
$credential = Get-Credential -Message "Enter credentials for: $Name"
```

**SEC-06.** Log that a value is present, not the value:

```powershell
# Compliant
Write-Verbose "Using API token: $(-not [string]::IsNullOrEmpty($ApiToken))"

# Non-compliant
Write-Verbose "Using API token $ApiToken"
Write-Debug ($PSBoundParameters | ConvertTo-Json)
```

When named values are written to a message, leave out each value whose name matches
`(password|secret|key|token|credential)`:

```powershell
$safeContext = @{}
foreach ($key in $context.Keys) {
    if ($key -notmatch '(password|secret|key|token|credential)') {
        $safeContext[$key] = $context[$key]
    }
}
```

**SEC-09.** Measured on PowerShell 7.6.10 and 7.7.0, against a local server that answers as two
hosts:

| Where the request goes | `Authorization` header | A key in another header, such as `X-Api-Key` |
| --- | --- | --- |
| A link followed by `-FollowRelLink` | Not sent, since PowerShell 7.6.5 | Sent, to another host as well |
| The same with `-PreserveAuthorizationOnRedirect` | Sent, to another host as well | Sent, to another host as well |
| The target of a redirect | Not sent | Sent, to another host as well |

With `-FollowRelLink` alone, every page after the first is requested as an anonymous caller. The
service refuses, or answers with only what an anonymous caller may see, and then no error is raised.
With `-PreserveAuthorizationOnRedirect`, the credential goes wherever a reply points. Windows
PowerShell 5.1 has no `-FollowRelLink`, and it treats a redirect as the last row says.

A redirect does the same to any request, paged or not: the cmdlet follows it without the
`Authorization` header, to the same host as well. The caller gets an error where the address needs
the credential, and the answer for an anonymous caller, with no error, where it does not. A key in
another header goes with the redirect to any host. A credential passed as `-Credential` alone was
not sent to the other host, and that request ended with an error.

With `-MaximumRedirection 0`, no request reaches the address that the redirect names, on all three
versions. PowerShell 7 raises the refused redirect as an error whose exception carries the reply,
with the address in `Response.Headers.Location`. Windows PowerShell 5.1, and PowerShell 7 with
`-SkipHttpErrorCheck`, return the reply, with the address in `Headers['Location']`, and write a
non-terminating error, so `-ErrorAction Stop` loses the address. A service that redirects by
design, such as a download that answers with a signed address on another host, is followed in the
function, and the credential goes with it only to the scheme, host, and port of the first request.

The function below follows the links itself and lets no redirect be followed. `$Request` holds the
parameters of `Invoke-WebRequest`, the credential among them. The function and its tests are files
in the standards repository, under `standards/examples`:

<!-- include: standards/examples/Get-PagedResponse.ps1 -->

Run on PowerShell 7.7.0, PowerShell 7.6.10, and Windows PowerShell 5.1 under strict mode, against the
same server. Three pages arrived with the credential on each, whether the link was absolute or
relative, stood among other relations, or came in a header named `link`. Each of these ended the
function with an error and without a further request: a next link on another host, a next link
back to the first page, and a redirect, at the first page or at a later one. The function reports
the redirect as `PageRedirected` on all three versions, where the errors of the cmdlet differ. A
body with the content type `application/vnd.api+json` arrived as text, where `Invoke-WebRequest`
returns bytes.

**SEC-10.** Arguments passed as an array reach a native executable as separate arguments, so input
cannot add switches or commands:

```powershell
# Compliant
$gitArguments = @('clone', '--depth', '1', '--', $RepositoryUrl, $destinationPath)
& git @gitArguments

# Non-compliant
Invoke-Expression "git clone --depth 1 $RepositoryUrl $destinationPath"
```

**SEC-11, SEC-16, SEC-17.** Anchor a pattern at both ends, or a match anywhere in the value passes:

```powershell
param(
    # Accepts a fully qualified name. For one label of at most 63 characters, without dots,
    # use '^[A-Za-z0-9][A-Za-z0-9-]{0,62}$'.
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9\-\.]+$')]
    [string]$ComputerName,

    [Parameter(Mandatory)]
    [ValidateLength(1, 1000)]
    [ValidateScript({ $_.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -lt 0 })]
    [string]$FileName
)
```

**SEC-18, SEC-19.** One helper applies the checks to input that has no parameter. `-like` cannot
make the token check: in a wildcard pattern a backtick escapes the next character, so the pattern
for a backtick finds an asterisk and misses a backtick.

```powershell
function Protect-UserInput {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$InputString,

        [Parameter()]
        [ValidateSet('General', 'ComputerName', 'FileName', 'EmailAddress')]
        [string]$InputType = 'General'
    )

    $injectionTokens = @(';', '&', '|', '<', '>', '`', '$(', 'Invoke-', 'iex', 'Remove-', 'Format-')
    $invalidFileNameChars = [System.IO.Path]::GetInvalidFileNameChars()
    $problem = $null
    if ($InputString.Length -gt 1000) {
        $problem = 'Input exceeds maximum length of 1000 characters.'
    } elseif ($InputType -eq 'ComputerName' -and $InputString -notmatch '^[a-zA-Z0-9\-\.]+$') {
        $problem = 'Invalid computer name format.'
    } elseif ($InputType -eq 'FileName' -and $InputString.IndexOfAny($invalidFileNameChars) -ge 0) {
        $problem = 'Invalid file name character.'
    } elseif ($InputType -eq 'EmailAddress' -and
        $InputString -notmatch '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
        $problem = 'Invalid email address format.'
    } else {
        foreach ($token in $injectionTokens) {
            if ($InputString.IndexOf($token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $problem = "Input contains potentially dangerous pattern: $token"
                break
            }
        }
    }

    if ($null -ne $problem) {
        $exception = [System.ArgumentException]::new($problem)
        $category = [System.Management.Automation.ErrorCategory]::InvalidArgument
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'InputRejected', $category, $null)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $InputString.Trim()
}
```

The error does not carry the rejected value (SEC-06). A path is checked as SEC-12 says.

**SEC-12.** Checking for `..` after a path has been resolved proves nothing, because a resolved path
never contains it. Compare the resolved path with the resolved root instead:

```powershell
function Test-PathInRoot {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$ChildPath
    )

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd($separator) + $separator
    $candidate = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootFull, $ChildPath))
    $comparison = if ($separator -eq '\') {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }

    $candidate.StartsWith($rootFull, $comparison)
}
```

`Root` must already be an absolute path. The function returns `$false` for `..\secret.txt`, for an
absolute path outside the root, and for a sibling folder whose name starts with the root's name.

**SEC-13.** A parameterized query keeps the value out of the query text:

```powershell
$command = $connection.CreateCommand()
$command.CommandText = 'SELECT Id, Name FROM dbo.Customer WHERE Region = @region'
$null = $command.Parameters.AddWithValue('@region', $Region)
```

**SEC-20.** The classification levels:

| Classification | What it means |
| --- | --- |
| Public | No restrictions; publicly accessible code |
| Internal | Internal use only; basic access controls required |
| Confidential | Sensitive data; enhanced protection required |
| Restricted | Highly sensitive; strict access controls mandatory |
| Top Secret | Maximum security; compartmentalized access |

**SEC-21.** The STRIDE threats and the controls that answer them:

| Threat | Controls |
| --- | --- |
| Spoofing | Identity verification and authentication controls |
| Tampering | Data integrity and code signing requirements |
| Repudiation | Audit logging and non-repudiation controls |
| Information disclosure | Data protection and access controls |
| Denial of service | Availability and resilience measures |
| Elevation of privilege | Authorization and privilege management |

### Code signing (SEC-30 to SEC-35)

`Get-CodeSigningConfiguration` and `Invoke-SecurityScan` stand for the project's own commands. The
configuration of an environment holds `CertificateThumbprint` and `TimestampServer`.

```powershell
function Invoke-CodeSigning {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('Example.SignedFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$FilePath,

        [Parameter()]
        [string]$Environment = 'Development'
    )

    begin {
        $allowedExtensions = @('.ps1', '.psm1', '.psd1', '.ps1xml')
        try {
            # SEC-35: fails when the environment has no signing configuration
            $signingConfig = Get-CodeSigningConfiguration -Environment $Environment -ErrorAction Stop
            # SEC-31: fails when the certificate is not in the store
            $certificatePath = "Cert:\CurrentUser\My\$($signingConfig.CertificateThumbprint)"
            $certificate = Get-Item -LiteralPath $certificatePath -ErrorAction Stop
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }

    process {
        foreach ($file in $FilePath) {
            $problem = $null
            $signature = $null
            try {
                $fileInfo = Get-Item -LiteralPath $file -ErrorAction Stop
                if ($fileInfo.Extension -notin $allowedExtensions) {
                    # SEC-30
                    $problem = "File type not approved for signing: $($fileInfo.Extension)"
                } else {
                    # SEC-34
                    $scanResult = Invoke-SecurityScan -FilePath $file -ErrorAction Stop
                    if ($scanResult.OverallRisk -in 'Critical', 'High') {
                        $problem = 'Security scan failed: high risk issues found.'
                    } elseif ($PSCmdlet.ShouldProcess($file, 'Sign')) {
                        # SEC-32
                        $signParameters = @{
                            LiteralPath = $file
                            Certificate = $certificate
                            TimestampServer = $signingConfig.TimestampServer
                            ErrorAction = 'Stop'
                        }
                        $signature = Set-AuthenticodeSignature @signParameters
                        if ($signature.Status -ne 'Valid') {
                            # SEC-33
                            $problem = "Signature status is $($signature.Status), not Valid."
                        }
                    }
                }
            } catch {
                $PSCmdlet.WriteError($_)
                continue
            }

            if ($null -ne $problem) {
                $exception = [System.InvalidOperationException]::new("$problem File: '$file'.")
                $category = [System.Management.Automation.ErrorCategory]::InvalidOperation
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'FileNotSigned', $category, $file)
                $PSCmdlet.WriteError($errorRecord)
                continue
            }

            if ($null -ne $signature) {
                [PSCustomObject]@{
                    PSTypeName = 'Example.SignedFile'
                    FilePath = $file
                    SignatureStatus = $signature.Status
                    SignerCertificate = $signature.SignerCertificate.Thumbprint
                    SignedAt = Get-Date
                }
            }
        }
    }
}
```

Each signed file gives one object and each file that is not signed gives one error, so the caller
can count both. The sample was run with stand-ins for the certificate and the signing command; no
file was signed with it.

### Security scan (SEC-40 to SEC-42)

```powershell
$scanPatterns = @(
    @{ Risk = 'Critical'; Pattern = '(?i)(password|pwd|pass)\s*[:=]\s*["'']?[^"''\s]{8,}' }
    @{ Risk = 'Critical'; Pattern = '(?i)(api[_-]?key|apikey)\s*[:=]\s*["'']?[a-zA-Z0-9]{20,}' }
    @{ Risk = 'High'; Pattern = '(?i)(secret|token)\s*[:=]\s*["'']?[a-zA-Z0-9]{16,}' }
    @{ Risk = 'High'; Pattern = 'ConvertTo-SecureString\s+-String\s+["''][^"'']+["'']' }
    @{ Risk = 'High'; Pattern = 'Invoke-Expression' }
    @{ Risk = 'High'; Pattern = 'iex\s' }
    @{ Risk = 'Medium'; Pattern = 'Add-Type.*-TypeDefinition' }
)
```

The first three flag a password of 8 or more characters, an API key of 20 or more, and a secret or
token of 16 or more. In a single-quoted string a quote character is written twice; `\'` ends the
string. The password pattern also matches `$password = Get-Secret -Name Db`, so read a match before
reporting it.

### Secret vault (SEC-50 to SEC-53)

The `Get-Secret` call for SEC-50 is the sample under SEC-02 above.

**SEC-51.** Run the check before `Get-Secret`, and end the function when the limit is exceeded, with
an error such as `Credential access rate limit exceeded for: <name>`. These rules set no limit; the
project chooses it.

**SEC-52, SEC-53.** `Test-CredentialSecurity` stands for the project's own strength check:

```powershell
$validation = Test-CredentialSecurity -Credential $Credential -SecurityLevel $SecurityLevel
if (-not $validation.IsValid) {
    $message = "Credential does not meet security requirements: $($validation.Errors -join '; ')"
    $exception = [System.ArgumentException]::new($message)
    $category = [System.Management.Automation.ErrorCategory]::InvalidArgument
    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $exception, 'CredentialTooWeak', $category, $Name)
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}

$metadata = @{
    StoredBy = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    StoredAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    SecurityLevel = $SecurityLevel
}
if ($PSCmdlet.ShouldProcess($Name, 'Store credential')) {
    try {
        Set-Secret -Name $Name -Secret $Credential -Vault $VaultName -Metadata $metadata -ErrorAction Stop
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
```

The help of `Set-Secret` says that a metadata value must be a string, an integer, or a `DateTime`,
and that the call fails when the vault does not support metadata.
