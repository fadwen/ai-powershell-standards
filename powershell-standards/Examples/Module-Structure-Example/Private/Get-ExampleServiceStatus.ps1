function Get-ExampleServiceStatus {
    <#
    .SYNOPSIS
    Gets the status of one service.

    .DESCRIPTION
    Looks the service name up in a fixed table that stands in for a real service, and returns
    the status found there. A name that is not in the table is a terminating error with the
    error ID ServiceNotFound.

    Get-ExampleData calls this function once for each service name. It reports a failure as a
    non-terminating error, so that the remaining names are still processed.

    .PARAMETER ServiceName
    Name of the service to query. The names in the table are Billing, Identity, and Reporting.

    .PARAMETER Session
    Session that Connect-ExampleService returned.

    .EXAMPLE
    Get-ExampleServiceStatus -ServiceName 'Billing' -Session (Connect-ExampleService -Environment 'Test')

    Gets the status of the Billing service in the Test environment.

    .INPUTS
    None. You cannot pipe objects to this function.

    .OUTPUTS
    System.String. One of Healthy, Degraded, or Unavailable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,

        [Parameter(Mandatory)]
        [hashtable]$Session
    )

    # There is no real service. This table stands in for one, so that a batch returns different
    # statuses and an unknown name gives the caller a real failure to handle.
    $statusByService = @{
        Billing = 'Healthy'
        Identity = 'Degraded'
        Reporting = 'Unavailable'
    }

    Write-Verbose "Querying '$ServiceName' at $($Session['Endpoint'])."

    if (-not $statusByService.ContainsKey($ServiceName)) {
        $message = "Service '$ServiceName' was not found in the $($Session['Environment']) environment."
        $exception = [System.Management.Automation.ItemNotFoundException]::new($message)
        $category = [System.Management.Automation.ErrorCategory]::ObjectNotFound
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'ServiceNotFound', $category, $ServiceName)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $statusByService[$ServiceName]
}
