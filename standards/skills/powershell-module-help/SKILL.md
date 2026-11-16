---
name: powershell-module-help
description: Generate, update, validate, or build PowerShell module help with Microsoft.PowerShell.PlatyPS, where help is written as Markdown and shipped as compiled external help. Use when asked to document a module's commands, update help after a parameter change, or fix Get-Help output for a module.
---

# Maintain module help with PlatyPS

Read `.github/instructions/powershell-platyps.instructions.md` first, unless it is already loaded. It
holds the rules and every command used below.

## Steps

1. Confirm the tool. `Get-Module -ListAvailable Microsoft.PowerShell.PlatyPS` must show version 1.0.3
   or later. Do not use the retired `platyPS` module or its commands.
2. Find the state of the module's help: whether `docs/<ModuleName>/` exists, which exported commands
   have a Markdown file, and whether the exported functions carry `.EXTERNALHELP`.
3. For a command with no Markdown yet: make sure the function has complete comment-based help, run
   `New-MarkdownCommandHelp` with `-Locale`, and only then add `.EXTERNALHELP` and reduce the comment
   block to a one-line `.SYNOPSIS`. The order matters.
4. For a command whose parameters changed: import the module and run `Update-MarkdownCommandHelp`,
   then update the module page. Do not edit syntax blocks or parameter metadata by hand.
5. Write the content. Replace every `{{ Fill in ... }}` placeholder, put each example's command in a
   fenced `powershell` block, and describe only what the command does.
6. Validate with the checks in the PlatyPS rules: structure, leftover placeholders, and relative
   links.
7. Build the compiled help with `Export-MamlCommandHelp`, copy it into the module's culture folder,
   and confirm with `Get-Help <Command> -Full` against the imported module that the text and the
   examples appear.

## Report

List the Markdown files you created or changed, the result of each validation, and what `Get-Help`
showed. Mention any command whose description or examples you could not write from the code alone,
and ask the user for the missing facts instead of inventing them.
