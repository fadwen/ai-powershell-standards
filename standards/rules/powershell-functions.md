# PowerShell functions: structure, parameters, output

These rules apply to every function in a `.ps1` or `.psm1` file. The function template in the core
instructions shows them together.

## Rules

### Structure

- **FUN-01** Write every function as an advanced function, with `[CmdletBinding()]` and a `param()`
  block. `$args` MUST NOT be used.
- **FUN-02** A function does one job and returns objects. Formatting (`Format-*`), `Out-*`, and
  `Write-Host` belong in the script that calls it, not in a reusable function.
- **FUN-03** State kept between calls lives in `$script:` variables. `$global:` variables MUST NOT be
  created.
- **FUN-04** `return` in a `begin` block ends only that block; `process` and `end` still run. To stop
  the command there, call `$PSCmdlet.ThrowTerminatingError()`, or set a variable and test it at the
  top of `process`.
- **FUN-05** Code that runs in `Start-Job`, a runspace, or `ForEach-Object -Parallel` does not see the
  caller's variables, `$script:` state, or the module's private functions. Pass what it needs with
  `-ArgumentList`, `$using:`, or a parameter, and keep a contract test that refuses a `$script:`
  read inside such a block.
- **FUN-06** Inside a nested function, `$PSBoundParameters` is that function's own. Capture what the
  nested function needs from the outer one in a plain variable before defining it.

### Output

- **FUN-10** Declare `[OutputType()]` with the type the function emits. For a custom object, name the
  type as a string and set `PSTypeName` on the object. `[OutputType([PSCustomObject])]` MUST NOT be
  used.
- **FUN-11** Write each object to the pipeline as soon as it is ready. A function MUST NOT collect
  its results in a list and return the list at the end.
- **FUN-12** Only intended output may reach the success stream. Discard a value returned by a method
  or command that is called for its side effect, with `$null = ...` or `[void](...)`.

### Parameters

- **FUN-20** Give every parameter a type. Use `[switch]` for a flag, never `[bool]`, and never give a
  switch a default of `$true`.
- **FUN-21** A parameter that accepts pipeline input MUST be handled in a `process` block. Declare it
  as an array and loop over it there, so that pipeline input and a directly passed array behave the
  same way.
- **FUN-22** Validate input with attributes so that a bad value fails at binding: `ValidateSet`,
  `ValidateRange`, `ValidatePattern`, `ValidateScript`, `ValidateNotNullOrEmpty`. A default value is
  not validated, so it MUST itself be valid.
- **FUN-23** Do not add `[ValidateNotNullOrEmpty()]` to a mandatory `[string]` parameter; mandatory
  binding already rejects `$null` and an empty string. Reject whitespace-only text with a validation
  attribute where one fits; FUN-27 covers the check in the function body.
- **FUN-24** At most the first one or two parameters SHOULD be positional. When only some are, set
  `[CmdletBinding(PositionalBinding = $false)]` and mark those parameters with `Position`.
- **FUN-25** A function that reduces its pipeline input to one result collects the input in `process`
  and emits the result in `end`, so that piped input and an array argument give the same answer.
- **FUN-26** Read data that came from an API or a file through one accessor that handles both a
  dictionary and an object. Index syntax (`$data['key']`) reads only a dictionary, and member syntax
  (`$data.key`) can return a dictionary's own property instead of the data.
- **FUN-27** A parameter value MUST NOT be passed to another command before the function knows that
  it has a value. An optional `[string]` that the caller omitted is an empty string, and its
  validation attributes do not run. Before a critical operation, also test the value in the
  function body, end with `$PSCmdlet.ThrowTerminatingError()` when it is empty or whitespace, and
  pass on the trimmed value.

### State changes

- **FUN-30** A function that changes state MUST declare `SupportsShouldProcess` and guard every change
  with `$PSCmdlet.ShouldProcess()`. Add `ConfirmImpact = 'High'` when the change is destructive.
- **FUN-31** A read-only function, such as one with the verb `Get`, `Test`, or `Find`, MUST NOT
  declare `SupportsShouldProcess`.
- **FUN-32** A command that asks for confirmation beyond `ShouldProcess` MUST offer `-Force` for
  unattended use, and MUST treat a session that cannot answer as a refusal.
- **FUN-33** `-WhatIf` sets `$WhatIfPreference` for every command and script that the function calls.
  Pass `-WhatIf:$false` to a call that must still run, and enumerate with a script block, not with
  `ForEach-Object -MemberName`, which returns nothing under `-WhatIf`.

## Notes and examples

The fragments below omit comment-based help to stay short. A real function carries it.

**FUN-04.** A `return` in `begin` that was meant to cancel the command lets `process` run for every
input object. Record the decision and act on it in `process`:

```powershell
begin {
    $targetExists = Test-Path -LiteralPath $LiteralPath
}

process {
    if (-not $targetExists) {
        return
    }

    foreach ($item in $Name) {
        Remove-ReportEntry -LiteralPath $LiteralPath -Name $item
    }
}
```

