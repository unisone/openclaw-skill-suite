# Skill Suite — Packaging + Demo Template (Draft)

## Goals
- Make every skill **self-contained**, **auditable**, and **easy to try**.
- Keep docs consistent so agents (and humans) can trust skills quickly.
- Support multi-ecosystem compatibility where feasible.

---

## Recommended folder structure

```
skills/
  <skill-name>/
    SKILL.md
    README.md               # human-oriented quick read (optional but recommended)
    resources/
      ...                   # templates, examples, reference docs
    scripts/
      ...                   # optional helpers used by the skill
    demo/
      README.md
      fixtures/
      run.sh                # or run.ts / run.py
      expected/
    tests/
      ...                   # optional unit tests for scripts
```

If you want cross-agent support:
```
agents/
  AGENTS.md                 # Codex-style fallback instructions
  gemini-extension.json      # Gemini CLI extension metadata (if applicable)
```

---

## SKILL.md template

```md
---
name: <skill-name>
description: <one sentence: the decision-making label the agent sees>
license: MIT
compatibility:
  - agent-skills
  - openclaw
metadata:
  category: devtools
  maturity: experimental  # experimental|stable
  requires_network: "no"
  requires_shell: "yes"
---

## What I do
- ...

## When to use me
Use me when...

## When NOT to use me
Don’t use me when...

## Inputs I expect
- Repository path
- Target branch

## Outputs I produce
- Copy-pasteable commands
- Files (list paths)

## Safety & permissions
- I may run: `git`, `gh`, `node`.
- I will never ask for secrets in plain text.
- If I need network access, I will explain why.

## Workflow
1) ...
2) ...

## Examples
### Example: ...
User: ...
Assistant: ...
```

Notes:
- Keep `description` crisp; it’s the primary discovery label.
- Keep scripts minimal and prefer standard tools.

---

## Demo package template

`demo/README.md` should include:
- Purpose (“what you’ll see when it works”)
- Requirements (docker? node? python?)
- One command to run
- Expected output artifacts

Example:

```md
# Demo

## Run
./run.sh

## Expected
- Creates `out/release-notes.md`
- Prints a `gh release create ...` command
```

`demo/run.sh` guidelines:
- Must be deterministic.
- Must run in CI.
- Must not require secrets.
- Must not perform destructive actions.

---

## Minimal eval hook (optional)

If you want to measure effectiveness:

```
eval/
  cases/
    basic.yaml
  run.ts
```

`eval/cases/basic.yaml` (example idea):
```yaml
id: release-notes-basic
prompt: "Generate release notes for these commits: ..."
expected_contains:
  - "Breaking changes"
  - "Upgrade"
```

---

## CI suggestions for the suite repo
- markdown lint
- schema validate SKILL.md frontmatter
- run all demos in sandbox
- (optional) run eval harness and publish report as artifact

---

## “Definition of done” for a new skill
- [ ] `SKILL.md` with frontmatter
- [ ] Safety/permissions section
- [ ] `demo/` with one-command run and expected output
- [ ] No secrets required
- [ ] CI passes
