# repo-security-scan

Scans a target repository for high-signal security issues and produces a report.

## What it does (MVP)
- **Secrets scanning** with **gitleaks** (local scan; secrets redacted in logs)
- **Dependency vulnerability scanning** with **osv-scanner** (matches dependencies against OSV)

Outputs:
- `report.md` — human-readable summary
- `summary.json` — machine-readable summary
- raw tool outputs (`gitleaks.json`, `osv.json`) + logs

## Why this stack (signal/noise)
- **gitleaks**: strong defaults, fast, easy to suppress false positives via `.gitleaks.toml` / `.gitleaksignore`.
- **osv-scanner**: accurate dependency vulnerability matching via OSV (broad ecosystem support, generally lower noise than per-ecosystem “audit” commands).

(Other scanners like Semgrep/SAST and language-specific auditors can be added later behind an explicit `--deep` mode to avoid noisy CI failures.)

## Safety
- Read-only scan of files.
- **Does not upload source code.**
- **gitleaks output is redacted** (`--redact`) and the report avoids printing secrets.
- **osv-scanner uses network access** by default to query OSV (and may consult deps.dev for package metadata). It sends **dependency metadata**, not source code.

## Usage
### Local
From this repo:

```bash
# Scan this repo and write outputs under .repo-security-scan/out
bash scripts/repo-security-scan/scan.sh --repo .

# Scan another repo
bash scripts/repo-security-scan/scan.sh --repo /path/to/target --out /tmp/repo-security-scan-out

# View the report
cat .repo-security-scan/out/report.md
```

### Demo
```bash
bash scripts/demo.sh            # scans this repo
bash scripts/demo.sh /path/repo # scans a target repo
```

## Outputs
In the output directory (default: `<skill-suite>/.repo-security-scan/out`):
- `report.md`
- `summary.json`
- `gitleaks.json`, `gitleaks.log`
- `osv.json`, `osv.log`

Exit codes:
- `0` no findings
- `1` findings detected
- `2` scanner error (missing tools, execution failures)

## Configuration / allowlists
Prefer **repo-local** configuration when scanning a specific project:
- gitleaks:
  - `<repo>/.gitleaks.toml`
  - `<repo>/.gitleaksignore`
- osv-scanner:
  - `<repo>/osv-scanner.toml` (applies only to that directory)

This skill-suite also includes conservative defaults under:
- `.repo-security-scan/gitleaks.toml`
- `.repo-security-scan/.gitleaksignore`
- `.repo-security-scan/osv-scanner.toml`

To force a specific osv-scanner config file:
```bash
bash scripts/repo-security-scan/scan.sh --repo /path/repo --osv-config /path/to/osv-scanner.toml
```

## Install prerequisites
- macOS:
  - `brew install gitleaks osv-scanner jq`
- Ubuntu:
  - `sudo apt-get update && sudo apt-get install -y jq`
  - Install gitleaks + osv-scanner from releases, or compile via `go install`.
