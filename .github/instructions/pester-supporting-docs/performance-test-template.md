# Performance Test Template

Use this template for performance benchmarking and regression detection. TST-43 requires
performance tests for a function that processes more than 100 items; they validate timing and
memory use. The limits come from a baseline file and from the requirement; the figures below are
placeholders. The rules are in the [Pester rules](../powershell-pester.instructions.md). The file
below passes on Pester 6.2.0 under PowerShell 7.6 and Windows PowerShell 5.1.

Do not use emoji in generated code, documentation, or test output. Use plain text and standard
ASCII characters only (STY-06, TST-07).

## The Code Under Test

The template tests the module `ModuleName` from the [unit test template](./unit-test-template.md).
`Get-ThingSummary -Thing <object[]>` reads each thing once and emits one object for each state, with
the number of things in that state.

## The Baseline File

The limits that change as the code changes are kept in a data file, so that a new baseline is a
change to data and not to the tests. A test falls back to a default when the file, or a figure in
it, is missing.

```powershell
# Tests/TestData/Baselines/performance-baselines.psd1
@{
    BaselineInputMilliseconds = 1000
}
```

A `.psd1` file holds literals only, so a duration is written as a number of milliseconds, not as a
`[timespan]`.

## The Test File

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

#pester:no-parallel

BeforeAll {
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $moduleRoot -ChildPath 'ModuleName.psd1'
    if (-not (Get-Module -Name ModuleName)) {
        Import-Module -Name $modulePath
    }

    # Performance test configuration
    $performanceConfig = @{
        BaselineDataSize = 2000
        ScaleTestDataSize = 20000
        MaxExecutionTime = [timespan]::FromSeconds(5)
        MaxMemoryUsageMB = 100
        WarmupIterations = 3
        TestIterations = 5
    }

    # Load the performance baselines. Without the file, each test falls back to its default.
    $dataPath = Join-Path -Path $PSScriptRoot -ChildPath 'TestData'
    $baselineFolder = Join-Path -Path $dataPath -ChildPath 'Baselines'
    $baselinePath = Join-Path -Path $baselineFolder -ChildPath 'performance-baselines.psd1'
    if (Test-Path -LiteralPath $baselinePath) {
        $performanceBaselines = Import-PowerShellDataFile -LiteralPath $baselinePath
    } else {
        $performanceBaselines = @{}
    }

    $largeInput = foreach ($index in 1..$performanceConfig.ScaleTestDataSize) {
        $state = if ($index % 3 -eq 0) { 'failed' } elseif ($index % 2 -eq 0) { 'stopped' } else { 'ready' }
        [PSCustomObject]@{ Name = "thing-$index"; State = $state }
    }
    $smallInput = $largeInput | Select-Object -First $performanceConfig.BaselineDataSize

    # The tests add their figures here, and AfterAll saves them.
    $performanceMetrics = @{}

    # The first call pays for module loading and compilation, so it is made before any measurement.
    $null = Get-ThingSummary -Thing $smallInput
}

AfterAll {
    # Save the performance metrics for comparison with later runs.
    $resultsPath = Join-Path -Path $PSScriptRoot -ChildPath 'Results'
    if (-not (Test-Path -LiteralPath $resultsPath)) {
        $null = New-Item -Path $resultsPath -ItemType Directory
    }

    $performanceMetrics.TestDate = (Get-Date).ToString('o')
    $performanceMetrics.PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    $performanceMetrics.Platform = [System.Environment]::OSVersion.Platform.ToString()

    $fileName = 'performance-results-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    $json = ConvertTo-Json -InputObject $performanceMetrics -Depth 10
    Set-Content -LiteralPath (Join-Path -Path $resultsPath -ChildPath $fileName) -Value $json -Encoding ascii
}

