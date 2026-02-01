#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
repo-security-scan

Scans a target repo for:
  1) secrets (gitleaks)
  2) vulnerable dependencies (osv-scanner)

Optional (only with --deep):
  3) SAST (semgrep)
  4) ecosystem-specific audits (best-effort): npm / pip / cargo / go

Outputs (in --out dir):
  - report.md     (human-readable)
  - summary.json  (machine-readable)
  - gitleaks.json (raw)
  - osv.json      (raw)
  - *.log         (tool logs, secrets redacted where applicable)

In --deep mode, additional raw outputs may be produced:
  - semgrep.json
  - npm-audit__*.json
  - pip-audit__*.json
  - cargo-audit__*.json
  - govulncheck__*.jsonl

Usage:
  scripts/repo-security-scan/scan.sh --repo /path/to/repo [--out /path/to/out] [--deep]

Options:
  --repo PATH          Repo/directory to scan (default: .)
  --out PATH           Output directory (default: <skill-suite>/.repo-security-scan/out)
  --config-dir PATH    Directory containing optional allowlist configs
                       (default: <skill-suite>/.repo-security-scan)
  --osv-config PATH    Explicit osv-scanner config file (overrides any auto-detection)
  --deep               Enable additional (noisier/slower) scans: semgrep + ecosystem audits
  --help               Show help

Exit codes:
  0  No findings
  1  Findings detected (secrets and/or vulnerable dependencies)
  2  Scanner error (missing tools, invalid args, tool execution failure)
EOF
}

require_cmd() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1
}

iso_utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Convert an absolute path under $2 into a stable filename-safe suffix.
# - /repo/path               -> root
# - /repo/path/sub/dir       -> sub__dir
sanitize_rel_dir() {
  local dir_abs="$1"
  local repo_abs="$2"
  local rel

  if [[ "$dir_abs" == "$repo_abs" ]]; then
    rel="root"
  else
    rel="${dir_abs#"$repo_abs"/}"
    [[ -z "$rel" ]] && rel="root"
  fi

  rel="${rel//\//__}"
  rel="${rel// /_}"
  rel="${rel//\t/_}"
  rel="${rel//\n/_}"

  echo "$rel"
}

SUITE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

