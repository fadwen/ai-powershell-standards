# PowerShell modules: layout, manifest, loading

These rules apply to `.psm1` and `.psd1` files and to the function files a module loads.

## Rules

- **MOD-01** Lay a module out as a manifest (`ModuleName.psd1`), a root module (`ModuleName.psm1`), a
  `Public` folder for exported functions, and a `Private` folder for internal ones. Put each function
  in its own file, named after the function.
- **MOD-02** The manifest names every exported function in `FunctionsToExport`. Wildcards MUST NOT be
  used there, and `CmdletsToExport`, `VariablesToExport`, and `AliasesToExport` are `@()` unless the
  module really exports one.
- **MOD-03** A manifest contains only literal values. `GUID` is a real GUID generated once with
  `New-Guid`, and `ModuleVersion` follows semantic versioning.
- **MOD-04** `RequiredModules` lists only modules that the code calls. A dependency MUST NOT be added
  for a feature the module does not use.
- **MOD-05** The root module sets strict mode, then dot-sources `Classes`, `Private`, and `Public` in
  that order, and fails the import when any file fails to load.
- **MOD-06** A module MUST NOT do work when it is imported beyond loading its files: no network calls,
  no prompts, no changes to the session outside the module.
- **MOD-07** A function MUST NOT be exported only so that a test can reach it. Tests reach private
  functions with `InModuleScope`.

### Releasing to the PowerShell Gallery

- **MOD-10** Publish from a staging folder that an allowlist of files and folders fills.
  `Publish-PSResource` MUST NOT be pointed at the repository root.
- **MOD-11** Before the upload, import the staged copy in a new process and compare what it exports
  with the manifest.
- **MOD-12** `ReleaseNotes` in the manifest covers the current release and points to `CHANGELOG.md`.
  Measure `ReleaseNotes`, `Description`, and the full tag list against the Gallery's limits before
  the release.
- **MOD-13** Leave a URI key such as `IconUri` out of the manifest until it has a value. An empty
  string MUST NOT be assigned to it.
- **MOD-14** In a release script, only the publish step is guarded by `$PSCmdlet.ShouldProcess()`.
  Every other step runs with `-WhatIf:$false` or with `$WhatIfPreference` cleared, so that `-WhatIf`
  rehearses the whole release.

## Notes and examples

### Layout (MOD-01)

```text
ModuleName/
    ModuleName.psd1
    ModuleName.psm1
    Classes/            optional
    Private/
        Get-InternalThing.ps1
    Public/
        Get-Thing.ps1
    Tests/
        Get-Thing.Tests.ps1
    docs/               only when help ships as compiled external help
    en-US/              only when help ships as compiled external help
```

Add other folders only when the module has something to put in them.

### Manifest (MOD-02, MOD-03, MOD-04)

A `.psd1` file is data. PowerShell does not evaluate expressions in it, so `'$(New-Guid)'` stays the
literal text `$(New-Guid)` and the manifest is rejected. Generate the value once and paste it in.

```powershell
@{
    RootModule = 'ModuleName.psm1'
    ModuleVersion = '1.0.0'
    GUID = '00000000-0000-0000-0000-000000000000'
    Author = 'Name supplied by the user'
    Description = 'One sentence that says what the module does.'

    PowerShellVersion = '7.6'
    CompatiblePSEditions = @('Core')

    FunctionsToExport = @('Get-Thing', 'Set-Thing')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @('Example')
            ProjectUri = 'https://github.com/owner/repository'
            LicenseUri = 'https://github.com/owner/repository/blob/main/LICENSE'
        }
    }
}
```

The GUID above is a placeholder. Run `New-Guid` once and paste its output: every module needs its own
GUID, and it never changes afterwards. Set `Author`, the URIs, and `Tags` from what the user or the
repository provides; do not invent them. Leave out `HelpInfoURI` unless the project publishes
updatable help at that address, and leave out `IconUri` when there is no icon (MOD-13).

### Root module (MOD-05)

<!-- include: powershell-standards/Examples/Module-Structure-Example/ModuleExample.psm1 -->

Without the `try` and `throw`, a function file that fails to load would produce an error message and
the import would continue, leaving the module loaded with commands missing.

Classes load first because a function file that uses a class as a parameter type needs the type to
exist when the file is read. When the function file is read first, the import still succeeds and the
function fails with `TypeNotFound` each time it is called. For the same reason such a file cannot be
dot-sourced on its own in a test; import the module instead. A function that only names a class in
`[OutputType()]` writes the name as a string.

The root module does not set `$ErrorActionPreference`; see ERR-02 in
`.github/instructions/powershell-error-handling.instructions.md`.

### Testing private functions (MOD-07)

```powershell
InModuleScope ModuleName {
    Get-InternalThing -Name 'alpha' | Should-Be 'ALPHA'
}
```

### Releasing to the PowerShell Gallery (MOD-10 to MOD-14)

A Gallery version is in use from the moment it uploads. It can be unlisted but not deleted. Each
rule here answers a release that passed every local check and then shipped the wrong content or
failed at the upload.

**MOD-10, MOD-11.** When the repository is the module root, publishing that folder packs the working
tree. Measured with Microsoft.PowerShell.PSResourceGet 1.2.0: the package contains `.git`, the tests,
and the build scripts. A staging folder ships only what the allowlist names:

