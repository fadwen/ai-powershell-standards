# A class gives the output of Get-ExampleData a type name that [OutputType()], the help, and the
# tests can refer to, and it keeps IsUsable() beside the data that the method reads.
class ExampleServiceResult {
    [string]$ServiceName
    [string]$Environment

    [ValidateSet('Healthy', 'Degraded', 'Unavailable')]
    [string]$Status

    [datetime]$CheckedAt

    ExampleServiceResult([string]$ServiceName, [string]$Environment, [string]$Status) {
        $this.ServiceName = $ServiceName
        $this.Environment = $Environment
        $this.Status = $Status
        $this.CheckedAt = Get-Date
    }

    [bool] IsUsable() {
        return $this.Status -in 'Healthy', 'Degraded'
    }

    [string] ToString() {
        return "$($this.ServiceName) [$($this.Environment)]: $($this.Status)"
    }
}
