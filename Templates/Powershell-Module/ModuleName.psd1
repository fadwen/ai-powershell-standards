# Module manifest. Before the module is used, replace GUID, Author, and Description. Generate the
# GUID once with New-Guid: every module needs its own.
@{
    RootModule = 'ModuleName.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'ff387de5-6a8c-43cf-844e-788e4e1124b3'
    Author = 'Your name'
    Description = 'Replace this text with one sentence that says what the module does.'

    PowerShellVersion = '7.6'
    CompatiblePSEditions = @('Core')

    # Name every function in the Public folder here. A function that is not named is not exported.
    FunctionsToExport = @('Get-TemplateFunction')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            # Add ProjectUri and LicenseUri beside Tags when the module has a repository and a license.
            Tags = @()
        }
    }
}
