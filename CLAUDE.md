# AI PowerShell Standards

PowerShell standards shared by GitHub Copilot, Claude Code, and Codex. The rules live once, under
`standards/`, and `Tools/Build-AgentInstructions.ps1` generates every file that an agent reads.
Nothing under `.github/`, `.claude/`, or `.agents/` is edited by hand, apart from the Pester guides.

- Always-on rules: `.claude/rules/powershell-standards/copilot-instructions.md` imports
  `.github/copilot-instructions.md`. A rule with no `paths` loads at launch, like this file.
- Scoped rules: the other files in `.claude/rules/powershell-standards/` import
  `.github/instructions/powershell-*.instructions.md` and carry the same globs as each file's
  `applyTo`. A topic whose glob is `**` becomes a rule with no `paths`.
- Pull requests: branch, commit, and PR conventions are in
  `.github/instructions/powershell-pull-requests.instructions.md` and load in every session.
- Skills: `.claude/skills/powershell-*` are copies of `standards/skills/`.
- `AGENTS.md` points Codex to the core. GitHub Copilot reads it too, which is why it does not repeat
  the rules.

## Working in this repository

- Before starting, run `git fetch` and confirm that the branch is not behind `origin/main`.
- Change a rule in `standards/rules/`, then run `./Tools/Build-AgentInstructions.ps1` and commit the
  sources and the generated files together.
- Test a claim about PowerShell, Pester, or a tool on PowerShell 7.6 and Windows PowerShell 5.1
  before writing it into a rule, and say what was measured.
- When a rule's wording is ambiguous, match the tested templates under `standards/examples/` and the
  worked examples under `powershell-standards/Examples/`.
- Run the gate before opening a PR. CI runs the same script from
  `.github/workflows/quality-gates-pr.yml`:
  - `./Tools/Invoke-QualityGate.ps1` (PowerShell 7.6, PSScriptAnalyzer 1.25.0, Pester 6.2.0)
  - `markdownlint-cli2 "**/*.md" "!**/docs/*/*.md"` using `.markdownlint.json` (120-column lines)
- `Templates/` is scaffolding and stays out of coverage.
  `Documentation/Anti-Patterns/Test-QualityGates.ps1` demonstrates violations on purpose. Do not
  "fix" either.
- Keep `.github/prompts/`, `powershell-standards/`, and `.claude/commands/powershell-standards/` in
  place. Consuming repositories that run an earlier sync workflow copy those folders, and their sync
  fails when one is missing.