REPO="."
OUT_DIR="$SUITE_ROOT/.repo-security-scan/out"
CONFIG_DIR="$SUITE_ROOT/.repo-security-scan"
OSV_CONFIG=""
DEEP=false

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
    --deep)
      DEEP=true; shift 1 ;;
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
  elif [[ -f "$CONFIG_DIR/.repo-security-scan/gitleaks.toml" ]]; then
    GITLEAKS_CONFIG="$CONFIG_DIR/.repo-security-scan/gitleaks.toml"
  fi

  GITLEAKS_IGNORE_ARG=()
  if [[ -f "$REPO_ABS/.gitleaksignore" ]]; then
    GITLEAKS_IGNORE_ARG=(--gitleaks-ignore-path "$REPO_ABS")
  elif [[ -f "$CONFIG_DIR/.gitleaksignore" ]]; then
    GITLEAKS_IGNORE_ARG=(--gitleaks-ignore-path "$CONFIG_DIR")
  elif [[ -f "$CONFIG_DIR/.repo-security-scan/.gitleaksignore" ]]; then
    GITLEAKS_IGNORE_ARG=(--gitleaks-ignore-path "$CONFIG_DIR/.repo-security-scan")
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

  # Prefer explicit override; otherwise use repo-local or suite config if present.
  OSV_CONFIG_TO_USE="$OSV_CONFIG"
  if [[ -z "$OSV_CONFIG_TO_USE" ]]; then
    if [[ -f "$REPO_ABS/osv-scanner.toml" ]]; then
      OSV_CONFIG_TO_USE="$REPO_ABS/osv-scanner.toml"
    elif [[ -f "$CONFIG_DIR/osv-scanner.toml" ]]; then
      OSV_CONFIG_TO_USE="$CONFIG_DIR/osv-scanner.toml"
    elif [[ -f "$CONFIG_DIR/.repo-security-scan/osv-scanner.toml" ]]; then
      OSV_CONFIG_TO_USE="$CONFIG_DIR/.repo-security-scan/osv-scanner.toml"
    fi
  fi

  # osv-scanner v1.x syntax (compatible with v1.9.0 pinned in CI)
  OSV_ARGS=(-r "$REPO_ABS" --format json)
  if [[ -n "$OSV_CONFIG_TO_USE" ]]; then
    OSV_ARGS+=(--config "$OSV_CONFIG_TO_USE")
  fi

  # JSON output is written to stdout; other output goes to stderr.
  set +e
  osv-scanner "${OSV_ARGS[@]}" >"$OSV_REPORT" 2>"$OSV_LOG"
  OSV_EXIT=$?
  set -e

  # Exit codes (per osv-scanner v1 docs):
  # 0 = packages found, no vulns
  # 1 = packages found, vulns
  # 128 = no packages found
  # others = execution error
  if [[ $OSV_EXIT -ne 0 && $OSV_EXIT -ne 1 && $OSV_EXIT -ne 128 ]]; then
    OSV_OK=false
    SCAN_ERROR=1
  fi

  # Ensure report is valid JSON even when no packages were found.
  if [[ ! -s "$OSV_REPORT" ]] || ! jq -e '.' "$OSV_REPORT" >/dev/null 2>&1; then
    echo '{"results": null}' >"$OSV_REPORT"
  fi

  if [[ -f "$OSV_REPORT" ]]; then
    OSV_PACKAGES="$(jq '[.results[]?.packages[]?] | length' "$OSV_REPORT" 2>/dev/null || echo 0)"
    OSV_VULNS="$(jq '[.results[]?.packages[]?.vulnerabilities[]?] | length' "$OSV_REPORT" 2>/dev/null || echo 0)"
  fi

  # If osv-scanner signals vulnerabilities via exit code, make sure we record it.
  if [[ $OSV_EXIT -eq 1 ]]; then
    FINDINGS=1
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

# -----------------
# Deep mode (semgrep + ecosystem audits)
# -----------------
SEMGREP_ENABLED=false
SEMGREP_OK=true
SEMGREP_EXIT=0
SEMGREP_FINDINGS=0
SEMGREP_VERSION=""
SEMGREP_REPORT="$OUT_DIR/semgrep.json"
SEMGREP_LOG="$OUT_DIR/semgrep.log"

NPM_ENABLED=false
NPM_OK=true
NPM_EXIT=0
NPM_VERSION=""
NPM_VULNS_TOTAL=0
NPM_RUNS_JSON='[]'

PIP_ENABLED=false
PIP_OK=true
PIP_EXIT=0
PIP_VERSION=""
PIP_VULNS_TOTAL=0
PIP_RUNS_JSON='[]'

CARGO_ENABLED=false
CARGO_OK=true
CARGO_EXIT=0
CARGO_VERSION=""
CARGO_VULNS_TOTAL=0
CARGO_RUNS_JSON='[]'

GO_ENABLED=false
GO_OK=true
GO_EXIT=0
GO_VERSION=""
GO_FINDINGS_TOTAL=0
GO_RUNS_JSON='[]'

