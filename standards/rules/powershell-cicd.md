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
        run: ./build/Invoke-Tests.ps1
```

The test script is the gate shown under "The CI gate" in
`.github/instructions/powershell-pester.instructions.md`: it fails when the Pester result is not
`Passed`, when no tests ran, and when coverage is below 80 percent.

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

### Help checks for a module with compiled help (CIC-01)

Run the validation and drift checks from `.github/instructions/powershell-platyps.instructions.md` on
every pull request, and build the compiled help into the module before packaging it.

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
