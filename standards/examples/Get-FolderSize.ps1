function Get-FolderSize {
    <#
    .SYNOPSIS
    Gets the number of files in a folder and their total size.

    .DESCRIPTION
    Emits one object for each folder, with the count and the total length of the files directly
    in it. A folder that cannot be read is reported as a non-terminating error and the remaining
    folders are still processed.

    The function writes its progress, its warnings, and its failures with Write-PSFMessage. A
    script that has enabled a PSFramework logging provider gets them in its log, and a caller
    still sees them on the verbose, warning, and error streams. The PSFramework module is
    required.

    .PARAMETER LiteralPath
    One or more folders to measure. Wildcard characters are not expanded.

    .EXAMPLE
    Get-FolderSize -LiteralPath './reports'

    Gets the file count and the total size of the reports folder.

    .EXAMPLE
    './reports', './archive' | Get-FolderSize

    Measures two folders, taking the paths from the pipeline.

    .INPUTS
    System.String. You can pipe folder paths to this function.

    .OUTPUTS
    Example.FolderSize. An object with Path, FileCount, and TotalBytes properties.
    #>
    [CmdletBinding()]
    [OutputType('Example.FolderSize')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$LiteralPath
    )

    process {
        foreach ($item in $LiteralPath) {
            Write-PSFMessage -Level Verbose -Message "Measuring '$item'." -Target $item -Tag 'measure'

            try {
                $fullPath = Convert-Path -LiteralPath $item -ErrorAction Stop
                $files = @(Get-ChildItem -LiteralPath $fullPath -File -ErrorAction Stop)
            } catch {
                # The message of a file system error holds the resolved path, which can hold the
                # user name. The log gets the type of the exception, and the caller the whole error.
                $failure = @{
                    Level = 'Error'
                    Message = "Could not measure '$item': $($_.Exception.GetType().Name)."
                    Target = $item
                    Tag = 'measure', 'failure'
                }
                # PSFramework writes this level to the warning stream as well. That warning is
                # discarded: the caller gets the failure once, as an error that -ErrorAction controls.
                Write-PSFMessage @failure 3>$null
                $PSCmdlet.WriteError($_)
                continue
            }

            $totalBytes = [long]0
            foreach ($file in $files) {
                $totalBytes += $file.Length
            }

            if ($files.Count -eq 0) {
                # The path as the caller gave it. The resolved path can hold the user name.
                $message = "'$item' contains no files."
                Write-PSFMessage -Level Warning -Message $message -Target $item -Tag 'measure'
            }

            [PSCustomObject]@{
                PSTypeName = 'Example.FolderSize'
                Path = $fullPath
                FileCount = $files.Count
                TotalBytes = $totalBytes
            }
        }
    }
}
