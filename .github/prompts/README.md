# Prompt files were replaced by skills

This folder is kept only so that a sync workflow installed before version 2.0 keeps running. That
workflow copies this folder into your repository, and it fails if the folder does not exist.

Version 2.0 of the PowerShell standards has no prompt files. The tasks they covered are now skills,
which GitHub Copilot, Claude Code, and Codex load from `.github/skills`, `.claude/skills`, and
`.agents/skills`.

If you are reading this in your own repository, the old sync workflow has updated your instruction
files but has not installed the skills or the files for Claude Code and Codex. To get them:

1. Clone the standards repository.
2. Run `./Tools/Install-CopilotStandards.ps1 -ProjectPath <your repository> -RemoveLegacyFiles`.
3. Replace `.github/workflows/sync-copilot-standards.yml` in your repository with the current
   template from `Templates/Workflows` in the standards repository.
4. Delete this folder.