Describe 'Get-ThingSummary performance' -Tag 'Performance', 'Benchmark' {
    Context 'Execution time baselines' {
        BeforeEach {
            # Warm up the function.
            foreach ($iteration in 1..$performanceConfig.WarmupIterations) {
                $null = Get-ThingSummary -Thing $smallInput
            }

            # Force garbage collection for a consistent baseline.
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
        }

        It 'Should process the baseline input faster than the limit' {
            { Get-ThingSummary -Thing $smallInput } | Should-BeFasterThan '1s'
        }

        It 'Should stay within the baseline across iterations' {
            $baselineMs = 1000
            if ($performanceBaselines.ContainsKey('BaselineInputMilliseconds')) {
                $baselineMs = $performanceBaselines.BaselineInputMilliseconds
            }

            # Run several iterations for an accurate measurement.
            $measurements = foreach ($iteration in 1..$performanceConfig.TestIterations) {
                (Measure-Command { $null = Get-ThingSummary -Thing $smallInput }).TotalMilliseconds
            }
            $averageMs = ($measurements | Measure-Object -Average).Average
            $maximumMs = ($measurements | Measure-Object -Maximum).Maximum
            $performanceMetrics.AverageMilliseconds = $averageMs
            $performanceMetrics.MaximumMilliseconds = $maximumMs

            $averageMs | Should-BeLessThan $baselineMs
            $maximumMs | Should-BeLessThan ($baselineMs * 1.5) -Because 'the peak may exceed the baseline by half'
        }

        It 'Should scale efficiently with data volume' {
            $smallRuns = foreach ($iteration in 1..$performanceConfig.TestIterations) {
                (Measure-Command { $null = Get-ThingSummary -Thing $smallInput }).TotalMilliseconds
            }
            $largeRuns = foreach ($iteration in 1..$performanceConfig.TestIterations) {
                (Measure-Command { $null = Get-ThingSummary -Thing $largeInput }).TotalMilliseconds
            }
            $smallBest = ($smallRuns | Measure-Object -Minimum).Minimum
            $largeBest = ($largeRuns | Measure-Object -Minimum).Minimum

            # A floor of one millisecond keeps timer resolution from deciding the ratio.
            $dataScaleFactor = $performanceConfig.ScaleTestDataSize / $performanceConfig.BaselineDataSize
            $timeScaleFactor = $largeBest / [math]::Max($smallBest, 1)
            $scalingEfficiency = $timeScaleFactor / $dataScaleFactor
            $performanceMetrics.ScalingEfficiency = $scalingEfficiency

            $scalingEfficiency | Should-BeLessThan 1.5 -Because 'the summary reads each thing once'
        }

        It 'Should complete a large data set within the time limit' {
            $elapsed = Measure-Command {
                $result = @(Get-ThingSummary -Thing $largeInput)
            }

            $result | Should-BeCollection -Count 3
            ($result | Measure-Object -Property Count -Sum).Sum | Should-Be $performanceConfig.ScaleTestDataSize
            $elapsed.TotalMilliseconds | Should-BeLessThan $performanceConfig.MaxExecutionTime.TotalMilliseconds
        }

        It 'Should maintain consistent performance across iterations' {
            # One measurement repeats the call until it lasts about a quarter of a second.
            $single = (Measure-Command { $null = Get-ThingSummary -Thing $largeInput }).TotalMilliseconds
            $callCount = [int][math]::Ceiling(250 / [math]::Max($single, 1))
            $iterations = 10

            $measurements = foreach ($iteration in 1..$iterations) {
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                $elapsed = Measure-Command {
                    foreach ($call in 1..$callCount) {
                        $null = Get-ThingSummary -Thing $largeInput
                    }
                }
                $elapsed.TotalMilliseconds
            }

            # Coefficient of variation: the standard deviation as a share of the average.
            $average = ($measurements | Measure-Object -Average).Average
            $squares = foreach ($measurement in $measurements) {
                ($measurement - $average) * ($measurement - $average)
            }
            $standardDeviation = [math]::Sqrt(($squares | Measure-Object -Sum).Sum / $iterations)
            $variation = $standardDeviation / $average
            $performanceMetrics.CoefficientOfVariation = $variation

            $variation | Should-BeLessThan 0.20 -Because 'the time should be stable across runs'
        }
    }

    Context 'Memory usage' {
        It 'Should maintain a reasonable memory footprint' {
            $beforeMemory = [System.GC]::GetTotalMemory($true)

            $null = Get-ThingSummary -Thing $largeInput

            # No collection is forced here, so the figure includes what the call left behind.
            $afterMemory = [System.GC]::GetTotalMemory($false)
            $memoryUsedMB = ($afterMemory - $beforeMemory) / 1MB
            $performanceMetrics.MemoryUsedMB = $memoryUsedMB

            $memoryUsedMB | Should-BeLessThan $performanceConfig.MaxMemoryUsageMB
        }

        It 'Should release memory after completion' {
            $beforeMemory = [System.GC]::GetTotalMemory($true)

            $null = Get-ThingSummary -Thing $largeInput

            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            $afterMemory = [System.GC]::GetTotalMemory($true)
            $memoryDifferenceMB = [math]::Abs($afterMemory - $beforeMemory) / 1MB

            # Most of the memory must be released. The tolerance is 10 MB.
            $memoryDifferenceMB | Should-BeLessThan 10 -Because 'the function should not retain allocations'
        }

        It 'Should not have memory leaks with repeated calls' {
            $initialMemory = [System.GC]::GetTotalMemory($true)

            # Measure the memory after every fifth call.
            $memoryMeasurements = foreach ($call in 1..20) {
                $null = Get-ThingSummary -Thing $smallInput
                if ($call % 5 -eq 0) {
                    [System.GC]::Collect()
                    ([System.GC]::GetTotalMemory($true) - $initialMemory) / 1MB
                }
            }

            # Memory must not keep growing: at most 5 MB between the first and the last measurement.
            $memoryMeasurements | Should-BeCollection -Count 4
            $memoryGrowth = $memoryMeasurements[-1] - $memoryMeasurements[0]
            $memoryGrowth | Should-BeLessThan 5 -Because 'repeated calls must not leak'
        }
    }

    Context 'Throughput and scalability' {
        It 'Should achieve the minimum throughput' {
            # Things for each second
            $requiredThroughput = 50

            $elapsed = Measure-Command {
                $result = @(Get-ThingSummary -Thing $smallInput)
            }

            ($result | Measure-Object -Property Count -Sum).Sum | Should-Be $performanceConfig.BaselineDataSize
            $actualThroughput = $performanceConfig.BaselineDataSize / $elapsed.TotalSeconds
            $performanceMetrics.ThingsPerSecond = $actualThroughput
            $actualThroughput | Should-BeGreaterThan $requiredThroughput
        }

        It 'Should handle concurrent execution efficiently' {
            $thingCount = $performanceConfig.ScaleTestDataSize
            $runCount = $performanceConfig.TestIterations
            $jobScript = {
                param($ModulePath, $ThingCount, $RunCount)

                Import-Module -Name $ModulePath
                $things = foreach ($index in 1..$ThingCount) {
                    [PSCustomObject]@{ Name = "thing-$index"; State = 'ready' }
                }
                $null = Get-ThingSummary -Thing $things
                $runs = foreach ($run in 1..$RunCount) {
                    (Measure-Command { $summary = @(Get-ThingSummary -Thing $things) }).TotalMilliseconds
                }

                [PSCustomObject]@{
                    ItemsProcessed = ($summary | Measure-Object -Property Count -Sum).Sum
                    BestMilliseconds = ($runs | Measure-Object -Minimum).Minimum
                }
            }

            $jobs = foreach ($jobNumber in 1..5) {
                Start-Job -ScriptBlock $jobScript -ArgumentList $modulePath, $thingCount, $runCount
            }
            $jobResults = @($jobs | Wait-Job | Receive-Job)
            $jobs | Remove-Job

            # Every job completed and processed every thing.
            $jobResults | Should-BeCollection -Count 5
            $jobResults | Should-All { $_.ItemsProcessed -eq $thingCount }
            $jobResults | Should-All { $_.BestMilliseconds -lt 30000 }

            # A call in a job must not take more than twice as long as a call made alone.
            $serialRuns = foreach ($run in 1..$runCount) {
                (Measure-Command { $null = Get-ThingSummary -Thing $largeInput }).TotalMilliseconds
            }
            $serialBest = ($serialRuns | Measure-Object -Minimum).Minimum
            $averageConcurrent = ($jobResults.BestMilliseconds | Measure-Object -Average).Average
            $averageConcurrent | Should-BeLessThan ([math]::Max($serialBest, 1) * 2)
        }
    }

    Context 'Resource utilization' {
        It 'Should use CPU resources efficiently' {
            $ownSample = $null
            if (Get-Command -Name Get-Counter -ErrorAction SilentlyContinue) {
                $processName = (Get-Process -Id $PID).ProcessName
                $idCounterPath = "\Process($processName*)\ID Process"
                $idCounter = Get-Counter -Counter $idCounterPath -ErrorAction SilentlyContinue
                if ($null -ne $idCounter) {
                    $ownSample = $idCounter.CounterSamples |
                        Where-Object { $_.CookedValue -eq $PID } |
                        Select-Object -First 1
                }
            }

            if ($null -eq $ownSample) {
                Set-ItResult -Skipped -Because 'CPU performance counters are not available'
            } else {
                $cpuCounter = $ownSample.Path -replace 'id process$', '% processor time'
                $before = (Get-Counter -Counter $cpuCounter).CounterSamples[0]

                foreach ($call in 1..10) {
                    $null = Get-ThingSummary -Thing $largeInput
                }

                $after = (Get-Counter -Counter $cpuCounter).CounterSamples[0]

                # The raw value counts processor time in the unit of the time stamp. 100 percent of
                # the result is every processor in use for the whole interval.
                $processorTime = $after.RawValue - $before.RawValue
                $interval = ($after.TimeStamp100nSec - $before.TimeStamp100nSec) * [Environment]::ProcessorCount
                $cpuUsage = 100 * $processorTime / $interval
                $performanceMetrics.ProcessorPercent = $cpuUsage

                $cpuUsage | Should-BeGreaterThan 0
                $cpuUsage | Should-BeLessThan 80
            }
        }

        It 'Should not create excessive temporary files' {
            $tempPath = [System.IO.Path]::GetTempPath()
            $startTime = Get-Date

            $null = Get-ThingSummary -Thing $largeInput

            $newFiles = @(
                Get-ChildItem -LiteralPath $tempPath -File | Where-Object { $_.CreationTime -ge $startTime }
            )

            # Other processes write to this folder too, so the limit is five files and not zero.
            $newFiles.Count | Should-BeLessThanOrEqual 5
        }
    }
}
```

## What The Template Shows

### A Time Limit

`Should-BeFasterThan` measures the piped script block and puts the measured time in the failure
message. Use it for a plain limit. Pipe the script block, not its result: any input other than a
script block or a `[timespan]` is an error.

Use `Measure-Command` when the test needs the number itself, for a ratio, an average, or a
coefficient of variation, or when it must also assert the result of the measured call.

### Assertions Stay Outside The Measurement

An assertion inside `Measure-Command` adds its own time to the figure. The large-input test assigns
the result inside the measured block, where the variable stays visible afterwards, and asserts
after the measurement. Asserting the result also proves that the fast call did the work.

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
- `BeforeEach` warms the function up again and forces a garbage collection, so that every timing
  test starts from the same state.
- The baseline test runs several iterations and asserts the average and the maximum. The maximum
  may exceed the baseline by half.
- The scaling test uses the best of several runs instead. The minimum is the better figure for a
  ratio, because a single run can include a garbage collection or another process taking the
  processor.
- Limits leave room for a slower machine. A limit close to the usual time makes the test fail at
  random, and a test that fails at random gets ignored.

### Scaling

The scaling test divides the growth in time by the growth in data. A function that reads each item
once stays near 1: measured here, between 0.5 and 1.2. The limit of 1.5 leaves room for noise and
fails a function whose time grows clearly faster than its input.

### Consistency

The consistency test computes the coefficient of variation over 10 iterations and requires less
than 20 percent. A measurement of a few milliseconds varies with the timer and the scheduler more
than with the code, so each measurement repeats the call until it lasts about a quarter of a
second. Measured here with this function: measurements of about 10 milliseconds gave a variation
between 0.13 and 0.33, and measurements of 250 milliseconds stayed below 0.15.

### Memory

Three tests cover memory: the footprint during a call, the release after it, and growth over
repeated calls. `[System.GC]::GetTotalMemory($true)` collects before it reads, which gives the
starting figure; the footprint test reads the second figure without a collection.

### Throughput And Concurrent Runs

The throughput test divides the number of items by the elapsed time and asserts the result of the
call as well. The concurrency test starts five jobs. A job is a new process, so the script block
receives the module path as an argument, imports the module, and makes one call before it measures.
The test then compares the time of a call in a job with the time of a call made alone.

### Processor And Temporary Files

The processor test reads the `% Processor Time` counter of its own process before and after the
work and computes the share from the raw values of the two samples. It finds its own counter
instance through the `ID Process` counter, because the instance name does not contain the process
ID: measured here, a filter on the ID in the instance name matched no sample, and the test then
compared nothing. The test is skipped when `Get-Counter` or the counter is not available.

The share is of all processors together. A single-threaded call that keeps one processor busy
reads 100 divided by the number of processors; measured here on 20 processors it was 4 percent.

The temporary-file test counts the files that appeared in the temporary folder during the call.

### Metrics Are Saved And Compared

Each test adds its figure to `$performanceMetrics`, and the top-level `AfterAll` writes them to a
JSON file in `Tests/Results`, one file for each run. The saved files are the history that the
regression guidelines below rely on, and `performance-baselines.psd1` holds the baseline that a
test compares with.

The large input can also come from a shared helper; see
[Test Data Management Guide](./test-data-guide.md#performance-test-data).

### The File Does Not Run In Parallel

Timings taken while other test files use the processor are noise. Put the comment
`#pester:no-parallel` at the top of every performance test file. It keeps the file in the main
session, one file at a time, when a run sets `Run.Parallel`. That option is experimental and off by
default.

