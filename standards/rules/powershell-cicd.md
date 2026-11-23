# CI pipelines for PowerShell projects

These rules apply to workflow and pipeline files, and to the build scripts they call, in a
repository that contains PowerShell code.

## Rules

- **CIC-01** A pull request pipeline runs PSScriptAnalyzer and Pester, and fails when either reports
  a problem. A module that ships compiled help also runs the help checks.
- **CIC-02** Install build tools at a fixed version, for example
  `Install-PSResource -Name Pester -Version 6.2.0`. An unpinned install can change what a passing
  build means.
- **CIC-03** Run PowerShell steps with `shell: pwsh`. When the project declares Windows PowerShell 5.1
  support, add a job that runs the tests under 5.1 (`shell: powershell` on a Windows runner). Do not
  add one otherwise.
- **CIC-04** A build matrix MUST NOT include a PowerShell version that is past its end-of-support
  date.
- **CIC-05** A pipeline script fails by throwing, with `$ErrorActionPreference = 'Stop'` set at the
  top. It MUST NOT report failure only by writing text, and it MUST NOT reset `$LASTEXITCODE` without
  first acting on the failure it carried.
- **CIC-06** Secrets come from the CI system's secret store and reach a step as environment
  variables. A secret MUST NOT be written in a workflow file or printed to the log.
- **CIC-07** Give each job the least permissions it needs with an explicit `permissions` block.
- **CIC-08** Publish a module only from a tagged release, with the API key taken from a secret.
- **CIC-09** Reference an action by a release tag or a full commit ID, never by a branch name such as
  `@main`.
- **CIC-10** A module that is published rehearses its release on every pull request: the release
  script runs with `-WhatIf`, stages the package, imports it in a new process, checks the Gallery's
  limits, and stops before the upload (MOD-10 to MOD-14).
- **CIC-11** The repository has a `.gitattributes` file that fixes line endings, for example
  `* text=auto eol=lf`, so that every platform checks out the same bytes.

### Further gates

- **CIC-12** A pipeline has a security gate: credential scanning, static analysis for security
  issues, and dependency vulnerability scanning, plus container scanning when the build runs in
  containers. A high-risk finding fails the build.
- **CIC-13** A performance gate compares execution time and memory use with recorded baselines, for
  the code that has performance tests (TST-43).
- **CIC-14** A documentation gate validates the README. The pipeline SHOULD also generate a status
  report and a deployment summary for each run, and keep the runbooks current.
- **CIC-23** A credential scan reads the history of every branch and tag as well as the files of
  the checkout. It runs a scanner at a fixed version whose download is checked against a hash,
  first finds a value that the job plants outside the repository, and writes no value that it
  finds to the log.

### Jobs and triggers

- **CIC-15** A pipeline that packages, deploys, or publishes separates the work into jobs: build
  and test, security scan, package, deploy, and publish. A later job takes the package from the
  packaging job as an artifact, and each deployment environment has protection rules.
- **CIC-16** When the project declares more than one operating system or PowerShell version, run
  the tests as a matrix over them, one parallel job for each combination.
- **CIC-17** Besides pull requests, run the pipeline on pushes to the main branch and on a nightly
  schedule.

### Release and deployment

- **CIC-18** Automated publishing derives the semantic version from the commit messages, publishes
  prerelease versions from development branches, and generates the release notes from the
  changelog.
- **CIC-19** When the project requires signed code, the pipeline signs it: the certificate comes
  from secure storage, a timestamp server is configured, and the signature is validated after
  signing.
- **CIC-20** A pipeline that deploys promotes a build through development, testing, staging, and
  production, with manual approval before staging and before production.
- **CIC-21** Monitor build performance and track deployment metrics.
- **CIC-22** An Azure DevOps pipeline is a multi-stage pipeline with approval gates, a variable
  group for each environment, and secrets taken from Azure Key Vault.

## Notes and examples

### Pull request workflow (CIC-01 to CIC-05, CIC-07)

