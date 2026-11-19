# PowerShell standards

These are the rules for writing and reviewing PowerShell in this repository. **MUST** and
**MUST NOT** are requirements. **SHOULD** is the default: depart from it only for a reason you state.

## How to apply the rules

- Apply them to code you write or change. Do not reformat or rewrite code the task does not touch.
- An explicit instruction from the user takes precedence. If following it breaks a MUST, say which
  one. A departure that is meant to stay is recorded in the code (DOC-22). Leave a recorded
  departure as it is, and do not record one that the user has not decided.
- Do not invent facts: no made-up module names, version numbers, measurements, links, or authors. Ask,
  or leave it out.
- When you can run commands, run PSScriptAnalyzer and the tests before you report the work as done,
  and say what you ran.

## Topic rules

Each topic has a file with the complete rules, the reasons, and examples:

| When the work involves | Read |
| --- | --- |
| Any `.ps1`, `.psm1`, or `.psd1` file | `.github/instructions/powershell-style.instructions.md` |
| Functions and parameters | `.github/instructions/powershell-functions.instructions.md` |
| Errors, strict mode, output streams | `.github/instructions/powershell-error-handling.instructions.md` |
| Secrets, credentials, untrusted input | `.github/instructions/powershell-security.instructions.md` |
| Comment-based help and comments | `.github/instructions/powershell-help.instructions.md` |
| Which PowerShell version a feature needs | `.github/instructions/powershell-version.instructions.md` |
| Module manifests, root modules, and releases | `.github/instructions/powershell-modules.instructions.md` |
| Pester tests | `.github/instructions/powershell-pester.instructions.md` |
| Help Markdown under `docs/` | `.github/instructions/powershell-platyps.instructions.md` |
| Workflows and build scripts | `.github/instructions/powershell-cicd.instructions.md` |
| `README.md` | `.github/instructions/powershell-readme.instructions.md` |
| Branches, commits, and pull requests | `.github/instructions/powershell-pull-requests.instructions.md` |

GitHub Copilot and Claude Code load the matching file automatically when you work on such a file. If
your tooling does not, you MUST read the matching files before creating or changing the file.

## Core rules

These are the rules that matter in almost every file. They are a selection from the topic files, and
each one keeps the ID it has there, so the numbers below are not consecutive: STY-04, for example, is
in the style file. The topic files have gaps of their own, because most of them start each section
at a new ten. A gap does not mean that a rule is missing, and a rule that is only in a topic file
counts as much as one listed here.

### Version

<!-- rules: VER-01, VER-02, VER-04, VER-06 -->

### Style

<!-- rules: STY-02, STY-03, STY-06, STY-12, STY-13, STY-14, STY-16, STY-20, STY-21, STY-32, STY-40, STY-42 -->

### Functions

<!-- rules: FUN-01, FUN-04, FUN-10, FUN-11, FUN-12, FUN-21, FUN-25, FUN-26, FUN-30, FUN-31 -->

### Errors

<!-- rules: ERR-01, ERR-02, ERR-03, ERR-10, ERR-11, ERR-12, ERR-13, ERR-15, ERR-20, ERR-23 -->

### Security

<!-- rules: SEC-01, SEC-03, SEC-05, SEC-06, SEC-10 -->

### Help

<!-- rules: DOC-01, DOC-02, DOC-05, DOC-07 -->

## Function template

Copy this shape. It runs under strict mode on PowerShell 7.6 and Windows PowerShell 5.1, and its
tests are the test template in `.github/instructions/powershell-pester.instructions.md`.

<!-- include: standards/examples/Get-ConfigValue.ps1 -->

What the template shows:

- Help is the first thing in the body and covers every parameter, the input, and the output.
- `begin` does the work that must succeed once. Its `catch` ends the function with
  `$PSCmdlet.ThrowTerminatingError($_)`, which keeps the original error.
- A problem the function detects itself becomes an `ErrorRecord` with its own ID and category.
- `process` handles each item. A missing item is reported with `$PSCmdlet.WriteError()` and the loop
  continues, so the caller decides with `-ErrorAction` whether that stops the work.
- Each result is written to the pipeline as it is produced, with a named type, and outside any `try`
  block.