if [[ "$DEEP" == true ]]; then
  # ----- semgrep
  SEMGREP_ENABLED=true
  if require_cmd semgrep; then
    SEMGREP_VERSION="$(semgrep --version 2>/dev/null | head -n 1 || true)"

    set +e
    (
      cd "$REPO_ABS"
      semgrep --config auto --json --output "$SEMGREP_REPORT" --quiet --metrics off
    ) >"$SEMGREP_LOG" 2>&1
    SEMGREP_EXIT=$?
    set -e

    if [[ $SEMGREP_EXIT -ne 0 && $SEMGREP_EXIT -ne 1 ]]; then
      SEMGREP_OK=false
      SCAN_ERROR=1
    fi

    if [[ -f "$SEMGREP_REPORT" ]]; then
      SEMGREP_FINDINGS="$(jq '.results | length' "$SEMGREP_REPORT" 2>/dev/null || echo 0)"
    else
      SEMGREP_OK=false
      SCAN_ERROR=1
      SEMGREP_FINDINGS=0
    fi
  else
    SEMGREP_OK=false
    SCAN_ERROR=1
    SEMGREP_EXIT=2
    echo "semgrep not installed (required for --deep)" >"$SEMGREP_LOG"
    echo '{"results": []}' >"$SEMGREP_REPORT"
  fi

  if [[ "$SEMGREP_FINDINGS" -gt 0 ]]; then
    FINDINGS=1
  fi

  # ----- npm audit (package-lock.json / npm-shrinkwrap.json)
  tmp_npm_dirs="$(mktemp -t repo-security-scan-npm-dirs)"
  find "$REPO_ABS" -type f \( -name package-lock.json -o -name npm-shrinkwrap.json \) -print0 \
    | while IFS= read -r -d '' f; do dirname "$f"; done \
    >"$tmp_npm_dirs" || true

  if [[ -s "$tmp_npm_dirs" ]]; then
    NPM_ENABLED=true
    if require_cmd npm; then
      NPM_VERSION="$(npm --version 2>/dev/null | head -n 1 || true)"

      while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        rel="$(sanitize_rel_dir "$dir" "$REPO_ABS")"
        report="$OUT_DIR/npm-audit__${rel}.json"
        log="$OUT_DIR/npm-audit__${rel}.log"

        set +e
        (
          cd "$dir"
          npm audit --json
        ) >"$report" 2>"$log"
        code=$?
        set -e

        # 0 = clean, 1 = vulns found, >1 = error
        if [[ $code -ne 0 && $code -ne 1 ]]; then
          NPM_OK=false
          SCAN_ERROR=1
        fi
        if [[ $code -gt $NPM_EXIT ]]; then
          NPM_EXIT=$code
        fi

        run_total="$(jq -r '(.metadata.vulnerabilities.total // null) // ((.advisories // {}) | length) // 0' "$report" 2>/dev/null || echo 0)"
        if [[ "$run_total" =~ ^[0-9]+$ ]]; then
          NPM_VULNS_TOTAL=$((NPM_VULNS_TOTAL + run_total))
        fi

        NPM_RUNS_JSON="$(jq -nc \
          --arg dir "$dir" \
          --arg report "$(basename "$report")" \
          --arg log "$(basename "$log")" \
          --argjson exitCode "$code" \
          --argjson vulnerabilities "$run_total" \
          --argjson prev "$NPM_RUNS_JSON" \
          '$prev + [{dir: $dir, exitCode: $exitCode, vulnerabilities: $vulnerabilities, report: $report, log: $log}]' \
        )"
      done < <(sort -u "$tmp_npm_dirs")

      if [[ "$NPM_VULNS_TOTAL" -gt 0 ]]; then
        FINDINGS=1
      fi
    else
      NPM_OK=false
      SCAN_ERROR=1
      NPM_EXIT=2
      echo "npm not installed (required for npm audit in --deep mode)" >"$OUT_DIR/npm-audit.log"
    fi
  fi
  rm -f "$tmp_npm_dirs" || true

  # ----- pip-audit (requirements*.txt)
  tmp_pip_reqs="$(mktemp -t repo-security-scan-pip-reqs)"
  find "$REPO_ABS" -type f \( -name 'requirements.txt' -o -name 'requirements-*.txt' \) -print0 \
    | while IFS= read -r -d '' f; do echo "$f"; done \
    >"$tmp_pip_reqs" || true

  if [[ -s "$tmp_pip_reqs" ]]; then
    PIP_ENABLED=true
    if require_cmd pip-audit; then
      PIP_VERSION="$(pip-audit --version 2>/dev/null | head -n 1 || true)"

      while IFS= read -r req; do
        [[ -z "$req" ]] && continue
        dir="$(dirname "$req")"
        rel="$(sanitize_rel_dir "$dir" "$REPO_ABS")"
        base="$(basename "$req" | sed 's/[^A-Za-z0-9._-]/_/g')"
        report="$OUT_DIR/pip-audit__${rel}__${base}.json"
        log="$OUT_DIR/pip-audit__${rel}__${base}.log"

        set +e
        pip-audit -r "$req" -f json >"$report" 2>"$log"
        code=$?
        set -e

        # 0 = clean, 1 = vulns found, >1 = error
        if [[ $code -ne 0 && $code -ne 1 ]]; then
          PIP_OK=false
          SCAN_ERROR=1
        fi
        if [[ $code -gt $PIP_EXIT ]]; then
          PIP_EXIT=$code
        fi

        run_total="$(jq -r '[.[].vulns[]?] | length' "$report" 2>/dev/null || echo 0)"
        if [[ "$run_total" =~ ^[0-9]+$ ]]; then
          PIP_VULNS_TOTAL=$((PIP_VULNS_TOTAL + run_total))
        fi

        PIP_RUNS_JSON="$(jq -nc \
          --arg requirement "$req" \
          --arg report "$(basename "$report")" \
          --arg log "$(basename "$log")" \
          --argjson exitCode "$code" \
          --argjson vulnerabilities "$run_total" \
          --argjson prev "$PIP_RUNS_JSON" \
          '$prev + [{requirement: $requirement, exitCode: $exitCode, vulnerabilities: $vulnerabilities, report: $report, log: $log}]' \
        )"
      done < <(sort -u "$tmp_pip_reqs")

      if [[ "$PIP_VULNS_TOTAL" -gt 0 ]]; then
        FINDINGS=1
      fi
    else
      PIP_OK=false
      SCAN_ERROR=1
      PIP_EXIT=2
      echo "pip-audit not installed (required when requirements*.txt are present in --deep mode)" >"$OUT_DIR/pip-audit.log"
    fi
  fi
  rm -f "$tmp_pip_reqs" || true

  # ----- cargo audit (Cargo.lock)
  tmp_cargo_dirs="$(mktemp -t repo-security-scan-cargo-dirs)"
  find "$REPO_ABS" -type f -name Cargo.lock -print0 \
    | while IFS= read -r -d '' f; do dirname "$f"; done \
    >"$tmp_cargo_dirs" || true

  if [[ -s "$tmp_cargo_dirs" ]]; then
    CARGO_ENABLED=true
    if require_cmd cargo && cargo audit --version >/dev/null 2>&1; then
      CARGO_VERSION="$(cargo audit --version 2>/dev/null | head -n 1 || true)"

      while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        rel="$(sanitize_rel_dir "$dir" "$REPO_ABS")"
        report="$OUT_DIR/cargo-audit__${rel}.json"
        log="$OUT_DIR/cargo-audit__${rel}.log"

        set +e
        (
          cd "$dir"
          cargo audit --json
        ) >"$report" 2>"$log"
        code=$?
        set -e

        # 0 = clean, 1 = vulns found, >1 = error
        if [[ $code -ne 0 && $code -ne 1 ]]; then
          CARGO_OK=false
          SCAN_ERROR=1
        fi
        if [[ $code -gt $CARGO_EXIT ]]; then
          CARGO_EXIT=$code
        fi

        run_total="$(jq -r '(.vulnerabilities.list // []) | length' "$report" 2>/dev/null || echo 0)"
        if [[ "$run_total" =~ ^[0-9]+$ ]]; then
          CARGO_VULNS_TOTAL=$((CARGO_VULNS_TOTAL + run_total))
        fi

        CARGO_RUNS_JSON="$(jq -nc \
          --arg dir "$dir" \
          --arg report "$(basename "$report")" \
          --arg log "$(basename "$log")" \
          --argjson exitCode "$code" \
          --argjson vulnerabilities "$run_total" \
          --argjson prev "$CARGO_RUNS_JSON" \
          '$prev + [{dir: $dir, exitCode: $exitCode, vulnerabilities: $vulnerabilities, report: $report, log: $log}]' \
        )"
      done < <(sort -u "$tmp_cargo_dirs")

      if [[ "$CARGO_VULNS_TOTAL" -gt 0 ]]; then
        FINDINGS=1
      fi
    else
      CARGO_OK=false
      SCAN_ERROR=1
      CARGO_EXIT=2
      echo "cargo audit not available (install with: cargo install cargo-audit)" >"$OUT_DIR/cargo-audit.log"
    fi
  fi
  rm -f "$tmp_cargo_dirs" || true

  # ----- go govulncheck (go.mod)
  tmp_go_dirs="$(mktemp -t repo-security-scan-go-dirs)"
  find "$REPO_ABS" -type f -name go.mod -print0 \
    | while IFS= read -r -d '' f; do dirname "$f"; done \
    >"$tmp_go_dirs" || true

  if [[ -s "$tmp_go_dirs" ]]; then
    GO_ENABLED=true
    if require_cmd govulncheck; then
      GO_VERSION="$(govulncheck -version 2>/dev/null | head -n 1 || true)"

      while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        rel="$(sanitize_rel_dir "$dir" "$REPO_ABS")"
        report="$OUT_DIR/govulncheck__${rel}.jsonl"
        log="$OUT_DIR/govulncheck__${rel}.log"

        set +e
        (
          cd "$dir"
          govulncheck -json ./...
        ) >"$report" 2>"$log"
        code=$?
        set -e

        if [[ $code -gt $GO_EXIT ]]; then
          GO_EXIT=$code
        fi

        # govulncheck JSON is a stream of JSON objects; slurp into an array.
        run_total="$(jq -s -r '[.[] | select(has("finding"))] | length' "$report" 2>/dev/null || echo 0)"
        if [[ "$run_total" =~ ^[0-9]+$ ]]; then
          GO_FINDINGS_TOTAL=$((GO_FINDINGS_TOTAL + run_total))
        fi

        GO_RUNS_JSON="$(jq -nc \
          --arg dir "$dir" \
          --arg report "$(basename "$report")" \
          --arg log "$(basename "$log")" \
          --argjson exitCode "$code" \
          --argjson findings "$run_total" \
          --argjson prev "$GO_RUNS_JSON" \
          '$prev + [{dir: $dir, exitCode: $exitCode, findings: $findings, report: $report, log: $log}]' \
        )"
      done < <(sort -u "$tmp_go_dirs")

      if [[ "$GO_FINDINGS_TOTAL" -gt 0 ]]; then
        FINDINGS=1
      fi
    else
      GO_OK=false
      SCAN_ERROR=1
      GO_EXIT=2
      echo "govulncheck not installed (install with: go install golang.org/x/vuln/cmd/govulncheck@latest)" >"$OUT_DIR/govulncheck.log"
    fi
  fi
  rm -f "$tmp_go_dirs" || true

  if [[ "$GO_FINDINGS_TOTAL" -gt 0 ]]; then
    FINDINGS=1
  fi
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
  --argjson deepEnabled "$( [[ "$DEEP" == true ]] && echo true || echo false )" \
  --arg gitleaksVersion "$GITLEAKS_VERSION" \
  --argjson gitleaksOk "$( [[ "$GITLEAKS_OK" == true ]] && echo true || echo false )" \
  --argjson gitleaksExit "$GITLEAKS_EXIT" \
  --argjson gitleaksFindings "$GITLEAKS_FINDINGS" \
  --arg osvVersion "$OSV_VERSION" \
  --argjson osvOk "$( [[ "$OSV_OK" == true ]] && echo true || echo false )" \
  --argjson osvExit "$OSV_EXIT" \
  --argjson osvPackages "$OSV_PACKAGES" \
  --argjson osvVulns "$OSV_VULNS" \
  --arg semgrepVersion "$SEMGREP_VERSION" \
  --argjson semgrepEnabled "$( [[ "$SEMGREP_ENABLED" == true ]] && echo true || echo false )" \
  --argjson semgrepOk "$( [[ "$SEMGREP_OK" == true ]] && echo true || echo false )" \
  --argjson semgrepExit "$SEMGREP_EXIT" \
  --argjson semgrepFindings "$SEMGREP_FINDINGS" \
  --arg npmVersion "$NPM_VERSION" \
  --argjson npmEnabled "$( [[ "$NPM_ENABLED" == true ]] && echo true || echo false )" \
  --argjson npmOk "$( [[ "$NPM_OK" == true ]] && echo true || echo false )" \
  --argjson npmExit "$NPM_EXIT" \
  --argjson npmVulns "$NPM_VULNS_TOTAL" \
  --argjson npmRuns "$NPM_RUNS_JSON" \
  --arg pipVersion "$PIP_VERSION" \
  --argjson pipEnabled "$( [[ "$PIP_ENABLED" == true ]] && echo true || echo false )" \
  --argjson pipOk "$( [[ "$PIP_OK" == true ]] && echo true || echo false )" \
  --argjson pipExit "$PIP_EXIT" \
  --argjson pipVulns "$PIP_VULNS_TOTAL" \
  --argjson pipRuns "$PIP_RUNS_JSON" \
  --arg cargoVersion "$CARGO_VERSION" \
  --argjson cargoEnabled "$( [[ "$CARGO_ENABLED" == true ]] && echo true || echo false )" \
  --argjson cargoOk "$( [[ "$CARGO_OK" == true ]] && echo true || echo false )" \
  --argjson cargoExit "$CARGO_EXIT" \
  --argjson cargoVulns "$CARGO_VULNS_TOTAL" \
  --argjson cargoRuns "$CARGO_RUNS_JSON" \
  --arg goVersion "$GO_VERSION" \
  --argjson goEnabled "$( [[ "$GO_ENABLED" == true ]] && echo true || echo false )" \
  --argjson goOk "$( [[ "$GO_OK" == true ]] && echo true || echo false )" \
  --argjson goExit "$GO_EXIT" \
  --argjson goFindings "$GO_FINDINGS_TOTAL" \
  --argjson goRuns "$GO_RUNS_JSON" \
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
    options: {
      deep: $deepEnabled
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
      },
      semgrep: {
        enabled: $semgrepEnabled,
        ok: $semgrepOk,
        exitCode: $semgrepExit,
        version: ($semgrepVersion | select(length > 0) // null),
        findings: $semgrepFindings,
        report: "semgrep.json",
        log: "semgrep.log"
      },
      npmAudit: {
        enabled: $npmEnabled,
        ok: $npmOk,
        exitCode: $npmExit,
        version: ($npmVersion | select(length > 0) // null),
        vulnerabilities: $npmVulns,
        runs: $npmRuns
      },
      pipAudit: {
        enabled: $pipEnabled,
        ok: $pipOk,
        exitCode: $pipExit,
        version: ($pipVersion | select(length > 0) // null),
        vulnerabilities: $pipVulns,
        runs: $pipRuns
      },
      cargoAudit: {
        enabled: $cargoEnabled,
        ok: $cargoOk,
        exitCode: $cargoExit,
        version: ($cargoVersion | select(length > 0) // null),
        vulnerabilities: $cargoVulns,
        runs: $cargoRuns
      },
      govulncheck: {
        enabled: $goEnabled,
        ok: $goOk,
        exitCode: $goExit,
        version: ($goVersion | select(length > 0) // null),
        findings: $goFindings,
        runs: $goRuns
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
  echo "- Deep mode: $DEEP"
  echo
  echo "## Summary"
  echo
  echo "- Secrets (gitleaks): $GITLEAKS_FINDINGS finding(s)"
  echo "- Vulnerable dependencies (osv-scanner): $OSV_VULNS vulnerability record(s) across $OSV_PACKAGES package(s)"
  if [[ "$DEEP" == true ]]; then
    echo "- SAST (semgrep): $SEMGREP_FINDINGS finding(s)"
    echo "- npm audit: $NPM_VULNS_TOTAL vulnerability record(s)"
    echo "- pip-audit: $PIP_VULNS_TOTAL vulnerability record(s)"
    echo "- cargo audit: $CARGO_VULNS_TOTAL vulnerability record(s)"
    echo "- govulncheck: $GO_FINDINGS_TOTAL finding(s)"
  fi
  echo

  if [[ $SCAN_ERROR -eq 1 ]]; then
    echo "**Scanner errors occurred.** See tool logs in this output directory."
    echo
  fi
  if [[ $FINDINGS -eq 1 ]]; then
    echo "**Findings detected.** Review the raw outputs in this output directory."
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

  if [[ "$DEEP" == true ]]; then
    echo "### Deep mode tools"
    echo

    echo "#### semgrep"
    echo
    echo "- Raw: semgrep.json"
    echo "- Log: semgrep.log"
    echo
    if [[ "$SEMGREP_FINDINGS" -gt 0 ]]; then
      echo "Findings (best-effort summary):"
      echo
      jq -r '.results[]? | "- \(.path // "(unknown)"):\(.start.line // 0) — \(.check_id // "(unknown)")"' "$SEMGREP_REPORT" \
        | head -n 80
      echo
    else
      echo "No findings reported by semgrep."
      echo
    fi

    echo "#### ecosystem audits"
    echo

    if [[ "$NPM_ENABLED" == true ]]; then
      if [[ "$NPM_OK" == true ]]; then
        echo "- npm audit: $NPM_VULNS_TOTAL (see npm-audit__*.json)"
      else
        echo "- npm audit: error (see npm-audit.log)"
      fi
    else
      echo "- npm audit: not applicable (no package-lock.json / npm-shrinkwrap.json)"
    fi

    if [[ "$PIP_ENABLED" == true ]]; then
      if [[ "$PIP_OK" == true ]]; then
        echo "- pip-audit: $PIP_VULNS_TOTAL (see pip-audit__*.json)"
      else
        echo "- pip-audit: error (see pip-audit.log)"
      fi
    else
      echo "- pip-audit: not applicable (no requirements*.txt)"
    fi

    if [[ "$CARGO_ENABLED" == true ]]; then
      if [[ "$CARGO_OK" == true ]]; then
        echo "- cargo audit: $CARGO_VULNS_TOTAL (see cargo-audit__*.json)"
      else
        echo "- cargo audit: error (see cargo-audit.log)"
      fi
    else
      echo "- cargo audit: not applicable (no Cargo.lock)"
    fi

    if [[ "$GO_ENABLED" == true ]]; then
      if [[ "$GO_OK" == true ]]; then
        echo "- govulncheck: $GO_FINDINGS_TOTAL (see govulncheck__*.jsonl)"
      else
        echo "- govulncheck: error (see govulncheck.log)"
      fi
    else
      echo "- govulncheck: not applicable (no go.mod)"
    fi

    echo
  fi

  echo "## Notes"
  echo
  echo "- This scan runs locally. It does not upload your source code."
  echo "- gitleaks output is redacted and this report avoids printing secrets."
  echo "- osv-scanner queries OSV (and optionally deps.dev) over the network using dependency metadata."
  echo "- Deep mode tools may access the network to fetch rules/advisories."
  echo "- If you need to suppress false positives, add repo-local allowlists (.gitleaks.toml, .gitleaksignore, osv-scanner.toml), or use tool-specific ignore mechanisms."
} >"$REPORT_MD"

if [[ $SCAN_ERROR -eq 1 ]]; then
  exit 2
fi
if [[ $FINDINGS -eq 1 ]]; then
  exit 1
fi
exit 0
