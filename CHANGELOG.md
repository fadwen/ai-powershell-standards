# Changelog

This file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

These changes make up version 2.0.0, a rewrite of the standards. The rules are now written once
under `standards/` and generated into the files that GitHub Copilot, Claude Code, and Codex read. A
project that installed an earlier version runs the installer with `-RemoveLegacyFiles`.

### Added

- Every rule has an ID and states whether it is a requirement (MUST) or a default (SHOULD).
- `standards/` holds the sources, and `Tools/Build-AgentInstructions.ps1` generates the agent files
  from them. With `-Check` it fails when they do not match.
- Codex support: `AGENTS.md` and the skills under `.agents/skills`.
- Eight skills, installed for all three agents.
- A function template and a test template that are real files, run by the test suite on
  PowerShell 7.6 and Windows PowerShell 5.1.
- `PSScriptAnalyzerSettings.psd1`, which checks the layout rules.
- `Tools/Invoke-QualityGate.ps1`, the one script that CI and developers run. It runs the tests in a
  shuffled order and reports the seed when one fails.
- Rules for failures that raise no error: a local variable named like a parameter (STY-16),
  `return` in `begin` (FUN-04), state that does not reach a job or a parallel block (FUN-05),
  functions that reduce their input (FUN-25), response data in two shapes (FUN-26), confirmation in
  unattended runs (FUN-32), and the reach of `-WhatIf` (FUN-33).
- Rules for releasing to the PowerShell Gallery (MOD-10 to MOD-14) and for rehearsing the release on
  every pull request (CIC-10).
- Test rules: import the module once (TST-05), mock scope across setup blocks (TST-23), both
  pipeline paths (TST-44), documented examples (TST-45), and a shuffled order in every test run
  (TST-46). The test runner shuffles unless `-NoShuffle` is passed, and performance tests keep
  their declared order.
