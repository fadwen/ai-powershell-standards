# README files for PowerShell projects

These rules apply to a project's `README.md`.

## Rules

- **RDM-01** A README says what the project does, what it needs, how to install it, how to use it, and
  how to run its tests, in that order.
- **RDM-02** State requirements exactly: the PowerShell version and edition, the operating systems,
  and each required module with its minimum version. Take them from the manifest and `#requires`
  lines, not from memory.
- **RDM-03** Every command in a README MUST run as written against the current code, and MUST be valid
  for the project's declared PowerShell version.
- **RDM-04** A README MUST NOT contain invented content: no badges for pipelines that do not exist, no
  coverage or performance figures that were not measured, no compliance claims, no testimonials.
- **RDM-05** Write in plain language. Do not add emoji to headings or marketing text.
- **RDM-06** Link to files with relative paths that exist in the repository. Do not describe folders
  or documents the repository does not contain.

## Notes and examples

A README built from these rules has this shape. Leave out a section that has nothing true to say.

````markdown
# ModuleName

One or two sentences that say what the module does and who it is for.

## Requirements

- PowerShell 7.6 or later
- Windows, Linux, or macOS
- Microsoft.PowerShell.SecretManagement 1.1.2 or later

## Installation

```powershell
Install-PSResource -Name ModuleName
```

## Usage

```powershell
Get-Thing -Name 'alpha'
```

Gets the thing named alpha. Run `Get-Help Get-Thing -Full` for every parameter.

## Tests

```powershell
Invoke-Pester -Path ./Tests
```

## License

MIT. See [LICENSE](LICENSE).
````

**RDM-03.** Before writing a usage example, read the function's parameters. Common mistakes are a
parameter name that does not exist, and a command that the declared version does not have.

**RDM-04.** Add a status badge only for a workflow file that exists in the repository, using that
workflow's own badge URL.
