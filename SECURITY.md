# Security

## Reporting a vulnerability

Please report a vulnerability privately through
[GitHub's private vulnerability reporting](https://github.com/fadwen/ai-powershell-standards/security/advisories/new)
rather than in a public issue. You will get an acknowledgement within a few days and a fix or a
mitigation as soon as one is ready. The report is credited in the fix's pull request unless you ask
otherwise.

## Why this repository matters for security

Most of what ships here is text, but it is text that other repositories trust in two ways:

- **AI coding agents follow it.** GitHub Copilot, Claude Code, and Codex load the instruction files,
  the rules, and the skills as guidance, and write code to match. An instruction that tells an agent
  to weaken a control, leak a secret, run a remote script, or ignore the user is a vulnerability,
  whether it arrived by mistake or on purpose. So is a code sample presented as the secure pattern
  that is not.
- **The sync workflow copies it into other repositories.** A consuming repository runs
  `sync-copilot-standards.yml`, which checks out this repository at the reference it names and
  installs the files from it. A change merged here reaches every consumer on its next sync, as a
  pull request the consumer still has to merge.

Report either kind of problem the same way as a code vulnerability.

## What the tooling touches

`Tools/Test-StandardsCompliance.ps1` reads the PowerShell files under the path it is given and
changes nothing. It returns its findings as objects.

`Tools/Build-AgentInstructions.ps1` writes the generated agent files in this repository from the
sources under `standards/`. With `-Check` it writes nothing.

`Tools/Invoke-QualityGate.ps1` runs the tests and writes `coverage.xml` in the repository root.

`Tools/Install-CopilotStandards.ps1` writes into the project folder it is given and supports
`-WhatIf`:

- It replaces the files that the standards own: `.github/instructions/powershell-*.instructions.md`,
  the Pester guides beside them, `.claude/rules/powershell-standards/`, and the skills whose names
  start with `powershell-`. It removes files in those locations that it no longer installs.
- It writes `.github/copilot-instructions.md` and `AGENTS.md` only when the project has none or an
  earlier installation wrote them. `-Force` replaces a file the project wrote itself.
- It never touches the project's `CLAUDE.md`.
- `-RemoveLegacyFiles` removes the files that earlier versions installed or mirrored, including the
  mirrored `powershell-standards/` folder.
- `-IncludeSyncWorkflow` installs the sync workflow, and never replaces one the project wrote.

The installed sync workflow runs with `contents: write` and `pull-requests: write` in the consuming
repository. It runs the installer and proposes the result as a pull request; it never pushes to the
default branch. Its actions are pinned to commit IDs.

Of the worked examples under `powershell-standards/Examples/`, only `Basic-Function-Example.ps1`
reaches another machine: it queries the computers it is given through CIM and changes nothing. The
module example's service is simulated and connects to nothing. The examples' tests mock every call
that would leave the machine.

`Documentation/Anti-Patterns/Test-QualityGates.ps1` breaks the coding standards on purpose so the
quality gates have something to catch. It contains no real credentials or injectable queries, and it
is never installed into consuming repositories.

## Supported versions

This repository has no releases. Only the default branch receives fixes, and consuming repositories
receive them through their next sync.
