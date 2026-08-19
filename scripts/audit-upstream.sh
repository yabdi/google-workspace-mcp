#!/usr/bin/env bash
# audit-upstream.sh — security gate for incoming upstream changes
# (google-workspace-mcp fork, upstream aaronsb/google-workspace-mcp).
#
# Runs the automated portion of the full security audit against changes about
# to be merged from upstream. Every check prints PASS/FAIL; the script exits
# non-zero if any check fails. Used by sync-upstream.sh as the "audit before
# merge" gate and safe to run standalone.
#
# The full security audit for this fork is: static scan of the incoming diff
# (this file, --range) + supply-chain audit (npm audit vs a zero baseline) +
# the repo's OWN full CI gate (`make check`: typecheck, lint, gate checks,
# the whole test suite, build, smoke, smoke-orphan) + lockfile/secrets
# hygiene (--worktree). A merge only happens after every layer passes.
#
# Modes:
#   --range BASE..HEAD     static scans over the incoming diff (no working
#                          tree changes needed) — run BEFORE merging
#   --worktree             supply-chain + full CI gate + tree scans on the
#                          current working tree (run AFTER `git merge
#                          --no-commit`)
#   (both, default)        everything
#
# Tuning (env):
#   AUDIT_MAX_HIGH        max acceptable `npm audit` high count (default 0 —
#                         this fork is audited to zero; raise only for a
#                         documented, unreachable dev-only chain)
#   AUDIT_MAX_CRITICAL    max acceptable critical count (default 0)
#   NPM_CACHE_DIR         writable npm cache (default
#                         ${TMPDIR:-/tmp}/npm-cache-gws — ~/.npm is a
#                         read-only mount on this box, npm dies with EROFS)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

export PATH="/usr/bin:/bin:/usr/local/bin:$HOME/.local/bin${PATH:+:$PATH}"

MODE_BOTH=1; MODE_RANGE=0; MODE_WORKTREE=0
RANGE=""
for arg in "$@"; do
  case "$arg" in
    --range) MODE_BOTH=0; MODE_RANGE=1 ;;
    --worktree) MODE_BOTH=0; MODE_WORKTREE=1 ;;
    --range=*) MODE_BOTH=0; MODE_RANGE=1; RANGE="${arg#--range=}" ;;
    *) RANGE="$arg" ;;
  esac
done
[[ -z "$RANGE" ]] && RANGE="HEAD..upstream/main"

AUDIT_MAX_HIGH="${AUDIT_MAX_HIGH:-0}"
AUDIT_MAX_CRITICAL="${AUDIT_MAX_CRITICAL:-0}"
NPM_CACHE_DIR="${NPM_CACHE_DIR:-${TMPDIR:-/tmp}/npm-cache-gws}"
mkdir -p "$NPM_CACHE_DIR"
export npm_config_cache="$NPM_CACHE_DIR"

FAILED=0
fail() { echo "FAIL  $1"; FAILED=1; }
pass() { echo "PASS  $1"; }

# Allowlisted hosts for http(s) endpoints in repo source. Everything this
# server legitimately talks to (Google APIs, the local OAuth callback) plus
# the toolchain/documentation hosts already present at baseline. Anything else
# in an incoming diff is a review item.
ALLOWED_HOSTS="accounts\.google\.com|oauth2\.googleapis\.com|www\.googleapis\.com|docs\.googleapis\.com|sheets\.googleapis\.com|gmail\.googleapis\.com|calendar\.googleapis\.com|calendar-json\.googleapis\.com|drive\.googleapis\.com|tasks\.googleapis\.com|people\.googleapis\.com|meet\.googleapis\.com|127\.0\.0\.1|localhost|example\.com|x|registry\.npmjs\.org|github\.com|raw\.githubusercontent\.com|npmjs\.org|static\.modelcontextprotocol\.io|modelcontextprotocol\.io|nodejs\.org|console\.cloud\.google\.com|developers\.google\.com|myaccount\.google\.com|mail\.google\.com|calendar\.google\.com|drive\.google\.com|docs\.google\.com|meet\.google\.com"

