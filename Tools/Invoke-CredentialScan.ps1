#requires -Version 7.6

<#
.SYNOPSIS
Scans a git repository for credentials with betterleaks, gitleaks, or trufflehog.

.DESCRIPTION
Runs one of three credential scanners over a repository and fails when it reports a finding.

The script downloads the scanner as a release archive, at one fixed version, and compares the
SHA-256 of the archive with the value it holds for that version before it unpacks it. A release
tag can be moved to other content; the hash then no longer matches.

Before it reads the repository, the scan has to find two values that the script makes in a folder
outside it. betterleaks and trufflehog end with exit code 0 for a folder that does not exist, and
a configuration can leave out more than was meant, so a scan that reports nothing proves nothing
by itself.

The repository is then scanned twice. The history scan reads what every commit of every branch
and tag added, because a credential stays in a repository after the commit that removes it. The
file scan reads the files of the checkout, because no scanner reads what a merge commit itself
added. The history scan needs the whole history, so the script fails on a shallow clone.

A finding is reported with its place and never with its value. Nothing that is found is sent to
the service that it seems to belong to: trufflehog runs with --no-verification, and betterleaks
without --validation.

Each scanner reads a configuration file and an ignore file from the root of the repository when
they exist:

  betterleaks   .betterleaks.toml         .betterleaksignore
  gitleaks      .gitleaks.toml            .gitleaksignore
  trufflehog    .trufflehog-exclude.txt   .trufflehogignore

For trufflehog the configuration is a list of regular expressions, one on a line, for paths to
leave out. trufflehog has no ignore file of its own: this script reads .trufflehogignore and
leaves out a finding whose fingerprint is listed there. A fingerprint has the form that the other
two scanners use, commit:file:rule:line for the history and file:rule:line for the files.

Both files come from the commit that is scanned, so a change can leave out the finding that it
adds. The scan guards against an accident, not against an author who means to get past it. To
keep what is left out in view, every run writes a warning that says how much the ignore file and
the configuration leave out. For betterleaks and gitleaks it counts the settings of the
configuration by name: an exception, a rule that is switched off, a rule that the file defines,
a file that it extends, and for betterleaks a filter.

.PARAMETER Scanner
The scanner to run: betterleaks, gitleaks, or trufflehog.

.PARAMETER RepositoryPath
The repository to scan. The default is the repository that contains this script.

.PARAMETER ConfigPath
The configuration file of the scanner. The default is the file named in the description, in the
root of the repository. A default file that does not exist is left out; a path given here must
exist.

.PARAMETER IgnorePath
The file that lists the findings to leave out. The default is the file named in the description,
in the root of the repository. A default file that does not exist is left out; a path given here
must exist.

.PARAMETER Version
A version of the scanner other than the one this script holds. It must have the same major
version, because the options of a scanner belong to its major version. Give Sha256 with it.

.PARAMETER Sha256
The SHA-256 of the release archive of Version for this operating system and processor, as the
checksum file of that release gives it.

.PARAMETER ScannerPath
A scanner that is already on this computer. The script then downloads nothing and does not check
a version.

.PARAMETER ToolPath
The folder that the scanner is downloaded to and unpacked in. The default is a folder under the
temporary folder of the runner or of the system.

.EXAMPLE
./Invoke-CredentialScan.ps1 -Scanner gitleaks

Scans the repository that contains the script with gitleaks, at the version the script holds.

.EXAMPLE
./Invoke-CredentialScan.ps1 -Scanner betterleaks -Version '1.10.1' -Sha256 $env:BETTERLEAKS_SHA256

Scans with a version and a hash that the workflow of the project names, so that the project
decides when the scanner changes.

.INPUTS
None.

.OUTPUTS
PowerShellStandards.CredentialFinding. One object for each finding, with Scanner, Source, Rule,
File, Line, Commit, and Fingerprint properties. Source is History or Files. The objects are written
before the error that ends the script when there is a finding.
#>
[CmdletBinding()]
[OutputType('PowerShellStandards.CredentialFinding')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('betterleaks', 'gitleaks', 'trufflehog')]
    [string]$Scanner,

    [Parameter()]
    [string]$RepositoryPath,

    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$IgnorePath,

    [Parameter()]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [Parameter()]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$Sha256,

    [Parameter()]
    [string]$ScannerPath,

    [Parameter()]
    [string]$ToolPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# What the script knows about each scanner. The hashes are those of the checksum file of the
