#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Get-PagedResponse.ps1')
}

Describe 'Get-PagedResponse' -Tag 'Unit', 'Public' {
    BeforeAll {
        $itemsUri = 'https://api.example.com/items'
        $secondUri = 'https://api.example.com/items?page=2'
        $headers = @{ Authorization = 'placeholder' }
    }

    BeforeEach {
        # A request that no test expects fails here and never reaches the network.
        Mock -CommandName Invoke-WebRequest -MockWith {
            throw [System.InvalidOperationException]::new("Unexpected request for $Uri")
        }
        Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri.AbsoluteUri -eq $secondUri } -MockWith {
            [PSCustomObject]@{ Content = '{"page":2}'; Headers = @{} }
        }
    }

    Context 'Parameter Validation' {
        It 'Declares Request as a mandatory hashtable' {
            Get-Command -Name Get-PagedResponse |
                Should-HaveParameter -ParameterName 'Request' -Type ([hashtable]) -Mandatory
        }

        It 'Rejects a request that has no Uri key' {
            { Get-PagedResponse -Request @{ Headers = $headers } } |
                Should-Throw -FullyQualifiedErrorId 'ParameterArgumentValidationError,Get-PagedResponse'
            Should-Invoke -CommandName Invoke-WebRequest -Times 0 -Exactly
        }
    }

    Context 'Core Functionality' {
        BeforeEach {
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri.AbsoluteUri -eq $itemsUri } -MockWith {
                $link = '<https://api.example.com/items?page=2>; rel="next"'
                [PSCustomObject]@{ Content = '{"page":1}'; Headers = @{ Link = $link } }
            }
        }

        It 'Writes the body of each page, in order' {
            $result = @(Get-PagedResponse -Request @{ Uri = $itemsUri; Headers = $headers })

            $result | Should-BeCollection -Count 2
            $result[0] | Should-Be '{"page":1}'
            $result[1] | Should-Be '{"page":2}'
        }

        It 'Sends the credential with every page and lets no redirect be followed' {
            $null = Get-PagedResponse -Request @{ Uri = $itemsUri; Headers = $headers }

            Should-Invoke -CommandName Invoke-WebRequest -Times 2 -Exactly -ParameterFilter {
                $Headers['Authorization'] -eq 'placeholder' -and $MaximumRedirection -eq 0
            }
        }

        It 'Overrides a MaximumRedirection value that the caller passes' {
            $null = Get-PagedResponse -Request @{ Uri = $itemsUri; Headers = $headers; MaximumRedirection = 5 }

            Should-Invoke -CommandName Invoke-WebRequest -Times 2 -Exactly -ParameterFilter {
                $MaximumRedirection -eq 0
            }
        }

        It 'Leaves the hashtable of the caller unchanged' {
            $request = @{ Uri = $itemsUri; Headers = $headers }

            $null = Get-PagedResponse -Request $request

            $request.Count | Should-Be 2
            $request['Uri'] | Should-Be $itemsUri
        }

        It 'Runs the example in its help' {
            $result = @(
                Get-PagedResponse -Request @{ Uri = 'https://api.example.com/items'; Headers = $headers } |
                    ConvertFrom-Json
            )

            $result | Should-BeCollection -Count 2
            $result[0].page | Should-Be 1
            $result[1].page | Should-Be 2
        }
    }

    Context 'Link Headers' {
        It 'Follows <Description>' -ForEach @(
            @{ Description = 'a relative link'; Name = 'Link'; Value = '</items?page=2>; rel="next"' }
            @{
                Description = 'a relation without quotes'
                Name = 'Link'
                Value = '<https://api.example.com/items?page=2>; rel=next'
            }
            @{
                Description = 'the next link among other relations'
                Name = 'Link'
                Value = '<https://api.example.com/items?page=9>; rel="last", </items?page=2>; rel="next"'
            }
            @{
                Description = 'a header named in lower case'
                Name = 'link'
                Value = '<https://api.example.com/items?page=2>; rel="next"'
            }
            @{
                Description = 'a header value that is a list'
                Name = 'Link'
                Value = @('<https://api.example.com/items?page=2>; rel="next"')
            }
        ) {
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri.AbsoluteUri -eq $itemsUri } -MockWith {
                [PSCustomObject]@{ Content = '{"page":1}'; Headers = @{ $Name = $Value } }
            }

            $result = @(Get-PagedResponse -Request @{ Uri = $itemsUri; Headers = $headers })

            $result | Should-BeCollection -Count 2
            $result[1] | Should-Be '{"page":2}'
        }

        It 'Stops at a page whose links name no next page' {
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri.AbsoluteUri -eq $itemsUri } -MockWith {
                $reply = '<https://api.example.com/items?page=2>; rel="prev"'
                [PSCustomObject]@{ Content = '{"page":1}'; Headers = @{ Link = $reply } }
            }

            $result = @(Get-PagedResponse -Request @{ Uri = $itemsUri; Headers = $headers })

            $result | Should-BeCollection -Count 1
        }

        It 'Converts a body that arrives as bytes to text' {
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri.AbsoluteUri -eq $itemsUri } -MockWith {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"page":1}')
                [PSCustomObject]@{ Content = $bytes; Headers = @{} }
            }

            $result = @(Get-PagedResponse -Request @{ Uri = $itemsUri; Headers = $headers })

            $result | Should-BeCollection -Count 1
            $result[0] | Should-HaveType ([string])
            $result[0] | Should-Be '{"page":1}'
        }
    }

    Context 'Error Handling' {
        It 'Does not request a next page that is on <Description>' -ForEach @(
            @{ Description = 'another host'; Target = 'https://other.example.net/items?page=2' }
            @{ Description = 'another scheme'; Target = 'http://api.example.com/items?page=2' }
            @{ Description = 'another port'; Target = 'https://api.example.com:8443/items?page=2' }
        ) {
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri.AbsoluteUri -eq $itemsUri } -MockWith {
                [PSCustomObject]@{ Content = '{"page":1}'; Headers = @{ Link = "<$Target>; rel=`"next`"" } }
            }

            { Get-PagedResponse -Request @{ Uri = $itemsUri; Headers = $headers } } |
                Should-Throw -FullyQualifiedErrorId 'NextPageOnAnotherHost,Get-PagedResponse'
            Should-Invoke -CommandName Invoke-WebRequest -Times 1 -Exactly
        }

        It 'Stops when a next link names a page that was already requested' {
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri.AbsoluteUri -eq $itemsUri } -MockWith {
                $reply = '<https://api.example.com/items?page=2>; rel="next"'
                [PSCustomObject]@{ Content = '{"page":1}'; Headers = @{ Link = $reply } }
            }
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri.AbsoluteUri -eq $secondUri } -MockWith {
                $reply = '<https://api.example.com/items>; rel="next"'
                [PSCustomObject]@{ Content = '{"page":2}'; Headers = @{ Link = $reply } }
            }

            { Get-PagedResponse -Request @{ Uri = $itemsUri; Headers = $headers } } |
                Should-Throw -FullyQualifiedErrorId 'NextPageAlreadyRequested,Get-PagedResponse'
            Should-Invoke -CommandName Invoke-WebRequest -Times 2 -Exactly
        }

        It 'Passes on the error of a request that fails' {
            Mock -CommandName Invoke-WebRequest -ParameterFilter { $Uri.AbsoluteUri -eq $itemsUri } -MockWith {
                throw [System.Net.WebException]::new('The request was refused.')
            }

            { Get-PagedResponse -Request @{ Uri = $itemsUri; Headers = $headers } } |
                Should-Throw -ExceptionType ([System.Net.WebException])
        }
    }

    Context 'Performance Requirements' {
        It 'Follows 100 pages in less than five seconds' {
            Mock -CommandName Invoke-WebRequest -MockWith {
                $page = [int]('0' + ($Uri.Query -replace '\D', ''))
                $replyHeaders = @{}
                if ($page -lt 99) {
                    $replyHeaders['Link'] = "</records?page=$($page + 1)>; rel=`"next`""
                }
                [PSCustomObject]@{ Content = "{`"page`":$page}"; Headers = $replyHeaders }
            }
            $request = @{ Uri = 'https://api.example.com/records'; Headers = $headers }

            { Get-PagedResponse -Request $request } | Should-BeFasterThan '5s'
            Should-Invoke -CommandName Invoke-WebRequest -Times 100 -Exactly
        }
    }
}
