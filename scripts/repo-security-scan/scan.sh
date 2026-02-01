#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
repo-security-scan

Scans a target repo for:
  1) secrets (gitleaks)
  2) vulnerable dependencies (osv-scanner)

Outputs (in --out dir):
  - report.md     (human-readable)
  - summary.json  (machine-readable)
  - gitleaks.json (raw)
  - osv.json      (raw)
  - *.log         (tool logs, secrets redacted)

Usage:
  scripts/repo-security-scan/scan.sh --repo /path/to/repo [--out /path/to/out]

Options:
  --repo PATH          Repo/directory to scan (default: .)
  --out PATH           Output directory (default: <skill-suite>/.repo-security-scan/out)
  --config-dir PATH    Directory containing optional allowlist configs
                       (default: <skill-suite>/.repo-security-scan)
  --osv-config PATH    Explicit osv-scanner config file (overrides any auto-detection)
  --help               Show help

Exit codes:
  0  No findings
  1  Findings detected (secrets and/or vulnerable dependencies)
  2  Scanner error (missing tools, invalid args, tool execution failure)
EOF
}

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    return 1
  fi
}

iso_utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

SUITE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

REPO="."
OUT_DIR="$SUITE_ROOT/.repo-security-scan/out"
CONFIG_DIR="$SUITE_ROOT/.repo-security-scan"
OSV_CONFIG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"; shift 2 ;;
    --out)
      OUT_DIR="$2"; shift 2 ;;
    --config-dir)
      CONFIG_DIR="$2"; shift 2 ;;
    --osv-config)
      OSV_CONFIG="$2"; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

REPO_ABS="$(cd "$REPO" 2>/dev/null && pwd || true)"
if [[ -z "$REPO_ABS" ]]; then
  echo "Repo path does not exist: $REPO" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"

STARTED_AT="$(iso_utc_now)"

# Best-effort git metadata (don’t fail if not a git repo)
GIT_COMMIT=""
GIT_REMOTE=""
if command -v git >/dev/null 2>&1 && git -C "$REPO_ABS" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_COMMIT="$(git -C "$REPO_ABS" rev-parse --short HEAD 2>/dev/null || true)"
  GIT_REMOTE="$(git -C "$REPO_ABS" remote get-url origin 2>/dev/null || true)"
fi

SCAN_ERROR=0
FINDINGS=0

if ! require_cmd jq; then
  echo "Missing required tool: jq" >&2
  echo "Install: brew install jq   (macOS) | sudo apt-get install -y jq   (ubuntu)" >&2
  exit 2
fi

# -----------------
# gitleaks
# -----------------
GITLEAKS_OK=true
GITLEAKS_EXIT=0
GITLEAKS_FINDINGS=0
GITLEAKS_VERSION=""
GITLEAKS_REPORT="$OUT_DIR/gitleaks.json"
GITLEAKS_LOG="$OUT_DIR/gitleaks.log"

if require_cmd gitleaks; then
  GITLEAKS_VERSION="$(gitleaks version 2>/dev/null | head -n 1 || true)"

  # Prefer repo-local config if present; otherwise fall back to suite config.
  GITLEAKS_CONFIG=""
  if [[ -f "$REPO_ABS/.gitleaks.toml" ]]; then
    GITLEAKS_CONFIG="$REPO_ABS/.gitleaks.toml"
  elif [[ -f "$CONFIG_DIR/gitleaks.toml" ]]; then
    GITLEAKS_CONFIG="$CONFIG_DIR/gitleaks.toml"
  fi

  GITLEAKS_IGNORE_ARG=()
  if [[ -f "$REPO_ABS/.gitleaksignore" ]]; then
    GITLEAKS_IGNORE_ARG=(--gitleaks-ignore-path "$REPO_ABS")
  elif [[ -f "$CONFIG_DIR/.gitleaksignore" ]]; then
    GITLEAKS_IGNORE_ARG=(--gitleaks-ignore-path "$CONFIG_DIR")
  fi

  GITLEAKS_ARGS=(
    detect
    --source "$REPO_ABS"
    --no-git
    --redact
    --no-banner
    --report-format json
    --report-path "$GITLEAKS_REPORT"
    --exit-code 1
  )
  if [[ -n "$GITLEAKS_CONFIG" ]]; then
    GITLEAKS_ARGS+=(--config "$GITLEAKS_CONFIG")
  fi
  GITLEAKS_ARGS+=("${GITLEAKS_IGNORE_ARG[@]}")

  set +e
  gitleaks "${GITLEAKS_ARGS[@]}" >"$GITLEAKS_LOG" 2>&1
  GITLEAKS_EXIT=$?
  set -e

  if [[ $GITLEAKS_EXIT -ne 0 && $GITLEAKS_EXIT -ne 1 ]]; then
    # 1 means leaks found, which is not a scanner error.
    GITLEAKS_OK=false
    SCAN_ERROR=1
  fi

  if [[ -f "$GITLEAKS_REPORT" ]]; then
    GITLEAKS_FINDINGS="$(jq 'length' "$GITLEAKS_REPORT" 2>/dev/null || echo 0)"
  fi
