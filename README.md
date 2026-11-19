# AI PowerShell Standards

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Jeffrey_Stuhr-0077B5?style=flat-square&logo=linkedin)](https://www.linkedin.com/in/jeffrey-stuhr-034214aa/)
[![BlueSky](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fpublic.api.bsky.app%2Fxrpc%2Fapp.bsky.actor.getProfile%2F%3Factor%3Dtechbyjeff.net&query=%24.followersCount&style=social&logo=bluesky&label=Follow%20on%20BSky)](https://bsky.app/profile/techbyjeff.net)
[![Blog](https://img.shields.io/badge/Read_My_Blog-TechbyJeff-lightgrey?style=flat-square&logo=ghost)](https://techbyjeff.net)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Quality gates](https://github.com/fadwen/ai-powershell-standards/actions/workflows/quality-gates-pr.yml/badge.svg)](https://github.com/fadwen/ai-powershell-standards/actions/workflows/quality-gates-pr.yml)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.6_LTS-blue.svg)](https://github.com/PowerShell/PowerShell)
[![GitHub Copilot](https://img.shields.io/badge/GitHub%20Copilot-Optimized-green.svg)](https://github.com/features/copilot)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Ready-blue.svg)](https://code.claude.com/docs/en/memory)
[![Codex](https://img.shields.io/badge/Codex-Ready-lightgrey.svg)](AGENTS.md)

PowerShell coding standards written for AI coding agents. One set of rules is generated into the
files that GitHub Copilot, Claude Code, and Codex each read, so that all three write and review
PowerShell the same way.

The rules target PowerShell 7.6 (LTS), with Windows PowerShell 5.1 as a compatibility target that a
project opts into, Pester 6.2, and Microsoft.PowerShell.PlatyPS 1.x. Statements in the rules about
how PowerShell and Pester behave were tested on PowerShell 7.6.9, Windows PowerShell 5.1, and
Pester 6.2.0 on 2026-11-15. The
[version rules](.github/instructions/powershell-version.instructions.md) hold the support lifecycle,
the features that differ between versions, and the changes in behaviour.

## What is in it

| Part | What it is |
| --- | --- |
| Core rules | A short file that every agent always loads: how to apply the rules, the rules that matter in almost every file, and a function template that is tested code. |
| Topic rules | Twelve files, each loaded when an agent works on a matching file: style, functions, error handling, security, help, versions, modules, Pester, PlatyPS, CI, README files, and pull requests. |
| Skills | Eight procedures for common tasks, such as writing a function with its tests or reviewing code. |
| Pester guides | Thirteen longer reference guides that the Pester rules point to. |
| Templates | A module to copy that has working code and tests, two reference layouts, and a workflow that keeps a project's copy of the standards up to date. |
| Worked examples | A function, a module with compiled help, and their tests, all passing every check. |
| Analyzer settings | A PSScriptAnalyzer settings file that checks the layout rules. |
| Tools | An installer, a script that checks code against the rules, the generator, and the quality gate. |

Every rule has an ID, such as `ERR-10`, and says whether it is a requirement (MUST) or a default
(SHOULD). The rules are written to be checked against the code in front of the reader, and each
topic file gives the reason and an example for the rules that need one.

The numbers are not consecutive, and a gap does not mean that a rule is missing. The core rules are
a selection from the topic files, each under the ID it has there, so the core lists STY-02 and
STY-03 and then STY-06. Most topic files also start each section at a new ten: the style rules run
from STY-01 to STY-08 for layout and from STY-10 to STY-16 for naming, so there is no STY-09.

## Requirements

- To install into a project: PowerShell 7.6, or Windows PowerShell 5.1.
- To work on this repository: PowerShell 7.6, PSScriptAnalyzer 1.25.0, and Pester 6.2.0.

## Quick start

Pick the starting point that fits:

| Starting from | Do this |
| --- | --- |
| A PowerShell project that already exists | [Install the standards into it](#install-in-a-project) |
| Nothing yet, and a module to write | [Start a new module from the template](#start-a-new-module-from-the-template) |
| A team that wants its own edition of the rules | [Use this repository as a template](#use-this-repository-as-a-template) |

Nothing needs configuring afterwards. Open the project in your editor and ask for PowerShell:
[each agent loads the rules by itself](#how-each-agent-loads-the-rules).

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
| `-Owner` | The GitHub owner whose attribution profile seeds `.github/powershell-attribution.md`. By default it is read from the `origin` remote. |
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
  them. The attribution file is the exception, described below.

### Author attribution

The installer also creates `.github/powershell-attribution.md`, a short list of author details:
name, company, copyright holder, blog, LinkedIn, and Bluesky. Agents write the lines that have a
value into the `.NOTES` of new help and into the `Author`, `CompanyName`, and `Copyright` keys of a
new module manifest (DOC-18). A line left empty is left out.

The file is yours. The installer creates it only when it is missing and never changes it afterwards,
not even with `-Force`, so edit it to put in your own details. Its first content comes from
[`standards/attribution/`](standards/attribution/README.md): the profile of the project's GitHub
owner when there is one, and an empty template otherwise.

### Start a new module from the template

[Templates/Powershell-Module](Templates/Powershell-Module/README.md) is a small module with working
code and tests that pass as shipped. Copy it, install the standards beside it, and run its tests:

```powershell
$projectPath = 'C:\Projects\MyModule'
Copy-Item -LiteralPath ./ai-powershell-standards/Templates/Powershell-Module -Destination $projectPath -Recurse
./ai-powershell-standards/Tools/Install-CopilotStandards.ps1 -ProjectPath $projectPath -IncludeAnalyzerSettings -IncludeSyncWorkflow
Invoke-Pester -Path (Join-Path -Path $projectPath -ChildPath 'Tests')
```

The template's README then lists the six steps that turn it into your module: rename the manifest
and root module, generate a GUID, and replace the sample function. The two other folders under
`Templates/` describe layouts and contain no code to copy:
[a collection of scripts](Templates/Script-Collection/README.md) and
[an application made of several modules](Templates/Enterprise-Application/README.md).

### Use this repository as a template

This repository is a GitHub template. **Use this template** on its GitHub page creates a repository
of your own with the same files. The agent files are already in place, so GitHub Copilot, Claude
Code, and Codex follow the rules in it from the first commit.

That suits two cases:

- **Trying the standards.** Create the repository, open it, and ask an agent for a PowerShell
  function.
- **Keeping your own edition of the rules.** Change the files under `standards/`, rebuild as
  [Work on this repository](#work-on-this-repository) describes, and set `STANDARDS_REPO` in the
  sync workflow of each project to your repository.

For a new module or a set of scripts, the module template and the installer give a cleaner start: a
repository made from this template also carries the tools, sources, and examples of the standards
themselves.

## How each agent loads the rules

Nothing needs configuring for any of the three.

- **GitHub Copilot.** VS Code applies `.github/copilot-instructions.md` to every request and each
  file under `.github/instructions/` to the files that match its `applyTo` pattern. A setting is
  needed only when the instruction files are kept somewhere else:

  ```json
  {
    "chat.instructionsFilesLocations": { ".github/instructions": true }
  }
  ```

- **Claude Code.** It discovers `.claude/rules/` by itself, including subfolders. The rule that has
  no `paths` loads the core rules when a session starts, and each other rule loads its topic when
  Claude reads or edits a matching file. The rules import the Copilot files, so there is one copy to
  maintain. Run `/memory` in Claude Code to see what is loaded. Your own `CLAUDE.md` is never
  touched.
- **Codex.** It reads `AGENTS.md`, which holds the core rules or points to them, and opens the topic
  file that the core rules name for the work at hand.

## Use the skills

A skill is a procedure for one kind of task. An agent loads a skill when a request matches its
description, so a plain request is enough: "Write a function that returns the free disk space of a
computer, with tests." Most agents also let you name the skill directly, for example
`/powershell-new-function`.

| Skill | Ask for it when you want |
| --- | --- |
| `powershell-new-function` | A new function with its comment-based help and Pester tests |
| `powershell-new-module` | A new module: manifest, root module, `Public` and `Private` folders, a first function, and tests |
| `powershell-write-tests` | Tests for code that exists, or more coverage |
| `powershell-review` | A review against the rules, with each finding named by rule ID |
| `powershell-security-review` | A review for exposed secrets, unsafe credential handling, injection, and disabled certificate checks |
| `powershell-performance-review` | Performance problems found by measuring, and their fixes |
| `powershell-ci-pipeline` | A CI workflow that runs PSScriptAnalyzer and Pester with a coverage gate |
| `powershell-module-help` | Module help written as Markdown and built with Microsoft.PowerShell.PlatyPS |

## Keep a project up to date

```powershell
./Tools/Install-CopilotStandards.ps1 -ProjectPath 'C:\Projects\MyModule' -IncludeSyncWorkflow
```

The workflow runs weekly, reinstalls the files from this repository, and opens a pull request when
anything changed. Two things to know before the first run:

- In your repository, turn on **Settings > Actions > General > Workflow permissions > Allow GitHub
  Actions to create and approve pull requests**. Without it the workflow cannot open the pull
  request.
- `STANDARDS_REF` in the workflow file names the branch, tag, or commit to install from. It starts
  as `main`; set it to a tag or a commit to decide when updates arrive.

[Templates/Workflows](Templates/Workflows/README.md) describes the workflow's other settings and
what it replaces.

## GitHub Actions

Two workflows matter to a project that uses the standards.

**The sync workflow** keeps the installed files current. It is described above.

**A quality gate for your own code.** The [CI rules](.github/instructions/powershell-cicd.instructions.md)
give a pull request workflow, and the [Pester rules](.github/instructions/powershell-pester.instructions.md)
give the gate script that it runs. Ask an agent to "set up CI for this module" and the
`powershell-ci-pipeline` skill adds both, or copy them from those files. The gate they describe:

- installs PSScriptAnalyzer and Pester at fixed versions, and runs with the least permissions;
- fails when PSScriptAnalyzer reports a problem;
- fails when the Pester result is not `Passed`, which also catches a failed setup block and a file
  that failed discovery, and fails when no tests ran;
- fails below 80 percent coverage;
- runs the tests in a shuffled order and prints the seed, so that a test that depends on another
  one is found;
- adds a Windows PowerShell 5.1 job when the project declares 5.1 support.

The [CI integration guide](.github/instructions/pester-supporting-docs/cicd-integration.md) has the
longer form, with test results and coverage uploaded as artifacts.

This repository runs the same kind of gate on itself.
[quality-gates-pr.yml](.github/workflows/quality-gates-pr.yml) runs
[Invoke-QualityGate.ps1](Tools/Invoke-QualityGate.ps1) and markdownlint on every pull request; see
[Work on this repository](#work-on-this-repository) for what the gate checks.

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


A team rule file for GitHub Copilot, saved as `.github/instructions/team.instructions.md`:

```markdown
---
applyTo: "**/*.ps1"
description: "Team rules for PowerShell"
---

# Team PowerShell rules

- Name internal modules with the `Contoso.` prefix.
- Read service endpoints from `Configuration/Endpoints.psd1`, never from a literal in the code.
- Functions that manage servers support bulk operations and report progress.
- Validate a server name with `[ValidatePattern('^(WEB|DB|APP|DC)\d{2}$')]` and an environment
  with `[ValidateSet('DEV', 'TEST', 'STAGE', 'PROD')]`.
- Use these error IDs: `E1001` server connectivity failure, `E1002` Active Directory operation
  failed, `E1003` SCOM integration error, `E1004` change management approval required.
```

The same rules for Claude Code go in `.claude/rules/team.md`, with `paths:` and a list of patterns
in place of `applyTo`. A skill of your own goes in a folder whose name does not start with
`powershell-`, with a `SKILL.md` that has a `name` and a `description`.

## Check code against the rules

```powershell
./Tools/Test-StandardsCompliance.ps1 -Path ./src
```

The script runs PSScriptAnalyzer with the settings file and adds checks that PSScriptAnalyzer does
not have, such as `throw` in an advanced function. Each finding names the rule it breaks. A clean
result does not prove that code follows every rule; many rules need a reader.

A project that departs from a rule on purpose records that in a comment directly above the
statement, `# Exception to ERR-11: <reason>` (DOC-22). The script then reports the finding with the
severity Information and does not fail on it. A security rule (SEC) cannot be excused this way: the
finding keeps its severity, and the comment is reported as well.

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

## Documentation

The rules, as the agents read them:

| Topic | File |
| --- | --- |
| Core rules and the function template | [copilot-instructions.md](.github/copilot-instructions.md) |
| Layout, naming, strings, paths, collections | [powershell-style](.github/instructions/powershell-style.instructions.md) |
| Functions, parameters, output | [powershell-functions](.github/instructions/powershell-functions.instructions.md) |
| Errors, strict mode, streams | [powershell-error-handling](.github/instructions/powershell-error-handling.instructions.md) |
| Secrets, credentials, untrusted input | [powershell-security](.github/instructions/powershell-security.instructions.md) |
| Comment-based help and comments | [powershell-help](.github/instructions/powershell-help.instructions.md) |
| Versions, lifecycle, differences on 5.1 | [powershell-version](.github/instructions/powershell-version.instructions.md) |
| Modules and releases to the PowerShell Gallery | [powershell-modules](.github/instructions/powershell-modules.instructions.md) |
| Pester 6.2 tests | [powershell-pester](.github/instructions/powershell-pester.instructions.md), with [thirteen guides](.github/instructions/pester-supporting-docs/) |
| Help built with PlatyPS | [powershell-platyps](.github/instructions/powershell-platyps.instructions.md) |
| CI workflows and build scripts | [powershell-cicd](.github/instructions/powershell-cicd.instructions.md) |
| README files | [powershell-readme](.github/instructions/powershell-readme.instructions.md) |
| Branches, commits, pull requests | [powershell-pull-requests](.github/instructions/powershell-pull-requests.instructions.md) |

Beside the rules:

- [Worked examples](powershell-standards/Examples/README.md): a function, a module with compiled
  help, and their tests.
- [Templates](Templates/Powershell-Module/README.md): the module to copy, and the
  [workflow template](Templates/Workflows/README.md).
- [CHANGELOG.md](CHANGELOG.md): what changed, and every statement that was corrected.
- [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

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
statement on PowerShell 7.6 and Windows PowerShell 5.1 before writing it down, and on PowerShell
7.7 as well when the statement is about 7.7.

The worked examples under [powershell-standards/Examples](powershell-standards/Examples/README.md) follow the rules
and have tests.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how the repository is laid out, the conventions that are
easy to break, the checks to run, and how pull requests are written. Every change here reaches each
consuming repository on its next sync, so open an issue first for anything larger than a fix.

## Measuring adoption

No benchmark study backs this repository, so it makes no claims about what adopting it will do for
your team. Measure it in your own environment instead. The checks emit most of what you need:

- PSScriptAnalyzer findings for each pull request, by severity
- Findings from `Test-StandardsCompliance.ps1`, by rule ID
- Test coverage and the pass rate from the Pester gate
- Help completeness: comment-based help on every function, and the markdownlint result

Track these before and after adoption for a real comparison.

## Support

- **Questions, bugs, and rules that are wrong or out of date**: open a GitHub issue.
  [CONTRIBUTING.md](CONTRIBUTING.md) says what to include.
- **Security vulnerabilities**: report privately, as [SECURITY.md](SECURITY.md) describes.

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
