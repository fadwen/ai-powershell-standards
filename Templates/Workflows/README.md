# Workflow templates

Workflows to copy into a project that uses these standards. They are templates: nothing in this
folder runs in the standards repository itself.

## sync-copilot-standards.yml

Keeps a project's copy of the standards up to date. It runs weekly, reinstalls the files from the
standards repository with `Tools/Install-CopilotStandards.ps1`, and opens a pull request when
anything changed.

### Install

```powershell
./Tools/Install-CopilotStandards.ps1 -ProjectPath 'C:\Projects\MyModule' -IncludeSyncWorkflow
```

Or copy the file by hand to `.github/workflows/sync-copilot-standards.yml` in the project. The
installer never replaces a workflow file that is already there.

### Enable the repository setting first

The job needs permission to open pull requests. In the project's repository, enable
Settings > Actions > General > Workflow permissions > "Allow GitHub Actions to create and approve
pull requests". Without it the job installs the files and then fails at the pull request step.

### Configuration

Edit the three values under `env` in the workflow file.

| Value | Default | Meaning |
| --- | --- | --- |
| `STANDARDS_REPO` | `fadwen/ai-powershell-standards` | The repository that publishes the standards. Change it if you maintain a fork. |
| `STANDARDS_REF` | `main` | The branch, tag, or commit to install from. Set a release tag to decide when updates arrive. |
| `STANDARDS_AGENTS` | `Copilot,ClaudeCode,Codex` | The agents the project uses. |

The schedule is Mondays at 06:00 UTC. The workflow can also be started by hand from the Actions tab,
once the file is on the default branch.

### What it changes

| Path | Behaviour |
| --- | --- |
| `.github/instructions/powershell-*.instructions.md` and `.github/instructions/pester-supporting-docs/` | Replaced. Files that the standards no longer contain are removed. |
| `.claude/rules/powershell-standards/` | Replaced, when Claude Code is selected. |
| Skills whose names start with `powershell-` | Replaced, in the skill folder of each selected agent. |
| `.github/copilot-instructions.md`, `AGENTS.md` | Replaced only if an earlier installation wrote them. A file the project wrote itself is left alone. |
| `.github/powershell-attribution.md` | Created when it is missing, from the profile of the project's GitHub owner or the empty template. Never changed afterwards. |
| Instruction and prompt files from versions before 2.0 | Removed. |
| Everything else, including other instruction files, rules, skills, and workflows | Never touched. |

A change made in the project to a file that the standards own is overwritten by the next run. Put
project-specific rules in a file of your own, as the main README describes, and propose changes to
the shared rules in the standards repository.

### Actions it uses

Both are pinned to a commit, with the release in a comment beside it:

- `actions/checkout` v7.0.1
- `peter-evans/create-pull-request` v8.1.3
