#requires -Version 7.6

<#
.SYNOPSIS
Finds newer releases of the modules and tools that this repository pins.

.DESCRIPTION
Reads the pins from a data file and looks up the latest release of each one: a module with
Find-PSResource in the PowerShell Gallery, and anything else in the releases of its GitHub
repository. Emits one object for each pin that has a newer release, and nothing for a pin that is
current. Prereleases and drafts do not count, and neither does a GitHub tag that is not a version
of three numbers. A pin with a Track counts only the releases whose major and minor version match
it, such as the PowerShell 7.6 LTS line. A pin of one number, such as 7 for an action written as
@v7, is behind only when a newer major version is released.

When the environment variable GH_TOKEN is set, the GitHub requests carry it, which raises the rate
limit that a shared runner would otherwise reach. No request follows a redirect, so the token goes
only to api.github.com (SEC-09).

A pin whose latest release cannot be looked up does not stop the others. The script reports every
such pin once the others are done, by throwing an error that names them.

.PARAMETER Path
The data file with the pins. The default is Dependencies.psd1 in the folder of this script.

.EXAMPLE
./Tools/Find-DependencyUpdate.ps1

Lists each pin of this repository that has a newer release.

.EXAMPLE
./Tools/Find-DependencyUpdate.ps1 | Format-Table -Property Name, Pinned, Latest

Shows the same list as a table.

.INPUTS
None.

.OUTPUTS
PowerShellStandards.DependencyUpdate. An object with Name, Source, Pinned, Latest, PinnedIn (the
files that hold the pin), and MovesCommit, which is true for an action that is pinned by a commit
whose ID has to move with the version.
#>
[CmdletBinding()]
[OutputType('PowerShellStandards.DependencyUpdate')]
param(
    [Parameter()]
    [string]$Path = (Join-Path -Path $PSScriptRoot -ChildPath 'Dependencies.psd1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$data = Import-PowerShellDataFile -LiteralPath $Path

$headers = @{
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}
if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
    $headers['Authorization'] = "Bearer $env:GH_TOKEN"
}

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($dependency in $data['Dependencies']) {
    $name = $dependency['Name']
    # A pin of one number, such as the @v7 of an action in a rule example, names a major version.
    $pinnedText = [string]$dependency['Version']
    $majorOnly = -not $pinnedText.Contains('.')
    $pinned = if ($majorOnly) { [version]"$pinnedText.0" } else { [version]$pinnedText }
    $track = if ($dependency.ContainsKey('Track')) { [version]$dependency['Track'] } else { $null }
    try {
        if ($dependency['Source'] -eq 'PSGallery') {
            $found = @(Find-PSResource -Name $name -Repository PSGallery -ErrorAction Stop)
            $versions = @($found | ForEach-Object { [version]$_.Version })
        } else {
            $request = @{
                Uri = "https://api.github.com/repos/$($dependency['Repository'])/releases?per_page=100"
                Headers = $headers
                MaximumRedirection = 0
                ErrorAction = 'Stop'
            }
            # Invoke-RestMethod writes a JSON array as one object. The pipeline unrolls it.
            $releases = @(Invoke-RestMethod @request | ForEach-Object -Process { $_ })
            $versions = @(
                foreach ($release in $releases) {
                    if ($release.draft -or $release.prerelease) {
                        continue
                    }
                    $match = [regex]::Match($release.tag_name, '^v?(\d+\.\d+\.\d+)$')
                    if (-not $match.Success) {
                        continue
                    }
                    $version = [version]$match.Groups[1].Value
                    if ($null -ne $track -and
                        ($version.Major -ne $track.Major -or $version.Minor -ne $track.Minor)) {
                        continue
                    }
                    $version
                }
            )
        }
    } catch {
        $failures.Add("${name}: $($_.Exception.Message)")
        continue
    }

    if ($versions.Count -eq 0) {
        $failures.Add("${name}: no release was found.")
        continue
    }

    $latest = $versions | Sort-Object -Descending | Select-Object -First 1
    $isNewer = if ($majorOnly) { $latest.Major -gt $pinned.Major } else { $latest -gt $pinned }
    if ($isNewer) {
        [PSCustomObject]@{
            PSTypeName = 'PowerShellStandards.DependencyUpdate'
            Name = $name
            Source = $dependency['Source']
            Pinned = $pinnedText
            Latest = $latest
            PinnedIn = @($dependency['PinnedIn'].Keys | Sort-Object)
            MovesCommit = $dependency.ContainsKey('Commit')
        }
    }
}

if ($failures.Count -gt 0) {
    throw "The latest release of $($failures.Count) pin(s) could not be looked up. $($failures -join ' ')"
}
