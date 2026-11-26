#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeDiscovery {
    $root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $pins = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $root -ChildPath 'Tools/Dependencies.psd1')
    $pinCases = foreach ($dependency in $pins['Dependencies']) {
        $commit = if ($dependency.ContainsKey('Commit')) { $dependency['Commit'] } else { '' }
        foreach ($file in $dependency['PinnedIn'].Keys) {
            @{
                Name = $dependency['Name']
                File = $file
                Text = $dependency['PinnedIn'][$file] -f $dependency['Version'], $commit
            }
        }
    }
    $dependencyCases = foreach ($dependency in $pins['Dependencies']) {
        @{ Name = $dependency['Name']; Dependency = $dependency }
    }
}

BeforeAll {
    $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $checkScript = Join-Path -Path $repositoryRoot -ChildPath 'Tools/Find-DependencyUpdate.ps1'

    # Writes a data file of pins under the test drive and returns its path.
    $newPinFile = {
        param([string[]]$Entries)

        $path = Join-Path -Path $TestDrive -ChildPath "pins-$([guid]::NewGuid().ToString('N')).psd1"
        $text = "@{`n    Dependencies = @(`n$($Entries -join "`n")`n    )`n}`n"
        Set-Content -LiteralPath $path -Value $text -Encoding ascii
        $path
    }

    # A release as the GitHub API returns it.
    $newRelease = {
        param([string]$Tag, [switch]$Prerelease, [switch]$Draft)

        [PSCustomObject]@{ tag_name = $Tag; prerelease = [bool]$Prerelease; draft = [bool]$Draft }
    }

    # Runs the check and keeps what it emitted and what it threw.
    $invokeCheck = {
        param([string]$PinPath)

        $updates = [System.Collections.Generic.List[object]]::new()
        $problem = $null
        try {
            & $checkScript -Path $PinPath | ForEach-Object -Process { $updates.Add($_) }
        } catch {
            # The test asserts the error, so it is kept here and not passed on.
            $problem = $_
        }

        @{ Updates = $updates.ToArray(); Problem = $problem }
    }

    $galleryPin = "@{ Name = 'Pester'; Source = 'PSGallery'; Version = '6.2.0'; PinnedIn = @{ 'a.yml' = 'x' } }"
    $gitHubPin = @'
@{
    Name = 'gitleaks'; Source = 'GitHub'; Repository = 'gitleaks/gitleaks'; Version = '8.30.1'
    PinnedIn = @{ 'b.ps1' = 'y' }
}
'@
    $trackPin = @'
@{
    Name = 'PowerShell 7.6'; Source = 'GitHub'; Repository = 'PowerShell/PowerShell'
    Track = '7.6'; Version = '7.6.10'; PinnedIn = @{ 'c.md' = 'z' }
}
'@

    $savedToken = $env:GH_TOKEN
}

AfterAll {
    $env:GH_TOKEN = $savedToken
}

Describe 'Tools/Dependencies.psd1' -Tag 'Unit', 'Tools' {
    It 'Holds the pin of <Name> in <File>' -ForEach $pinCases {
        $content = Get-Content -LiteralPath (Join-Path -Path $repositoryRoot -ChildPath $File) -Raw

        $content.Contains($Text) | Should-BeTrue -Because "'$File' should hold '$Text'"
    }

    It 'Describes <Name> with a known source and a version' -ForEach $dependencyCases {
        @('PSGallery', 'GitHub') | Should-ContainCollection $Dependency['Source']
        $Dependency['Version'] | Should-MatchString '^\d+(\.\d+\.\d+)?$'
        $Dependency['PinnedIn'].Count | Should-BeGreaterThan 0
        if ($Dependency['Source'] -eq 'GitHub') {
            $Dependency['Repository'] | Should-MatchString '^[\w.-]+/[\w.-]+$'
        }
    }
}

