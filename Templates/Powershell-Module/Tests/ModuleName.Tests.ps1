#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'ModuleName.psd1'
    Import-Module -Name $manifestPath -Force
}

Describe 'ModuleName' -Tag 'Unit' {
    Context 'The manifest' {
        It 'Is accepted by PowerShell and declares the target version' {
            $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop

            $manifest.Name | Should-Be 'ModuleName'
            $manifest.PowerShellVersion | Should-Be ([version]'7.6')
            $manifest.CompatiblePSEditions | Should-BeCollection @('Core')
        }
    }

    Context 'The exported commands' {
        BeforeAll {
            $module = Get-Module -Name ModuleName
            $exportedNames = @($module.ExportedCommands.Keys | Sort-Object)
        }

        It 'Exports one function for each file in the Public folder, and nothing else' {
            $publicFolder = Join-Path -Path $moduleRoot -ChildPath 'Public'
            $publicNames = @(
                Get-ChildItem -LiteralPath $publicFolder -Filter '*.ps1' -File |
                    ForEach-Object { $_.BaseName } |
                    Sort-Object
            )

            $publicNames | Should-NotBeNull
            ($exportedNames -join ', ') | Should-Be ($publicNames -join ', ')
        }

        It 'Keeps the functions in the Private folder out of the exports' {
            $privateFolder = Join-Path -Path $moduleRoot -ChildPath 'Private'
            $privateNames = @(
                Get-ChildItem -LiteralPath $privateFolder -Filter '*.ps1' -File |
                    ForEach-Object { $_.BaseName }
            )
            $exportedPrivateNames = @($privateNames | Where-Object { $exportedNames -contains $_ })

            $privateNames | Should-NotBeNull
            $exportedPrivateNames | Should-BeCollection -Count 0
        }
    }
}
