#!/usr/bin/env bash
# sync-upstream.sh — keep the google-workspace-mcp fork current with upstream
# (aaronsb/google-workspace-mcp), audit-gated.
#
# RULE: upstream is NEVER merged unvetted. The order is always
#     fetch upstream  →  full security audit  →  merge
# and only a passing audit lets the merge land (committed and pushed).
#
# Pipeline (safe to run manually; cron optional):
#   1. fast-forward local main to the fork's origin/main
#   2. fetch upstream; exit early if nothing new
#   3. PRE-MERGE AUDIT GATE: static scan of the incoming diff + secrets in
#      the incoming commits (scripts/audit-upstream.sh --range)
#   4. stage the merge (git merge --no-commit --no-ff)
#   5. POST-MERGE AUDIT GATE on the merged tree (scripts/audit-upstream.sh
#      --worktree): npm install, npm audit vs a zero baseline, FULL CI GATE
#      (make check: typecheck, lint, gate checks, full test suite, build,
#      smoke, smoke-orphan), lockfile hygiene, no tracked credentials
#   6. commit the merge (incl. any audit-fix lockfile changes)
#   7. MCP stdio smoke test (built server boots and answers initialize)
#   8. push to the fork
#
# Any gate failure aborts BEFORE the merge is committed/pushed (the staged
# merge is aborted), so a bad upstream change never lands on the fork.
# Failures are notified via ntfy when the gmail-inbox-watcher config exists;
# otherwise they land in ~/.local/share/google-workspace-mcp/sync.log.
#
# Tuning (env): AUDIT_MAX_HIGH / AUDIT_MAX_CRITICAL / NPM_CACHE_DIR
#               (see scripts/audit-upstream.sh).
# Flags: --dry-run (do everything except push).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

export PATH="/usr/bin:/bin:/usr/local/bin:$HOME/.local/bin${PATH:+:$PATH}"
LOG_DIR="$HOME/.local/share/google-workspace-mcp"
LOG_FILE="$LOG_DIR/sync.log"
mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# ntfy notification — only when the watcher config exists (topic/base).
notify() {
  local cfg="$HOME/.config/gmail-inbox-watcher/config.json" title="$1" msg="$2"
  [[ -f "$cfg" ]] || { log "ntfy: not configured ($cfg missing) — skipped"; return 0; }
  local topic base
  topic="$(python3 -c "import json;print(json.load(open('$cfg')).get('ntfy_topic',''))" 2>/dev/null || true)"
  base="$(python3 -c "import json;print(json.load(open('$cfg')).get('ntfy_base','https://ntfy.sh'))" 2>/dev/null || true)"
  [[ -n "$topic" ]] || { log "ntfy: no ntfy_topic in $cfg — skipped"; return 0; }
  curl -sf -H "Title: $title" -d "$msg" "$base/$topic" >/dev/null 2>&1 \
    && log "ntfy: notified ($title)" || log "ntfy: send failed ($title)"
}

cd "$REPO_DIR"

# ── 1. sync local main with the fork (in case it moved elsewhere) ──────────
git fetch origin --quiet
if ! git merge-base --is-ancestor origin/main HEAD; then
  if git merge --ff-only origin/main >/dev/null 2>&1; then
    log "fast-forwarded local main to origin/main"
  else
    log "ERROR: local main diverged from origin/main — resolve manually"; exit 1
  fi
fi

# ── 2. fetch upstream, short-circuit when nothing new ───────────────────────
git fetch upstream --quiet
NEW="$(git rev-list --count HEAD..upstream/main)"
if [[ "$NEW" == "0" ]]; then
  log "up to date with upstream/main ($(git rev-parse --short upstream/main)) — nothing to do"
  exit 0
fi

log "upstream has $NEW new commit(s):"
git log --oneline HEAD..upstream/main | sed 's/^/    /' | tee -a "$LOG_FILE"

# ── 3. PRE-MERGE AUDIT GATE ─────────────────────────────────────────────────
log "PRE-MERGE AUDIT GATE: static scan of incoming diff..."
if ! ./scripts/audit-upstream.sh --range "HEAD..upstream/main" 2>&1 | tee -a "$LOG_FILE"; then
  notify "google-workspace fork: sync BLOCKED (pre-merge audit)" \
    "$NEW new upstream commit(s) failed the pre-merge security audit. See $LOG_FILE"
  log "ABORT: pre-merge audit failed — nothing merged, nothing pushed"
  exit 1
fi

# ── 4. stage the merge ──────────────────────────────────────────────────────
log "staging merge of upstream/main..."
if ! git merge --no-commit --no-ff upstream/main >/dev/null 2>&1; then
  git merge --abort >/dev/null 2>&1 || true
  notify "google-workspace fork: sync BLOCKED (merge conflict)" \
    "Merging upstream/main conflicts. Resolve manually in $REPO_DIR (likely package-lock.json)."
  log "ABORT: merge conflict — nothing merged, nothing pushed"
  exit 1
fi

# ── 5. POST-MERGE AUDIT GATE on the merged tree ─────────────────────────────
log "POST-MERGE AUDIT GATE: supply chain + full CI gate + tree scans..."
if ! ./scripts/audit-upstream.sh --worktree 2>&1 | tee -a "$LOG_FILE"; then
  git merge --abort >/dev/null 2>&1 || true
  notify "google-workspace fork: sync BLOCKED (post-merge audit)" \
    "Merged tree failed the security audit (npm audit / make check / lockfile / secrets). Merge aborted. See $LOG_FILE"
  log "ABORT: post-merge audit failed — merge aborted, nothing pushed"
  exit 1
fi

# ── 6. commit the merge (incl. any audit-fix lockfile changes) ──────────────
git add -A
git commit --no-edit >/dev/null
MERGED_SHA="$(git rev-parse --short HEAD)"
log "merge committed: $MERGED_SHA"

# ── 7. MCP stdio smoke test (built server from the merged tree) ─────────────
log "smoke test: MCP stdio handshake on built server..."
if ! printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"sync-check","version":"1"}}}' \
  | timeout 20 env GOOGLE_CLIENT_ID=smoke.invalid GOOGLE_CLIENT_SECRET=smoke \
      node build/index.js 2>/dev/null | grep -q '"serverInfo"'; then
  notify "google-workspace fork: sync BLOCKED (smoke test)" \
    "Merged tree committed locally ($MERGED_SHA) but the MCP server failed to boot — NOT pushed."
  log "ABORT: smoke test failed — merge committed locally but NOT pushed"
  exit 1
fi
log "smoke test OK"

# ── 8. push ─────────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "1" ]]; then
  log "dry-run: skipping push (local main at $MERGED_SHA)"
  exit 0
fi
git push origin main >/dev/null
log "pushed to origin/main: $MERGED_SHA ($NEW upstream commit(s) merged, audit passed)"
notify "google-workspace fork: synced" \
  "Merged $NEW upstream commit(s) -> $MERGED_SHA. Audit gates passed. Log: $LOG_FILE"
