function Get-BasicServerInfo {
    <#
    .SYNOPSIS
    Gets operating system and hardware information from Windows computers.

    .DESCRIPTION
    Opens a CIM session to each computer, reads its operating system and computer system
    information, and emits one object for each computer. A computer that cannot be queried is
    reported as a non-terminating error and the remaining computers are still processed. Each
    session is closed before the next computer is queried.

    .PARAMETER ComputerName
    One or more computer names, as NetBIOS names or fully qualified domain names. A name starts
    with a letter or a digit and contains only letters, digits, hyphens, and dots.

    .PARAMETER Credential
    Credential for the CIM sessions. Without it, the sessions use the identity of the current
    user.

    .PARAMETER IncludeServices
    Adds the running services of each computer to the RunningServices property.

    .EXAMPLE
    Get-BasicServerInfo -ComputerName 'SERVER01'

    Gets operating system and hardware information from SERVER01.

    .EXAMPLE
    'WEB01', 'WEB02' | Get-BasicServerInfo -IncludeServices

    Takes the computer names from the pipeline and adds the running services of each computer.

    .EXAMPLE
    Get-BasicServerInfo -ComputerName 'DB01' -Credential (Get-Credential)

    Asks for a credential and uses it to query DB01.

    .INPUTS
    System.String. You can pipe computer names, or objects that have a ComputerName property, to
    this function.

    .OUTPUTS
    Example.ServerInfo. An object with ComputerName, OperatingSystem, Version, Architecture,
    LastBootTime, UptimeDays, Manufacturer, Model, Domain, TotalMemoryGB, LogicalProcessors, and
    RunningServices properties. RunningServices is empty unless IncludeServices is specified.
    #>
    [CmdletBinding()]
    [OutputType('Example.ServerInfo')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]{0,254}$')]
        [Alias('CN', 'ServerName')]
        [string[]]$ComputerName,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [Parameter()]
        [switch]$IncludeServices
    )

    begin {
        $sessionParameters = @{
            ErrorAction = 'Stop'
        }
        if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
            $sessionParameters['Credential'] = $Credential
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            $cimSession = $null
            try {
                Write-Verbose "Querying '$computer'."
                $cimSession = New-CimSession -ComputerName $computer @sessionParameters
                $queryParameters = @{
                    CimSession = $cimSession
                    ErrorAction = 'Stop'
                }
                $operatingSystem = Get-CimInstance -ClassName 'Win32_OperatingSystem' @queryParameters
                $computerSystem = Get-CimInstance -ClassName 'Win32_ComputerSystem' @queryParameters

                $runningServices = @()
                if ($IncludeServices) {
                    $serviceParameters = @{
                        ClassName = 'Win32_Service'
                        Filter = 'State = "Running"'
                    }
                    $runningServices = @(
                        Get-CimInstance @serviceParameters @queryParameters |
                            Select-Object -Property Name, DisplayName, StartMode
                    )
                }

                $uptime = (Get-Date) - $operatingSystem.LastBootUpTime
                $serverInfo = [PSCustomObject]@{
                    PSTypeName = 'Example.ServerInfo'
                    ComputerName = $computer
                    OperatingSystem = $operatingSystem.Caption
                    Version = $operatingSystem.Version
                    Architecture = $operatingSystem.OSArchitecture
                    LastBootTime = $operatingSystem.LastBootUpTime
                    UptimeDays = [math]::Round($uptime.TotalDays, 2)
                    Manufacturer = $computerSystem.Manufacturer
                    Model = $computerSystem.Model
                    Domain = $computerSystem.Domain
                    TotalMemoryGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
                    LogicalProcessors = $computerSystem.NumberOfLogicalProcessors
                    RunningServices = $runningServices
                }
            } catch {
                $message = "Server information could not be read from '$computer'. $($_.Exception.Message)"
                $exception = [System.InvalidOperationException]::new($message, $_.Exception)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'ServerInfoQueryFailed', $_.CategoryInfo.Category, $computer)
                $PSCmdlet.WriteError($errorRecord)
                continue
            } finally {
                if ($null -ne $cimSession) {
                    Remove-CimSession -CimSession $cimSession
                }
            }

            # Emitted outside the try block. An exception thrown by a script block further down the
            # pipeline would otherwise be caught above and reported as a failed query.
            $serverInfo
        }
    }
}
