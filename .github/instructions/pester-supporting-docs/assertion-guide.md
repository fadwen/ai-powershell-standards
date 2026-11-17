# Pester 6 Assertion Guide

Reference for the `Should-*` assertions. The rules are TST-10 to TST-17 in the
[Pester rules](../powershell-pester.instructions.md); this guide holds the detail behind them. Every
statement about behaviour was checked by running it on Pester 6.2.0.

## Which Syntax To Use

Pester 6 has two assertion styles: the `Should-*` commands (`Should-Be`) and the classic operator
(`Should -Be`). TST-10 decides between them: `Should-*` in a new file, the existing style in an
existing file, never both in one file.

Setting `Should.DisableV5 = $true` makes every classic assertion fail with
`Pester Should -Be syntax is disabled`. Leave it at its default until no test file uses that style.

## What The Should-* Assertions Change

- Each assertion does one job, so its options are its own (`Should-BeString -IgnoreWhitespace`) and
  its failure message is specific: a caret under the first differing character of a string, a line
  diff for a long string, the missing and extra values of a collection with the index of each.
- `-Expected` decides how the values are compared. `1 | Should-Be $true` and `'1' | Should-Be 1` both
  pass, so assert the type as well when the type matters.
- `$null`, an empty collection, and a single-item array are handled by the same rules in every
  assertion of a family. The table under "Pipeline Or -Actual" lists them.
- A value assertion refuses a collection as `-Expected`. `Should-Be -Expected @(1, 2)` is an error
  that names `Should-BeCollection`.
- The set can be extended. See the [custom assertion guide](./custom-assertions.md).

## Pipeline Or -Actual

The value under test comes from the pipeline or from `-Actual`:

```powershell
1 | Should-Be -Expected 1
Should-Be -Actual 1 -Expected 1
```

The pipeline unrolls its input, and the two kinds of assertion read the result differently:

| Piped input | A value assertion sees | A collection assertion sees |
| --- | --- | --- |
| `1` or `@(1)` | `1` | one item |
| `@()` | `$null` | no items |
| `$null` | `$null` | one item, which is `$null` |
| `1, 2, 3` | one `[Object[]]`, and the failure message says so | three items |
| `[int[]](1, 2)` | `[Object[]]`; the element type is lost | two items |

Pass the value with `-Actual` when its exact type matters:

```powershell
Should-HaveType -Actual ([int[]](1, 2)) -Expected ([int[]])
```

When a value assertion fails on a piped collection, the message ends with a hint that explains what
the pipeline did and points to `-Actual`.

## Migration Map: Should -Be To Should-*

| Classic | Pester 6 | Notes |
| --- | --- | --- |
| `Should -Be $x` | `Should-Be $x` | |
| `Should -Not -Be $x` | `Should-NotBe $x` | |
| `Should -BeExactly $x` | `Should-BeString $x -CaseSensitive` | For strings |
| `Should -BeOfType [T]` | `Should-HaveType ([T])` | Not with `[PSCustomObject]`; see Types |
| `Should -Not -BeOfType [T]` | `Should-NotHaveType ([T])` | |
| `Should -Match 'regex'` | `Should-MatchString 'regex'` | |
| `Should -Not -Match 'regex'` | `Should-NotMatchString 'regex'` | |
| `Should -BeLike 'pat*'` | `Should-BeLikeString 'pat*'` | |
| `Should -BeTrue` / `-BeFalse` | `Should-BeTrue` / `Should-BeFalse` | Only a real `[bool]` passes |
| `Should -BeNullOrEmpty` | `Should-BeNull`, `Should-BeEmptyString`, or `Should-BeFalsy` | No single equivalent |
| `Should -Not -BeNullOrEmpty` | `Should-NotBeNull`, `Should-NotBeEmptyString`, or `Should-BeTruthy` | No single equivalent |
| `Should -BeGreaterThan $x` | `Should-BeGreaterThan $x` | |
| `Should -BeLessThan $x` | `Should-BeLessThan $x` | |
| `Should -BeGreaterOrEqual $x` | `Should-BeGreaterThanOrEqual $x` | Name changed |
| `Should -BeLessOrEqual $x` | `Should-BeLessThanOrEqual $x` | Name changed |
| `Should -Contain $item` | `Should-ContainCollection $item` | |
| `$item \| Should -BeIn $list` | `$list \| Should-ContainCollection $item` | The list is piped. `$list \| Should-Any { $_ -eq $item }` also works |
| `Should -HaveCount 3` | `Should-BeCollection -Count 3` | |
| `Should -Throw '*msg*'` | `Should-Throw -ExceptionMessage '*msg*'` | Both need the wildcards |
| `Should -Invoke Cmd` | `Should-Invoke Cmd` | |
| `Should -Not -Invoke Cmd` | `Should-NotInvoke Cmd` | |
| `Should -InvokeVerifiable` | `Should-Invoke -Verifiable` | |
| `Should -HaveParameter Name` | `Should-HaveParameter -ParameterName Name` | |
| `$path \| Should -Exist` | `Test-Path -LiteralPath $path \| Should-BeTrue` | There is no `Should-Exist` |

