# PowerShell style: layout, naming, strings, paths, collections

These rules apply to every `.ps1`, `.psm1`, and `.psd1` file. Apply them to code you write or
change. Do not reformat code that the task does not otherwise touch.

## Rules

### Layout

- **STY-01** Indent with four spaces. Tabs MUST NOT be used.
- **STY-02** Use One True Brace Style: an opening brace ends the line that starts the block, a closing
  brace starts its own line, and `else`, `elseif`, `catch`, and `finally` follow that closing brace on
  the same line.
- **STY-03** Lines SHOULD NOT exceed 115 characters. Shorten a long command with splatting, or break
  the line after a pipe, comma, or operator. Backtick line continuation MUST NOT be used.
- **STY-04** Put one space around binary and assignment operators, after commas, and between a
  command, its parameter names, and their values. Padding that aligns `=` or values across lines
  MUST NOT be added.
- **STY-05** Lines MUST NOT end in whitespace, and a file MUST end with exactly one newline.
- **STY-06** Source MUST be ASCII unless a string literal needs another character: no emoji,
  typographic quotes, or en and em dashes in code or comments. Generated documentation and test
  output MUST NOT contain emoji either.
- **STY-07** Put two blank lines between a function definition and the code around it, one blank
  line between the methods of a class, and at most one blank line between statements inside a
  function.
- **STY-08** In a `param()` block, write each attribute on its own line above the parameter, and
  separate parameters with one blank line. Break a `[Parameter()]` attribute that is too long for
  one line after a comma, and indent the continuation lines by four spaces.

### Naming

- **STY-10** Name a function `Verb-Noun`, with a verb that `Get-Verb` lists and a singular PascalCase
  noun.
- **STY-11** Name parameters in PascalCase and reuse the standard names where they fit: `Path`,
  `LiteralPath`, `Name`, `Id`, `ComputerName`, `Credential`, `Force`, `PassThru`.
- **STY-12** Name local variables in descriptive camelCase without a type prefix: `$retryCount`, not
  `$RetryCount` or `$intRetryCount`.
- **STY-13** Automatic variables MUST NOT be assigned or reused as parameter, loop, or test-data
  names. The ones most often hit are `$args`, `$input`, `$matches`, `$error`, `$event`, `$host`,
  `$home`, `$pid`, `$profile`, `$sender`, `$this`, `$_`, and `$PSItem`.
- **STY-14** Call commands by their full name with named parameters. Aliases such as `gci`, `ls`,
  `%`, `?`, and `where` MUST NOT be used. One leading positional argument is acceptable where it is
  unambiguous, as in `Write-Verbose 'text'`.
- **STY-15** Write keywords and operators in lowercase (`foreach`, `-eq`), and write command,
  parameter, and type names with their defined casing (`Get-ChildItem`, `-LiteralPath`).
- **STY-16** A local variable MUST NOT have the name of a parameter in any letter case. Variable names
  are case-insensitive, so `$settings = @{}` replaces the value that was passed as `-Settings`.

### Comparisons and strings

- **STY-20** Put `$null` on the left of a comparison: `$null -eq $value`.
- **STY-21** Use single quotes for a string that needs no expansion and contains no single quote. In
  an expandable string write `$($object.Property)` for member access, and `${name}` when a colon or
  a name character follows the variable.
- **STY-22** Choose by size. For fewer than about 100 concatenations, `+=` is fine and more
  readable, and `[System.Text.StringBuilder]` SHOULD NOT be used. Build a longer string, or one
  whose size is not known, with `-join`, the `-f` operator, or `[System.Text.StringBuilder]`; there
  a string MUST NOT be extended with `+=` inside a loop.
- **STY-23** Apply the `-f` operator inside the parentheses of a command argument:
  `Write-Verbose ('{0} items' -f $count)`. Written after the closing parenthesis, `-f` is passed to
  the command as an argument.

### Paths and files

- **STY-30** Build paths with `Join-Path` or `[System.IO.Path]::Combine()`. Path separators MUST NOT be
  concatenated by hand.