# release, for the six archives that the script can use, under the system and the processor.
# Change a version and its hashes together, run the tests, and read what the new version
# reports: its built-in rules belong to the version.
$scanners = @{
    betterleaks = @{
        Version = '1.10.1'
        ReleaseUri = 'https://github.com/betterleaks/betterleaks/releases/download/v{0}'
        Archive = 'betterleaks_{0}_{1}_{2}.{3}'
        Architecture = @{ X64 = 'x64'; Arm64 = 'arm64' }
        WindowsExtension = 'zip'
        ConfigFile = '.betterleaks.toml'
        IgnoreFile = '.betterleaksignore'
        # One key that a specific rule knows, and one quoted password. The second is the rule that
        # a configuration for PowerShell adds exceptions to, so the probe shows that the
        # exceptions did not switch the rule off.
        ProbeRules = 'generic-password', 'stripe-access-token'
        Hashes = @{
            'darwin_arm64' = 'ca91eb3b006f15478411f235b5e2712fb15cea74f6701ebadc2364efe0af1403'
            'darwin_x64' = '1ae2e3885d161918d8ad2e911e205e73f0d9ffba52c85b38126586c52d355ef4'
            'linux_arm64' = '62a63199f9f61a6b5e5a6f58f048493db20fbc8c770014f4d903a4d97886e1bf'
            'linux_x64' = 'c174b42d7aa60caf58c0c3e555c0e4bed01fe6b0d99a412bce777b5af4ce913e'
            'windows_arm64' = 'f93d26dfc7b939f967c74e3f908b44faec1b1cb6ffb29c75c0a1d7e713ab8f70'
            'windows_x64' = '53d4b37635a999992fb8e1d79f8215279315cbb3b4139314289b69407e79143d'
        }
    }
    gitleaks = @{
        Version = '8.30.1'
        ReleaseUri = 'https://github.com/gitleaks/gitleaks/releases/download/v{0}'
        Archive = 'gitleaks_{0}_{1}_{2}.{3}'
        Architecture = @{ X64 = 'x64'; Arm64 = 'arm64' }
        WindowsExtension = 'zip'
        ConfigFile = '.gitleaks.toml'
        IgnoreFile = '.gitleaksignore'
        # Two keys that specific rules know. gitleaks has no rule for a password, and its generic
        # rule depends on how random a value is, which a probe cannot rely on.
        ProbeRules = 'github-pat', 'stripe-access-token'
        Hashes = @{
            'darwin_arm64' = 'b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5'
            'darwin_x64' = 'dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709'
            'linux_arm64' = 'e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080'
            'linux_x64' = '551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb'
            'windows_arm64' = 'b95f5e4f5c425cedca7ee203d9afd29597e692c4924a12ed42f970537c72cc0f'
            'windows_x64' = 'd29144deff3a68aa93ced33dddf84b7fdc26070add4aa0f4513094c8332afc4e'
        }
    }
    trufflehog = @{
        Version = '3.99.9'
        ReleaseUri = 'https://github.com/trufflesecurity/trufflehog/releases/download/v{0}'
        Archive = 'trufflehog_{0}_{1}_{2}.{3}'
        Architecture = @{ X64 = 'amd64'; Arm64 = 'arm64' }
        WindowsExtension = 'tar.gz'
        ConfigFile = '.trufflehog-exclude.txt'
        IgnoreFile = '.trufflehogignore'
        ProbeRules = 'Github', 'Stripe'
        Hashes = @{
            'darwin_amd64' = '1f18f69a49a8cfb9d59e730bace971722dfdf79266d9b8cf71e59ac161eb19ae'
            'darwin_arm64' = '1d85e5c9c7eddbf12ae2714eb89317ba2cbbbf59be4e161e4b2ff396adbaa3a8'
            'linux_amd64' = '12050095c8063bf4d34f9f6cbce6ba9fa8d0deea9d503d0570364feba093658e'
            'linux_arm64' = '778b1913196dc9b9234e8fd366f64387efeb08c01930a1d2110dcb2ffd07e68b'
            'windows_amd64' = 'da6754ea6f16be84fbda9860bdc49492edfa7a141eddc3ac900047fe88d16648'
            'windows_arm64' = 'e1872ac23e3310245d924ed365f7a04c08e9f181c552eb8b11989ac28bc6ace6'
        }
    }
}
$definition = $scanners[$Scanner]
$isLeaksFamily = $Scanner -ne 'trufflehog'

