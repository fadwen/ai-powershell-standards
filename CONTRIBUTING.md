# Contributing

Issues and pull requests are welcome.

## Before you start

- **A standard is wrong or out of date:** that is the most useful issue this repository can get.
  Say which rule ID or file, what it should say, and link the source, such as the PowerShell, Pester,
  PlatyPS, VS Code, Claude Code, or Codex documentation. Several files record the date their facts
  were checked; a newer source outranks them.
- **Generated code breaks a standard:** include the prompt or skill that was used, the tool that ran
  it (GitHub Copilot, Claude Code, or Codex), and the code it produced.
- **A change:** open an issue first if it is more than a fix, so the shape can be agreed before the
  work. Every change here reaches every consuming repository on its next sync.

## How the repository is laid out

The rules exist once, under `standards/`. `Tools/Build-AgentInstructions.ps1` generates everything
that the agents read from them.

| Path | Role | Installed into consumers |
| --- | --- | --- |
| `standards/` | Sources: the core, one rule file for each topic, the skills, the tested templates | No |
| `.github/copilot-instructions.md`, `.github/instructions/powershell-*.instructions.md` | Generated: the rules as GitHub Copilot reads them | Yes |
| `.github/instructions/pester-supporting-docs/` | Hand-written Pester guides that the rules point to | Yes |
| `.claude/rules/powershell-standards/` | Generated: one Claude Code rule for each instruction file, importing it | Yes |
| `AGENTS.md` | Generated: points Codex to the core | Yes |
| `.github/skills/`, `.claude/skills/`, `.agents/skills/` | Generated: each skill, with the tested files that it includes | Yes |
| `powershell-standards/Examples/` | Worked examples that pass every check | No |
| `Documentation/`, `Templates/`, `Tools/` | The anti-pattern example, scaffolding, and tooling | No |

`CLAUDE.md` holds the same working notes for Claude Code sessions in this repository.

## The conventions that are easy to break

- **Edit the source, then rebuild.** Change the files under `standards/`, run
  `./Tools/Build-AgentInstructions.ps1`, and commit the sources and the generated files together. A
  test fails when they differ.
- **State each rule once, with an ID.** A rule is a bullet of the form `- **XXX-NN** text` in one
  rule file. The core lists rule IDs, and the generator copies their text.
- **Test a claim before writing it down.** Run a statement about how PowerShell, Pester, or a tool
  behaves on PowerShell 7.6 and Windows PowerShell 5.1 first, and say in the rule what was measured.
  Run a statement about PowerShell 7.7 on PowerShell 7.7 as well.
- **Keep samples honest.** Every PowerShell sample in the instruction files and guides must parse
  and be ASCII. The function and test templates are real files with their own tests.
- **Link only to installed files.** A link from an instruction file or a guide must stay inside
  `.github/instructions/`, or it dangles in every consumer. Name other files by path, and link to
  the rest of this repository by absolute GitHub URL.
- **Keep the folders that earlier sync workflows copy.** A consuming repository that still runs an
  earlier `sync-copilot-standards.yml` copies `.github/instructions/`, `.github/prompts/`,
  `powershell-standards/`, `.claude/rules/powershell-standards/`, and
  `.claude/commands/powershell-standards/`. Its next sync fails when one of them is missing here,
  which is why two of them hold only a placeholder.
- **Leave the anti-pattern alone.** `Documentation/Anti-Patterns/Test-QualityGates.ps1` breaks the
  standards on purpose. `Templates/` is scaffolding and stays out of coverage.

## The checks

The pull request gate runs one script, and it can be run locally to get the same answer. It needs
PowerShell 7.6, PSScriptAnalyzer 1.25.0, and Pester 6.2.0:

```powershell
./Tools/Invoke-QualityGate.ps1
```

It runs every test, including the comparison of the generated files with their sources and the
compliance check of this repository's own PowerShell, and fails below 80 percent coverage. The
tests of the logging examples that write a real log file also need PSFramework 1.15.479. They are
skipped where it is not installed or is not allowed to load, as under Windows Smart App Control,
and CI runs them. Markdown is checked separately:

```bash
markdownlint-cli2 "**/*.md" "!**/docs/*/*.md"    # uses .markdownlint.json, 120-column lines
```

CI runs the gate on Windows, Linux, and macOS, and lints the Markdown. All four checks are required
for `main`: a pull request cannot be merged until each of them has passed, and the ruleset lets no
one bypass that.

## Pull requests

Branches, commit messages, PR titles, and PR bodies follow
[powershell-pull-requests.instructions.md](.github/instructions/powershell-pull-requests.instructions.md),
the same conventions the standards give every consuming repository. In short: a
`<type>/<description>` branch from an up-to-date default branch, a Conventional Commits title, one
concern per pull request, and a Verification section that reports the checks as they came out.

A change to `Templates/Workflows/sync-copilot-standards.yml` does not reach consumers by itself,
because the sync never touches a consumer's workflows. Each consumer needs its own copy updated.