else
  GITLEAKS_OK=false
  SCAN_ERROR=1
  echo "gitleaks not installed" >"$GITLEAKS_LOG"
  echo "[]" >"$GITLEAKS_REPORT"
fi

if [[ "$GITLEAKS_FINDINGS" -gt 0 ]]; then
  FINDINGS=1
fi

# -----------------
# osv-scanner
# -----------------
OSV_OK=true
OSV_EXIT=0
OSV_PACKAGES=0
OSV_VULNS=0
OSV_VERSION=""
OSV_REPORT="$OUT_DIR/osv.json"
OSV_LOG="$OUT_DIR/osv.log"

if require_cmd osv-scanner; then
  OSV_VERSION="$(osv-scanner --version 2>/dev/null | head -n 1 || true)"

  OSV_ARGS=(scan source -r "$REPO_ABS" --format json --output "$OSV_REPORT" --verbosity error --allow-no-lockfiles --data-source native)
  if [[ -n "$OSV_CONFIG" ]]; then
    OSV_ARGS+=(--config "$OSV_CONFIG")
  fi

  set +e
  osv-scanner "${OSV_ARGS[@]}" >"$OSV_LOG" 2>&1
  OSV_EXIT=$?
  set -e

  if [[ $OSV_EXIT -ne 0 ]]; then
    # osv-scanner uses non-zero for execution errors; findings should still be reflected in JSON output.
    OSV_OK=false
    SCAN_ERROR=1
  fi

  if [[ -f "$OSV_REPORT" ]]; then
    OSV_PACKAGES="$(jq '[.results[]?.packages[]?] | length' "$OSV_REPORT" 2>/dev/null || echo 0)"
    OSV_VULNS="$(jq '[.results[]?.packages[]?.vulnerabilities[]?] | length' "$OSV_REPORT" 2>/dev/null || echo 0)"
  fi
else
  OSV_OK=false
  SCAN_ERROR=1
  echo "osv-scanner not installed" >"$OSV_LOG"
  echo '{"results": null}' >"$OSV_REPORT"
fi

if [[ "$OSV_VULNS" -gt 0 ]]; then
  FINDINGS=1
fi

FINISHED_AT="$(iso_utc_now)"

SUMMARY_JSON="$OUT_DIR/summary.json"
REPORT_MD="$OUT_DIR/report.md"