`Should -BeNullOrEmpty` asked three questions at once. Choose the one that is meant:

```powershell
$result.Error | Should-BeNull
$result.Name | Should-BeEmptyString
$result.Items | Should-BeFalsy
```

`Should-BeFalsy` passes for `$null`, `''`, `0`, `$false`, and `@()`. `'' | Should-BeNull` fails, and
so does `$null | Should-BeEmptyString`.

A file that keeps the classic style keeps `Should -Exist`. Pester 6 gave it a `-LiteralPath` switch:
`$path | Should -Exist -LiteralPath` passes for a path that contains brackets, where the plain form
reads the brackets as a wildcard and fails.

## The Four Families

| Family | Examples | Use for |
| --- | --- | --- |
| Value, generic | `Should-Be`, `Should-NotBe`, `Should-BeGreaterThan`, `Should-BeSame`, `Should-BeNull`, `Should-HaveType` | One value, compared the way the PowerShell operators compare |
| Value, typed | `Should-BeString`, `Should-MatchString`, `Should-BeLikeString`, `Should-BeTrue`, `Should-BeFalsy`, `Should-BeBefore`, `Should-BeFasterThan` | One value of a known type, with options for that type |
| Collection, generic | `Should-BeCollection`, `Should-ContainCollection`, `Should-NotContainCollection` | The same items in any order, or a sub-collection in order |
| Collection, combinator | `Should-All`, `Should-Any` | A condition on every item, or on at least one |

There are also assertions for errors (`Should-Throw`), mocks (`Should-Invoke`, `Should-NotInvoke`),
command metadata (`Should-HaveParameter`), hashtables (`Should-BeHashtable`), and deep comparison
(`Should-BeEquivalent`).

## Common Patterns

### Strings

```powershell
'  hello ' | Should-BeString 'hello' -TrimWhitespace
'a  b' | Should-BeString 'a b' -IgnoreWhitespace
'Hello' | Should-BeString 'Hello' -CaseSensitive
$name | Should-MatchString '^[A-Z][a-z]+$'
$path | Should-BeLikeString '*.json'
```

`Should-Be`, `Should-BeString`, and `Should-BeLikeString` ignore case. `Should-BeString` and
`Should-BeLikeString` take `-CaseSensitive`.

Use `-NormalizeLineEnding` when the actual value was read from a file. It treats `` `n `` and
`` `r`n `` as equal, so the test does not depend on the platform that wrote the file:

```powershell
Get-Content -LiteralPath $reportPath -Raw | Should-BeString $expected -NormalizeLineEnding
```

`Should-NotBeString` takes the same switches, and its `-Expected` is mandatory.

#### Long Strings

From 6.2, a failing `Should-BeString` prints a line diff in place of the caret when the strings have
more than one line and either more than 10 lines or more than 120 characters. Pester 6.1 prints the
caret for the same strings. Expected line numbers are on the left and actual on the right, so the
output stays readable when lines were added or removed:

```text
Expected strings to be the same, but they were different.
Expected length: 309
Actual length:   296
Expected 11 line(s), actual 11 line(s).
1 region differs.

   3  3 |   line 3 of the expected text
   4  4 |   line 4 of the expected text
   5    | - line 5 of the expected text
      5 | + line 5 CHANGED
   6  6 |   line 6 of the expected text
   7  7 |   line 7 of the expected text
