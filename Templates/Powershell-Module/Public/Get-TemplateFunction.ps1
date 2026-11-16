function Get-TemplateFunction {
    <#
    .SYNOPSIS
    Gets the settings that the module defines for an environment.

    .DESCRIPTION
    Reads the settings file of the module once, then emits one object for each requested
    environment. An environment that the file does not define is reported as a non-terminating
    error and the remaining names are still processed. A settings file that cannot be read, or that
    has no Environments table, is a terminating error.

    .PARAMETER Name
    One or more environment names, such as Development or Production.

    .EXAMPLE
    Get-TemplateFunction -Name 'Production'

    Gets the settings of the Production environment.

    .EXAMPLE
    'Development', 'Production' | Get-TemplateFunction

    Gets the settings of two environments, taking the names from the pipeline.

    .INPUTS
    System.String. You can pipe environment names to this function.

    .OUTPUTS
    ModuleName.EnvironmentSetting. An object with Name, LogLevel, TimeoutSeconds, and RetryCount
    properties.
    #>
    [CmdletBinding()]
    [OutputType('ModuleName.EnvironmentSetting')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Name
    )

    begin {
        try {
            $settings = Import-TemplateSetting -ErrorAction Stop
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }

        $environments = $settings['Environments']
        if ($environments -isnot [hashtable]) {
            $message = 'The settings file of the module does not define an Environments table.'
            $exception = [System.IO.InvalidDataException]::new($message)
            $category = [System.Management.Automation.ErrorCategory]::InvalidData
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception, 'EnvironmentsNotDefined', $category, $null)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    process {
        foreach ($item in $Name) {
            if (-not $environments.ContainsKey($item)) {
                $message = "The environment '$item' is not defined in the settings file of the module."
                $exception = [System.Management.Automation.ItemNotFoundException]::new($message)
                $category = [System.Management.Automation.ErrorCategory]::ObjectNotFound
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'EnvironmentNotFound', $category, $item)
                $PSCmdlet.WriteError($errorRecord)
                continue
            }

            $environment = $environments[$item]
            [PSCustomObject]@{
                PSTypeName = 'ModuleName.EnvironmentSetting'
                Name = $item
                LogLevel = $environment['LogLevel']
                TimeoutSeconds = $environment['TimeoutSeconds']
                RetryCount = $environment['RetryCount']
            }
        }
    }
}
