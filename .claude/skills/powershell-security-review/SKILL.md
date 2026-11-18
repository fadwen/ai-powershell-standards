---
name: powershell-security-review
description: Review PowerShell code for security problems such as exposed secrets, unsafe credential handling, command or path injection, and disabled certificate checks. Use when asked for a security review or audit of PowerShell code.
---

# Security review of PowerShell code

Read `.github/instructions/powershell-security.instructions.md` first, unless it is already loaded.

## Steps

1. Map where data enters the code: parameters, files, environment variables, web responses, and
   pipeline input. Treat each as untrusted unless the code proves otherwise.
2. Follow each input to where it is used and check:
   - Secrets and credentials: SEC-01 to SEC-08, and SEC-50 to SEC-53 where the code uses a secret
     vault. Search for literals that look like passwords, tokens, keys, and connection strings,
     including in comments, defaults, and test data.
   - Web requests that carry a credential: SEC-09. Look for a request that does not pass
     `-MaximumRedirection 0`, and for `-FollowRelLink` and `-PreserveAuthorizationOnRedirect`.
   - Command construction: SEC-10. Look for `Invoke-Expression`, `[scriptblock]::Create()`,
     `Start-Process` with a built argument string, and strings passed to `cmd /c` or `pwsh -Command`.
   - Paths: SEC-12. Look for input joined into a path that is then read, written, or deleted.
   - Queries: SEC-13.
   - Input checks: SEC-11 and SEC-16 to SEC-19.
   - Code signing, where the code signs files: SEC-30 to SEC-35.
   - Transport and privilege: SEC-14 and SEC-15.
3. Check what the code writes. Verbose, debug, warning, and error messages, log files, and exported
   files must not contain secrets or personal data.
4. Run PSScriptAnalyzer. Its rules `PSAvoidUsingPlainTextForPassword`,
   `PSAvoidUsingConvertToSecureStringWithPlainText`, `PSAvoidUsingUsernameAndPasswordParams`, and
   `PSAvoidUsingInvokeExpression` cover part of this.
5. Confirm each finding by reading the full path from input to use. A pattern match alone is not a
   finding. The patterns of SEC-40 find candidates. `Add-Type -TypeDefinition` is a Medium finding
   (SEC-41).

## Report

List findings with the most serious first, each with its tier (Critical, High, Medium, or Low), and
state the overall risk as the highest tier found (SEC-42): file and line, rule ID, how the problem
could be exploited or exposed, and the corrected code. Say which inputs you traced and which you did
not. If you find a real secret, tell the user that it must be revoked and replaced; removing it from
the file does not remove it from the repository history. This review covers the code only. It is not
a compliance assessment, so do not state that the code meets any regulation or framework.