- **STY-31** Locate files relative to `$PSScriptRoot`, never relative to the current location, and
  pass only absolute paths to .NET methods.
- **STY-32** Use `-LiteralPath` whenever the path names one specific item, and always for a path held
  in a variable. `-Path` is for wildcard patterns.
- **STY-33** State the encoding whenever code writes text to a file.
- **STY-34** Normalize line endings before comparing text that came from a file, a here-string, or a
  serializer, and before writing a file that is compared exactly. Read the whole file with
  `Get-Content -Raw` or `[System.IO.File]::ReadAllText()`, and compare bytes with
  `[System.IO.File]::ReadAllBytes()`.
- **STY-35** Code that does long work and then writes a file SHOULD confirm, before the work starts,
  that the file can be written, without truncating a file that is already there.

### Collections

- **STY-40** Build a collection by assigning the output of a loop or pipeline to a variable. An array
  MUST NOT be grown with `+=` inside a loop.
- **STY-41** When items are added conditionally or from several places, use
  `[System.Collections.Generic.List[T]]` with the most specific `T` that fits.
  `[System.Collections.ArrayList]` MUST NOT be used.
- **STY-42** Wrap a command call in `@()` before the code reads `.Count` or an index from its result,
  or passes the result to a parameter that needs a collection.
- **STY-43** Filter at the source: prefer a command's own filtering parameters (`-Filter`, `-Include`,
  a query) to piping everything into `Where-Object`.
- **STY-44** Prefer the `foreach` statement for a collection that is already in memory. Use the
  pipeline to stream a large dataset from its source, or input whose size is unknown.
- **STY-45** Where speed matters, prefer a language feature to a cmdlet that does the same job, as
  in `foreach` with `if` instead of `ForEach-Object` and `Where-Object`, and measure the difference.
  When `Where-Object` tests one property, prefer its comparison form,
  `Where-Object -Property Status -EQ -Value 'Running'`, to a script block.

### Preferred constructs

- **STY-50** Create a .NET object with the type's constructor, `[TypeName]::new()`, not with
  `New-Object`: `[PSCredential]::new($userName, $securePassword)`.
- **STY-51** To learn only whether something exists, call the command with
  `-ErrorAction SilentlyContinue` and test the result for `$null`. Do not force an exception for
  that. Use `try` and `catch` with `-ErrorAction Stop` when the error detail is needed or the
  failure must stop the work.

## Notes and examples

Compliant layout (STY-02, STY-03, STY-04). Splatting replaces a long line and needs no backticks:

```powershell
$copyParameters = @{
    LiteralPath = $sourcePath
    Destination = $destinationPath
    Force = $true
    ErrorAction = 'Stop'
}

if (Test-Path -LiteralPath $sourcePath) {
    Copy-Item @copyParameters
} else {
    Write-Warning "Nothing to copy: '$sourcePath' does not exist."
}
```

**STY-06.** Windows PowerShell 5.1 reads a UTF-8 file that has no byte order mark in the system ANSI
code page, so a typographic quote or dash can change how the file parses. If a file must contain
non-ASCII characters and must also run on 5.1, save it as UTF-8 with a byte order mark.

**STY-07.** A file that holds a single function needs no blank lines around it. A comment that
describes a function sits directly above it, after the two blank lines.

**STY-08.** Continuation lines are not aligned under the first argument: with this standard's
settings, PSScriptAnalyzer reports that under `PSUseConsistentIndentation`.

```powershell
param(
    [Parameter(
        Mandatory,
        ValueFromPipeline,
        ValueFromPipelineByPropertyName)]
    [string[]]$ComputerName,

    [ValidateRange(1, 100)]
    [int]$Threshold = 90
)
```

**STY-13.** A parameter named `$Input`, or a loop written as `foreach ($event in $events)`, silently
reads or replaces the automatic variable. PSScriptAnalyzer reports assignments under
`PSAvoidAssignmentToAutomaticVariable`.

