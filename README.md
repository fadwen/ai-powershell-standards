# AI PowerShell Standards

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Jeffrey_Stuhr-0077B5?style=flat-square&logo=linkedin)](https://www.linkedin.com/in/jeffrey-stuhr-034214aa/)
[![BlueSky](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fpublic.api.bsky.app%2Fxrpc%2Fapp.bsky.actor.getProfile%2F%3Factor%3Dtechbyjeff.net&query=%24.followersCount&style=social&logo=bluesky&label=Follow%20on%20BSky)](https://bsky.app/profile/techbyjeff.net)
[![Blog](https://img.shields.io/badge/Read_My_Blog-TechbyJeff-lightgrey?style=flat-square&logo=ghost)](https://techbyjeff.net)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

PowerShell coding standards written for AI coding agents. One set of rules is generated into the
files that GitHub Copilot, Claude Code, and Codex each read, so that all three write and review
PowerShell the same way.

The rules target PowerShell 7.6 (LTS), with Windows PowerShell 5.1 as a compatibility target that a
project opts into, Pester 6.2, and Microsoft.PowerShell.PlatyPS 1.x. Statements in the rules about
how PowerShell and Pester behave were tested on PowerShell 7.6.9, Windows PowerShell 5.1, and
Pester 6.2.0 on 2026-11-15.

## What is in it

| Part | What it is |
| --- | --- |
| Core rules | A short file that every agent always loads: how to apply the rules, the rules that matter in almost every file, and a function template that is tested code. |
| Topic rules | Twelve files, each loaded when an agent works on a matching file: style, functions, error handling, security, help, versions, modules, Pester, PlatyPS, CI, README files, and pull requests. |
| Skills | Eight procedures for common tasks, such as writing a function with its tests or reviewing code. |
| Pester guides | Thirteen longer reference guides that the Pester rules point to. |
| Analyzer settings | A PSScriptAnalyzer settings file that checks the layout rules. |
| Tools | An installer, a sync workflow, and a script that checks code against the rules. |

Every rule has an ID, such as `ERR-10`, and says whether it is a requirement (MUST) or a default
(SHOULD). The rules are written to be checked against the code in front of the reader, and each
topic file gives the reason and an example for the rules that need one.

## Requirements

- To install into a project: PowerShell 7.6, or Windows PowerShell 5.1.
- To work on this repository: PowerShell 7.6, PSScriptAnalyzer 1.25.0, and Pester 6.2.0.

## Install in a project

```powershell
git clone https://github.com/fadwen/ai-powershell-standards.git
./ai-powershell-standards/Tools/Install-CopilotStandards.ps1 -ProjectPath 'C:\Projects\MyModule'
```

This installs the files for all three agents. Run it again at any time to update them. Add
`-WhatIf` to see what would change first.

| Parameter | Effect |
| --- | --- |
| `-Agent Copilot, ClaudeCode, Codex` | Installs only for the agents named. The default is all three. |
| `-IncludeAnalyzerSettings` | Also installs `PSScriptAnalyzerSettings.psd1`. In an existing project this can report many layout findings. |
| `-IncludeSyncWorkflow` | Also installs a scheduled workflow that keeps the files up to date. |
| `-RemoveLegacyFiles` | Removes the files that versions before 2.0 installed or mirrored. |
| `-Force` | Replaces an `AGENTS.md` or `.github/copilot-instructions.md` that the project wrote itself. |

What each agent receives:

| Agent | Core rules | Topic rules | Skills |
| --- | --- | --- | --- |
| GitHub Copilot | `.github/copilot-instructions.md` | `.github/instructions/powershell-*.instructions.md` | `.github/skills/` |
| Claude Code | A rule that imports the Copilot file | `.claude/rules/powershell-standards/`, whose rules import the Copilot files | `.claude/skills/` |
| Codex | `AGENTS.md` | Read on demand from `.github/instructions/` | `.agents/skills/` |

Things to know:

- The topic rules under `.github/instructions/` are installed for every agent, because the core file
  tells an agent that does not load them automatically to read them.
- The installer never replaces a file that your project wrote. If the project already has its own
  `AGENTS.md` or `.github/copilot-instructions.md`, the file is left alone and a
  warning says how to connect it to the standards.
- The core rules are installed once, so that no agent loads them twice. They go into
  `.github/copilot-instructions.md`, which GitHub Copilot reads and which a Claude Code rule
  imports. Copilot also reads `AGENTS.md`, so that file is then a short pointer, and Codex reads the
  core rules by following it. When you install for Codex alone, or the project has its own
  `.github/copilot-instructions.md`, `AGENTS.md` holds the core rules.
- When you change `-Agent`, the files that an earlier installation wrote for an agent you no longer
  list are removed.
- The installed files are generated. Do not edit them in your project: the next update replaces
  them.

## Keep a project up to date

```powershell
./Tools/Install-CopilotStandards.ps1 -ProjectPath 'C:\Projects\MyModule' -IncludeSyncWorkflow
```

The workflow runs weekly, reinstalls the files from this repository, and opens a pull request when
anything changed. See [Templates/Workflows](Templates/Workflows/README.md) for the repository setting
it needs and for how to pin it to a release.

## Add your own rules

Put project-specific rules in your own files, not in the generated ones:

- For GitHub Copilot, a file under `.github/instructions/` whose name does not start with
  `powershell-`.
- For Claude Code, your own `CLAUDE.md`, or a file under `.claude/rules/` outside the
  `powershell-standards` folder. The installer never touches `CLAUDE.md`.
- For Codex, your own `AGENTS.md`. The installer leaves a file that you wrote alone, and its warning
  names the line to add so that the file points to the standards.

The core rules state that an explicit instruction from the user takes precedence over them. If a
rule in this repository is wrong for many projects, change it here instead.

## Check code against the rules

```powershell
./Tools/Test-StandardsCompliance.ps1 -Path ./src
```

The script runs PSScriptAnalyzer with the settings file and adds checks that PSScriptAnalyzer does
not have, such as `throw` in an advanced function. Each finding names the rule it breaks. A clean
result does not prove that code follows every rule; many rules need a reader.

## Upgrading from a version before 2.0

Version 2.0 replaced the instruction files and the prompt files. Run the installer with
`-RemoveLegacyFiles` so that the old files do not stay behind and contradict the new ones.

| Before 2.0 | In 2.0 |
| --- | --- |
| `.github/prompts/new-function.prompt.md` | Skill `powershell-new-function` |
| `create-module`, `scaffold-project` | Skills `powershell-new-module` and `powershell-ci-pipeline` |
| `create-test` | Skill `powershell-write-tests` |
| `code-analysis`, `validate-standards` | Skill `powershell-review` |
| `security-review` | Skill `powershell-security-review` |
| `optimize-performance`, `performance-analysis` | Skill `powershell-performance-review` |
| `create-workflow` | Removed |
| Instruction files with mixed names | Twelve files named `powershell-<topic>.instructions.md` |
| `.claude/commands/powershell-standards/` | Removed with the prompt files. The same skills are installed for Claude Code. |
| Mirrored `powershell-standards/Examples/` | No longer installed. The rules carry their own tested templates. |
| Installer parameters `-StandardsType` and `-LinkType` | Removed. The installer no longer creates project folders or links. |

Prompt files were replaced because VS Code documents that they run only in a mode that is being
removed. Agents load a skill when a request matches its description, and most let you name one
directly, for example `/powershell-review`.

Rules that changed in substance are listed in [CHANGELOG.md](CHANGELOG.md).

## Work on this repository

The rules are written once, under `standards/`, and everything the agents read is generated from
there.

```text
standards/
    manifest.psd1      the list of rule files, their file patterns, and the skills
    core.md            the always-loaded core
    rules/             one file for each topic
    skills/            one folder for each skill
    examples/          the function template and its tests
Tools/
    Build-AgentInstructions.ps1    generates the files below from standards/
    Install-CopilotStandards.ps1   installs the generated files into a project
    Test-StandardsCompliance.ps1   checks code against the rules
    Invoke-QualityGate.ps1         runs the tests and the coverage gate
.github/copilot-instructions.md, AGENTS.md                   generated
.github/instructions/powershell-*.instructions.md            generated
.claude/rules/powershell-standards/, and the three skills folders   generated
.github/instructions/pester-supporting-docs/                 written by hand
```

To change a rule:

1. Edit the file under `standards/`. Do not edit a generated file.
2. Run `./Tools/Build-AgentInstructions.ps1`.
3. Run `./Tools/Invoke-QualityGate.ps1`.

The gate runs every test and fails below 80 percent coverage. The tests also check that the
generated files match their sources, that every PowerShell sample in the instructions parses, that
every file the instructions mention exists, and that the repository's own PowerShell passes
`Test-StandardsCompliance.ps1`. When a rule states how PowerShell or Pester behaves, test the
statement on PowerShell 7.6 and Windows PowerShell 5.1 before writing it down.

The worked examples under [powershell-standards/Examples](powershell-standards/Examples/README.md) follow the rules
and have tests.

## Acknowledgments

- **PowerShell Community**: For establishing excellent best practices and style guidelines
- **GitHub Copilot Team**: For creating the extensible instruction system
- **Enterprise PowerShell Users**: For real-world validation and feedback

The format of the rules owes a good deal to Frank Lesniak's
[PSStyleGuide](https://github.com/franklesniak/PSStyleGuide): requirement keywords, rules short enough
to check, reasons kept apart from the rules, and agent files generated from one source. Six rules
were adopted from it as well, after testing: STY-07, STY-23, STY-34, STY-35, ERR-32, and VER-10.

## License

MIT. See [LICENSE](LICENSE).
