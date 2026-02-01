# Repo Security Scan

This repo includes a lightweight security scan that runs in GitHub Actions.

## What it does
- **Secrets scan** via `gitleaks`
- **Dependency vulnerability scan** via `osv-scanner`

Outputs are written to `.repo-security-scan/out/` and uploaded as a workflow artifact.

## Local usage
```bash
# install prereqs
brew install jq
brew install gitleaks
brew install osv-scanner

bash scripts/repo-security-scan/scan.sh --repo . --out .repo-security-scan/out
```

## Tuning
- Add repo-specific ignores in `.gitleaksignore`
- (Optional) add a custom `.gitleaks.toml`

Keep allowlists narrow.
