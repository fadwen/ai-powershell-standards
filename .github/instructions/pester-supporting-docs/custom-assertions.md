# Custom Assertion Guide

How to add an assertion to the `Should-*` family with `New-ShouldAssertion`. That command was added
in Pester 6.1 and does not exist in 6.0. Every statement about behaviour was checked by running it
on Pester 6.2.0. The built-in assertions are described in the [assertion guide](./assertion-guide.md).

The older mechanism, `Add-ShouldOperator`, extends only the classic `Should -Be` syntax and stops at
32 operators. Use `New-ShouldAssertion` for new work.

## When To Write One

Write a custom assertion when the same check appears in several test files and a built-in failure
message cannot explain what went wrong. If it does not produce a better message than `Should-BeTrue`
with `-Because`, it is not worth having.

| Situation | Do this |
| --- | --- |
| One test needs a special check | Plain PowerShell and `Should-Be` |
| The shape of an object | `Should-BeEquivalent -ExcludePathsNotOnExpected` |
| A condition on every item | `Should-All { ... }` |
| A project rule checked in many files, where the message must name the item that breaks it | Custom assertion |

A custom assertion gets what the built-in ones have: input from the pipeline or from `-Actual`,
Pester's value formatting, the hint about piped collections, soft assertions, and use inside a mock
`-ParameterFilter`.

## The Shape

The functions in this guide omit comment-based help to stay short. A real one carries it.

```powershell
function Assert-BeValidSemVer {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [object]$Actual,

        [string]$Because
    )

    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input
    $Actual = $assert.Actual()

    $version = $null
    $isVersion = [version]::TryParse($Actual, [ref]$version)
    if (-not $isVersion -or $version.Build -lt 0 -or $version.Revision -ge 0) {
        $assert.Fail(
            'Expected a Major.Minor.Patch version,<because> but got <actual>.',
            @{ Because = $Because })
    }
}


Set-Alias -Name Should-BeValidSemVer -Value Assert-BeValidSemVer
```

```powershell
'1.2.3' | Should-BeValidSemVer
$manifest.ModuleVersion | Should-BeValidSemVer -Because 'the module is published to a gallery'
```

```text
Expected a Major.Minor.Patch version, because the module is published to a gallery, but got '1.0'.
```

Three rules cover most of it:

1. Call `New-ShouldAssertion` once, at the top, with the function's own `$PSCmdlet`, its `-Actual`
   value, and `$Input`. Pass all three every time: `-Actual` is `$null` for a piped call, `$Input` is
   empty for an `-Actual` call, and the helper works out which was used.
2. Read the value from `$assert.Actual()`, not from `$Actual`. That applies the same input handling
   as the built-in assertions.
3. A pass is implicit. Return without calling `Fail()`.

This is the one place where a function reads the automatic variable `$Input`. It is read, never
assigned.

### No Process Block

Do not add a `process` block, even though the parameter takes pipeline input. The body must run
once, in the `end` block, which is where a function body runs when it names no blocks. `$Input`
holds the whole pipeline only there.

A `process` block causes no error. It changes what the assertion does: the body runs once for each
piped item, and the hint describes a collection that the assertion never saw.

```powershell
'ok', 'bad' | Should-BeOk
```

```text
Body in the end block:      runs once.   Expected ok but got @('ok', 'bad').
Body in a process block:    runs twice.  Expected ok but got 'bad'.
```

For a check on each item, use `Should-All`.

### Parameter Positions

Match the built-in assertions, so that a custom assertion reads the same way at a call site.
`-Actual` always accepts pipeline input. Its position depends on whether there is an expected value:

| Shape | `-Expected` | `-Actual` | Built-in examples |
| --- | --- | --- | --- |
| Nothing to compare with | none | `Position = 0` | `Should-BeNull`, `Should-BeTrue`, `Should-BeHashtable` |
| An expected value | `Position = 0`, mandatory | `Position = 1` | `Should-Be`, `Should-BeString`, `Should-HaveType` |

`Get-Command -Syntax Should-BeHashtable` shows the positions of any assertion.

## Collecting The Input: -As

`-As` selects how piped input is collected and which hint is added to a failure.

| `-As` | A single piped item | Hint added when | Use for |
| --- | --- | --- | --- |
| `Scalar` (default) | Unrolled | A collection was piped and inspected as one value | A value assertion, like `Should-Be` |
| `ExactType` | Unrolled | A typed collection was piped and lost its type | A type assertion, like `Should-HaveType` |
| `Collection` | Kept as a one-item array | A single value, `$null`, or a dictionary was given | A whole-collection assertion, like `Should-BeCollection` |
| `CollectionItems` | Kept as a one-item array | A dictionary was given | An item-by-item assertion, like `Should-All` |
| `None` | Unrolled | Never | A structural comparison, like `Should-BeEquivalent` |