```

Only the differing lines are expanded. In them a tab or a trailing space is drawn as a visible
symbol, and the unchanged lines around them are printed as they are, not turned into escape codes.

This makes `Should-BeString` the assertion for rendered templates and generated files. `Should-Be`
on the same strings prints both in full.

### Booleans And Null

```powershell
$result.IsReady | Should-BeTrue
$result.Error | Should-BeNull
$result.Name | Should-NotBeEmptyString
```

`Should-BeTrue` and `Should-BeFalse` pass only for a `[bool]`: `1 | Should-BeTrue` fails. Use
`Should-BeTruthy` and `Should-BeFalsy` when any value that PowerShell converts to that Boolean will
do.

An empty array reaches a value assertion as `$null`, so `@() | Should-BeNull` passes and
`@() | Should-NotBeNull` fails. To assert that a command returned something, assert the count
(TST-12).

### Types

```powershell
$result | Should-HaveType 'ModuleName.Thing'
$result.RetryCount | Should-HaveType ([int])
$result | Should-NotHaveType ([hashtable])
```

A string argument is matched against the object's type and against its `PSTypeName`, so a custom
object is asserted by the name its function gives it (TST-13). Related facts:

- `Should-HaveType ([PSCustomObject])` passes for every piped value, including `5`. For an object
  that carries no type name, such as the output of `ConvertFrom-Json`, pass the full name as a
  string: `Should-HaveType 'System.Management.Automation.PSCustomObject'` fails for a number, a
  string, and a hashtable.
- `PSTypeName` is not a property. `$result.PSTypeName` is `$null`; the name is
  `$result.PSObject.TypeNames[0]`.
- A piped array arrives as `[Object[]]`. Assert a typed array with `-Actual`, as shown under
  "Pipeline Or -Actual".

### Collections

```powershell
$names | Should-BeCollection @('alpha', 'beta')
$names | Should-BeCollection -Count 2
$names | Should-All { $_ -like '*a' }
$names | Should-Any { $_ -eq 'beta' }
$names | Should-ContainCollection @('alpha', 'beta')
$names | Should-ContainCollection @('beta', 'alpha') -IgnoreOrder
$names | Should-NotContainCollection @('gamma')
```

The Pester rules list the results that matter most: `Should-BeCollection` does not compare order,
and `Should-All` fails on an empty input. In addition:

| Assertion | Behaviour |
| --- | --- |
| `1, 1, 2 \| Should-BeCollection @(1, 2, 2)` | Fails. Each value must occur the same number of times. |
| `1, 2, 3 \| Should-BeCollection @(1, 2)` | Fails. The counts differ. |
| `$null \| Should-BeCollection -Count 0` | Fails. `$null` is one item. Pipe `@()` for an empty collection. |
| `'a' \| Should-BeCollection -Count 1` | Passes. |
| `'a', 'b', 'c' \| Should-ContainCollection @('a', 'c')` | Passes. The items must appear in this order; gaps are allowed. |
| `'a', 'b', 'c' \| Should-ContainCollection @('c', 'a')` | Fails. It passes with `-IgnoreOrder`. |

To assert order, assert the count and then each element (TST-14). For a list of strings, one
assertion on the joined text also shows the whole sequence when it fails:

```powershell
$result | Should-BeCollection -Count 2
$result[0].Name | Should-Be 'beta'
$result[1].Name | Should-Be 'alpha'