- A rule to write a function's output after its `try` block (ERR-15).
- Six rules taken from a comparison with Frank Lesniak's
  [PSStyleGuide](https://github.com/franklesniak/PSStyleGuide), each tested on PowerShell 7.6 and Windows
  PowerShell 5.1: blank lines around functions (STY-07), the `-f` operator inside a command's
  parentheses (STY-23), line endings in comparisons (STY-34), a check that an output file can be
  written before long work starts (STY-35), a preference test around log messages in loops
  (ERR-32), and an operating system check that fails early (VER-10).
- A `.gitattributes` file that checks every text file out with LF, and the rule that asks for one
  (CIC-11). `Tools/Test-StandardsCompliance.ps1` now reports STY-07 and STY-23.
- The cautions and prescriptions of the earlier instruction files that the first draft of this
  version had dropped, about 345 of them, restored as rules with IDs and as sections of the guides.
  Among them: what help contains (DOC-10 to DOC-17), preferred constructs (STY-50, STY-51), code
  signing, classification, and input checks (SEC-16 to SEC-53), the features promoted out of
  experimental in 7.5 and 7.6, the release cautions for the PowerShell Gallery, the multi-job CI
  workflow with its matrix and nightly run (CIC-12 to CIC-22), the README sections (RDM-07 to
  RDM-18), the test runner and its reports, and the performance, security, and integration test
  cases. Each statement about behaviour was run again first; the Fixed section below lists the
  ones that did not hold.
- A caution that one `CodeCoverage.Path` entry in a folder that does not exist makes Pester 6.2.0
  measure nothing while the result stays `Passed` (TST-40).
- `.github/powershell-attribution.md`, the author details that agents write into the `.NOTES` of
  new help and into a new module manifest (DOC-18). The installer creates it when it is missing and
  never changes it afterwards, not even with `-Force`. It starts from the profile of the project's
  GitHub owner under `standards/attribution/profiles`, or from an empty template; the new `-Owner`
  parameter chooses the profile when the `origin` remote does not.
- PowerShell 7.7 in the version rules: its support dates, the features it adds with what to use on
  7.6, and the behaviour it changes. PowerShell 7.6 stays the default target. Three changes made by
  servicing releases of 7.6 are listed as well: the `Authorization` header is not sent to a link
  followed with `-FollowRelLink` (7.6.5), `Test-Json` needs `-FetchExternalReference` for a schema
  reference by URL (7.6.7), and a version 1 file catalog writes a warning (7.6.10).
- A rule for a web request that carries a credential (SEC-09): it passes `-MaximumRedirection 0`
  and is not paged with `-FollowRelLink`. The cmdlet follows a redirect without the `Authorization`
  header, and since PowerShell 7.6.5 a link as well, so the reply can be the one an anonymous
  caller gets, and a key in another header goes to any host that a redirect or a link names. The
  function that follows the links itself, `standards/examples/Get-PagedResponse.ps1`, is a real
  file with tests. `Tools/Test-StandardsCompliance.ps1` reports the rule as an error for a request
  that names a credential (`-Authentication`, `-Token`, `-Credential`, or
  `-UseDefaultCredentials`) and follows a redirect, is paged with `-FollowRelLink`, or passes
  `-PreserveAuthorizationOnRedirect`. In a project that runs the check, existing calls of that
  kind fail it until they pass `-MaximumRedirection 0`. A limit that is not a number, such as a
  variable, is reported without failing the check.

### Changed

- The always-loaded core went from about 33 KB to about 15 KB. For a `.ps1` file an agent loads
  about 118 KB of instructions in total, against about 123 KB before.
- Twelve topic files named `powershell-<topic>.instructions.md` replace the earlier instruction
  files. Their front matter contains only keys that instruction files support.
- The Claude Code rules under `.claude/rules/powershell-standards/` are generated. Each one imports
  its instruction file, as before, and is now named after it.
- The core rules are installed once. GitHub Copilot loads `AGENTS.md` as well as its own file, so
  `AGENTS.md` is a short pointer to `.github/copilot-instructions.md` wherever that file is installed.
- The branch, commit, and pull request conventions are now a topic with rule IDs (PRQ), and ask for
  a fetch before work starts (PRQ-01).
- Errors that end an advanced function are raised with `$PSCmdlet.ThrowTerminatingError()` from a
  `catch` block. `throw` and `Write-Error -ErrorAction Stop` are no longer used there (ERR-10,
  ERR-11). A failure of one input item is reported with `$PSCmdlet.WriteError()` (ERR-13).
- A script that is run directly sets `$ErrorActionPreference = 'Stop'`; module code never sets it.
  `Set-StrictMode -Version Latest` is required, and code must run under it (ERR-01 to ERR-03).
- Local variables are camelCase (STY-12), and hashtables are not padded to align their `=` signs
  (STY-04).
- An array is never grown with `+=` in a loop, on any version (STY-40).
- Help written as `#` lines is valid (DOC-04). Help contains no version, date, or change history
  (DOC-07).
- `SupportsShouldProcess` is not declared on functions that only read (FUN-31).
- CI fails when the Pester result is not `Passed`, which also catches a failed setup or teardown
  block, and when coverage is below 80 percent (TST-40, TST-42).
- The tests of a module sit directly in `Tests` or in `Unit`, `Integration`, and `Performance`
  folders under it (MOD-01). In a flat folder the test runner selects the test type by its tag.
- `Tools/Install-CopilotStandards.ps1` installs for the agents selected with `-Agent`, never
  replaces a file the project wrote, never touches `CLAUDE.md`, and removes files it no longer
  installs.
- `Tools/Test-StandardsCompliance.ps1` reports findings by rule ID and returns objects.
- The sync workflow template runs the installer instead of copying folders, pins its actions to
  commits, and lets a project choose the reference to install from. An earlier sync workflow keeps
  working, because the folders it copies are still present.
- The thirteen Pester guides were rewritten against Pester 6.2.0. The test suite checks that every
  PowerShell sample in them parses.
- The core rules and the README say that the core rules are a selection from the topic files and
  that rule numbers have gaps, so a number that is skipped is not read as a missing rule.
- Only the body of a commit message is wrapped at 72 columns (PRQ-12). A pull request description
  or a comment has one line for each paragraph and list item, because GitHub renders a line break
  inside one as a line break.
- ERR-24 says that `-ErrorAction Stop` on a call does not make a terminating error of that command
  end the script, so a script sets `$ErrorActionPreference = 'Stop'` as well. The error-handling
  rules now compare what a calling script sees when a function fails with
  `$PSCmdlet.ThrowTerminatingError()`, with `throw`, and with
  `Write-Error -ErrorRecord $_ -ErrorAction Stop`. With the first, which ERR-10 requires, a script
  without the preference goes on after the failed command and ends with exit code 0. Text that
  tells a caller to pass `-ErrorAction Stop` so that a failure fails a job step is wrong for such
  a command; an unattended example sets the preference (RDM-13). The note on `throw` names the two
  cases in which `-ErrorAction` does not suppress it: a bare `throw` that passes on an error raised
  with `-ErrorAction Stop`, and `-ErrorAction Ignore` on Windows PowerShell 5.1.

### Fixed

- The worked example `Get-BasicServerInfo` ends with an error that names Windows on another
  operating system (VER-10), and its tests are skipped there. Before, its 22 tests failed on Linux
  and macOS, because the CIM commands that they mock do not exist there.
- The quality gate runs on Linux and macOS in CI as well as on Windows. Its message for a project
  without tests starts with "No tests were run", so that a long path cannot break the words apart.
- `Test-Json` takes `-Options IgnoreComments, AllowTrailingCommas`. The earlier text named switches
  that do not exist.
- `Join-Path` with several child paths has worked since PowerShell 6. It was described as new in 7.6.
- `+=` on an array still copies the array on every append in PowerShell 7.5 and 7.6. It keeps pace
  with `List.Add()` up to about 10,000 elements and is more than ten times slower by 40,000.
- `Should-BeCollection` does not check order in Pester 6.2.0.
- A custom object's `PSTypeName` is its type name, not a property, so the earlier test template
  could not pass.
- PowerShell 7.4 and 7.5 reached the end of support on 10-Nov-2026.
- A module class can be a parameter type when the class file loads before the function file. The
  earlier text said that it breaks the import.
- `.Count` on a `[PSCustomObject]` is `1` on PowerShell 7 and `$null` on Windows PowerShell 5.1. The
  earlier text said the two versions agree.
- Adding `Tls12` to a `SecurityProtocol` of `SystemDefault` restricts a session to TLS 1.2. The
  earlier sample did that on every import.
- A mandatory collection parameter rejects an empty array as well as `$null`, so wrapping a call in
  `@()` is not enough without `[AllowEmptyCollection()]`.
- `HelpInfoURI = ''` does not fail the pack. `IconUri`, `ProjectUri`, and `LicenseUri` set to an
  empty string each do (MOD-13).
- The `foreach` statement is faster than the pipeline for a collection in memory: 291 ms against
  2,518 ms for 200,000 objects on PowerShell 7.6 (STY-44).
- `::set-output` is deprecated, not disabled: GitHub postponed its removal in July 2023.
- `[System.Web.HttpUtility]::HtmlEncode` needs `Add-Type` on Windows PowerShell 5.1, not on
  PowerShell 7.
- `Run.ExcludePath` does not exclude files from code coverage.
- When a parallel worker dies, Pester 6.2.0 returns no result object.
- `Should-BeEquivalent -Comparator Equality` still compares nested objects, `-As None` unrolls a
  single item, and `PassedCount` does not show whether a tag filter worked.
- A discovery-only run does not find a test file that depends on another one.
- `Install-Module` and `Find-Module` are PowerShellGet 2.2.5's own functions on PowerShell 7.6, not
  a compatibility layer.
- Samples that did not run are repaired: the deny-list check that a backtick defeated, the secret
  pattern that did not parse, the test runner that did not parse, the processor test whose filter
  matched nothing, and a signing check that let a file with only critical findings through.
- The README again tells a new user how to start: the quick start, the module template, the
  template repository, how each agent loads the rules, the skills, the GitHub Actions workflows,
  an example of a project's own rules, and links to the documentation. It also acknowledges the
  PowerShell community, the GitHub Copilot team, and enterprise PowerShell users again. The rewrite
  had cut all of these.
- The example test `Basic-Function-Example.Tests.ps1` no longer fails PSScriptAnalyzer in a project
  that installs the examples and analyzes its whole repository. It suppresses
  `PSAvoidUsingComputerNameHardcoded`, because its computer names are test data for mocked calls.

### Removed

- The ten prompt files and the Claude Code commands that attached them. VS Code documents that
  prompt files run only in a mode that is being removed; the skills replace them.
- Correlation IDs, `Write-EnterpriseLog`, and the PSFramework dependency. Functions use the output
  streams (ERR-30).
- The compliance patterns for specific regulations. They called functions that were defined
  nowhere, and one block did not parse.
- The `Troubleshooting` folder. Its samples broke the rules, for example with `Write-Host`, `+=` in
  loops, and correlation IDs, and nothing referred to it.
- `Documentation/PowerShell-Best-Practices.md`, `Implementation-Guide.md`, `Prompt-Files-Guide.md`,
  and `Enterprise-Extensions.md`, which repeated or contradicted the rules.
- The installer parameters `-StandardsType` and `-LinkType`, and the compliance checker parameters
  `-Detailed`, `-OutputFormat`, and `-OutputPath`.