**STY-16.** STY-12 writes local variables in camelCase and STY-11 writes parameters in PascalCase, but
the two spellings name the same variable. In a function that has a `-Settings` parameter, call the
local `$mergedSettings`, not `$settings`.

**STY-20.** When the left operand is a collection, `-eq` returns the matching elements instead of a
Boolean, so `$values -eq $null` does not test whether `$values` is null.

**STY-21.** `"$computer: failed"` does not parse, because PowerShell reads `$computer:` as a drive
reference. `"$state.Attempt"` parses but expands only `$state`, followed by the literal text
`.Attempt`.

```powershell
Write-Verbose "${computer}: retry $($state.Attempt) of $maximumAttempts"
```

**STY-22.** Measured on PowerShell 7.6 and Windows PowerShell 5.1: 100 concatenations take less
than a millisecond with `+=` and with `StringBuilder`. For 10,000, `+=` took 0.8 seconds on 7.6 and
2.8 seconds on 5.1, against less than 0.1 seconds for `StringBuilder` or `-join` on both.

**STY-23.** Measured on PowerShell 7.6 and Windows PowerShell 5.1:
`Write-Output ('{0} items' + ' found') -f 5` emits three objects, the unformatted text, `-f`, and
`5`, and raises no error. `Write-Warning` rejects the same call, because it has no parameter that
`-f` could mean.

```powershell
# Compliant
Write-Warning ('{0} of {1} items failed.' -f $failedCount, $totalCount)

# Non-compliant: -f and the values are arguments of Write-Warning
Write-Warning ('{0} of {1} items failed.') -f $failedCount, $totalCount
```

**STY-30.** On Windows PowerShell 5.1 `Join-Path` accepts one child path. Nest the calls in code that
must run there; `Join-Path -Path $root -ChildPath 'a' -AdditionalChildPath 'b'` needs PowerShell 6 or
later.

**STY-31.** .NET resolves a relative path against the process working directory, which `Set-Location`
does not change. Convert the path first:

```powershell
# The item may not exist yet
$fullPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)

# The item must exist
$fullPath = Convert-Path -LiteralPath $Path -ErrorAction Stop
```

**STY-32.** `-Path` treats `[`, `]`, `*`, and `?` as wildcard characters, so
`Get-Content -Path 'report[1].txt'` finds nothing. `New-Item` and `Join-Path` have no `-LiteralPath`
parameter; their `-Path` is correct.

**STY-33.** `-Encoding utf8` writes a byte order mark on Windows PowerShell 5.1 and none on
PowerShell 7. To write UTF-8 without a byte order mark on both:

```powershell
[System.IO.File]::WriteAllText($fullPath, $text, [System.Text.UTF8Encoding]::new($false))
```

In code that targets PowerShell 7 only, `-Encoding utf8NoBOM` and `-Encoding utf8BOM` state the choice
directly.

**STY-34.** The same text has different line endings depending on where it comes from. Measured on
PowerShell 7.6 and Windows PowerShell 5.1:

- A here-string takes the line endings of the script file that holds it, so it has CRLF or LF
  according to how git checked the file out.
- `ConvertTo-Json` and `Out-String` use the line ending of the platform, which is CRLF on Windows.
- `Get-Content` without `-Raw` returns the lines without their endings, which hides the difference.

A comparison that passes on a developer's computer therefore fails on a CI runner, or the reverse.
Normalize both sides, and normalize what is written when the file itself is compared:

```powershell
$expected = $expectedText.Replace("`r`n", "`n")
$actual = [System.IO.File]::ReadAllText($fullPath).Replace("`r`n", "`n")
$isSame = $actual -ceq $expected