$calls -join ', ' | Should-Be 'Connect, Query, Disconnect'
```

The script block of `Should-All` may contain assertions. When one fails, the message of `Should-All`
includes its reason:

```powershell
$results | Should-All { $_.State | Should-Be 'ready' }
```

Use `-IgnoreOrder` on `Should-ContainCollection` when the source has no defined order, such as the
keys of a hashtable.

### Errors

`Should-Throw` takes the script block from the pipeline and can match the message, the type, or the
error ID:

```powershell
{ throw 'kaboom' } | Should-Throw -ExceptionMessage 'kaboom'
{ throw 'the disk is full' } | Should-Throw -ExceptionMessage '*disk*'

{ Get-Thing -Name 'alpha' -ErrorAction Stop } |
    Should-Throw -ExceptionType ([System.InvalidOperationException])

{ Get-Thing -Name 'alpha' -ErrorAction Stop } |
    Should-Throw -FullyQualifiedErrorId 'ThingReadFailed,Get-Thing'
```

- `-ExceptionMessage` and `-FullyQualifiedErrorId` compare with `-like` against the whole value,
  ignoring case. Without wildcards the pattern must equal the whole message, and `'ThingReadFailed'`
  does not match `'ThingReadFailed,Get-Thing'`. Write `'*disk*'` or `'ThingReadFailed*'` for a
  partial match. The classic `Should -Throw 'text'` compares the same way.
- `-ExceptionType` passes for that type or a type derived from it. It compares the outer exception:
  a failure inside a .NET method call arrives as a `MethodInvocationException`.
- `-Because` is named only. The positional arguments are the message, the error ID, and the type,
  in that order.
- `Should-Throw` returns the error record, so a test can assert more about it:

```powershell
$failure = { Export-Thing -Thing $things -LiteralPath $missingPath } |
    Should-Throw -ExceptionType ([System.Management.Automation.MethodInvocationException])

$failure.Exception.InnerException | Should-HaveType ([System.IO.DirectoryNotFoundException])
```

Because the match is `-like`, the characters `[ ] * ?` in the expected message are wildcards. A
message that contains brackets does not match itself until they are escaped:

```powershell
{ throw 'value is [1]' } | Should-Throw -ExceptionMessage 'value is `[1]'

$pattern = [System.Management.Automation.WildcardPattern]::Escape('value is [1]')
{ throw 'value is [1]' } | Should-Throw -ExceptionMessage $pattern
```

When the two messages differ only in those characters, the failure message says so.

#### Code That Must Not Fail

There is no `Should-NotThrow` (TST-16). Call the command in the test, with `-ErrorAction Stop`:

```powershell
It 'Accepts a name with a hyphen' {
    $null = Get-Thing -Name 'alpha-2' -ErrorAction Stop
}
```

Any error then fails the test. Without `-ErrorAction Stop`, a non-terminating error is only written
to the error stream and the test still passes.

#### Non-Terminating Errors

`Should-Throw` runs the script block with `$ErrorActionPreference` set to `Stop`. The result depends
on where the error comes from:

| Source of the non-terminating error | `Should-Throw` |
| --- | --- |
| A cmdlet, such as `Get-Item` on a missing path | Passes |
| A function defined in the test file | Passes |
| A function in a module | Fails. A module does not see that preference. |
| A function in a module, called with `-ErrorAction Stop` | Passes |

`-AllowNonTerminatingError` does not help here. It runs the script block with `Continue`, so
non-terminating errors are let through and only a terminating error passes.

For module code, follow TST-17: merge the error stream and count the records. To test that the error
stops the caller on request, pass `-ErrorAction Stop` inside the script block.

### Mocks

```powershell
Should-Invoke -CommandName Invoke-RestMethod -ModuleName ModuleName -Times 1 -Exactly
Should-NotInvoke -CommandName Remove-Item -ModuleName ModuleName
Should-Invoke -Verifiable
```

The [mocking guide](./mocking-patterns.md) covers parameter filters, scopes, and the invocation
history that a failed assertion prints.

### Command Metadata

```powershell
Get-Command -Name Get-Thing | Should-HaveParameter -ParameterName Name -Type ([string[]]) -Mandatory
Get-Command -Name Get-Thing | Should-HaveParameter -ParameterName Path -DefaultValue '.'
Get-Command -Name Get-Thing | Should-NotHaveParameter -ParameterName Force
```

### Time And Duration

```powershell
{ Get-ThingSummary -Thing $things } | Should-BeFasterThan '100ms'
{ Start-Sleep -Milliseconds 50 } | Should-BeSlowerThan '10ms'
$record.Created | Should-BeBefore ([datetime]::Now)
$record.Created | Should-BeAfter 10minutes -Ago
```

- `Should-BeFasterThan` and `Should-BeSlowerThan` measure a piped script block, or compare a piped
  `[timespan]`. Any other input is an error:
  `Expected a [scriptblock] to measure or a [timespan] to compare, but got [string] 'result'.` Pipe
  the script block, not its result.
- `-Expected` is mandatory. It is a `[timespan]` or a number with a unit: `ms`, `s`, `m`, `h`, `d`,
  `w`, or a longer form such as `'1.5hours'`.
- The failure message contains the measured time.
- `Should-BeLessThan` cannot compare a `[timespan]` with a number; it stops with
  `Could not compare`. Compare `$elapsed.TotalMilliseconds` with a number, or a `[timespan]` with a
  `[timespan]`.
- `-Ago`, `-FromNow`, and `-Now` compare with the current time. When the code under test reads the
  clock, mock `Get-Date` instead (TST-31).

### Deep Object Comparison

`Should-BeEquivalent` compares nested properties, hashtables, and collections, and prints the
differences by property. Use it for a whole response or configuration object:

```powershell
$expected = [PSCustomObject]@{
    Name = 'Jakub'
    Age = 31
    Address = [PSCustomObject]@{ City = 'Prague'; Country = 'CZ' }
    Roles = @('admin', 'user')
}

