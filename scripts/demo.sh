#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_REPO="${1:-$ROOT}"
OUT_DIR="$ROOT/.repo-security-scan/out-demo"

mkdir -p "$OUT_DIR"

set +e
bash "$ROOT/scripts/repo-security-scan/scan.sh" --repo "$TARGET_REPO" --out "$OUT_DIR"
code=$?
set -e

summary="$OUT_DIR/summary.json"
report="$OUT_DIR/report.md"

if [[ ! -f "$summary" ]]; then
  echo "demo failed: summary.json not produced" >&2
  exit 1
fi

# Print a short summary for humans
if command -v jq >/dev/null 2>&1; then
  repo=$(jq -r '.repo.path' "$summary")
  secrets=$(jq -r '.tools.gitleaks.findings' "$summary")
  vulns=$(jq -r '.tools.osvScanner.vulnerabilities' "$summary")
  echo "Repo Security Scan demo"
  echo "- repo: $repo"
  echo "- gitleaks findings: $secrets"
  echo "- osv vulnerabilities: $vulns"
  echo "- report: $report"
else
  echo "Wrote report: $report"
fi

# Propagate scan exit code (0=clean, 1=findings, 2=error)
exit $code
