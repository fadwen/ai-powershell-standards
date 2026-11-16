---
name: powershell-ci-pipeline
description: Add or fix a CI workflow for a PowerShell project that runs PSScriptAnalyzer and Pester with a coverage gate. Use when asked to set up, create, or repair CI, GitHub Actions, or quality gates for PowerShell code.
---

# Set up CI for a PowerShell project

Read `.github/instructions/powershell-cicd.instructions.md` first, unless it is already loaded. It
holds the rules, a pull request workflow, and a publishing workflow.

## Steps

1. Look at what exists: workflow files, a build script, the test folder, and the module manifest.
   Extend an existing workflow instead of adding a second one that does the same job.
2. Establish what the project supports from its manifest and `#requires` lines: PowerShell 7.6 only,
   or also Windows PowerShell 5.1, and which operating systems. Build the job list from that. Do not
   add a version or operating system the project does not claim to support.
3. Add the pull request workflow from the CI rules: install PSScriptAnalyzer and Pester at fixed
   versions, run PSScriptAnalyzer and fail on findings, and run the test gate.
4. Put the test gate in a script in the repository, using the gate in
   `.github/instructions/powershell-pester.instructions.md`, so that developers can run the same
   check locally. Set its test path and coverage paths to the project's real folders.
5. If the repository has no `PSScriptAnalyzerSettings.psd1`, offer to add the one shown in the CI
   rules. Adding it can surface many layout findings in existing code, so say that first.
6. If the repository has no `.gitattributes` file, add one that contains `* text=auto eol=lf`
   (CIC-11), so that the tests see the same line endings on every runner.
7. If the module ships compiled help, add the help checks from
   `.github/instructions/powershell-platyps.instructions.md`.
8. Validate the workflow file's syntax, and run the gate script locally if you can.

## Report

Say which files you added or changed, what each job runs, and what you were able to run locally. A
workflow is not verified until it has run on the CI system; say so, and do not claim that it passes.
Do not add publishing, signing, or deployment steps unless the user asked for them.
