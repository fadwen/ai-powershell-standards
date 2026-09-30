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

## Write for a Reader Who Was Not There

Commit messages and PRs are permanent records. They are read months later by reviewers, maintainers,
and auditors who never saw the conversation that produced the change. Write every one so it stands on
its own for that reader.

- **Describe the change, not the session.** State what the code does now and why. Leave out how the
  work unfolded: the approaches tried and dropped, the order things were done in, what was fixed
  along the way. Mention a rejected approach only when a reviewer would otherwise ask why it was not
  used.
- **No conversational voice.** No "as discussed", "per your request", "you asked", "I noticed",
  "let me know", "happy to", or "we decided". Write in the third person about the code: "Adds",
  "Fixes", "The gate now fails when".
- **No references a stranger cannot resolve.** No "the earlier issue", "the approach above", "option
  B", "the second fix", or names coined during the session. Link an issue, PR, commit, or file, or
  describe the thing itself.
- **No assistant artifacts.** No mention of an AI tool, prompts, or chat. No hedging written for the
  person at the keyboard, such as "should work now" or "hopefully".
- **Explain the domain.** Expand acronyms on first use and name the command or setting involved, so
  a reviewer outside the team can follow.

A quick test: if the text would read oddly pasted into a changelog or a release note, rewrite it.

## Before Opening the PR

1. Run the repository's gates locally. At minimum PSScriptAnalyzer and Pester, plus markdownlint
   when Markdown changed. Use the same commands the CI workflow runs.
2. When the repository keeps a `CHANGELOG.md`, add the change under `## [Unreleased]` in the
   [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) section that fits: `Added`, `Changed`,
   `Fixed`, `Removed`, `Deprecated`, or `Security`. Write it for someone using the module.
3. When a public function's signature changed, update its PlatyPS Markdown under `docs/`, as
   [platyps.instructions.md](./platyps.instructions.md) describes.
4. In a repository that consumes these standards, one with
   `.github/workflows/sync-copilot-standards.yml`, do not edit the paths that workflow mirrors:
   `.github/copilot-instructions.md`, `.github/instructions/`, `.github/prompts/`,
   `powershell-standards/`, `.claude/rules/powershell-standards/`, and
   `.claude/commands/powershell-standards/`. The next sync overwrites them, so change
   [ai-powershell-standards](https://github.com/fadwen/ai-powershell-standards) instead. In
   ai-powershell-standards itself those paths are the source, and editing them is the point.

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
- Annotate the diff, as described below.
- Do not merge your own PR, force-push a branch someone else has reviewed, or delete a branch unless
  asked.

## Annotate the Diff

Once the PR is open, read its diff as a reviewer would and leave inline review comments on the lines
whose reason the code does not make plain. They explain the change to the reviewer now and stay
attached to the PR for anyone tracing the line's history later.

Decide first where each explanation belongs:

- **Why the code is the way it is** belongs in a code comment, because it must stay true as long as
  the code does. Add the code comment rather than a review comment.
- **Why the code changed** belongs in a review comment, because it describes this change and would
  go stale in the code. That covers a deleted guard, a changed default, a test expectation that
  moved, a workaround for a tool's behavior, a value chosen from several reasonable ones, or a line
  that fixes a bug found elsewhere.

Skip lines whose reason is already plain from the code, a code comment, or the PR body. Do not
restate what a line does. A PR with nothing that needs explaining needs no annotations.

Post all the annotations as a single review with the `COMMENT` event, so they arrive together and
do not approve or block the PR. The same audience rules apply as for the PR body. `gh pr review`
cannot comment on lines, so use the REST API:

```powershell
$review = @{
    commit_id = (gh pr view <number> --json headRefOid --jq .headRefOid)
    event     = 'COMMENT'
    body      = 'Notes on the lines whose reason the diff does not show.'
    comments  = @(
        @{ path = 'Public/Get-Thing.ps1'; line = 42; side = 'RIGHT'; body = 'Why this line changed.' }
    )
}
# ConvertTo-Json stops at a depth of 2 by default, which would turn each comment into a string
$review | ConvertTo-Json -Depth 5 | gh api --method POST repos/<owner>/<repo>/pulls/<number>/reviews --input -
```

`line` is the line number in the file as the PR leaves it, with `side = 'RIGHT'`. For a deleted line,
use its number in the old file with `side = 'LEFT'`. A comment must sit on a line inside the diff.
