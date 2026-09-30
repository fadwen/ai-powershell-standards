# Security

## Reporting a vulnerability

Please report a vulnerability privately through
[GitHub's private vulnerability reporting](https://github.com/fadwen/ai-powershell-standards/security/advisories/new)
rather than in a public issue. You will get an acknowledgement within a few days and a fix or a
mitigation as soon as one is ready. The report is credited in the fix's pull request unless you ask
otherwise.

## Why this repository matters for security

Most of what ships here is text, but it is text that other repositories trust in two ways:

- **AI coding agents follow it.** GitHub Copilot and Claude Code load the instruction files, the
  Claude rules, and the prompt commands as guidance, and write code to match. An instruction that
  tells an agent to weaken a control, leak a secret, run a remote script, or ignore the user is a
  vulnerability, whether it arrived by mistake or on purpose. So is a code sample presented as the
  secure pattern that is not.
- **The sync workflow copies it into other repositories.** Every consuming repository runs
  `sync-copilot-standards.yml`, which checks out this repository's default branch and replaces its
  own copies of the mirrored paths with it. A change merged here reaches every consumer on its next
  sync, as a pull request the consumer still has to merge.

Report either kind of problem the same way as a code vulnerability.

## What the tooling touches

`Tools/Test-StandardsCompliance.ps1` reads the PowerShell files under the path you give it and
changes nothing. With `-OutputPath` it writes a JSON, XML, or HTML report to that file.

`Tools/Install-CopilotStandards.ps1` writes into the project folder you give it and supports
`-WhatIf`:

- **Copy mode** overwrites that project's `.github/copilot-instructions.md`, `.github/instructions/`,
  `.github/prompts/`, `powershell-standards/`, `.claude/rules/powershell-standards/`, and
  `.claude/commands/powershell-standards/` with this repository's copies. It creates the project's
  folder layout, and a `.gitignore` only when none exists.
- **Symlink mode** links `.github/copilot-instructions.md` to this repository instead of copying it.
  On Windows that needs Administrator rights; without them the script falls back to copy mode.
- **Submodule mode** runs `git submodule add` against this repository's GitHub URL.
- **`-IncludeSyncWorkflow`** installs the sync workflow, and never replaces one already present.

The installed sync workflow runs with `contents: write` and `pull-requests: write` in the consuming
repository. It changes only the mirrored paths and proposes the change as a pull request; it never
pushes to the default branch. Its actions are pinned by major version.

Of the worked examples under `powershell-standards/Examples/`, only `Basic-Function-Example.ps1`
reaches another machine: it pings the computers you name with `Test-Connection` and queries them
through CIM, and it supports `-WhatIf`. The module example's service is simulated and connects to
nothing. The examples' tests mock every call that would leave the machine.

`Documentation/Anti-Patterns/Test-QualityGates.ps1` breaks the coding standards on purpose so the
quality gates have something to catch. It contains no real credentials or injectable queries, and it
is never mirrored into consuming repositories.

## Supported versions

This repository has no releases. Only the default branch receives fixes, and consuming repositories
receive them through their next sync.