# ── 1. Static scan of the incoming diff ─────────────────────────────────────
if [[ "$MODE_BOTH" == "1" || "$MODE_RANGE" == "1" ]]; then
  echo "== static scan: $RANGE =="
  FILES="$(git diff --name-only --diff-filter=ACMR "$RANGE" -- '*.ts' '*.js' '*.json' '*.yml' '*.yaml' '*.sh' 'Dockerfile' 2>/dev/null || true)"

  if [[ -z "$FILES" ]]; then
    pass "no source files changed in $RANGE"
  else
    # 1a. code execution primitives
    if git diff "$RANGE" -- "$FILES" | grep -nE '\b(eval|new Function|child_process|exec\(|spawn\(|execFile\(|vm\.|require\(["'"'"']child_process)' >/dev/null 2>&1; then
      fail "code-execution primitives (eval/Function/child_process/exec/spawn/vm) in $RANGE"
    else
      pass "no code-execution primitives in $RANGE"
    fi

    # 1b. unexpected network endpoints (hosts outside the allowlist)
    BAD=$(git diff "$RANGE" -- "$FILES" | grep -oE 'https?://[a-zA-Z0-9.-]+' | sed 's|https\?://||' | sort -u | grep -vE "^($ALLOWED_HOSTS)$" || true)
    if [[ -n "$BAD" ]]; then
      fail "unexpected network host(s) in $RANGE: $(echo "$BAD" | tr '\n' ' ')"
    else
      pass "no unexpected network endpoints in $RANGE"
    fi

    # 1c. TLS verification bypass
    if git diff "$RANGE" -- "$FILES" | grep -nE 'rejectUnauthorized:\s*false|NODE_TLS_REJECT_UNAUTHORIZED|allowInsecure|checkServerIdentity' >/dev/null 2>&1; then
      fail "TLS verification disabled somewhere in $RANGE"
    else
      pass "no TLS-verification bypass in $RANGE"
    fi

    # 1d. hardcoded credentials (Google OAuth + generic)
    if git diff "$RANGE" -- "$FILES" | grep -nE '(GOOGLE_CLIENT_(ID|SECRET)|client_secret|refresh_token|password|secret|token|api[_-]?key)\s*[:=]\s*["'"'"'][^"'"'"']{8,}' >/dev/null 2>&1; then
      fail "possible hardcoded credential(s) in $RANGE"
    else
      pass "no hardcoded credentials in $RANGE"
    fi

    # 1e. obfuscation: long base64 blobs
    if git diff "$RANGE" -- "$FILES" | grep -nE '[A-Za-z0-9+/]{60,}={0,2}' >/dev/null 2>&1; then
      fail "possible base64 blob(s) (obfuscation) in $RANGE"
    else
      pass "no base64 blobs in $RANGE"
    fi
  fi

  # 1f. secrets in the incoming commit messages/patch
  if git log -p "$RANGE" 2>/dev/null | grep -nE '^\+.*(password|secret|token|api[_-]?key|GOOGLE_CLIENT|refresh_token|BEGIN (RSA|OPENSSH|EC|PRIVATE))' | grep -viE 'password:\s*false|passwordless' >/dev/null 2>&1; then
    fail "possible secret material in incoming commits"
  else
    pass "no secret material in incoming commits"
  fi
fi

# ── 2. Supply chain + full CI gate + tree scans (merged working tree) ───────
if [[ "$MODE_BOTH" == "1" || "$MODE_WORKTREE" == "1" ]]; then
  echo "== supply chain: merged tree =="

  # 2a. dependency install (syncs node_modules to the merged lockfile)
  if ! npm install --no-audit --no-fund --loglevel=error >/dev/null 2>&1; then
    fail "npm install failed on the merged tree"
  else
    pass "npm install OK on the merged tree"
  fi

  # 2b. npm audit vs baseline; auto-apply semver-safe fixes to reach baseline
  AUDIT_JSON="$(npm audit --json 2>/dev/null || true)"
  HIGH=$(printf '%s' "$AUDIT_JSON" | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin); v=d.get("metadata",{}).get("vulnerabilities",{})
  print(v.get("high",0), v.get("critical",0))
