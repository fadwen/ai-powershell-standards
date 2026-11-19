---
name: powershell-review
description: Review PowerShell code against this repository's PowerShell standards and report findings by rule ID. Use when asked to review, validate, analyze, or check PowerShell code for quality or standards compliance.
---

# Review PowerShell code against the standards

Read the core rules (`.github/copilot-instructions.md`, or `AGENTS.md` if the repository has no such
file) and the topic files they list for the kind of file under review, unless they are already
loaded. Every rule has an ID such as `ERR-10`; cite it.

## Steps

1. Establish the target version from `#requires` lines and the module manifest. Judge the code
   against that version, not against the newest one.
2. Run the tools first when you can: PSScriptAnalyzer, with `-Settings ./PSScriptAnalyzerSettings.psd1`
   when that file exists, and the existing tests. Include what they report.
3. Read the code for what tools cannot see, in this order:
   1. Correctness: logic errors, unhandled failure paths, wrong assumptions about a command's output.
   2. Error handling: the ERR rules, in particular `throw` in advanced functions, a missing
      `-ErrorAction Stop` inside `try`, and empty or silent `catch` blocks.
   3. Security: the SEC rules.
   4. Functions and output: the FUN rules.
   5. Version fit: the VER rules.
   6. Help and style: the DOC and STY rules.
4. Confirm each finding before reporting it. Read the surrounding code, and where behaviour is in
   doubt, run a small test. Do not report a rule violation in code that the change did not touch,
   unless it is a defect.
5. A comment of the form `# Exception to ERR-11: reason` records a decision of the project (DOC-22).
   Do not report the code under it as a finding of that rule. Do report the comment when its reason
   is missing or no longer matches the code. Do not propose such a comment as the fix for a finding.

## Report

List findings with the most serious first. For each one give the file and line, the rule ID or the
word "defect", what is wrong, and the corrected code. Separate requirements (MUST) from
recommendations (SHOULD). List the recorded exceptions with their reasons, apart from the findings.
State what you ran and what you did not check. If nothing is wrong, say so; do not invent findings.