jq -n \
  --arg startedAt "$STARTED_AT" \
  --arg finishedAt "$FINISHED_AT" \
  --arg repoPath "$REPO_ABS" \
  --arg gitCommit "$GIT_COMMIT" \
  --arg gitRemote "$GIT_REMOTE" \
  --arg gitleaksVersion "$GITLEAKS_VERSION" \
  --argjson gitleaksOk "$( [[ "$GITLEAKS_OK" == true ]] && echo true || echo false )" \
  --argjson gitleaksExit "$GITLEAKS_EXIT" \
  --argjson gitleaksFindings "$GITLEAKS_FINDINGS" \
  --arg osvVersion "$OSV_VERSION" \
  --argjson osvOk "$( [[ "$OSV_OK" == true ]] && echo true || echo false )" \
  --argjson osvExit "$OSV_EXIT" \
  --argjson osvPackages "$OSV_PACKAGES" \
  --argjson osvVulns "$OSV_VULNS" \
  --argjson findings "$( [[ $FINDINGS -eq 1 ]] && echo true || echo false )" \
  --argjson scanError "$( [[ $SCAN_ERROR -eq 1 ]] && echo true || echo false )" \
  '{
    startedAt: $startedAt,
    finishedAt: $finishedAt,
    repo: {
      path: $repoPath,
      git: {
        commit: ($gitCommit | select(length > 0) // null),
        remote: ($gitRemote | select(length > 0) // null)
      }
    },
    tools: {
      gitleaks: {
        ok: $gitleaksOk,
        exitCode: $gitleaksExit,
        version: ($gitleaksVersion | select(length > 0) // null),
        findings: $gitleaksFindings,
        report: "gitleaks.json",
        log: "gitleaks.log"
      },
      osvScanner: {
        ok: $osvOk,
        exitCode: $osvExit,
        version: ($osvVersion | select(length > 0) // null),
        packages: $osvPackages,
        vulnerabilities: $osvVulns,
        report: "osv.json",
        log: "osv.log"
      }
    },
    status: {
      findings: $findings,
      scanError: $scanError
    }
  }' >"$SUMMARY_JSON"

{
  echo "# Repo Security Scan Report"
  echo
  echo "- Repo: $REPO_ABS"
  if [[ -n "$GIT_COMMIT" ]]; then
    echo "- Git commit: $GIT_COMMIT"
  fi
  if [[ -n "$GIT_REMOTE" ]]; then
    echo "- Git remote: $GIT_REMOTE"
  fi
  echo "- Started (UTC): $STARTED_AT"
  echo "- Finished (UTC): $FINISHED_AT"
  echo
  echo "## Summary"
  echo
  echo "- Secrets (gitleaks): $GITLEAKS_FINDINGS finding(s)"
  echo "- Vulnerable dependencies (osv-scanner): $OSV_VULNS vulnerability record(s) across $OSV_PACKAGES package(s)"
  echo
  if [[ $SCAN_ERROR -eq 1 ]]; then
    echo "**Scanner errors occurred.** See tool logs in this output directory."
    echo
  fi
  if [[ $FINDINGS -eq 1 ]]; then
    echo "**Findings detected.** Raw outputs: gitleaks.json, osv.json"
  else
    echo "No findings detected by the enabled scanners."
  fi
  echo
  echo "## Details"
  echo
  echo "### gitleaks"
  echo
  echo "- Raw: gitleaks.json"
  echo "- Log: gitleaks.log (secrets redacted)"
  echo
  if [[ "$GITLEAKS_FINDINGS" -gt 0 ]]; then
    echo "Top findings (redacted):"
    echo
    jq -r '.[] | "- \(.File // "(unknown file)"):\(.StartLine // .Line // 0) — \(.RuleID // "(unknown rule)")"' "$GITLEAKS_REPORT" \
      | head -n 50
    echo
  else
    echo "No secrets detected by gitleaks."
    echo
  fi

  echo "### osv-scanner"
  echo
  echo "- Raw: osv.json"
  echo "- Log: osv.log"
  echo
  if [[ "$OSV_VULNS" -gt 0 ]]; then
    echo "Packages with vulnerabilities (best-effort summary):"
    echo
    jq -r '
      .results[]?.packages[]? as $p
      | select(($p.vulnerabilities // []) | length > 0)
      | $p.vulnerabilities[]?
      | "- \($p.name // "(unknown)")@\($p.version // "?") — \(.id // "(unknown id)")"
    ' "$OSV_REPORT" | head -n 80
    echo
  else
    echo "No vulnerable dependencies reported by osv-scanner."
    echo
  fi

  echo "## Notes"
  echo
  echo "- This scan runs locally. It does not upload your source code."
  echo "- osv-scanner queries OSV (and optionally deps.dev) over the network using dependency metadata." 
  echo "- If you need to suppress false positives, add repo-local allowlists (.gitleaks.toml, .gitleaksignore, osv-scanner.toml) or pass custom configs." 
} >"$REPORT_MD"

if [[ $SCAN_ERROR -eq 1 ]]; then
  exit 2
fi
if [[ $FINDINGS -eq 1 ]]; then
  exit 1
fi
exit 0
