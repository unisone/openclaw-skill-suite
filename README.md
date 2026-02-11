# OpenClaw Skill Suite

A curated collection of agent skills for [OpenClaw](https://github.com/openclaw/openclaw) — production-quality, documented, and tested.

## Skills

| Skill | Description | Install |
|-------|-------------|---------|
| [**design-inspo**](skills/design-inspo/) | Design inspiration router — 12+ curated galleries for web design, landing pages, SaaS, navbars, CTAs, animations, mobile apps, branding, icons, and design systems | `npm i openclaw-skill-design-inspo` |
| [**remotion-product-demos**](skills/remotion-product-demos/) | Apple-keynote-quality product demo videos with Remotion — glass phone mockups, 3D spheres, typing animations, card UIs, smooth transitions | Skill file |
| [**repo-security-scan**](skills/repo-security-scan/) | Lightweight security scanning — secrets detection (gitleaks) + dependency vulnerability scanning (osv-scanner) with CI integration | Skill file |

## Quick Start

### Install a skill via npm

```bash
npm install openclaw-skill-design-inspo
```

OpenClaw auto-discovers installed skills. Once installed, just ask your agent for design inspiration and it routes to the right gallery.

### Install from source

```bash
git clone https://github.com/unisone/openclaw-skill-suite.git
# Copy or symlink the skill folder into your OpenClaw skills directory
cp -r skills/design-inspo ~/.openclaw/skills/
```

## Repo Structure

```
skills/
  <skill-name>/
    SKILL.md              # Skill definition (agent reads this)
    package.json          # npm metadata (for publishable skills)
    references/           # Reference docs, catalogs, style guides
    scripts/              # Helper scripts
scripts/
  repo-security-scan/     # Security scan tooling
  demo.sh                 # Demo runner
.github/
  workflows/              # CI: security scan, layout validation, dependabot
docs/                     # Additional documentation
SKILL_TEMPLATE.md         # Template for creating new skills
```

## Creating a New Skill

See [`SKILL_TEMPLATE.md`](SKILL_TEMPLATE.md) for the recommended structure, frontmatter schema, and packaging guidelines.

Every skill should include:
- A clear `SKILL.md` with structured frontmatter
- Safety/permissions section
- References or examples where applicable

## Security

- Automated security scanning runs on every push and PR (gitleaks + osv-scanner)
- Weekly scheduled scans catch new CVEs in dependencies
- Dependabot keeps GitHub Actions up to date
- Skills are designed to be read-only and non-destructive by default

## License

[Apache 2.0](LICENSE)
