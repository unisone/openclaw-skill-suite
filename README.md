# Skill Suite Repo — README Skeleton (Draft)

> Repo purpose: a **curated, maintained set of skills** designed to work exceptionally well in OpenClaw/Moltbot (and ideally in other Agent Skills-compatible tools).

## Title
**OpenClaw Skill Suite** (draft name)

## Why this exists
- High-signal skills with consistent quality, docs, and demos.
- Opinionated defaults and “stacks” for real workflows.
- Automated tests/evals to prevent regressions.

## What’s inside
- `skills/<skill-name>/SKILL.md` — skill definition
- `skills/<skill-name>/resources/` — references, templates
- `skills/<skill-name>/scripts/` — optional helper scripts
- `skills/<skill-name>/demo/` — runnable demo + fixtures
- `eval/` — eval harness and tasks

## Install
### Option A: Git clone
```bash
git clone <repo-url>
# copy/link skills into ~/.claude/skills or OpenClaw skills directory
```

### Option B: Marketplace install (if supported)
```bash
# e.g. Claude Code style
/plugin marketplace add <repo>
/plugin install <skill>@<repo>
```

## Skills included
- `...`

## Skill stacks
- `dev-release-stack`
- `incident-response-stack`
- `docs-writer-stack`

## Contributing
- Add a new skill via template
- Include a demo
- Ensure CI passes

## Safety
- Skills must not exfiltrate secrets.
- Scripts should be transparent and minimal.

## License
- Prefer OSS licenses for suite skills.
- If any “source-available” components exist, isolate and label clearly.
