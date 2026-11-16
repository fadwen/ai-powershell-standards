function Import-TemplateSetting {
    <#
    .SYNOPSIS
    Reads the settings file that ships with the module.

    .DESCRIPTION
    Reads Configuration/DefaultConfiguration.psd1 from the module folder and returns its content.
    The file is read each time the function is called. A file that cannot be read is a terminating
    error.

    .EXAMPLE
    $settings = Import-TemplateSetting

    Reads the settings of the module into a hashtable.

    .INPUTS
    None.

    .OUTPUTS
    System.Collections.Hashtable. The content of the settings file.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    $configurationFolder = Join-Path -Path $moduleRoot -ChildPath 'Configuration'
    $settingsPath = Join-Path -Path $configurationFolder -ChildPath 'DefaultConfiguration.psd1'

    try {
        $settings = Import-PowerShellDataFile -LiteralPath $settingsPath -ErrorAction Stop
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $settings
}
