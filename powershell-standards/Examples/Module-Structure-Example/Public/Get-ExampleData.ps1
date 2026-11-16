function Get-ExampleData {
    <#
    .EXTERNALHELP ModuleExample-Help.xml
    .SYNOPSIS
    Gets the status of one or more services.
    #>
    [CmdletBinding()]
    [OutputType('ExampleServiceResult')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$ServiceName,

        [ValidateSet('Development', 'Test', 'Production')]
        [string]$Environment = 'Development'
    )

    begin {
        $session = Connect-ExampleService -Environment $Environment
    }

    process {
        foreach ($name in $ServiceName) {
            try {
                $status = Get-ExampleServiceStatus -ServiceName $name -Session $session -ErrorAction Stop
            } catch {
                # One service that cannot be queried must not end the batch. Passing the original
                # error on as non-terminating lets the caller decide that with -ErrorAction.
                $PSCmdlet.WriteError($_)
                continue
            }

            [ExampleServiceResult]::new($name, $Environment, $status)
        }
    }
}
