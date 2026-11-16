# Performance Test Template

A test file for a function that has a stated performance requirement. Write one only for such a
function (TST-43), and take the limits from the requirement; the figures below are placeholders.
The rules are in the [Pester rules](../powershell-pester.instructions.md). The file below passes on
Pester 6.2.0 under PowerShell 7.6 and Windows PowerShell 5.1.

## The Code Under Test

The template tests the module `ModuleName` from the [unit test template](./unit-test-template.md).
`Get-ThingSummary -Thing <object[]>` reads each thing once and emits one object for each state, with
the number of things in that state.

## The Test File

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

#pester:no-parallel

BeforeAll {
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'ModuleName.psd1')
    }

    $largeInput = foreach ($index in 1..20000) {
        $state = if ($index % 3 -eq 0) { 'failed' } elseif ($index % 2 -eq 0) { 'stopped' } else { 'ready' }
        [PSCustomObject]@{ Name = "thing-$index"; State = $state }
    }
    $smallInput = $largeInput | Select-Object -First 2000

    # The first call pays for module loading and compilation, so it is made before any measurement.
    $null = Get-ThingSummary -Thing $smallInput
}

Describe 'Get-ThingSummary performance' -Tag 'Performance' {
    It 'Summarizes 2,000 things in less than one second' {
        { Get-ThingSummary -Thing $smallInput } | Should-BeFasterThan '1s'
    }

    It 'Summarizes 20,000 things correctly in less than five seconds' {
        $elapsed = Measure-Command {
            $result = @(Get-ThingSummary -Thing $largeInput)
        }

        $result | Should-BeCollection -Count 3
        ($result | Measure-Object -Property Count -Sum).Sum | Should-Be 20000
        $elapsed.TotalMilliseconds | Should-BeLessThan 5000
    }

    It 'Takes less than 30 times as long for 10 times the input' {
        $smallRuns = foreach ($run in 1..5) {
            (Measure-Command { $null = Get-ThingSummary -Thing $smallInput }).TotalMilliseconds
        }
        $largeRuns = foreach ($run in 1..5) {
            (Measure-Command { $null = Get-ThingSummary -Thing $largeInput }).TotalMilliseconds
        }
        $smallBest = ($smallRuns | Measure-Object -Minimum).Minimum
        $largeBest = ($largeRuns | Measure-Object -Minimum).Minimum

        # A floor of one millisecond keeps timer resolution from deciding the ratio.
        $ratio = $largeBest / [math]::Max($smallBest, 1)
        $ratio | Should-BeLessThan 30 -Because 'the summary reads each thing once'
    }
}
```

## What The Template Shows

### A Time Limit

`Should-BeFasterThan` measures the piped script block and puts the measured time in the failure
message. Use it for a plain limit. Pipe the script block, not its result: any input other than a
script block or a `[timespan]` is an error.

Use `Measure-Command` when the test needs the number itself, for a ratio or for the best of several
runs, or when it must also assert the result of the measured call.

### Assertions Stay Outside The Measurement

An assertion inside `Measure-Command` adds its own time to the figure. The second test assigns the
result inside the measured block, where the variable stays visible afterwards, and asserts after
the measurement. Asserting the result also proves that the fast call did the work.

### Like Is Compared With Like

`Should-BeLessThan` cannot compare a `[timespan]` with a number. It stops with `Could not compare`:

```powershell
# Non-compliant: a TimeSpan compared with a number
$elapsed | Should-BeLessThan 5000

# Compliant: milliseconds compared with milliseconds
$elapsed.TotalMilliseconds | Should-BeLessThan 5000

# Compliant: a TimeSpan compared with a TimeSpan
$elapsed | Should-BeLessThan ([timespan]::FromSeconds(5))
```

### Measurements Are Made Stable

- The input is built once in `BeforeAll`, and one call is made before any measurement.
- A ratio uses the best of several runs. A single run can include a garbage collection or another
  process taking the processor.
- Limits leave room for a slower machine. A limit close to the usual time makes the test fail at
  random, and a test that fails at random gets ignored.

### The File Does Not Run In Parallel

Timings taken while other test files use the processor are noise. The comment `#pester:no-parallel`
keeps the file in the main session, one file at a time, when a run sets `Run.Parallel`. That option
is experimental and off by default.

### Coverage Is Off

Do not enable code coverage in a run that measures time. Coverage instruments the code that is being
measured. Tag the `Describe` block `Performance` (TST-04), and run these tests in their own job with
`Filter.Tag`, without `CodeCoverage.Enabled`.
