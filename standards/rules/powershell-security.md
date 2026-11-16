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

### Input and execution

- **SEC-10** Commands MUST NOT be built from strings: no `Invoke-Expression`, and no
  `[scriptblock]::Create()` on text that includes input. Pass arguments with splatting, or as an
  array for a native executable.
- **SEC-11** Treat input from outside the script as untrusted. Constrain it at the parameter with an
  allow-list (`ValidateSet`, or an anchored `ValidatePattern`), not by removing bad characters.
- **SEC-12** Before using a path that comes from input, resolve it to a full path and confirm that it
  stays inside the folder it is allowed in.
- **SEC-13** Send values to SQL, LDAP, and similar query languages as parameters. Input MUST NOT be
  concatenated or interpolated into query text.
- **SEC-14** TLS certificate validation MUST NOT be disabled, whether with `-SkipCertificateCheck` or
  with a validation callback that always succeeds.
- **SEC-15** Code MUST NOT change the execution policy or require elevation that the task does not
  need. Declare a real need for elevation with `#requires -RunAsAdministrator`.

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

**SEC-02, SEC-05.** Fail clearly when the secret is not available:

```powershell
try {
    $apiCredential = Get-Secret -Name 'ReportingApi' -ErrorAction Stop
} catch {
    $PSCmdlet.ThrowTerminatingError($_)
}
```

**SEC-06.** Log that a value is present, not the value:

```powershell
# Compliant
Write-Verbose "Using API token: $(-not [string]::IsNullOrEmpty($ApiToken))"

# Non-compliant
Write-Verbose "Using API token $ApiToken"
Write-Debug ($PSBoundParameters | ConvertTo-Json)
```

**SEC-10.** Arguments passed as an array reach a native executable as separate arguments, so input
cannot add switches or commands:

```powershell
# Compliant
$gitArguments = @('clone', '--depth', '1', '--', $RepositoryUrl, $destinationPath)
& git @gitArguments

# Non-compliant
Invoke-Expression "git clone --depth 1 $RepositoryUrl $destinationPath"
```

**SEC-11.** Anchor a pattern at both ends, or a match anywhere in the value passes:

```powershell
[ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]{0,62}$')]
[string]$ComputerName
```

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
