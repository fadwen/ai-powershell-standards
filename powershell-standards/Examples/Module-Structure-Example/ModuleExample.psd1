@{
    RootModule = 'ModuleExample.psm1'
    ModuleVersion = '1.0.0'
    GUID = '8f2b1c9d-4e7a-4b3f-9c21-5d6e8a0f7b34'
    Author = 'Example Author'
    Description = 'Example module with Public, Private, and Classes folders and an explicit export list.'

    PowerShellVersion = '7.6'
    CompatiblePSEditions = @('Core')

    # Only Get-ExampleData is exported. The functions in Private stay internal, so they can change
    # without breaking a caller of the module.
    FunctionsToExport = @('Get-ExampleData')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @('PowerShell', 'Example', 'Standards', 'Reference')
            ProjectUri = 'https://github.com/fadwen/Powershell-Copilot-Standards'
            LicenseUri = 'https://github.com/fadwen/Powershell-Copilot-Standards/blob/main/LICENSE'
        }
    }
}