Several piped items reach the assertion as an `[Object[]]` in every mode.

```powershell
function Assert-HaveTag {
    [CmdletBinding()]
    param(
        [Parameter(Position = 1, ValueFromPipeline)]
        [object]$Actual,

        [Parameter(Position = 0, Mandatory)]
        [string]$Expected,

        [string]$Because
    )

    $assert = New-ShouldAssertion -Caller $PSCmdlet -Actual $Actual -Buffer $Input -As Collection
    $blocks = $assert.Actual()

    $untagged = @($blocks | Where-Object { $_.Tag -notcontains $Expected })
    if ($untagged.Count -gt 0) {
        $assert.Fail(
            'Expected every block to be tagged <expected>,<because> but <Untagged> were not.',
            @{ Expected = $Expected; Because = $Because; Untagged = $untagged.Name })
    }
}


Set-Alias -Name Should-HaveTag -Value Assert-HaveTag
```

```powershell
$blocks | Should-HaveTag 'Unit' -Because 'the tagging audit depends on it'
```

```text
Expected every block to be tagged 'Unit', because the tagging audit depends on it, but
@('Connectivity', 'Retry') were not.
```

Naming the items that break the rule is the reason to write this in place of
`$blocks | Should-All { $_.Tag -contains 'Unit' }`.

## The Failure Message

Call `Fail(message)` or `Fail(message, data)`. The message is a template and `data` is a hashtable.

Four keys of `data` have a fixed meaning:

| Key | Effect |
| --- | --- |
| `Expected` | Fills `<expected>` and `<expectedType>` |
| `Actual` | Fills `<actual>` and `<actualType>`. When omitted, the collected input is used. |
| `Because` | Fills `<because>` with a space, `because <text>`, and a comma. With no text it fills it with nothing. |
| `Hint` | Replaces the default hint. It is printed after a blank line as `Hint: <text>`. |

Every other key fills the token of the same name, such as `<Untagged>`. Values are formatted the way
Pester formats them: a string in quotes, a collection as `@(...)`, a type name as `[int]`.

- `<because>` is filled only when `Because` is in `data`. Declaring a `-Because` parameter is not
  enough; pass its value on, as both functions above do.
- Write the comma before `<because>`, as in `Expected <expected>,<because> but got <actual>.` The
  sentence then reads correctly with and without a reason.
- A token for a custom key must match the key's case. With the key `Untagged`, `<Untagged>` is
  filled and `<untagged>` stays in the message as written. A token with no key also stays as
  written, and nothing reports it, so read the message once when writing the assertion.

### Hint

Add the `Hint` key when the assertion knows something more useful than the default hint:

```powershell
$assert.Fail(
    'Expected at most 5 characters,<because> but <actual> has <Length>.',
    @{
        Because = $Because
        Length = $Actual.Length
        Hint = 'Rename the function rather than abbreviating the noun.'
    })
```

Without that key, the default hint covers the usual mistake with piped input:

```text
Expected a Major.Minor.Patch version, but got @('1.2.3', '2.0.0').

Hint: You piped a [Object[]] into a single-value assertion, but the pipeline streams a multi-item
collection and re-collects it into a single [Object[]], so the whole collection was inspected as one
value. To assert on a collection use Should-BeCollection or Should-BeEquivalent; to assert on a
single value pass it as the -Actual argument instead of piping it, e.g. -Actual $value.
```

## Other Members Of $assert

| Member | Purpose |
| --- | --- |
| `Actual()` | The collected value to assert on |
| `Fail(message)`, `Fail(message, data)`, `Fail(message, data, pretty)` | Report a failure. `pretty` is a Boolean that formats values over several lines. |
| `EnsureScalar(expected)` | Returns `expected`, or throws when it is a collection |
| `Format(value)` | Formats a value as Pester does in messages |
| `IsCollection(value)` | Whether Pester treats the value as a collection |
| `Hint()` | The default hint, or `$null` |

`EnsureScalar` guards the expected side of an assertion that makes sense for one value only. Call it
before comparing:

```powershell
$Expected = $assert.EnsureScalar($Expected)
```

```text
You provided a collection to the -Expected parameter. Using a collection on the -Expected side is
not allowed by Assert-BeUnder, because it leads to unexpected behavior. To compare collections use
Should-BeCollection, or a more specialized collection assertion such as Should-Any or Should-All.
```

The message names the function, not the alias it was called through.

