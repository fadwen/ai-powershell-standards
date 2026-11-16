---
name: powershell-new-module
description: Create a new PowerShell module with a manifest, a root module, Public and Private folders, a first function, and Pester tests, following this repository's PowerShell standards. Use when asked to create, scaffold, or start a PowerShell module.
---

# Create a new PowerShell module

Read these before writing files, unless they are already loaded:

- `.github/copilot-instructions.md`, or `AGENTS.md` if the repository has no such file (the core rules
  and the function template)
- `.github/instructions/powershell-modules.instructions.md`
- `.github/instructions/powershell-version.instructions.md`

## Steps

1. Ask for, or confirm, the module name, what it is for, and whether it must run on Windows PowerShell
   5.1. Without a 5.1 requirement, target PowerShell 7.6.
2. Create the layout from the module rules: `ModuleName.psd1`, `ModuleName.psm1`, `Public/`,
   `Private/`, and `Tests/`. Add `Classes/` only if the module defines a class. Do not create empty
   folders for things the module does not have.
3. Write the manifest with literal values only. Generate the GUID once with `New-Guid` and paste the
   result. Set `PowerShellVersion` and `CompatiblePSEditions` for the target. List exported functions
   by name. Take `Author` and the project links from the user or the repository; leave out what you do
   not know.
4. Write the root module exactly as the module rules show it: strict mode, then `Classes`, `Private`,
   and `Public` dot-sourced in that order, failing the import if a file fails to load.
5. Add the first function with the `powershell-new-function` skill, or follow its steps.
6. Import the module in a new session with `Import-Module ./ModuleName.psd1 -Force`, confirm that
   `Get-Command -Module ModuleName` lists exactly the exported functions, and run the tests.
7. Add a `README.md` that follows `.github/instructions/powershell-readme.instructions.md`.

## Report

List the files you created, the target version, and the results of the import check and the tests. Do
not add dependencies, CI workflows, or help generation unless the user asked for them; mention them as
possible next steps instead.