$user | Should-BeEquivalent $expected
```

By default every property must be present on both sides: an extra property on the actual object
fails, and so does a missing one. Two options relax that:

```powershell
# Properties that $expected does not have are not compared.
$user | Should-BeEquivalent ([PSCustomObject]@{ Name = 'Jakub' }) -ExcludePathsNotOnExpected

# Everything is compared except the named paths. A dot reaches a nested property.
$actual | Should-BeEquivalent $expected -ExcludePath 'Id', 'Metadata.Timestamp'
```

What it does not check:

- The order of a collection. `@(1, 2, 3) | Should-BeEquivalent @(3, 2, 1)` passes, and so does a
  property that holds the same items in another order.
- The type of a value. A property that holds `1` is equivalent to one that holds `'1'`.

Compare like with like: an object is not equivalent to a hashtable that has the same keys.

## Writing Your Own

A custom assertion is a function that calls `New-ShouldAssertion`. It gets the same input handling,
formatting, and failure path as the built-in assertions. Write one only when the same check recurs
in several test files and the built-in failure message cannot name what went wrong. The
[custom assertion guide](./custom-assertions.md) has the details.

## Soft Assertions

With `Should.ErrorAction = 'Continue'`, a failed assertion is recorded and the test goes on, so one
`It` reports every failure:

```powershell
$configuration = New-PesterConfiguration
$configuration.Should.ErrorAction = 'Continue'
```

```powershell
It 'Returns the expected user' {
    $user.Name | Should-Be 'Jakub'
    $user.Age | Should-Be 31
    $user.City | Should-Be 'Prague'
}
```

A single assertion can opt in with `-ErrorAction Continue`. Keep the default, `Stop`, for assertions
that later lines depend on, such as a count before an index.

## Choosing An Assertion

- Assert the narrowest fact that proves the behaviour. `Should-Be 'Active'` is better than
  `Should-NotBeNull` (TST-11).
- Assert the count before reading an element by index (TST-12).
- Use `Should-HaveType` rather than asserting on `.GetType().Name` as a string (TST-13).
- Prefer one `Should-BeEquivalent -ExcludePathsNotOnExpected` to a run of property assertions, and
  add index assertions when order matters.
- Assert an error by its type or error ID. A message that the code owns changes more often.
- Use `-Because` to record the reason for a value that is not obvious:
  `$retryCount | Should-Be 3 -Because 'the retry policy stops after three attempts'`.
