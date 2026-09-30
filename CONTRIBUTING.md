# Contributing

Issues and pull requests are welcome.

## Before you start

- **A standard is wrong or out of date:** that is the most useful issue this repository can get.
  Say which file and section, what it should say, and link the source, such as the PowerShell, Pester,
  PlatyPS, VS Code, or Claude Code documentation. Several files record the date their facts were
  checked; a newer source outranks them.
- **Generated code breaks a standard:** include the prompt or command you ran, the tool that ran it
  (GitHub Copilot or Claude Code), and the code it produced.
- **A change:** open an issue first if it is more than a fix, so the shape can be agreed before the
  work. Every change here reaches every consuming repository on its next sync.

## How the repository is laid out

The standards exist once, under `.github/`. Everything else either references them or stays here.

| Path | Role | Mirrored to consumers |
| --- | --- | --- |
| `.github/copilot-instructions.md`, `.github/instructions/` | The standards | Yes |
| `.github/prompts/` | Task prompts for Copilot Chat | Yes |
| `.claude/rules/powershell-standards/` | One Claude Code rule per instruction file, importing it | Yes |
| `.claude/commands/powershell-standards/` | One Claude Code command per prompt file, attaching it | Yes |
| `powershell-standards/Examples/` | Worked examples the standards link to | Yes |
| `Documentation/`, `Templates/`, `Tools/`, `Troubleshooting/` | Guides and tooling for this repository | No |

`CLAUDE.md` holds the same working notes for Claude Code sessions in this repository.

## The conventions that are easy to break

- **Keep the Claude files in step with `.github/`.** A new instruction file needs a rule in
  `.claude/rules/powershell-standards/` whose `paths` match its `applyTo`; `applyTo: '**'` becomes a
  rule with no `paths`. A new prompt file needs a command in `.claude/commands/powershell-standards/`.
  Neither copies the source; each imports or attaches it. `Tools/Tests/ClaudeMirror.Tests.ps1`
  fails when they drift.
- **Use only the header fields VS Code supports.** Prompt files take `description`, `name`,
  `argument-hint`, `agent`, `model`, and `tools`. Instruction files take `name`, `description`, and
  `applyTo`. `Tools/Tests/CopilotFrontmatter.Tests.ps1` fails on anything else.
- **Link only into mirrored paths.** A relative link from a mirrored file must stay inside
  `.github/` or `powershell-standards/`, or it dangles in every consumer. Link to anything else in
  this repository by its absolute GitHub URL.
- **Examples pass full-rule analysis, tests included.** Consumers' gates do not relax
  PSScriptAnalyzer for test files, so neither does the pull request gate for
  `powershell-standards/`. Keep literal computer names out of `-ComputerName` arguments and leave
  out `param()` blocks on `-ForEach` tests.
- **No `../` in production PowerShell.** The gate's security scan treats it as path traversal, even
  inside a comment.
- **Leave the anti-pattern alone.** `Documentation/Anti-Patterns/Test-QualityGates.ps1` breaks the
  standards on purpose. `Templates/` is scaffolding and stays out of coverage.

## The checks

These are the checks the pull request gate runs:

```powershell
./Tools/Test-StandardsCompliance.ps1 -Path .
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error, Warning
Invoke-Pester                                    # from the repository root
```

```bash
markdownlint-cli2 "**/*.md" "!**/docs/*/*.md"    # uses .markdownlint.json, 120-column lines
```

## Pull requests

Branches, commit messages, PR titles, and PR bodies follow
[pull-requests.instructions.md](.github/instructions/pull-requests.instructions.md), the same
conventions the standards give every consuming repository. In short: a `<type>/<description>`
branch, a Conventional Commits title, one concern per pull request, and a Verification section that
reports the checks as they came out.

A change to `Templates/Workflows/sync-copilot-standards.yml` does not reach consumers by itself,
because the sync never touches a consumer's workflows. Each consumer needs its own copy updated,
merged after this repository's change, since a step that copies a new folder fails until that folder
exists upstream.
