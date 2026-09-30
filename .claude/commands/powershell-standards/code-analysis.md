---
description: 'Comprehensive code quality analysis with expert-reviewed standards'
argument-hint: '[file-or-code]'
---

Run the shared prompt in @.github/prompts/code-analysis.prompt.md.

That file is written for GitHub Copilot Chat and is the only copy of the prompt. Apply it here as
follows:

- Ignore its `agent` and `tools` frontmatter.
- `${input:NAME:...}` is a value to collect. Take it from the arguments below when they supply it,
  otherwise ask before starting. The text after the name lists the choices or a placeholder, and a
  final segment after another colon is the default.
- `${selection}` is the code the user selected or named in the arguments. `${fileBasename}` is the
  file that code lives in, and `${workspaceFolderBasename}` is the repository folder name.
- If the contents of the prompt file are not shown above, read `.github/prompts/code-analysis.prompt.md`
  before doing anything else.

Arguments: $ARGUMENTS
