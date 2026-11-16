---
name: powershell-new-function
description: Write a new PowerShell function with its comment-based help and Pester tests, following this repository's PowerShell standards. Use when asked to create, add, or scaffold a PowerShell function or command.
---

# Write a new PowerShell function

Read these before writing code, unless they are already loaded:

- `.github/copilot-instructions.md`, or `AGENTS.md` if the repository has no such file (the core rules
  and the function template)
- `.github/instructions/powershell-functions.instructions.md`
- `.github/instructions/powershell-error-handling.instructions.md`
- `.github/instructions/powershell-help.instructions.md`

## Steps

1. Find the target version. Read the `#requires -Version` lines and the nearest module manifest. If the
   project declares nothing, target PowerShell 7.6 and say that you assumed it.
2. Choose the name. Use a verb that `Get-Verb` lists and a singular noun. Search the repository for an
   existing function with that name or purpose before creating a new one.
3. Decide where the file goes. In a module, an exported function goes in `Public/<Name>.ps1` and its
   name is added to `FunctionsToExport` in the manifest; an internal one goes in `Private/<Name>.ps1`.
   Outside a module, put it where the user asked.
4. Write the function in the shape of the function template: help first, `[CmdletBinding()]`,
   `[OutputType()]`, typed and validated parameters, a `process` block for pipeline input, `try` and
   `$PSCmdlet.ThrowTerminatingError()` for a failure that ends the function,
   `$PSCmdlet.WriteError()` for a failure of one item, and objects written to the pipeline as they are
   produced.
5. If the function changes state, add `SupportsShouldProcess` and guard each change with
   `$PSCmdlet.ShouldProcess()`. If it only reads, do not.
6. Write `Tests/<Name>.Tests.ps1` following `.github/instructions/powershell-pester.instructions.md`.
   Cover each parameter set, the documented output, each validation failure, and each error path.
7. Run PSScriptAnalyzer on the new files, with `-Settings ./PSScriptAnalyzerSettings.psd1` when that
   file exists, and run the tests. Fix what they report.

## Report

Say which files you created or changed, which PowerShell version you targeted and why, what you ran
and what it reported, and anything you could not verify. Ask instead of guessing when the purpose, the
inputs, or the output of the function is unclear.
