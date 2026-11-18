function Get-PagedResponse {
    <#
    .SYNOPSIS
    Gets every page of a paged web request that carries a credential.

    .DESCRIPTION
    Requests the first page, follows each link that a reply marks as rel="next" in its Link header,
    and writes the body of each page as text. The credential in the request is sent with every
    page, and only to the scheme, host, and port of the first request. A next link to another
    host, a next link to a page that was already requested, a redirect, and a failed request each
    end the function with a terminating error.

    .PARAMETER Request
    The parameters of Invoke-WebRequest for the first page, as a hashtable. It must have a Uri key,
    and it holds the credential, for example in Headers, or in Authentication and Token. The
    function sets UseBasicParsing, ErrorAction, and MaximumRedirection itself.

    .EXAMPLE
    Get-PagedResponse -Request @{ Uri = 'https://api.example.com/items'; Headers = $headers } | ConvertFrom-Json

    Gets every page of the item list and converts each one from JSON. $headers holds the
    Authorization header.

    .INPUTS
    None.

    .OUTPUTS
    System.String. The body of each page.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ $_.ContainsKey('Uri') })]
        [hashtable]$Request
    )

    $firstUri = [uri]$Request['Uri']
    $pageRequest = $Request.Clone()
    $pageRequest['UseBasicParsing'] = $true
    $pageRequest['ErrorAction'] = 'Stop'
    # Invoke-WebRequest follows a redirect without the Authorization header, and the page then
    # arrives as an anonymous caller sees it. With this value a redirect is an error instead.
    $pageRequest['MaximumRedirection'] = 0
    $requestedUris = [System.Collections.Generic.HashSet[string]]::new()
    $pageUri = $firstUri
    while ($null -ne $pageUri) {
        $null = $requestedUris.Add($pageUri.AbsoluteUri)
        $pageRequest['Uri'] = $pageUri
        try {
            $response = Invoke-WebRequest @pageRequest
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }

        # A body whose content type is not a text type, such as application/vnd.api+json, is bytes.
        if ($response.Content -is [byte[]]) {
            [System.Text.Encoding]::UTF8.GetString($response.Content)
        } else {
            $response.Content
        }

        # The header value is a string on Windows PowerShell 5.1 and a list of strings on PowerShell 7.
        $linkText = ($response.Headers.GetEnumerator() |
                Where-Object -Property Key -EQ -Value 'Link' |
                ForEach-Object { $_.Value }) -join ','
        $nextUri = $null
        foreach ($link in $linkText -split ',\s*(?=<)') {
            $match = [regex]::Match($link, '^\s*<([^>]+)>.*\brel="?[^";]*\bnext\b')
            if ($match.Success) {
                $nextUri = [uri]::new($pageUri, $match.Groups[1].Value)
                break
            }
        }

        $errorId = $null
        if ($null -ne $nextUri) {
            $sameOrigin = ($nextUri.Scheme -eq $firstUri.Scheme -and $nextUri.Host -eq $firstUri.Host -and
                $nextUri.Port -eq $firstUri.Port)
            if (-not $sameOrigin) {
                $errorId = 'NextPageOnAnotherHost'
                $category = [System.Management.Automation.ErrorCategory]::SecurityError
                $message = "The next page is on another host, '$($nextUri.Host)'. It was not requested."
            } elseif ($requestedUris.Contains($nextUri.AbsoluteUri)) {
                $errorId = 'NextPageAlreadyRequested'
                $category = [System.Management.Automation.ErrorCategory]::InvalidResult
                $message = 'The next link names a page that was already requested. It was not requested again.'
            }
        }

        if ($null -ne $errorId) {
            $exception = [System.InvalidOperationException]::new($message)
            # The address is reported without its query string, which can carry a token.
            $target = $nextUri.GetLeftPart([System.UriPartial]::Path)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception, $errorId, $category, $target)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $pageUri = $nextUri
    }
}
