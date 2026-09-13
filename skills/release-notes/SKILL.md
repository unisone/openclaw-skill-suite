---
name: release-notes
description: Generate polished release notes from git history. Use when cutting a release, before publishing a GitHub release, or when you need a changelog from commits between two tags. Groups changes by type, surfaces breaking changes, and drafts highlights.
license: MIT
metadata:
  author: unisone
---

# release-notes

Turns raw git history into release notes a human would actually want to read.

## What it does

- Diffs commits between two refs (tags, branches, or `HEAD`)
- Groups changes by type: features, fixes, breaking changes, chores
- Detects breaking changes from conventional-commit `!` markers and
  `BREAKING CHANGE:` footers
- Drafts a highlights section (the 3-5 changes users actually care about)
- Outputs GitHub-release-ready Markdown

## Usage

```bash
# Notes for the upcoming release (last tag -> HEAD)
git log $(git describe --tags --abbrev=0)..HEAD --oneline

# Between two tags
git log v1.2.0..v1.3.0 --pretty=format:'%h %s %b'
```

Then ask the agent: "draft release notes for v1.3.0 from these commits."

Or with the GitHub CLI, straight into a release draft:

```bash
# Create the tag, then draft release notes from the diff
git tag v1.3.0 && git push origin v1.3.0
gh release create v1.3.0 --generate-notes --draft
# then refine the generated notes with this skill
```

## Process

### 1. Collect the commits

```bash
git log <prev-tag>..<new-tag> --pretty=format:'%h|%s|%b|%an' --no-merges
```

Include merge commits separately if the repo uses merge-based flow —
the merge title usually summarizes the PR better than individual commits.

### 2. Classify each commit

| Prefix / signal | Section |
|---|---|
| `feat`, `feat!` | Features |
| `fix` | Bug fixes |
| `!` or `BREAKING CHANGE:` | ⚠️ Breaking changes (also listed in their own section) |
| `perf` | Performance |
| `docs`, `chore`, `ci`, `refactor`, `test` | Grouped under "Other" or omitted |

Commits without conventional prefixes: classify by message content.
When in doubt, put it in "Other changes" rather than dropping it silently.

### 3. Draft highlights

Pick the 3-5 changes that matter most to users of the software:

- New capabilities they'll notice
- Breaking changes they must act on
- Fixes for widely-reported issues

Write each as one plain sentence. No marketing adjectives.

### 4. Write the notes

```markdown
## v1.3.0

**Highlights**
- ...
- ...

### ⚠️ Breaking changes
- ...

### Features
- ...

### Bug fixes
- ...

### Other changes
- ...

**Full changelog:** <prev-tag>...<new-tag>
```

### 5. Sanity checks before publishing

- Every breaking change appears in the ⚠️ section with a migration hint
- No internal-only chores presented as user-facing features
- Contributor names credited where the repo convention does so
- Version number matches the tag

## Conventions

- Follow the repo's existing release-notes style if it has one — consistency
  beats any template.
- If the repo uses `gh release --generate-notes`, use its output as the
  starting draft and refine: it gets the list right but the highlights wrong.
- Never invent changes that aren't in the commit range. When the range is
  ambiguous, ask which refs to compare instead of guessing.
