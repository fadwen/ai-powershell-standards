---
applyTo: '**'
description: 'How to branch, commit, and open pull requests in repositories that use these standards'
---

# Branches, Commits, and Pull Requests

Follow these whenever you commit or open a pull request. They match the history already in these
repositories, so a new PR reads like the ones before it.

## Branch

- Never commit to the default branch. Start from an up-to-date default branch.
- Name the branch `<type>/<short-kebab-description>`, with the same type as the title:
  `feat/onelogin-provider`, `fix/release-notes-length`, `docs/pester-6-2`.
- A release branch is `release/vX.Y.Z`.
- One concern per branch. Unrelated fixes found on the way get their own branch and PR.

## Commit Messages and PR Title

Use [Conventional Commits](https://www.conventionalcommits.org/). The PR title follows the same form
as the commit, because a squash merge turns the title into the commit on the default branch.

```text
<type>(<scope>): <subject>
```

- **Type**: `feat`, `fix`, `docs`, `refactor`, `test`, `perf`, `ci`, `build`, or `chore`. A release
  is `release: X.Y.Z`.
- **Scope**: optional. The area touched, in lower case: `feat(graph)`, `fix(release)`,
  `docs(pester)`.
- **Subject**: imperative mood, lower case, no trailing period, at most 72 characters. Say what the
  change does, not which files it touched.
- **Body**: wrap at 72 columns. Explain why the change was needed and what it fixes. The diff already
  shows how.
- **Breaking change**: add `!` after the type or scope, and a `BREAKING CHANGE:` footer saying what a
  caller must do.
- **Attribution**: no `Co-Authored-By` trailer, "Generated with" footer, or any other AI tool
  attribution in commits, PR titles, PR bodies, or files.

## Before Opening the PR

1. Run the repository's gates locally. At minimum PSScriptAnalyzer and Pester, plus markdownlint
   when Markdown changed. Use the same commands the CI workflow runs.
2. When the repository keeps a `CHANGELOG.md`, add the change under `## [Unreleased]` in the
   [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) section that fits: `Added`, `Changed`,
   `Fixed`, `Removed`, `Deprecated`, or `Security`. Write it for someone using the module.
3. When a public function's signature changed, update its PlatyPS Markdown under `docs/`, as
   [platyps.instructions.md](./platyps.instructions.md) describes.
4. Do not edit paths the standards sync mirrors: `.github/copilot-instructions.md`,
   `.github/instructions/`, `.github/prompts/`, `powershell-standards/`,
   `.claude/rules/powershell-standards/`, and `.claude/commands/powershell-standards/`. The next sync
   overwrites them. Change the standards repository instead.

Open the PR as a draft when a gate fails and you cannot fix it, and say which gate in the body.

## PR Body

Use these sections, in this order. Leave out a section only when it would be empty.

```markdown
## Summary

What changed and why, in a few sentences. Lead with the problem it solves.

## Changes

- One bullet per change a reviewer should know about.

## Verification

- The commands you ran and their results, for example "Pester: 248 passed, 0 failed".
- Anything you could not verify, stated plainly.

## Notes

- Merge order, follow-ups, or decisions left for the reviewer.
```

- Link the issue it resolves with `Closes #123` in the Summary.
- When the PR depends on another, in this repository or elsewhere, say which one merges first.
- Report results as they were. A skipped or failing check is written as skipped or failing.

## After Opening

- Watch the PR's checks. When one fails, read its log, fix the cause, and push to the same branch.
- Do not merge your own PR, force-push a branch someone else has reviewed, or delete a branch unless
  asked.