Guard the actual side as well when the check uses an operator or a method that fails on a
collection. Such a failure is an ordinary PowerShell error, raised before `Fail()` is reached, and it
carries no hint. Test the value first and call `Fail()`.

## Packaging: Name It Assert-, Export A Should- Alias

`Should` is not an approved verb. A module that exports a function named `Should-*` makes
`Import-Module` warn about unapproved verbs, on PowerShell 7 and Windows PowerShell 5.1, and listing
the function in `FunctionsToExport` does not prevent the warning. `-DisableNameChecking` only moves
the problem onto the module's users: the warning is back for everyone who imports without it.

Name the function with the approved verb `Assert` and export a `Should-*` alias. Aliases are not
checked:

```powershell
# Tests/TestHelpers/Assertions.psd1
@{
    RootModule = 'Assertions.psm1'
    ModuleVersion = '1.0.0'
    FunctionsToExport = @('Assert-BeValidSemVer', 'Assert-HaveTag')
    CmdletsToExport = @()
    AliasesToExport = @('Should-BeValidSemVer', 'Should-HaveTag')
}
```

The root module holds the functions and the `Set-Alias` lines shown above. Pester works from the
`$PSCmdlet` passed as `-Caller`, not from the name of the command, so the assertion behaves the same
when it is called through the alias.

This applies only to modules. A test file that defines or dot-sources a `Should-*` function directly
gets no warning and needs none of it. Where PSScriptAnalyzer checks the test files, its
`PSUseApprovedVerbs` rule still reports the name (STY-10).

## Where To Put Them

Custom assertions are test helpers, and each test file loads the helpers it uses (TST-02). The
[test structure guide](./test-structure-guide.md) describes the folder layout.

```text
Tests/
  TestHelpers/
    Assertions.psd1
    Assertions.psm1
    Assertions.Tests.ps1
  Unit/
```

```powershell
# In Tests/Unit/Get-Thing.Tests.ps1
BeforeAll {
    $testRoot = Split-Path -Path $PSScriptRoot -Parent
    $helperFolder = Join-Path -Path $testRoot -ChildPath 'TestHelpers'
    Import-Module -Name (Join-Path -Path $helperFolder -ChildPath 'Assertions.psd1') -Force
}
```

To load them for every test file, put the same import in a `BeforeAll` block of
`Pester.BeforeContainer.ps1` in the repository root. It must be inside `BeforeAll`: top-level code in
that file runs during discovery only. The [configuration guide](./pester-configuration.md) describes
`Run.RepoRoot`, where Pester starts looking for that file. Pester marks the setup file as
experimental; the import in each test file's own `BeforeAll` needs no such file.

## Test The Assertion Itself

An assertion that cannot fail is worse than none. Cover the pass, the failure, and the message:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Assertions.psd1') -Force
}

Describe 'Should-BeValidSemVer' -Tag 'Unit', 'TestHelpers' {
    It 'Passes for <Version>' -ForEach @(
        @{ Version = '1.2.3' }
        @{ Version = '0.0.1' }
        @{ Version = '10.20.30' }
    ) {
        $Version | Should-BeValidSemVer
    }

    It 'Fails for <Version>' -ForEach @(
        @{ Version = '1.0' }
        @{ Version = 'v1.2.3' }
        @{ Version = '1.2.3.4' }
    ) {
        { $Version | Should-BeValidSemVer } |
            Should-Throw -ExceptionMessage 'Expected a Major.Minor.Patch version*'
    }

    It 'Names the value and the reason in the message' {
        $failure = { '1.0' | Should-BeValidSemVer -Because 'the module is published' } | Should-Throw

        $expected = "Expected a Major.Minor.Patch version, because the module is published, but got '1.0'."
        $failure.Exception.Message | Should-BeString $expected
    }
}
```

The message pattern in the second test matters. A bare `Should-Throw` would also pass if the
assertion could not be found. The third test is the one that catches a token that was not filled.

## Soft Assertions And Mock Filters

Both work without extra code, because `Fail()` uses the same failure path as the built-in
assertions. With `Should.ErrorAction = 'Continue'`, a failed custom assertion is recorded and the
test goes on.

Inside a `-ParameterFilter`, a passing assertion emits `$true`, so the filter matches. A failing one
ends the test with the assertion's own message:

```powershell
Should-Invoke -CommandName Publish-Module -ModuleName ModuleName -Times 1 -Exactly -ParameterFilter {
    $RequiredVersion | Should-BeValidSemVer
    $true
}
```

The trailing `$true` keeps the result of the filter explicit when the assertion is not the last
statement.
