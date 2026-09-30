@../../../.github/instructions/pull-requests.instructions.md

Source of this rule: `.github/instructions/pull-requests.instructions.md` (shared with GitHub Copilot,
which applies it to every file through `applyTo: '**'`). This rule has no `paths`, so Claude Code loads
it at launch: opening a pull request does not always involve reading a file. Relative links inside it
resolve from `.github/instructions/`.