```yaml
name: Quality gates

on:
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Install build tools
        shell: pwsh
        run: |
          Install-PSResource -Name PSScriptAnalyzer -Version 1.25.0 -TrustRepository
          Install-PSResource -Name Pester -Version 6.2.0 -TrustRepository

      - name: Run PSScriptAnalyzer
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          $findings = @(Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error, Warning)
          $findings | Format-Table -Property Severity, RuleName, ScriptName, Line -AutoSize
          if ($findings.Count -gt 0) {
              throw "PSScriptAnalyzer reported $($findings.Count) finding(s)."
          }

      - name: Run Pester
        shell: pwsh
        run: ./Tests/Invoke-Tests.ps1 -TestType Unit -Environment CI -CodeCoverage
```

The test script is the runner in `.github/instructions/pester-supporting-docs/test-execution.md`.
It fails when the Pester result is not `Passed`, when no tests ran, and, with `-CodeCoverage`, when
coverage is below the configured target of 80 percent (TST-40). Without that switch the runner does
not measure coverage. The alternative is the minimal gate shown under "The CI gate" in
`.github/instructions/powershell-pester.instructions.md`, which makes the same three checks and is
called without parameters.

The runner and the Pester settings files are kept in the `Tests` folder. A `build` folder beside
`Tests` is the alternative; both are one level below the repository root, so the scripts are the
same in either.

**CIC-02.** The pin also avoids a known failure: Pester 6.0.0, 6.0.1, and 6.1.0 do not import on
PowerShell 7.4.0 to 7.4.4, which bites self-hosted agents and pinned container images. The error is
`Cannot convert the "PesterConfigurationDeserializer" value of type "System.String" to type "System.Type"`.
Pester 6.2.0 imports on every 7.4 release. Measured on Linux, macOS, and Windows with PowerShell
7.4.0 to 7.4.7 and 7.4.22.

A commit ID is the stricter choice for CIC-09, because a tag can be moved. Write the tag after it in a
comment, as in `actions/checkout@<commit ID> # v7.0.1`, and look the ID up; do not invent one.

Use `runs-on: windows-latest` when the code is Windows-only. For a project that declares Windows
PowerShell 5.1 support, add a second job on a Windows runner whose steps use `shell: powershell`.

### PSScriptAnalyzer settings

PSScriptAnalyzer's default rules cover correctness but not layout. To check layout as well, enable
the formatting rules in a settings file. Save this as `PSScriptAnalyzerSettings.psd1` in the
repository root and run
`Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`:

<!-- include: PSScriptAnalyzerSettings.psd1 -->

With these settings a hashtable padded to align its `=` signs is reported, which enforces STY-04.

PSScriptAnalyzer 1.25.0 also applies a file with this name when it is in the folder passed to
`-Path` and `-Settings` is omitted. Pass `-Settings` anyway, so that the result does not depend on
which folder is analyzed.

`PSUseCorrectCasing` is left out on purpose. In PSScriptAnalyzer 1.25.0 it intermittently fails with a
`NullReferenceException` in a new session, which makes a CI run fail at random.

Do not use the built-in `CodeFormattingOTBS` preset for this standard. It enables
`PSAlignAssignmentStatement`, which requires the `=` signs of a hashtable to be aligned, the opposite
of STY-04.

`-Settings` also takes the name of a preset that ships with PSScriptAnalyzer. The `PSGallery` preset
is run with `Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSGallery`, and any finding fails the
build. Run a preset and the settings file together when correctness and formatting are both to be
checked. No shipped preset covers the 115-character line limit (STY-03), which is why the settings
file enables `PSAvoidLongLines` itself. Which presets to adopt is the consuming team's decision.

### Help checks for a module with compiled help (CIC-01)

Run the validation and drift checks from `.github/instructions/powershell-platyps.instructions.md` on
every pull request, and build the compiled help into the module before packaging it. Install
Microsoft.PowerShell.PlatyPS on the runner with the other build tools, at a fixed version (CIC-02).

### Publishing (CIC-06, CIC-08)

```yaml
name: Publish

on:
  push:
    tags: ['v*']

permissions:
  contents: read

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Publish to the PowerShell Gallery
        shell: pwsh
        env:
          GALLERY_API_KEY: ${{ secrets.GALLERY_API_KEY }}
        run: |
          $ErrorActionPreference = 'Stop'
          Publish-PSResource -Path ./ModuleName -ApiKey $env:GALLERY_API_KEY
```

### Failing correctly (CIC-05)

