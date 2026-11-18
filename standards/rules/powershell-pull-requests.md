# Branches, commits, and pull requests

These rules apply whenever you commit or open a pull request in a repository that uses these
standards. They match the history of those repositories, so a new pull request reads like the ones
before it.

## Rules

### Branch

- **PRQ-01** Never commit to the default branch. Before starting work, run `git fetch` and confirm
  that the local default branch is not behind the remote, then branch from the up-to-date default
  branch.
- **PRQ-02** Name the branch `<type>/<short-kebab-description>`, with the same type as the title. A
  release branch is `release/vX.Y.Z`.
- **PRQ-03** One concern per branch. An unrelated fix found on the way gets its own branch and pull
  request.

### Commit messages and titles

- **PRQ-10** Use Conventional Commits, `<type>(<scope>): <subject>`, for commit messages and for the
  pull request title. A squash merge turns the title into the commit on the default branch.
- **PRQ-11** The type is `feat`, `fix`, `docs`, `refactor`, `test`, `perf`, `ci`, `build`, or `chore`,
  and a release is `release: X.Y.Z`. The subject is imperative, lower case, has no trailing period,
  and is at most 72 characters.
- **PRQ-12** Wrap the body of a commit message at 72 columns and explain why the change was needed.
  Mark a breaking change with `!` after the type or scope and a `BREAKING CHANGE:` footer that says
  what a caller must do. A pull request description or a comment MUST NOT be wrapped that way:
  write each paragraph and each list item on one line.
- **PRQ-13** Commits, titles, pull request bodies, and files MUST NOT carry AI tool attribution: no
  `Co-Authored-By` trailer for a tool and no "Generated with" footer.

### A reader who was not there

- **PRQ-20** Describe the change, not the session: what the code does now and why. Leave out how the
  work unfolded, and mention a rejected approach only when a reviewer would otherwise ask about it.
- **PRQ-21** Write in the third person about the code. Conversational voice, references that a
  stranger cannot resolve, mentions of an AI tool or a chat, and hedging MUST NOT appear.

### Before opening the pull request

- **PRQ-30** Run the repository's checks locally with the commands that CI runs, and report each
  result as it was. The minimum is PSScriptAnalyzer and Pester, plus markdownlint when Markdown
  changed. A skipped or failing check is written as skipped or failing.
- **PRQ-31** When the repository keeps a `CHANGELOG.md`, add the change under `## [Unreleased]` in the
  Keep a Changelog section that fits: `Added`, `Changed`, `Fixed`, `Removed`, `Deprecated`, or
  `Security`. Write the entry for someone using the module.
- **PRQ-32** When a public function's signature changed, update its help Markdown under `docs/`.
- **PRQ-33** In a repository that consumes these standards, the files that the standards installed
  MUST NOT be edited. Change them in the standards repository.
- **PRQ-34** Open the pull request as a draft when a check fails and cannot be fixed, and name the
  check in the body.

### Body

- **PRQ-40** The body has the sections Summary, Changes, Verification, and Notes, in that order.
  Leave out a section only when it would be empty.

### After opening

- **PRQ-50** Watch the checks. When one fails, read its log, fix the cause, and push to the same
  branch.
- **PRQ-51** Annotate the diff: leave inline review comments on the lines whose reason the code does
  not make plain, posted as one review with the `COMMENT` event.
- **PRQ-52** Do not merge your own pull request, force-push a branch that someone has reviewed, or
  delete a branch unless asked.

## Notes and examples

**PRQ-01.** A local clone can be many merges behind without showing it: `git status` and
`git log` compare with the last fetched state, not with the remote. Work that starts from a stale
branch conflicts with everything merged since, and the conflict appears only when the pull request
is opened.

```powershell
& git fetch origin
$behind = & git rev-list --count 'HEAD..origin/main'
if ([int]$behind -gt 0) {
    throw "The local branch is $behind commit(s) behind origin/main. Update it before starting."
}
```

**PRQ-10 to PRQ-12.** The scope is optional and names the area touched, in lower case:
`feat(graph)`, `fix(release)`, `docs(pester)`. The subject says what the change does, not which
files it touched.

**PRQ-12.** GitHub renders a line break inside a paragraph or a list item of a pull request
description or a comment as a line break. It joins the lines of a Markdown file in a repository,
so text that is wrapped like the repository's files reads as short broken lines once it is posted.
Measured on 2026-11-18 with GitHub's Markdown API: `gfm` mode, which is how a comment is rendered,
gave one `<br>` for each wrapped line, and `markdown` mode, which is how a file is rendered, gave
none. A description wrapped at 100 columns was shown with 67 such breaks.

**PRQ-20, PRQ-21.** Commit messages and pull requests are permanent records. They are read months
later by reviewers and maintainers who never saw the conversation that produced the change.

- Write "Adds", "Fixes", "The gate now fails when". Do not write "as discussed", "you asked",
  "I noticed", "let me know", or "we decided".
- Do not write "the earlier issue", "the approach above", or a name coined during the work. Link an
  issue, a pull request, a commit, or a file, or describe the thing itself.
- Do not write hedging for the person at the keyboard, such as "should work now".
- Expand an acronym on first use and name the command or setting involved.

A quick test: if the text would read oddly when pasted into a changelog, rewrite it.

**PRQ-33.** The files that the standards install either carry a "Generated from" notice or have a
name that starts with `powershell-`. The next update replaces them. A repository that has
`.github/workflows/sync-copilot-standards.yml` consumes these standards, and each run of that
workflow replaces the installed files.

**PRQ-40.** Use this shape:

```markdown
## Summary

What changed and why, in a few sentences. Lead with the problem it solves.

## Changes

- One bullet for each change a reviewer should know about.

## Verification

- The commands that were run and their results, for example "Pester: 248 passed, 0 failed".
- Anything that could not be verified, stated plainly.

## Notes

- Merge order, follow-ups, or decisions left for the reviewer.
```

Link the issue that the pull request resolves with `Closes #123` in the Summary. When it depends on
another pull request, say which one merges first.

**PRQ-51.** Decide first where each explanation belongs. Why the code is the way it is belongs in a
code comment, because it must stay true as long as the code does. Why the code changed belongs in a
review comment, because it describes this change and would go stale in the code: a deleted guard, a
changed default, a test expectation that moved, a workaround for a tool, or a value chosen from
several reasonable ones. Skip lines whose reason is already plain, and do not restate what a line
does. A pull request with nothing to explain needs no annotations.

`gh pr review` cannot comment on lines, so use the REST API:

```powershell
$review = @{
    commit_id = (& gh pr view $number --json headRefOid --jq '.headRefOid')
    event = 'COMMENT'
    body = 'Notes on the lines whose reason the diff does not show.'
    comments = @(
        @{ path = 'Public/Get-Thing.ps1'; line = 42; side = 'RIGHT'; body = 'Why this line changed.' }
    )
}
# ConvertTo-Json stops at a depth of 2 by default, which would turn each comment into a string.
$json = $review | ConvertTo-Json -Depth 5
$json | & gh api --method POST "repos/$owner/$repository/pulls/$number/reviews" --input -
```

`line` is the line number in the file as the pull request leaves it, with `side = 'RIGHT'`. For a
deleted line, use its number in the old file with `side = 'LEFT'`. A comment must sit on a line that
is inside the diff.