Describe 'Find-DependencyUpdate.ps1' -Tag 'Unit', 'Tools' {
    BeforeEach {
        $env:GH_TOKEN = $null
    }

    Context 'A module in the PowerShell Gallery' {
        It 'Emits an update when the Gallery has a newer version' {
            Mock -CommandName Find-PSResource -MockWith { [PSCustomObject]@{ Version = [version]'6.3.0' } }
            $pinPath = & $newPinFile -Entries $galleryPin

            $result = & $invokeCheck -PinPath $pinPath

            $result.Problem | Should-BeNull
            $result.Updates | Should-BeCollection -Count 1
            $result.Updates[0] | Should-HaveType 'PowerShellStandards.DependencyUpdate'
            $result.Updates[0].Name | Should-Be 'Pester'
            $result.Updates[0].Pinned | Should-Be '6.2.0'
            $result.Updates[0].Latest | Should-Be ([version]'6.3.0')
            $result.Updates[0].PinnedIn -join ',' | Should-Be 'a.yml'
            $result.Updates[0].MovesCommit | Should-BeFalse
            Should-Invoke -CommandName Find-PSResource -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Pester' -and $Repository -eq 'PSGallery'
            }
        }

        It 'Emits nothing when the pin is the latest version' {
            Mock -CommandName Find-PSResource -MockWith { [PSCustomObject]@{ Version = [version]'6.2.0' } }
            $pinPath = & $newPinFile -Entries $galleryPin

            $result = & $invokeCheck -PinPath $pinPath

            $result.Problem | Should-BeNull
            $result.Updates.Count | Should-Be 0
        }
    }

    Context 'A release on GitHub' {
        It 'Takes the highest stable release, and leaves out drafts, prereleases, and other tags' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                # The API returns the array as one object, as Invoke-RestMethod does with JSON.
                , @(
                    & $newRelease -Tag 'v9.0.0' -Prerelease
                    & $newRelease -Tag 'v8.40.0' -Draft
                    & $newRelease -Tag 'nightly'
                    & $newRelease -Tag 'v8.31.0'
                    & $newRelease -Tag '8.30.2'
                )
            }
            $pinPath = & $newPinFile -Entries $gitHubPin

            $result = & $invokeCheck -PinPath $pinPath

            $result.Problem | Should-BeNull
            $result.Updates | Should-BeCollection -Count 1
            $result.Updates[0].Latest | Should-Be ([version]'8.31.0')
        }

        It 'Compares versions as numbers, so 3.100.1 is newer than 3.99.9' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                , @((& $newRelease -Tag 'v3.99.9'), (& $newRelease -Tag 'v3.100.1'))
            }
            $pin = @'