if ($PSBoundParameters.ContainsKey('Version') -ne $PSBoundParameters.ContainsKey('Sha256')) {
    throw 'Version and Sha256 belong together. Give both, or neither to use the version that this script holds.'
}

if (-not (Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'git was not found. The scan of the history needs it.'
}

# --- The repository ----------------------------------------------------------------------------

$startPath = if ($RepositoryPath) { Convert-Path -LiteralPath $RepositoryPath } else { $PSScriptRoot }
$topLevel = & git -C $startPath rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "'$startPath' is not inside a git repository. Exit code $LASTEXITCODE."
}
$repositoryRoot = Convert-Path -LiteralPath $topLevel

$shallow = & git -C $repositoryRoot rev-parse --is-shallow-repository
if ($LASTEXITCODE -ne 0 -or $shallow -ne 'false') {
    $advice = 'In a workflow, check out with fetch-depth: 0.'
    throw "The clone does not hold the whole history, so the scan would read a part of it. $advice"
}

# A path that the caller names must exist. A default is used only when the file is there.
$resolveOptionalFile = {
    param([string]$GivenPath, [string]$DefaultName, [string]$Label)

    if ($GivenPath) {
        if (-not (Test-Path -LiteralPath $GivenPath -PathType Leaf)) {
            throw "The $Label file '$GivenPath' does not exist."
        }
        return Convert-Path -LiteralPath $GivenPath
    }

    $defaultPath = Join-Path -Path $repositoryRoot -ChildPath $DefaultName
    if (Test-Path -LiteralPath $defaultPath -PathType Leaf) {
        return $defaultPath
    }
    return $null
}
$configArguments = @{ GivenPath = $ConfigPath; DefaultName = $definition.ConfigFile; Label = 'configuration' }
$configFile = & $resolveOptionalFile @configArguments
$ignoreArguments = @{ GivenPath = $IgnorePath; DefaultName = $definition.IgnoreFile; Label = 'ignore' }
$ignoreFile = & $resolveOptionalFile @ignoreArguments
Write-Verbose "Repository: $repositoryRoot. Configuration: $configFile. Ignore file: $ignoreFile."

$temporaryRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$workPath = Join-Path -Path $temporaryRoot -ChildPath "credential-scan-$([guid]::NewGuid().ToString('N'))"
$null = New-Item -Path $workPath -ItemType Directory -Force

