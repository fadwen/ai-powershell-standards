# PowerShell standards

The rules for writing and reviewing PowerShell in this repository are in
`.github/copilot-instructions.md`. This file only points to them, so that an agent which loads both
files does not receive the rules twice.

- If rules with IDs such as `STY-02` and `ERR-10` are already in your context, that file is loaded.
  Do not read it again.
- Otherwise you MUST read `.github/copilot-instructions.md` before you create, change, or review a
  `.ps1`, `.psm1`, or `.psd1` file, and you MUST then read the topic files that it lists for the
  work.