As a second safeguard, also keep `Run.Parallel = $false` in `PesterConfiguration.Performance.psd1`,
the settings file of the performance run; see
[Pester Configuration Guide](./pester-configuration.md#settings-for-each-environment).

### The Run Is Not Shuffled

A performance baseline assumes a fixed order. Do not turn `Run.Shuffle` on for a run of performance
tests. The runner script in [Test Execution Guide](./test-execution.md#the-test-runner-script)
ignores `-Shuffle` for them.

### Coverage Is Off

Do not enable code coverage in a run that measures time. Coverage instruments the code that is being
measured. Tag the `Describe` block `Performance` and with the category, here `Benchmark` (TST-04),
and run these tests in their own job with `Filter.Tag`, without `CodeCoverage.Enabled`.

## Performance Test Guidelines

### Baseline Establishment

- Warm up functions before measurement.
- Run several iterations for accuracy.
- Force garbage collection for consistency.
- Establish realistic performance targets.

### Memory Testing

- Measure memory usage during execution.
- Verify memory release after completion.
- Test for memory leaks with repeated calls.
- Monitor garbage collection patterns.

### Scalability Testing

- Test with increasing data sizes.
- Measure throughput and response time.
- Validate concurrent execution performance.
- Test the limits of resource utilization.

### Regression Detection

- Compare against historical baselines.
- Track performance trends over time.
- Alert on significant performance degradation.
- Maintain a database of performance metrics.

### Resource Monitoring

- Monitor CPU utilization.
- Track the creation of temporary files.
- Measure network usage where it applies.
- Validate resource cleanup.