$json = ($settings | ConvertTo-Json -Depth 5).Replace("`r`n", "`n") + "`n"
[System.IO.File]::WriteAllText($fullPath, $json, [System.Text.UTF8Encoding]::new($false))
```

A `.gitattributes` file removes the difference between checkouts; see CIC-11 in
`.github/instructions/powershell-cicd.instructions.md`.

**STY-35.** A report that takes an hour to build and then cannot be saved has wasted the hour. Check
the destination first:

```powershell
$fullPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputPath)
$existed = [System.IO.File]::Exists($fullPath)
try {
    # OpenOrCreate does not truncate, so a file that is already there keeps its content.
    $stream = [System.IO.File]::Open(
        $fullPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None)
    $stream.Dispose()
    if (-not $existed) {
        [System.IO.File]::Delete($fullPath)
    }
} catch {
    $PSCmdlet.ThrowTerminatingError($_)
}
```

The code belongs in an advanced function or script that has an `-OutputPath` parameter. Tested on
both versions: the check leaves no file behind when the file did not exist, leaves the
content of an existing file unchanged, and fails for a missing folder, a read-only file, and a file
that another process holds open.

**STY-40, STY-41.** Direct assignment is the fastest form on every version:

```powershell
# Compliant: the loop's output becomes the array
$reports = foreach ($server in $servers) {
    Get-ServerReport -ComputerName $server
}

# Compliant: items come from more than one place
$missingPaths = [System.Collections.Generic.List[string]]::new()
foreach ($requiredPath in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        $missingPaths.Add($requiredPath)
    }
}

# Non-compliant: copies the whole array on every iteration
$reports = @()
foreach ($server in $servers) {
    $reports += Get-ServerReport -ComputerName $server
}
```

Each `+=` allocates a new array and copies the old one. Measured on PowerShell 7.6, `+=` keeps pace
with `List.Add()` up to about 10,000 elements and is more than ten times slower by 40,000. On Windows
PowerShell 5.1 it is slower at every size. When reviewing existing code that targets PowerShell 7.5 or
later only, `+=` on a collection that is known to stay small is not a defect; do not write it in new
code.

`$list.Add((Get-Thing))` adds one element even when the command returns several objects. Use
`foreach` with `Add()`, or `AddRange()`, when each object should be an element.

**STY-42.** A command can emit nothing, one object, or many. Under strict mode, `.Count` on a single
object and an index past the end are errors. Apply `@()` to the call, not to a variable that may hold
`$null`: `@($null).Count` is 1.

```powershell
$logFiles = @(Get-ChildItem -LiteralPath $logDirectory -Filter '*.log' -File)
if ($logFiles.Count -eq 0) {
    Write-Warning "No log files were found in '$logDirectory'."
}
```

A function that writes an empty array gives its caller nothing, which is `$null` once it is assigned,
because PowerShell unrolls the array on the way out. `@()` around the call restores the empty array.
The function can instead return the array whole with `Write-Output -NoEnumerate`. Use one remedy or
the other: `@()` around a call that returns with `-NoEnumerate` gives an array of one element, which
is the array. A mandatory collection parameter rejects both `$null` and an empty array unless it
carries `[AllowEmptyCollection()]`.

**STY-44, STY-45.** Measured with 200,000 objects in memory, on PowerShell 7.6 and on Windows
PowerShell 5.1: a `foreach` statement with `if` filtered them in 0.2 and 0.3 seconds, `Where-Object`
in its comparison form in 1.1 and 2.0 seconds, and `Where-Object` with a script block in 1.7 and 3.0
seconds. A pipeline of `Where-Object` and `ForEach-Object` took 2.5 and 3.6 seconds where one
`foreach` statement took 0.3 on both. The pipeline earns its place when the data is streamed from
its source and is never held whole in memory.

**STY-50.** `::new()` is available from PowerShell 5.0. Measured for 20,000 objects: `New-Object`
took 0.36 seconds against 0.07 on PowerShell 7.6, and 2.1 seconds against 0.01 on Windows
PowerShell 5.1.

**STY-51.** A null test is enough when only the presence matters:

```powershell
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($null -eq $service) {
    Write-Verbose "Service '$serviceName' is not installed."
}
```

`-ErrorAction SilentlyContinue` silences a non-terminating error only. A command that raises a
terminating error, as `ConvertFrom-Json` does for invalid text, still needs `try` (ERR-20).
