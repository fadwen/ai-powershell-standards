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

## credential-scan.yml

Scans a project for credentials on every pull request and every push to `main`. It runs
`.github/scripts/Invoke-CredentialScan.ps1` with the scanner that the project chose: betterleaks,
gitleaks, or trufflehog. The file here is a template with three placeholders. The installer fills
them in, so install it with the installer and do not copy it by hand.

### Install

```powershell
./Tools/Install-CopilotStandards.ps1 -ProjectPath 'C:\Projects\MyModule' -IncludeCredentialScan gitleaks
```

The installer writes the workflow, the scan script, and the configuration of the scanner from
[Templates/CredentialScan](../CredentialScan). It installs none of them without the parameter, and
it never replaces a workflow or a configuration that the project already has. The scan script is
the exception: it belongs to the standards, and every later installation or sync replaces it.

### Configuration

| Value | Meaning |
| --- | --- |
| `CREDENTIAL_SCANNER` | The scanner: `betterleaks`, `gitleaks`, or `trufflehog`. |
| `CREDENTIAL_SCANNER_VERSION` | The version to download. The installer writes the one that the scan script was tested with. |
| `CREDENTIAL_SCANNER_SHA256` | The SHA-256 of the release archive of that version for the runner, as the checksum file of the release gives it. |

Change the version and the hash together, and read what the new version reports in the same change:
the built-in rules of a scanner belong to its version. The script supports betterleaks 1.x,
gitleaks 8.x, and trufflehog 3.x, and refuses another major version.

The job checks out with `fetch-depth: 0`. The script refuses a clone that does not hold the whole
history, because a scan of one commit passes while a credential is in an earlier one.

### What it uses

- `actions/checkout` v7.0.1, pinned to a commit.
- The release archive of the scanner, downloaded from the scanner's repository on GitHub and
  compared with the hash above before it is unpacked.
