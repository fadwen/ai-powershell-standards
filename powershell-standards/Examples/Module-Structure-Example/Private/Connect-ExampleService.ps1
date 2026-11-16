function Connect-ExampleService {
    <#
    .SYNOPSIS
    Creates the session that the module uses to query the example service.

    .DESCRIPTION
    Returns a hashtable that names the environment and the endpoint of its service. There is no
    real service behind this module, so no connection is opened.

    The manifest does not export this function, so its parameters and its output can change
    without breaking a caller of the module.

    .PARAMETER Environment
    Environment whose service the session targets.

    .EXAMPLE
    $session = Connect-ExampleService -Environment 'Test'

    Creates a session for the Test environment and keeps it in a variable.

    .INPUTS
    None. You cannot pipe objects to this function.

    .OUTPUTS
    System.Collections.Hashtable. A session with the keys Environment and Endpoint.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Development', 'Test', 'Production')]
        [string]$Environment
    )

    @{
        Environment = $Environment
        Endpoint = "https://service.example.com/$($Environment.ToLowerInvariant())"
    }
}
