---
name: powershell-performance-review
description: Find and fix performance problems in PowerShell code by measuring it. Use when asked to optimize, speed up, profile, or analyze the performance of PowerShell code.
---

# Performance review of PowerShell code

The collection and string rules are in `.github/instructions/powershell-style.instructions.md`
(STY-22, STY-40 to STY-45, and STY-50). Read them first, unless that file is already loaded.

## Steps

1. Ask what is slow and how large the real input is, if the user has not said. An improvement that
   matters at 100,000 items can be noise at 100.
2. Measure before changing anything. Use `Measure-Command` around the code with realistic input, and
   repeat the run several times. If you cannot run the code, say so and present your suggestions as
   unmeasured.
3. Look for the causes that usually dominate:
   - An array grown with `+=` inside a loop, or a string extended with `+=` about 100 times or
     more. Below that, `+=` on a string is fine (STY-22); do not report it.
   - A command called once for each item when it accepts all items at once, or a remote or disk call
     inside a loop that could be made once outside it.
   - Filtering with `Where-Object` what the source command could have filtered.
   - A lookup that scans a collection inside a loop, where a hashtable built once would do.
   - `ForEach-Object` over a large collection that is already in memory.
   - Output piped to `Out-Null` in a tight loop.
4. Change one thing at a time and measure again with the same input. Keep a change only if it is
   faster and the output is the same.
5. Do not trade correctness or clarity for a small gain, and do not add parallelism
   (`ForEach-Object -Parallel`, thread jobs) unless the work is slow per item and the items are
   independent.

## Report

Give the measurements before and after, with the input size and the PowerShell version, for each
change you kept. Performance figures MUST come from runs you made; do not estimate percentages. List
what you tried that did not help.