**FUN-05.** A job starts in a new process, and a runspace or parallel block starts without the
calling scope. A read of `$script:` state there returns `$null`, a call to a private function fails
only inside the worker, and a Pester mock does not reach the worker either. No error appears in the
caller unless the worker's output is checked.

```powershell
$results = $computerNames | ForEach-Object -Parallel {
    Test-Connection -TargetName $_ -Count 1 -TimeoutSeconds $using:timeoutSeconds -Quiet
} -ThrottleLimit 8
```

Measure before making code parallel. A module that keeps one session for each process can fail
under runspaces in ways that separate processes do not.

The contract test parses each source file and fails when a `$script:` variable appears inside the
script block of `Start-Job`, `Start-ThreadJob`, or `ForEach-Object -Parallel`.

**FUN-06.** Tested on PowerShell 7.6 and Windows PowerShell 5.1: called from a function that was
given `-Force`, a nested function finds no `Force` key in `$PSBoundParameters`, and it does see a
variable that the outer function assigned first.

**FUN-10.** `PSTypeName` becomes the object's first type name. It is not a property of the object, so
read it with `$object.PSObject.TypeNames[0]`, not `$object.PSTypeName`.

```powershell
[CmdletBinding()]
[OutputType('Contoso.DiskReport')]
param()

[PSCustomObject]@{
    PSTypeName = 'Contoso.DiskReport'
    Name = $drive.Name
    FreeGigabytes = [math]::Round($drive.Free / 1GB, 1)
}
```

For a class that the module defines, write the class name as a string too
(`[OutputType('DiskReport')]`), so that the function file parses before the class is loaded.

**FUN-11, FUN-21.** Streaming keeps memory flat and lets the caller stop early. A caller that needs an
array wraps the call: `$reports = @(Get-DiskReport)`.

```powershell
function Get-FileHashSummary {
    [CmdletBinding()]
    [OutputType('Contoso.FileHashSummary')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$LiteralPath
    )

    process {
        foreach ($item in $LiteralPath) {
            $hash = Get-FileHash -LiteralPath $item -Algorithm SHA256 -ErrorAction Stop
            [PSCustomObject]@{
                PSTypeName = 'Contoso.FileHashSummary'
                Path = $hash.Path
                Hash = $hash.Hash
            }
        }
    }
}
```

Without the `process` block, a function that receives pipeline input runs once, with the last item
only.

**FUN-12.** Anything a statement returns and nothing captures becomes function output. Common
sources are `StringBuilder.Append()`, `HashSet.Add()`, `Dictionary.Remove()`, and `New-Item`.

```powershell
$null = $builder.AppendLine($line)
$null = New-Item -Path $reportDirectory -ItemType Directory -Force
```

**FUN-23.** `[ValidateNotNullOrWhiteSpace()]` exists in PowerShell 7.6 but not in Windows
PowerShell 5.1.

```powershell
# PowerShell 7.6
[Parameter(Mandatory)]
[ValidateNotNullOrWhiteSpace()]
[string]$DisplayName

# Also valid on Windows PowerShell 5.1
[Parameter(Mandatory)]
[ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
[string]$DisplayName
```

**FUN-25.** Passed by parameter, a collection reaches `process` once, as one argument. Piped, it is
unrolled and `process` runs once for each element. A function that folds its input into one result
therefore gives a different answer on each path unless it collects first. No error is raised either
way, and every result has the declared type.

```powershell
function Get-SizeSummary {
    [CmdletBinding()]
    [OutputType('Contoso.SizeSummary')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [long[]]$Length
    )

    begin {
        $lengths = [System.Collections.Generic.List[long]]::new()
    }

    process {
        foreach ($item in $Length) {
            $lengths.Add($item)
        }
    }

    end {
        [PSCustomObject]@{
            PSTypeName = 'Contoso.SizeSummary'
            Count = $lengths.Count
            Total = ($lengths | Measure-Object -Sum).Sum
        }
    }
}
```

Without the `end` block, `10, 20, 30 | Get-SizeSummary` emits three summaries of one item each. This
is the one case where a function holds its input: FUN-11 still applies to its results. When the
parameter is typed `[object]`, decide what one element arriving alone means, and write that
decision into the function. A whole input that is itself one object, such as an envelope with a
`value` property or a JSON string, is folded as it arrives, so piping several whole inputs still
yields one result each. Test for `[string]` and `[hashtable]` before testing for `IEnumerable`: a
string enumerates as characters and a hashtable as entries, and each is one object. Test both
paths, as TST-44 requires.

`Get-FoldedOutcome` stands for the module's own function that folds a set into one outcome:

```powershell
function ConvertTo-Outcome {
    [CmdletBinding()]
    [OutputType('Module.Outcome')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject
    )

    begin {
        # Elements piped in one at a time are held here and folded together in end
        $loose = [System.Collections.Generic.List[object]]::new()
    }

    process {
        # A lone element is a single object without the envelope's value property. A string is
        # IEnumerable (of characters) and a hashtable is IEnumerable (of entries), so both are
        # settled before the enumerable check.
        $isLoneElement = $null -ne $InputObject -and $InputObject -isnot [string] -and
            ($InputObject -is [hashtable] -or $InputObject -isnot [System.Collections.IEnumerable])
        if ($isLoneElement) {
            if ($InputObject -is [hashtable]) {
                $isLoneElement = -not $InputObject.ContainsKey('value')
            } else {
                $isLoneElement = -not $InputObject.PSObject.Properties['value']
            }
        }

        if ($isLoneElement) {
            $loose.Add($InputObject)
        } else {
            # A whole input arrived at once: a collection by parameter, an envelope, a JSON string
            Get-FoldedOutcome -Response $InputObject
        }
    }

    end {
        if ($loose.Count -gt 0) {
            Get-FoldedOutcome -Response $loose.ToArray()
        }
    }
}
```

Run on PowerShell 7.6 and Windows PowerShell 5.1: three elements give one outcome piped and by
parameter, and two piped envelopes or two piped JSON strings give two.

**FUN-26.** The same JSON reaches a function in two shapes. `ConvertFrom-Json` returns objects, or
dictionaries with `-AsHashtable` (PowerShell 7 only). `Invoke-MgGraphRequest` returns dictionaries
unless `-OutputType PSObject` is passed. A fixture read back from disk comes through
`ConvertFrom-Json`. Measured on PowerShell 7.6 and Windows PowerShell 5.1:

| Read | Dictionary | Object |
| --- | --- | --- |
| `$data['value']` | The value | `$null`; an error under strict mode |
| `$data.value` | The value | The value |
| `$data.missing` | `$null`; an error under strict mode | `$null`; an error under strict mode |
| `$data.Count` | The entry named `Count` when there is one, otherwise the number of entries | The property when there is one; otherwise `1` on PowerShell 7, and `$null` or a strict-mode error on 5.1 |

Without strict mode, code written for one shape computes from `$null` when it meets the other, and
nothing fails. One private accessor removes the difference:

```powershell
function Get-ResponseProperty {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return $property.Value
    }
    return $null
}
```

Like any function, it unrolls a collection on the way out, so wrap a read of a collection in `@()`
(STY-42). Test the public function with both shapes, and keep fixtures real: a recorded response
with its identifiers rewritten.

**FUN-27.** Tested on PowerShell 7.6 and Windows PowerShell 5.1: an optional `[string]` that the
caller omitted is `''` even when it carries `[ValidateNotNullOrEmpty()]`, and a mandatory `[string]`
accepts `'   '`. Passed on, the empty value fails in the other command with `Cannot bind argument to
parameter 'Server' because it is an empty string`, or is accepted there without an error when that
parameter is optional.

```powershell
$server = $ServerName.Trim()
if (-not $server) {
    $exception = [System.ArgumentException]::new('ServerName cannot be empty or whitespace.')
    $category = [System.Management.Automation.ErrorCategory]::InvalidArgument
    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $exception, 'ServerNameEmpty', $category, $ServerName)
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}

$connection = Connect-Database -Server $server -ErrorAction Stop
```

**FUN-30.** `ShouldProcess` gives the caller `-WhatIf` and `-Confirm`:

```powershell
function Remove-StaleReport {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath,

        [ValidateRange(1, 3650)]
        [int]$OlderThanDays = 30
    )

    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $staleFiles = Get-ChildItem -LiteralPath $LiteralPath -Filter '*.html' -File -ErrorAction Stop |
        Where-Object { $_.LastWriteTime -lt $cutoff }

    foreach ($file in $staleFiles) {
        if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove report')) {
            Remove-Item -LiteralPath $file.FullName -ErrorAction Stop
        }
    }
}
```

**FUN-31.** A read-only function has nothing to confirm. If it wraps its query in `ShouldProcess()`,
`-WhatIf` makes the query return nothing. If it declares the attribute and never calls
`ShouldProcess()`, PSScriptAnalyzer reports `PSShouldProcess`.

**FUN-32.** `Read-Host` and `$PSCmdlet.ShouldContinue()` cannot be answered in an unattended session:
the prompt fails, returns nothing, or waits. A confirmation that compares the answer with a word
must take anything else, including no answer, as a refusal, and `-Force` is how a scheduled job says
yes. See SEC-05 for values that are missing.

**FUN-33.** Measured on PowerShell 7.6 and Windows PowerShell 5.1: under `-WhatIf`,
`$items | ForEach-Object -MemberName Name` returns nothing, because that parameter set calls
`ShouldProcess` for each object, while `$items | ForEach-Object { $_.Name }` returns the names. A
script that the function calls also runs its cmdlets under `-WhatIf`, even when the script does not
declare `SupportsShouldProcess`. A release script depends on this; see MOD-14 in
`.github/instructions/powershell-modules.instructions.md`.
