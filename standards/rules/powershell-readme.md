# README files for PowerShell projects

These rules apply to a project's `README.md`.

## Rules

- **RDM-01** A README says what the project does, what it needs, how to install it, how to use it, and
  how to run its tests, in that order.
- **RDM-02** State requirements exactly: the PowerShell version and edition, the operating systems,
  and each required module with its minimum version. Take them from the manifest and `#requires`
  lines, not from memory. State Windows PowerShell 5.1 support only when the project is tested on
  it.
- **RDM-03** Every command in a README MUST run as written against the current code, and MUST be valid
  for the project's declared PowerShell version.
- **RDM-04** A README MUST NOT contain invented content: no badges for pipelines that do not exist, no
  coverage or performance figures that were not measured, no compliance claims, no testimonials.
- **RDM-05** Write in plain language. Do not add emoji to headings or marketing text.
- **RDM-06** Link to files with relative paths that exist in the repository. Do not describe folders
  or documents the repository does not contain.

### Sections

- **RDM-07** Open with an overview: a technical summary, the key features, and the audiences that
  the project serves.
- **RDM-08** Give a quick start: one command that installs the project and one that uses it, the
  output to expect, and links to the sections to read next.
- **RDM-09** Give the system requirements as a table with a minimum and a recommended value for
  each component: PowerShell, operating system, memory, disk space, and network.
- **RDM-10** State the permissions and access that the project needs: the account, its rights on
  the target systems, and the protocols and ports.
- **RDM-11** Describe every supported way to install: the PowerShell Gallery, a manual download
  with a signature check, and an organization's own deployment system. Each one ends with a
  command that verifies the installation.
- **RDM-12** Document configuration: the template to copy, the structure of the configuration
  file, and the environment variables.
- **RDM-13** Order the usage examples from basic to advanced, and give each one its expected output
  or the use case it serves.
- **RDM-14** Give troubleshooting guidance: a diagnostic command, the common problems with their
  symptoms, causes, and solutions, and a table of error codes with the action to take. An error
  code in the table MUST be one that the code emits.
- **RDM-15** Document the project's performance characteristics from measurements, and its
  monitoring integration where it has one.

### Structure and presentation

- **RDM-16** Give the README a table of contents whose links work, keep the heading levels in a
  logical order, and keep the layout readable on a narrow screen.
- **RDM-17** Name the language of every code block, so that it is highlighted.
- **RDM-18** Use tables for structured information, Mermaid diagrams for workflow and
  architecture, and collapsible `<details>` sections for detail that most readers skip.

## Notes and examples

A README built from these rules has this shape. Leave out a section that has nothing true to say.

````markdown
# ModuleName

One or two sentences that say what the module does and who it is for.

- Feature: what it lets the user do.
- Feature: what it lets the user do.

## Contents

- [Quick start](#quick-start)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Tests](#tests)
- [License](#license)

## Quick start

```powershell
Install-PSResource -Name ModuleName
Get-Thing -Name 'alpha'
```

Expected output:

```text
Name  Status
----  ------
alpha Ready
```

Next: [Configuration](#configuration) and [Usage](#usage).

## Requirements

| Component | Minimum | Recommended |
| --- | --- | --- |
| PowerShell | 7.6 | 7.6 |
| Operating system | Windows 10, Linux, or macOS | Windows Server 2022 |

| Module | Version | Purpose |
| --- | --- | --- |
| Microsoft.PowerShell.SecretManagement | 1.1.2 or later | Reads the API token |

<details>
<summary>Permissions and access</summary>

- The account that runs the commands is a local administrator on the target computers.
- WinRM over HTTPS, port 5986, outbound to the target computers.

</details>

## Installation

### From the PowerShell Gallery

```powershell
Install-PSResource -Name ModuleName
Get-Module -Name ModuleName -ListAvailable
```

### Manual download

```powershell
$uri = 'https://github.com/owner/repository/releases/latest/download/ModuleName.zip'
Invoke-WebRequest -Uri $uri -OutFile './ModuleName.zip'
Expand-Archive -LiteralPath './ModuleName.zip' -DestinationPath './ModuleName'
Get-AuthenticodeSignature -LiteralPath './ModuleName/ModuleName.psm1'
```

## Configuration

Copy `config-template.json` to `config.json` and edit it:

```json
{
  "environment": "Production",
  "logging": { "level": "Information", "path": "./Logs/" }
}
```

| Environment variable | Purpose |
| --- | --- |
| `MODULE_CONFIG_PATH` | Path of the configuration file |

## Usage

### Basic

```powershell
Get-Thing -Name 'alpha'
```

Gets the thing named alpha. Run `Get-Help Get-Thing -Full` for every parameter.

### Advanced

```powershell
'alpha', 'beta' | Get-Thing | Export-Csv -LiteralPath './things.csv'
```

Use case: a weekly inventory report.

## Troubleshooting

Run the failing command again with `-Verbose`.

<details>
<summary>"Access is denied"</summary>

- Symptoms: the command fails with an authentication error.
- Cause: the account has no rights on the target computer.
- Solution: grant the rights listed under Requirements, then check with
  `Test-WSMan -ComputerName 'SERVER01'`.

</details>

| Error code | Description | Immediate action |
| --- | --- | --- |
| `ThingNotFound` | No thing has the given name | List the names with `Get-Thing` |

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
workflow's own badge URL. The other header badges (Gallery version, license, coverage, downloads)
follow the same rule: each one shows what a real source reports. A static image with a typed-in
figure, such as a fixed coverage percentage, is invented content.

**RDM-07.** The overview is plain description. Return-on-investment statements and other business
claims are marketing text (RDM-05).

**RDM-09, RDM-15.** Give a memory, disk space, network, or performance figure only when it was
measured or when a dependency declares it; leave the row out otherwise (RDM-04).

**RDM-11.** For an organization's own deployment system, show the command that system really uses.
The verification step can be `Get-Module -Name ModuleName -ListAvailable`, and for a manual
download `Get-AuthenticodeSignature`.