@{
    Name = 'trufflehog'; Source = 'GitHub'; Repository = 'trufflesecurity/trufflehog'; Version = '3.99.9'
    PinnedIn = @{ 'd.ps1' = 'w' }
}
'@
            $pinPath = & $newPinFile -Entries $pin

            $result = & $invokeCheck -PinPath $pinPath

            $result.Updates | Should-BeCollection -Count 1
            $result.Updates[0].Latest | Should-Be ([version]'3.100.1')
        }

        It 'Counts only the releases of its track for a pin with a Track' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                , @(
                    & $newRelease -Tag 'v7.7.1'
                    & $newRelease -Tag 'v7.6.11'
                    & $newRelease -Tag 'v7.6.10'
                )
            }
            $pinPath = & $newPinFile -Entries $trackPin

            $result = & $invokeCheck -PinPath $pinPath

            $result.Updates | Should-BeCollection -Count 1
            $result.Updates[0].Latest | Should-Be ([version]'7.6.11')
        }

        It 'Reports a pin of a major version only when a newer major version is released' -ForEach @(
            @{ Tags = 'v7.9.0', 'v7.0.1'; Expected = 0 }
            @{ Tags = 'v8.0.0', 'v7.9.0'; Expected = 1 }
        ) {
            $releases = foreach ($tag in $Tags) {
                & $newRelease -Tag $tag
            }
            Mock -CommandName Invoke-RestMethod -MockWith { , @($releases) }
            $pin = @'
@{
    Name = 'actions/upload-artifact in the rules'; Source = 'GitHub'; Repository = 'actions/upload-artifact'
    Version = '7'; PinnedIn = @{ 'e.md' = 'v' }
}
'@
            $pinPath = & $newPinFile -Entries $pin

            $result = & $invokeCheck -PinPath $pinPath

            $result.Problem | Should-BeNull
            $result.Updates | Should-BeCollection -Count $Expected
            if ($Expected -gt 0) {
                $result.Updates[0].Pinned | Should-Be '7'
                $result.Updates[0].Latest | Should-Be ([version]'8.0.0')
            }
        }

        It 'Says that the commit moves with an action that is pinned by its commit' {
            Mock -CommandName Invoke-RestMethod -MockWith { , @(& $newRelease -Tag 'v7.1.0') }
            $pin = @'
@{
    Name = 'actions/checkout'; Source = 'GitHub'; Repository = 'actions/checkout'; Version = '7.0.1'
    PinnedIn = @{ 'f.yml' = 'u' }; Commit = '3d3c42e5aac5ba805825da76410c181273ba90b1'
}
'@
            $pinPath = & $newPinFile -Entries $pin

            $result = & $invokeCheck -PinPath $pinPath

            $result.Updates | Should-BeCollection -Count 1
            $result.Updates[0].MovesCommit | Should-BeTrue
        }

        It 'Asks the releases of the repository, and follows no redirect' {
            Mock -CommandName Invoke-RestMethod -MockWith { , @() }
            $pinPath = & $newPinFile -Entries $gitHubPin

            $null = & $invokeCheck -PinPath $pinPath

            Should-Invoke -CommandName Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/gitleaks/gitleaks/releases?per_page=100' -and
                $MaximumRedirection -eq 0 -and -not $Headers.ContainsKey('Authorization')
            }
        }

        It 'Sends GH_TOKEN as a bearer token when it is set' {
            Mock -CommandName Invoke-RestMethod -MockWith { , @() }
            # A random value, so that no token is written in the source (SEC-01).
            $env:GH_TOKEN = [guid]::NewGuid().ToString('N')
            $pinPath = & $newPinFile -Entries $gitHubPin

            $null = & $invokeCheck -PinPath $pinPath

            Should-Invoke -CommandName Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Headers['Authorization'] -eq "Bearer $env:GH_TOKEN" -and $MaximumRedirection -eq 0
            }
        }
    }

    Context 'A pin that cannot be looked up' {
        It 'Still emits the updates of the other pins, then fails and names the pin' {
            Mock -CommandName Find-PSResource -MockWith { [PSCustomObject]@{ Version = [version]'6.3.0' } }
            Mock -CommandName Invoke-RestMethod -MockWith {
                throw 'Response status code does not indicate success: 404.'
            }
            $pinPath = & $newPinFile -Entries $gitHubPin, $galleryPin

            $result = & $invokeCheck -PinPath $pinPath

            $result.Updates | Should-BeCollection -Count 1
            $result.Updates[0].Name | Should-Be 'Pester'
            $message = $result.Problem.Exception.Message
            $message | Should-BeLikeString '*1 pin(s) could not be looked up*'
            $message | Should-BeLikeString '*gitleaks: Response status code does not indicate success: 404.*'
        }

        It 'Fails when no release of the track is found' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                , @(& $newRelease -Tag 'v7.7.1')
            }
            $pinPath = & $newPinFile -Entries $trackPin

            $result = & $invokeCheck -PinPath $pinPath

            $result.Updates.Count | Should-Be 0
            $result.Problem.Exception.Message | Should-BeLikeString '*PowerShell 7.6: no release was found.*'
        }
    }
}
