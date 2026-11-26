---
name: powershell-credential-scan
description: Add a credential scan to the CI of a PowerShell project with betterleaks, gitleaks, or trufflehog, and deal with what it reports. Use when asked to add, set up, or repair secret scanning, credential scanning, or leak detection, or to handle the findings of such a scan.
---

# Add a credential scan

A credential that was committed stays in the repository after the commit that removes it. This
skill adds a scan of the history and the files to the project's CI (CIC-23), with the scanner that
the user chooses, and deals with what the first run reports.

Read these first, unless they are already loaded:

- `.github/copilot-instructions.md`, or `AGENTS.md` if the repository has no such file
- `.github/instructions/powershell-cicd.instructions.md`
- `.github/instructions/powershell-security.instructions.md`

Every statement about a scanner below was measured with betterleaks 1.10.1, gitleaks 8.30.1, and
trufflehog 3.100.1 on Linux, macOS, and Windows.

## Steps

1. Look for a scan that the project already has: a workflow job or a hook that runs betterleaks,
   gitleaks, trufflehog, or another scanner, and files such as `.betterleaks.toml`,
   `.gitleaks.toml`, and `.gitleaksignore`. A scan that works is left as it is. Do not replace it,
   add a second one beside it, or move it to the form below unless the user asks for that.
2. Ask the user which scanner to use, and say that the scan runs on every pull request and every
   push to the default branch, which uses the project's CI time. Do not choose for them. The
   three differ in what they report:

   | | betterleaks | gitleaks | trufflehog |
   | --- | --- | --- | --- |
   | A quoted word after such a name, as in `$password = 'qwerty'` | Reported | Not reported | Not reported |
   | A quoted random value after such a name | Reported | Reported for some values and not for others | Not reported |
   | `$password = [System.Security.SecureString]::new()` | Reported without the installed configuration | Not reported | Not reported |
   | A key in the form of a known service | Reported | Reported | Reported |
   | Leaving out one finding | Fingerprint in `.betterleaksignore` | Fingerprint in `.gitleaksignore` | Fingerprint in `.trufflehogignore`, which the scan script reads |

3. Install the scan with the installer of the standards repository, from a clone at the reference
   that the project's sync workflow names (`STANDARDS_REPO` and `STANDARDS_REF`), or `main`. Give
   the path of the project and the scanner that the user chose, here gitleaks:

   ```powershell
   ./Tools/Install-CopilotStandards.ps1 -ProjectPath '../MyModule' -IncludeCredentialScan gitleaks
   ```

   It writes `.github/scripts/Invoke-CredentialScan.ps1`, `.github/workflows/credential-scan.yml`,
   and the configuration of the scanner in the root of the project. The script belongs to the
   standards and later updates replace it. The workflow and the configuration belong to the
   project, and a file that is already there is not replaced.
4. When the project has one workflow that its release also runs, move the job from
   `credential-scan.yml` into that workflow with its three `env` values and remove the separate
   file, so that a release cannot go out past the scan. Keep `fetch-depth: 0`: the script refuses
   a clone that does not hold the whole history.
5. Say that the ignore file, the configuration, the scan script, and the workflow decide what the
   scan reports, and that a pull request runs its own copies of them, so a change can leave out
   the finding that it adds. When the project has more than one maintainer, offer to require a
   review for those paths with entries in its CODEOWNERS file, here for gitleaks:

   ```text
   /.gitleaks.toml @owner
   /.gitleaksignore @owner
   /.github/scripts/Invoke-CredentialScan.ps1 @owner
   /.github/workflows/credential-scan.yml @owner
   ```

   Put them after the other lines, because the last pattern that matches a file decides, and say
   that the entries require nothing until the branch rule "Require review from Code Owners" is
   on. Do not turn that rule on unasked. When the project has one maintainer, say that no such
   rule binds the author of a change, and that the warning which the scan writes in every run,
   "Left out of this scan", is the check to read.
6. Run the scan. On a computer where the scanner may run:

   ```powershell
   ./.github/scripts/Invoke-CredentialScan.ps1 -Scanner gitleaks
   ```

   The script downloads the scanner, and an application control policy can refuse to start a
   downloaded program. Do not look for a way around the policy: push the branch and read the
   result of the workflow instead.
7. Read every finding, as the next section says, until the scan passes. Then report.

## Reading a finding

The scan reports a place, never a value: the rule, the file, the line, the commit for a finding in
the history, and a fingerprint. Look at the place itself, with `git show <commit>:<file>` for the
history.

- **A real credential.** Tell the user at once, and that it has to be revoked at the service that
  issued it before anything else. Removing it from the file does not remove it from the history,
  and everyone who can read the repository can read it there. Only after it is revoked does its
  fingerprint go into the ignore file, with a comment that says so. Rewriting the history is the
  user's decision, not a step of this skill.
- **A placeholder in a file**, such as a password in a test or a sample. Prefer changing the value
  so that the scanner no longer reports it: build it at run time, or use a value that is not in
  the form of a credential.
- **A placeholder in the history.** A commit does not change, so the value cannot be changed
  there. Its fingerprint goes into the ignore file, under a comment that says what it is.
- **A form that is never a credential**, reported in many places. For betterleaks and gitleaks,
  add an `[[allowlists]]` entry to the configuration that names the rule and the form. gitleaks
  refuses a configuration that names a rule which it does not have. For trufflehog, leave a path
  out in `.trufflehog-exclude.txt` only when nothing in that path can be a credential.

An entry in an ignore file or an exception in a configuration MUST NOT be added to make the scan
pass. Each one is a finding that was read. A rule MUST NOT be switched off with `disabledRules`,
replaced by a rule of the same name, or filtered for that either: the scan runs again without the
configuration, and its warning counts every place that the configuration leaves out. Show the
user the list before it is committed: the user decides what is left out.

To change the scanner later, change the three `env` values of the workflow to the name, the
version, and the SHA-256 of the archive for the runner, as the checksum file of that release gives
it, and add the configuration of the new scanner. To change the version, change the version and
the hash together and read what the new version reports: its built-in rules belong to it. The
script supports betterleaks 1.x, gitleaks 8.x, and trufflehog 3.x.

## Report

Say which scanner the user chose and which files were added or changed. List every finding of the
first run with its place and what was done about it: revoked, changed, or left out, with the
reason. Quote the "Left out of this scan" warning of the last run, so that the user sees how much
the scan does not report. Say whether the scan was run on this computer or only in the workflow, and what its last
run reported. If a real credential was found, say so first.