`Invoke-Pester` sets `$LASTEXITCODE` to the number of failures, and the runner fails the step on a
non-zero value. A script that resets it to zero has to have thrown for every failure first, or the
step passes with failing tests.

The integration and performance steps of the CI guide report a failed test as a warning and let the
build go on. Such a step resets `$LASTEXITCODE` to zero only after it has written the warning.

### Line endings (CIC-11)

Without a `.gitattributes` file, git decides the line endings of a checkout from each computer's
settings. GitHub's Windows runners check text files out with CRLF, and Linux runners with LF. A test
that compares the text of a file with a here-string, or with text built in the test, then passes on
one and fails on the other (STY-34).

```text
* text=auto eol=lf
```

This line stores text files with LF and checks them out with LF on every platform. PowerShell 7 and
Windows PowerShell 5.1 both read such files.

### Security and documentation gates (CIC-12, CIC-14)

The security gate is made of these scans:

- Credential scanning, so that no secret is committed (SEC-01, CIC-23).
- Static analysis for security issues.
- Dependency vulnerability scanning.
- Container scanning, when the build runs in containers.
- Findings sent to the security monitoring system, where the organization has one.

PSScriptAnalyzer 1.25.0 ships a `ScriptSecurity` preset that covers part of the static analysis:

```powershell
$findings = @(Invoke-ScriptAnalyzer -Path . -Recurse -Settings ScriptSecurity)
if ($findings.Count -gt 0) {
    throw "The security scan reported $($findings.Count) finding(s)."
}
```

The documentation gate validates the README and the other documentation the project keeps. The
reports that the pipeline generates are a status report for each run, a deployment summary, and
updates to the runbooks.

### Credential scan (CIC-23)

Each part of the rule answers a scan that passes while a credential is in the repository. Measured
with betterleaks 1.10.1, gitleaks 8.30.1, and trufflehog 3.99.9 on Linux, macOS, and Windows:

- A credential stays in the history after the commit that removes it. All three scanners find it
  there, also on a branch that was never merged and on a commit that only a tag holds. A checkout
  of one commit hides it, so the job checks out with `fetch-depth: 0`.
- No scanner's history scan reads what a merge commit itself added. The scan of the files does.
- betterleaks and trufflehog end with exit code 0 for a folder that does not exist, and a
  configuration can leave out more than was meant. The job therefore first has to find a value
  in the form of a key that it makes outside the repository, put together from parts so that no
  file holds it.
- A scanner does not report every value that has the form of a key. On Linux, trufflehog left out
  6 of 1,500 random values in the form of a Stripe key and 1 of 1,500 in the form of a GitHub
  token, and reported each of them with `filtered_unverified` among its `--results`. The job
  therefore makes several values of each form, and a rule has to report one of them.
- A scanner is a release archive and not a module. Pin it by its version and by the SHA-256 of
  the archive, because a release tag can be moved to other content.
- trufflehog writes every value that it finds into its output, as text and as JSON. betterleaks
  and gitleaks write `REDACTED` in its place when `--redact` is given. The log of a public
  repository is public (CIC-06).
- trufflehog reads the `.git` folder as files unless that folder is left out, and then reports
  again what its history scan reports.

betterleaks and trufflehog can check a value against the service that it seems to belong to, with
`--validation` and by default. The scan switches that off, with `--no-verification` for
trufflehog. What such a check sends was not measured.

The scan reads its ignore file, its configuration, and its own script from the commit that it
scans, which on a pull request is the pull request's own copy. A change can therefore leave out
the finding that it adds. The scan guards against an accident, not against an author who means to
get past it. Two things keep what is left out in view. The scan says in every run how much the
ignore file and the configuration leave out. And a change to one of those files, or to the
workflow, is reviewed as a change to what the scan reports: where a project has a second reader,
it requires one for those paths, for example with CODEOWNERS entries and the branch rule "Require
review from Code Owners". GitHub's documentation says that an entry requires nothing without that
rule, that the code owners are taken from the base branch, and that an author cannot approve
their own pull request. In a repository with one maintainer no rule binds the author, and the
line that the scan writes is the check to read.

