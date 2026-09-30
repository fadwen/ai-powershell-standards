# AI PowerShell Standards

Enterprise PowerShell standards shared by GitHub Copilot and Claude Code. The standards live under
`.github/` and are the single source of truth. Nothing under `.claude/` restates them.

- Always-on standards: `.claude/rules/powershell-standards/copilot-instructions.md` imports
  `.github/copilot-instructions.md`. A rule with no `paths` loads at launch, like CLAUDE.md.
- Scoped standards: `.github/instructions/*.instructions.md`, loaded per file type by the other rules
  in `.claude/rules/powershell-standards/`. Each uses the same globs as its instruction file's `applyTo`,
  except that `applyTo: '**'` becomes a rule with no `paths`, which loads at launch.
- Pull requests: branch, commit, and PR conventions live in
  `.github/instructions/pull-requests.instructions.md` and load in every session.
- Prompts: each file in `.github/prompts/` has a command in `.claude/commands/powershell-standards/`
  that attaches it, for example `/powershell-standards:create-test`.
- The sync workflow mirrors `.github/`, `powershell-standards/`, and the two `powershell-standards/`
  folders under `.claude/rules/` and `.claude/commands/` into consuming projects. Anything an
  instruction file links to must live under one of those. Link to the rest of this repository by
  absolute GitHub URL.

## Working in this repository

- Read the relevant instruction file before building anything. When its wording is ambiguous, match
  the worked examples under `powershell-standards/Examples/`, which pass every gate and are mirrored
  into consuming projects by the sync workflow.
- Target PowerShell 7.6 (LTS) with Windows PowerShell 5.1 compatibility. Tests are Pester 6.2.
- Run the gates locally before opening a PR. CI runs the same checks from
  `.github/workflows/quality-gates-pr.yml`:
  - `./Tools/Test-StandardsCompliance.ps1 -Path .`
  - `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error, Warning`
  - `Invoke-Pester` from the repository root
  - `markdownlint-cli2 "**/*.md" "!**/docs/*/*.md"` using `.markdownlint.json` (120-column lines)
- `Templates/` is scaffolding and stays out of coverage. `Documentation/Anti-Patterns/Test-QualityGates.ps1`
  demonstrates violations on purpose. Do not "fix" either.
- When you add or rescope a file in `.github/instructions/`, add or update the matching
  `.claude/rules/powershell-standards/<name>.md` so its `paths` stay identical to `applyTo`.
- When you add a prompt file, add the matching command. `Tools/Tests/ClaudeMirror.Tests.ps1` fails
  when either mirror drifts from `.github/`.
