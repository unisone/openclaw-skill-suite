#!/usr/bin/env bash
set -euo pipefail

# Minimal smoke test: scan this repo and verify expected output files exist and are valid JSON/Markdown.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/.repo-security-scan/out-test"

rm -rf "$OUT"
mkdir -p "$OUT"

# Expect tools to be installed in CI.
command -v gitleaks >/dev/null 2>&1
command -v osv-scanner >/dev/null 2>&1
command -v jq >/dev/null 2>&1

set +e
bash "$ROOT/scripts/repo-security-scan/scan.sh" --repo "$ROOT" --out "$OUT"
code=$?
set -e

# Scan might return 0 (clean) or 1 (findings) in future; for test we mainly assert it produced outputs.
if [[ $code -ne 0 && $code -ne 1 ]]; then
  echo "Unexpected exit code from scan: $code" >&2
  exit 1
fi

[[ -f "$OUT/summary.json" ]]
[[ -f "$OUT/report.md" ]]
[[ -f "$OUT/gitleaks.json" ]]
[[ -f "$OUT/osv.json" ]]

jq -e '.tools.gitleaks.report == "gitleaks.json"' "$OUT/summary.json" >/dev/null
jq -e '.tools.osvScanner.report == "osv.json"' "$OUT/summary.json" >/dev/null

# report should have a title
grep -q "^# Repo Security Scan Report" "$OUT/report.md"

echo "repo-security-scan smoke test: OK (exit=$code)"