The standards ship a scan that does all of this, for whichever of the three scanners the project
chooses. It is installed only on request, because its workflow uses the project's CI time:
`Install-CopilotStandards.ps1 -IncludeCredentialScan <scanner>` writes
`.github/scripts/Invoke-CredentialScan.ps1`, a workflow that runs it, and a configuration for the
scanner. The `powershell-credential-scan` skill adds the scan to a project and reads what its
first run reports. A project whose own scan works keeps it.

### A workflow with several jobs (CIC-15 to CIC-17)

```yaml
name: Build and release

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
    tags: ['v*']
  schedule:
    - cron: '0 2 * * *'

permissions:
  contents: read

jobs:
  build-and-test:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v7

      - name: Install build tools
        shell: pwsh
        run: |
          Install-PSResource -Name PSScriptAnalyzer -Version 1.25.0 -TrustRepository
          Install-PSResource -Name Pester -Version 6.2.0 -TrustRepository

      - name: Run Pester
        shell: pwsh
        run: ./Tests/Invoke-Tests.ps1 -TestType Unit -Environment CI -CodeCoverage

  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Run the security scans
        shell: pwsh
        run: ./build/Invoke-SecurityScan.ps1

  package-artifact:
    needs: [build-and-test, security-scan]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - name: Stage the package
        shell: pwsh
        run: ./build/Publish-Module.ps1 -WhatIf

      - uses: actions/upload-artifact@v7
        with:
          name: module
          path: out/ModuleName

  deploy-environments:
    needs: package-artifact
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/download-artifact@v8
        with:
          name: module
          path: out/ModuleName

      - name: Deploy
        shell: pwsh
        run: ./build/Deploy-Module.ps1 -Path ./out/ModuleName

  publish-gallery:
    needs: package-artifact
    if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/download-artifact@v8
        with:
          name: module
          path: out/ModuleName

      - name: Publish to the PowerShell Gallery
        shell: pwsh
        env:
          GALLERY_API_KEY: ${{ secrets.GALLERY_API_KEY }}
        run: |
          $ErrorActionPreference = 'Stop'
          Publish-PSResource -Path ./out/ModuleName -ApiKey $env:GALLERY_API_KEY
```

The scripts under `build/` are the project's own, and the test runner is the one described under
the pull request workflow. The action versions are the releases that were current on 2026-11-16;
look up the current release before copying one (CIC-09). The `staging` and `production`
environments carry the protection rules, such as required reviewers, and the `if` conditions run
the deployment only for the main branch and the publish only for a version tag.

The matrix lists the operating systems that the project declares. Windows PowerShell 5.1 is one more
job (CIC-03). PowerShell 7.4 and 7.5 are past end of support and stay out of every matrix (CIC-04).

GitHub's hosted runners carry PowerShell 7.6, the LTS release, so `shell: pwsh` runs 7.6 there and
a job that tests on PowerShell 7.7 has to install it first. That was the state of the Ubuntu 24.04,
Windows Server 2025, and macOS 15 images on 2026-11-17.

### Release, signing, and deployment (CIC-18 to CIC-20)

- Versioning: the next semantic version is derived from the commit messages (PRQ-10 to PRQ-12), a
  development branch publishes a prerelease version, and the release notes are generated from
  `CHANGELOG.md` (MOD-12).
- Code signing: keep the certificate in secure storage, configure a timestamp server, validate each
  signature after signing, and use the certificate type that each environment needs.
- Environment promotion:

| Environment | Deployment |
| --- | --- |
| Development | Automatic, on commits to a feature branch |
| Testing | Automatic, on commits to the main branch |
| Staging | Manual approval; mirrors production |
| Production | Several approvals |

- Blue-green deployment, for a release without downtime: deploy to the inactive environment slot,
  run smoke tests and health checks, switch traffic to the new deployment, and keep the previous
  version for a quick rollback.

### Metrics (CIC-21)

- Build performance: build execution time, test execution duration, artifact size, and resource
  usage.
- Deployment: deployment frequency and duration, failure rates and their root causes, mean time to
  recovery (MTTR), and change failure rate.

### Azure DevOps (CIC-22)

The pipeline has these stages:

```text
Build and Validate
Security Scanning
Package Creation
Environment Deployments
PowerShell Gallery Publishing
```

It also has parallel jobs for the PowerShell versions under test, artifact management and
retention, and automated rollback when a deployment fails.
