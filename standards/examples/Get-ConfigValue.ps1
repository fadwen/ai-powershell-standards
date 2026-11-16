function Get-ConfigValue {
    <#
    .SYNOPSIS
    Gets named values from a JSON configuration file.

    .DESCRIPTION
    Reads the JSON file once, then emits one object for each requested name. A name that is
    not in the file is reported as a non-terminating error and the remaining names are still
    processed. A file that cannot be read, or that does not contain a JSON object, is a
    terminating error.

    .PARAMETER Path
    Path of the JSON configuration file. Wildcard characters are not expanded.

    .PARAMETER Name
    One or more top-level property names to read.

    .EXAMPLE
    Get-ConfigValue -Path './settings.json' -Name 'Region'

    Gets the Region value from settings.json.

    .EXAMPLE
    'Region', 'Tier' | Get-ConfigValue -Path './settings.json'

    Gets two values, taking the names from the pipeline.

    .INPUTS
    System.String. You can pipe value names to this function.

    .OUTPUTS
    Example.ConfigValue. An object with Name, Value, and Path properties.
    #>
    [CmdletBinding()]
    [OutputType('Example.ConfigValue')]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Name
    )

    begin {
        try {
            $fullPath = Convert-Path -LiteralPath $Path -ErrorAction Stop
            $config = Get-Content -LiteralPath $fullPath -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }

        if ($config -isnot [System.Management.Automation.PSCustomObject]) {
            $exception = [System.IO.InvalidDataException]::new("'$fullPath' does not contain a JSON object.")
            $category = [System.Management.Automation.ErrorCategory]::InvalidData
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception, 'ConfigNotAnObject', $category, $fullPath)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    process {
        foreach ($item in $Name) {
            $property = $config.PSObject.Properties[$item]
            if ($null -eq $property) {
                $message = "Configuration value '$item' was not found in '$fullPath'."
                $exception = [System.Management.Automation.ItemNotFoundException]::new($message)
                $category = [System.Management.Automation.ErrorCategory]::ObjectNotFound
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'ConfigValueNotFound', $category, $item)
                $PSCmdlet.WriteError($errorRecord)
                continue
            }

            [PSCustomObject]@{
                PSTypeName = 'Example.ConfigValue'
                Name = $property.Name
                Value = $property.Value
                Path = $fullPath
            }
        }
    }
}