except Exception:
  print("999 999")')
  HIGH_N="${HIGH%% *}"; CRIT_N="${HIGH##* }"
  if [[ "$HIGH_N" =~ ^[0-9]+$ ]] && (( HIGH_N > AUDIT_MAX_HIGH || CRIT_N > AUDIT_MAX_CRITICAL )); then
    echo "     npm audit: $HIGH_N high / $CRIT_N critical (baseline $AUDIT_MAX_HIGH/$AUDIT_MAX_CRITICAL) — trying npm audit fix"
    npm audit fix --no-fund >/dev/null 2>&1 || true
    AUDIT_JSON="$(npm audit --json 2>/dev/null || true)"
    HIGH=$(printf '%s' "$AUDIT_JSON" | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin); v=d.get("metadata",{}).get("vulnerabilities",{})
  print(v.get("high",0), v.get("critical",0))
except Exception:
  print("999 999")')
    HIGH_N="${HIGH%% *}"; CRIT_N="${HIGH##* }"
  fi
  if [[ "$HIGH_N" =~ ^[0-9]+$ ]] && (( HIGH_N <= AUDIT_MAX_HIGH && CRIT_N <= AUDIT_MAX_CRITICAL )); then
    pass "npm audit within baseline ($HIGH_N high / $CRIT_N critical, max $AUDIT_MAX_HIGH/$AUDIT_MAX_CRITICAL)"
  else
    fail "npm audit above baseline: $HIGH_N high / $CRIT_N critical (max $AUDIT_MAX_HIGH/$AUDIT_MAX_CRITICAL)"
  fi

  # 2c. FULL CI GATE — the repo's own gate: typecheck, lint, gate checks, the
  #     whole test suite, build, smoke, smoke-orphan. This is the heart of the
  #     audit: a merged tree must build and pass its own tests.
  echo "== full CI gate: make check =="
  if ! make check >/tmp/gws-audit-makecheck.log 2>&1; then
    tail -40 /tmp/gws-audit-makecheck.log
    fail "make check failed on the merged tree (see /tmp/gws-audit-makecheck.log)"
  else
    pass "make check OK on the merged tree (typecheck, lint, gates, tests, build, smoke, smoke-orphan)"
  fi

  # 2d. lockfile hygiene: foreign tarballs + install scripts
  BAD_URLS=$(grep -oE '"resolved": "https?://[^/]+' package-lock.json 2>/dev/null | sed 's/.*https\?:\/\///' | sort -u | grep -v '^registry\.npmjs\.org$' || true)
  if [[ -n "$BAD_URLS" ]]; then
    fail "foreign tarball host(s) in lockfile: $(echo "$BAD_URLS" | tr '\n' ' ')"
  else
    pass "all lockfile tarballs from registry.npmjs.org"
  fi
  if grep -qE '"(preinstall|install|postinstall)":' package-lock.json 2>/dev/null; then
    fail "install/preinstall/postinstall scripts present in lockfile"
  else
    pass "no install scripts in lockfile"
  fi

  # 2e. no credentials tracked (everything in .gitignore must stay untracked)
  TRACKED_BAD=$(git ls-files | grep -E '(^|/)\.env($|\.)|config/(gauth|accounts)\.json|config/credentials/|\.token\.json|\.mcp\.json' || true)
  if [[ -n "$TRACKED_BAD" ]]; then
    fail "credential file(s) tracked in git: $(echo "$TRACKED_BAD" | tr '\n' ' ')"
  else
    pass "no credential files tracked (gitignore intact)"
  fi
fi

if [[ "$FAILED" == "1" ]]; then
  echo "AUDIT GATE: FAILED"
  exit 1
fi
echo "AUDIT GATE: PASSED"
