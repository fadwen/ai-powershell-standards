---
name: powershell-write-tests
description: Write or extend Pester 6 tests for existing PowerShell code, following this repository's testing rules. Use when asked to add tests, raise coverage, or test a PowerShell function, script, or module.
---

# Write Pester tests for PowerShell code

Read `.github/instructions/powershell-pester.instructions.md` first, unless it is already loaded. It
holds the rules, a complete test file, and a table of assertion behaviour.

## Steps

1. Read the code under test completely: its parameters and parameter sets, validation attributes,
   output type, every `catch`, and every call that leaves the process (network, files, other modules,
   the clock).
2. Look at an existing test file in the repository. Keep its assertion style and layout. In a new
   file use the Pester 6 `Should-*` assertions.
3. List the behaviours to test before writing any: each parameter set, the documented output, each
   validation failure, each error path, pipeline input, and for a `Test-` function both outcomes.
4. Write the file so that it runs on its own: a versioned `#Requires` for Pester, the code loaded in a
   top-level `BeforeAll`, and test data built in `BeforeDiscovery`.
5. Mock only what crosses a boundary. For code inside a module, pass `-ModuleName` to `Mock` and
   `Should-Invoke`, and reach private functions with `InModuleScope`.
6. Make every test able to fail: assert specific values, assert the count before reading by index, and
   assert expected errors with `Should-Throw` or by counting error records.
7. Run the tests. A test that passes on its first run has not been shown to work: break the behaviour
   it covers, or the expected value, once to see it fail, then restore it.

## Report

Say which behaviours are covered and which are not, the pass and fail counts, and the coverage figure
if you measured it. If a test exposes a defect in the code, report the defect; do not weaken the test
to make it pass, and do not change the code under test unless the user asked for that.