try {
    # --- The scanner ---------------------------------------------------------------------------

    if ($ScannerPath) {
        $executable = Convert-Path -LiteralPath $ScannerPath
    } else {
        $scannerVersion = if ($Version) { $Version } else { $definition.Version }
        if ($scannerVersion.Split('.')[0] -ne $definition.Version.Split('.')[0]) {
            $known = "This script is written for $Scanner $($definition.Version.Split('.')[0]).x"
            throw "$known, whose options it uses. Version $scannerVersion has another major version."
        }

        $system = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'darwin' } else { 'linux' }
        $processor = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        if (-not $definition.Architecture.ContainsKey($processor)) {
            throw "$Scanner is not downloaded for the processor architecture $processor. Give ScannerPath."
        }
        $extension = if ($IsWindows) { $definition.WindowsExtension } else { 'tar.gz' }
        $architecture = $definition.Architecture[$processor]
        $archiveName = $definition.Archive -f $scannerVersion, $system, $architecture, $extension

        $expectedHash = $Sha256
        $hashKey = "$($system)_$architecture"
        if (-not $expectedHash -and $definition.Hashes.ContainsKey($hashKey)) {
            $expectedHash = $definition.Hashes[$hashKey]
        }
        if (-not $expectedHash) {
            throw "This script holds no SHA-256 for $archiveName. Give Version and Sha256, or ScannerPath."
        }

        $toolRoot = if ($ToolPath) { $ToolPath } else { Join-Path -Path $workPath -ChildPath 'tool' }
        $null = New-Item -Path $toolRoot -ItemType Directory -Force
        $toolRoot = Convert-Path -LiteralPath $toolRoot
        $archivePath = Join-Path -Path $toolRoot -ChildPath $archiveName
        $downloadUri = "$($definition.ReleaseUri -f $scannerVersion)/$archiveName"
        Write-Verbose "Downloading $downloadUri"
        $savedProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $downloadUri -OutFile $archivePath
        } finally {
            $ProgressPreference = $savedProgress
        }

        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) {
            Remove-Item -LiteralPath $archivePath -Force
            $difference = "The SHA-256 of $archiveName is $actualHash. The expected value is $expectedHash."
            throw "$difference Nothing was unpacked."
        }

        if ($archiveName.EndsWith('.zip')) {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $toolRoot, $true)
        } else {
            $archiveStream = [System.IO.File]::OpenRead($archivePath)
            $gzipStream = $null
            try {
                $decompress = [System.IO.Compression.CompressionMode]::Decompress
                $gzipStream = [System.IO.Compression.GZipStream]::new($archiveStream, $decompress)
                [System.Formats.Tar.TarFile]::ExtractToDirectory($gzipStream, $toolRoot, $true)
            } finally {
                if ($null -ne $gzipStream) {
                    $gzipStream.Dispose()
                }
                $archiveStream.Dispose()
            }
        }

        $executableName = if ($IsWindows) { "$Scanner.exe" } else { $Scanner }
        $executable = Join-Path -Path $toolRoot -ChildPath $executableName
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            throw "$archiveName does not contain $executableName."
        }
        if (-not $IsWindows) {
            & chmod +x $executable
            if ($LASTEXITCODE -ne 0) {
                throw "chmod could not make $executable executable. Exit code $LASTEXITCODE."
            }
        }
    }
    Write-Verbose "Scanner: $executable"

    # Runs the scanner in a folder and returns its exit code and its output as text. The output
    # of trufflehog holds every value it found, so it is never written anywhere by this script.
    $invokeScanner = {
        param([string]$WorkingDirectory, [string[]]$Arguments)

        Push-Location -LiteralPath $WorkingDirectory
        try {
            $lines = @(& $executable @Arguments 2>&1 | ForEach-Object { "$_" })
            $exitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }

        @{ ExitCode = $exitCode; Lines = $lines }
    }

    # What a scan that could not run said, without anything that a scanner found.
    $getFailureText = {
        param([string[]]$Lines)

        $messages = if ($isLeaksFamily) {
            # With --redact the output of these two holds no value. Colour codes are removed.
            $Lines | ForEach-Object { $_ -replace "`e\[[0-9;]*m", '' } | Where-Object { $_.Trim() }
        } else {
            foreach ($line in $Lines) {
                if ($line -notlike '{*') {
                    $line
                    continue
                }
                try {
                    $entry = $line | ConvertFrom-Json -ErrorAction Stop
                } catch [System.ArgumentException] {
                    # Not a JSON line after all, so it cannot be a finding. It is left out all the same.
                    continue
                }
                if ($entry.PSObject.Properties['level'] -and $entry.level -eq 'error') {
                    $entry.msg
                }
            }
        }

        (@($messages) | Select-Object -Last 5) -join ' '
    }

    # --- The ignore list of trufflehog, which this script applies ------------------------------

    $ignoredFingerprints = [System.Collections.Generic.HashSet[string]]::new()
    if (-not $isLeaksFamily -and $ignoreFile) {
        foreach ($line in Get-Content -LiteralPath $ignoreFile) {
            $entry = $line.Trim()
            if ($entry -and -not $entry.StartsWith('#')) {
                $null = $ignoredFingerprints.Add($entry)
            }
        }
    }

    # trufflehog reads the .git folder as files unless it is left out, and would report there what
    # the history scan already reports. The paths that the project leaves out are added.
    $excludeFile = $null
    if (-not $isLeaksFamily) {
        $excludeLines = @(
            '(^|[\\/])\.git[\\/]'
            if ($configFile) {
                Get-Content -LiteralPath $configFile |
                    Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') }
            }
        )
        $excludeFile = Join-Path -Path $workPath -ChildPath 'exclude-paths.txt'
        Set-Content -LiteralPath $excludeFile -Value $excludeLines -Encoding utf8NoBOM
    }

    # Runs one scan and returns its findings and, when it could not run, the reason.
    $invokeScan = {
        param([string]$Source, [string]$WorkingDirectory, [string]$Target)

        $findings = [System.Collections.Generic.List[object]]::new()
        $failure = $null
        $ignoredCount = 0
        if ($isLeaksFamily) {
            $reportPath = Join-Path -Path $workPath -ChildPath "report-$([guid]::NewGuid().ToString('N')).json"
            $command = if ($Source -eq 'History') { 'git' } else { 'dir' }
            # --exit-code 3 tells a finding from a failure: both scanners end with 1 when they
            # cannot run. --redact keeps every value out of the report and the output.
            $arguments = @(
                $command, $Target
                '--exit-code', '3'
                '--redact'
                '--no-banner'
                '--no-color'
                '--log-level', 'error'
                '--report-format', 'json'
                '--report-path', $reportPath
                if ($configFile) {
                    '--config', $configFile
                }
                if ($ignoreFile) {
                    '--gitleaks-ignore-path', $ignoreFile
                }
            )
            $run = & $invokeScanner -WorkingDirectory $WorkingDirectory -Arguments $arguments
            if ($run.ExitCode -notin 0, 3) {
                $failure = "Exit code $($run.ExitCode). $(& $getFailureText -Lines $run.Lines)"
            } elseif (Test-Path -LiteralPath $reportPath) {
                foreach ($item in @(Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json)) {
                    $findings.Add([PSCustomObject]@{
                            PSTypeName = 'PowerShellStandards.CredentialFinding'
                            Scanner = $Scanner
                            Source = $Source
                            Rule = $item.RuleID
                            File = $item.File
                            Line = $item.StartLine
                            Commit = $item.Commit
                            Fingerprint = $item.Fingerprint
                        })
                }
            }

            # The scanner applies the ignore file itself, so exit code 3 means that a finding is
            # left. A report that holds none then was not written or not read, and the scan must
            # not pass for that.
            if (-not $failure -and $run.ExitCode -eq 3 -and $findings.Count -eq 0) {
                $failure = 'The scanner ended with the exit code for a finding, and its report holds none.'
            }
        } else {
            # --fail gives exit code 183 for a finding. --fail-on-scan-errors gives 1 for a source
            # that cannot be read, which is exit code 0 without it.
            $arguments = @(
                if ($Source -eq 'History') {
                    'git', $Target
                } else {
                    'filesystem', $Target
                }
                '--exclude-paths', $excludeFile
                '--no-update'
                '--no-verification'
                '--json'
                '--fail'
                '--fail-on-scan-errors'
            )
            $run = & $invokeScanner -WorkingDirectory $WorkingDirectory -Arguments $arguments
            if ($run.ExitCode -notin 0, 183) {
                $failure = "Exit code $($run.ExitCode). $(& $getFailureText -Lines $run.Lines)"
            } else {
                $readCount = 0
                foreach ($line in $run.Lines) {
                    if ($line -notlike '{*"DetectorName"*') {
                        continue
                    }
                    $readCount++
                    $item = $line | ConvertFrom-Json
                    $data = $item.SourceMetadata.Data
                    $place = if ($data.PSObject.Properties['Git']) { $data.Git } else { $data.Filesystem }
                    $file = [string]$place.file
                    if ([System.IO.Path]::IsPathRooted($file)) {
                        $file = [System.IO.Path]::GetRelativePath($WorkingDirectory, $file)
                    }
                    $file = $file.Replace('\', '/') -replace '^\./', ''
                    $commit = if ($place.PSObject.Properties['commit']) { [string]$place.commit } else { '' }
                    $fingerprint = "$($file):$($item.DetectorName):$($place.line)"
                    if ($commit) {
                        $fingerprint = "$($commit):$fingerprint"
                    }
                    if ($ignoredFingerprints.Contains($fingerprint)) {
                        $ignoredCount++
                        continue
                    }
                    $findings.Add([PSCustomObject]@{
                            PSTypeName = 'PowerShellStandards.CredentialFinding'
                            Scanner = $Scanner
                            Source = $Source
                            Rule = $item.DetectorName
                            File = $file
                            Line = $place.line
                            Commit = $commit
                            Fingerprint = $fingerprint
                        })
                }

                # This script applies the ignore list, so exit code 183 with no finding in the
                # output means that the output was not read.
                if ($run.ExitCode -eq 183 -and $readCount -eq 0) {
                    $failure = 'The scanner ended with the exit code for a finding, and its output holds none.'
                }
            }
        }

        @{ Findings = $findings; Failure = $failure; IgnoredCount = $ignoredCount }
    }

    # --- The probe -----------------------------------------------------------------------------

    # The values are put together from parts, so that no file holds one, this script included.
    # There are four values of each form, because a scanner leaves out a random value now and
    # then: trufflehog 3.99.9 did not report 6 of 1,500 values of the first form and 1 of 1,500 of
    # the second. A rule that reports one of its four values has shown that it works.
    $probePath = Join-Path -Path $workPath -ChildPath 'probe'
    $null = New-Item -Path $probePath -ItemType Directory -Force
    $probeLines = foreach ($index in 1..4) {
        $randomBytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(96)
        $randomText = [System.Convert]::ToBase64String($randomBytes) -replace '[^A-Za-z0-9]', ''
        'key: ' + 'sk_' + 'live_' + $randomText.Substring(0, 32)
        'token: ' + 'gh' + 'p_' + $randomText.Substring(32, 36)
        'password = "{0}"' -f [guid]::NewGuid().ToString('N')
    }
    $probeFile = Join-Path -Path $probePath -ChildPath 'probe.txt'
    Set-Content -LiteralPath $probeFile -Value $probeLines -Encoding ascii

    $probe = & $invokeScan -Source 'Files' -WorkingDirectory $probePath -Target '.'
    if ($probe.Failure) {
        throw "The scan of the probe failed. $($probe.Failure)"
    }
    $probeRules = @($probe.Findings | ForEach-Object { $_.Rule } | Sort-Object -Unique)
    $missingRules = @($definition.ProbeRules | Where-Object { $_ -notin $probeRules })
    if ($missingRules.Count -gt 0) {
        $found = if ($probeRules.Count -gt 0) { $probeRules -join ', ' } else { 'nothing' }
        $expected = $definition.ProbeRules -join ', '
        $problem = "The scan of the probe reported $found. It has to report $expected"
        throw "$problem, so the scan cannot be trusted to find a credential. Check the configuration."
    }
    Write-Verbose "The scan found the values of the probe: $($definition.ProbeRules -join ', ')."

    # --- The repository ------------------------------------------------------------------------

    # Both scans run, so that one run shows everything there is to see.
    $problems = [System.Collections.Generic.List[string]]::new()
    $allFindings = [System.Collections.Generic.List[object]]::new()
    $ignoredTotal = 0
    $historyTarget = if ($isLeaksFamily) { '.' } else { 'file://' + $repositoryRoot.Replace('\', '/') }
    foreach ($scan in @{ Source = 'History'; Target = $historyTarget }, @{ Source = 'Files'; Target = '.' }) {
        Write-Verbose "$Scanner, $($scan.Source)"
        $result = & $invokeScan -Source $scan.Source -WorkingDirectory $repositoryRoot -Target $scan.Target
        if ($result.Failure) {
            $problems.Add("The scan of the $($scan.Source.ToLowerInvariant()) failed. $($result.Failure)")
        }
        $allFindings.AddRange($result.Findings)
        $ignoredTotal += $result.IgnoredCount
    }

    # --- What the project leaves out -----------------------------------------------------------

    # The ignore file and the configuration come from the commit that is scanned, so a change can
    # leave out the finding that it adds. Every run says how much is left out, so that a list
    # that grows shows in the log of the run.
    $leftOut = [System.Collections.Generic.List[string]]::new()
    $countEntries = {
        param([string]$Path)

        $entries = Get-Content -LiteralPath $Path |
            Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') }
        @($entries).Count
    }
    if ($ignoreFile) {
        $ignoreName = Split-Path -Path $ignoreFile -Leaf
        if ($isLeaksFamily) {
            $entryCount = & $countEntries -Path $ignoreFile
            if ($entryCount -gt 0) {
                $leftOut.Add("the findings that the $entryCount fingerprint(s) in $ignoreName name")
            }
        } elseif ($ignoredTotal -gt 0) {
            $leftOut.Add("$ignoredTotal finding(s) whose fingerprint is in $ignoreName")
        }
    }
    if ($configFile) {
        $configName = Split-Path -Path $configFile -Leaf
        if ($isLeaksFamily) {
            # The settings that leave a value out, each by its name in the file. Measured with
            # gitleaks 8.30.1 and betterleaks 1.10.1: with each of them a scan passed over a value
            # that it reports without it, and the probe still found its values. A rule that the
            # file defines replaces the built-in rule of the same name. An extended file brings
            # exceptions of its own, which are not read here. Only betterleaks knows a filter.
            $settings = @(
                @{
                    Pattern = '(?m)^\s*\[\[?(?:rules\.)?allowlists?\]\]?'
                    Text = 'what the {0} exception(s) in {1} match'
                }
                @{
                    Pattern = '(?<=\bdisabledRules\s*=\s*\[[^\]]*)["''][^"''\r\n]+["'']'
                    Text = 'what the {0} rule(s) that {1} switches off report'
                }
                @{
                    Pattern = '(?m)^\s*\[\[rules\]\]'
                    Text = 'what the built-in rule of the same name reports, ' +
                    'for each of the {0} rule(s) that {1} defines'
                }
                @{
                    Pattern = '(?m)^\s*\[extend\]\s*$(?:\n(?!\s*\[).*)*?\n\s*path\s*=|\bextend\b[^\n]*\bpath\s*='
                    Text = 'what the file that {1} extends leaves out, which is not counted here'
                }
                if ($Scanner -eq 'betterleaks') {
                    @{
                        Pattern = '(?m)^\s*(?:pre)?filter\s*='
                        Text = 'what the {0} filter(s) in {1} discard'
                    }
                }
            )
            # A comment can name a setting, so the comment lines are left out before the count.
            $configLines = Get-Content -LiteralPath $configFile |
                Where-Object { -not $_.TrimStart().StartsWith('#') }
            $configText = $configLines -join "`n"
            foreach ($setting in $settings) {
                $settingCount = [regex]::Matches($configText, $setting.Pattern).Count
                if ($settingCount -gt 0) {
                    $leftOut.Add(($setting.Text -f $settingCount, $configName))
                }
            }
        } else {
            $patternCount = & $countEntries -Path $configFile
            if ($patternCount -gt 0) {
                $leftOut.Add("the paths that the $patternCount pattern(s) in $configName match")
            }
        }
    }
} finally {
    Remove-Item -LiteralPath $workPath -Recurse -Force -ErrorAction SilentlyContinue
}

if ($leftOut.Count -gt 0) {
    Write-Warning "Left out of this scan: $($leftOut -join '; ')."
}

$allFindings

if ($allFindings.Count -gt 0) {
    $places = foreach ($finding in $allFindings | Select-Object -First 50) {
        $values = $finding.Source, $finding.Rule, $finding.File, $finding.Line, $finding.Fingerprint
        '  {0}: {1} in {2}, line {3}. Fingerprint: {4}' -f $values
    }
    $count = "$Scanner reported $($allFindings.Count) value(s) that may be credentials."
    $advice = 'Read each one. Revoke a real credential first: a commit that removes it leaves it in the history.'
    $problems.Add((@("$count $advice") + $places) -join "`n")
}
if ($problems.Count -gt 0) {
    throw ($problems -join "`n")
}

Write-Verbose "$Scanner found no credential in the history or in the files of '$repositoryRoot'."