```powershell
$shipFiles = 'ModuleName.psd1', 'ModuleName.psm1', 'README.md', 'CHANGELOG.md', 'LICENSE'
$shipFolders = 'Classes', 'Private', 'Public', 'en-US'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$outputRoot = Join-Path -Path $repositoryRoot -ChildPath 'out'
$stagePath = Join-Path -Path $outputRoot -ChildPath 'ModuleName'
if (Test-Path -LiteralPath $stagePath) {
    Remove-Item -LiteralPath $stagePath -Recurse -Force -WhatIf:$false
}
$null = New-Item -Path $stagePath -ItemType Directory -Force -WhatIf:$false

foreach ($item in $shipFiles + $shipFolders) {
    $sourcePath = Join-Path -Path $repositoryRoot -ChildPath $item
    Copy-Item -LiteralPath $sourcePath -Destination $stagePath -Recurse -WhatIf:$false
}

# A new process proves that the staged copy imports by itself.
$manifestPath = Join-Path -Path $stagePath -ChildPath 'ModuleName.psd1'
$listExports = '(Import-Module -Name $args[0] -PassThru).ExportedFunctions.Keys'
$exported = @(& pwsh -NoProfile -Command $listExports -args $manifestPath)
if ($LASTEXITCODE -ne 0) {
    throw "The staged module failed to import. Exit code $LASTEXITCODE."
}

$expected = @((Import-PowerShellDataFile -LiteralPath $manifestPath).FunctionsToExport)
if (Compare-Object -ReferenceObject $expected -DifferenceObject $exported) {
    throw 'The staged module does not export what its manifest lists.'
}

if ($PSCmdlet.ShouldProcess($stagePath, 'Publish to the PowerShell Gallery')) {
    Publish-PSResource -Path $stagePath -Repository PSGallery -ApiKey $env:PSGALLERY_API_KEY
}
```

The script declares `[CmdletBinding(SupportsShouldProcess)]`, keeps `out/` in `.gitignore`, and takes
the API key from an environment variable that the CI secret store fills (CIC-06).

**MOD-12.** Three manifest fields have limits that are enforced only at upload, so every local check
passes until the publish step is refused. The limits below were met in real releases; the release
notes limit is stated in the Gallery's error response.

| Field | Limit |
| --- | --- |
| `ReleaseNotes` | 10,600 characters |
| `Description` | 4,000 characters |
| Tags | 4,000 characters for the whole list |

The tag list that the Gallery stores is the manifest's `Tags` plus the tags the publish adds:
`PSModule`, `PSEdition_<edition>` for each compatible edition, `PSIncludes_Function`, and
`PSFunction_<name>` and `PSCommand_<name>` for every exported function. A module that keeps adding
commands therefore reaches the limit without its `Tags` key changing, and `ReleaseNotes` grows the
same way when every release adds a paragraph and none removes one. Measure all three in the release
script and in a test:

```powershell
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$psData = $manifest.PrivateData.PSData
$publishTags = @(
    $psData.Tags
    'PSModule'
    'PSIncludes_Function'
    foreach ($edition in $manifest.CompatiblePSEditions) {
        "PSEdition_$edition"
    }
    foreach ($functionName in $manifest.FunctionsToExport) {
        "PSFunction_$functionName"
        "PSCommand_$functionName"
    }
)

$measurements = @(
    @{ Field = 'Description'; Length = $manifest.Description.Length; Limit = 4000 }
    @{ Field = 'Tags'; Length = ($publishTags -join ' ').Length; Limit = 4000 }
    @{ Field = 'ReleaseNotes'; Length = $psData.ReleaseNotes.Length; Limit = 10600 }
)
foreach ($measurement in $measurements) {
    if ($measurement.Length -gt $measurement.Limit) {
        $problem = "The manifest's $($measurement.Field) is $($measurement.Length) characters."
        throw "$problem The PowerShell Gallery accepts at most $($measurement.Limit)."
    }
}
```

A module that exports cmdlets or DSC resources gains further tags of the same kind.

**MOD-13.** `IconUri = ''` is not "no icon". Measured with PSResourceGet 1.2.0, the pack fails with
`IconUrl cannot be empty`, and the message names neither the manifest nor the key.

**MOD-14.** `-WhatIf` sets `$WhatIfPreference`, and every cmdlet and script that the release script
calls inherits it (FUN-33). Unless the other steps are pinned, a rehearsal copies nothing and builds
nothing, and then either fails on the empty folder or passes having checked nothing. A script that
does not declare `SupportsShouldProcess` has no `-WhatIf` parameter to pin, so clear the preference
around the call:

```powershell
$savedWhatIf = $WhatIfPreference
$WhatIfPreference = $false
try {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Build-Help.ps1')
} finally {
    $WhatIfPreference = $savedWhatIf
}
```

Rehearse from a clean checkout, and test `-WhatIf` together with the script's other switches. A
folder left by an earlier run hides a step that now produces nothing.

Run the release from a version tag. The workflow runs every check again, refuses a tag that differs
from the manifest's `ModuleVersion`, stages, verifies, and publishes (CIC-08, CIC-10).
