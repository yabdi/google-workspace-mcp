# AGENTS.md — google-workspace-mcp fork

This is a fork of [`aaronsb/google-workspace-mcp`](https://github.com/aaronsb/google-workspace-mcp),
cloned at `~/code/google-workspace-mcp`, run **locally** as the Gmail /
Workspace MCP for Yusuf (opencode + DeepSeek Harness). Remotes: `origin` =
`yabdi/google-workspace-mcp`, `upstream` = aaronsb.

## Fork state & docs

Fork-local documentation lives in `FORK-NOTES.md` at the repo root — open
upstream PRs opened from this fork, local deviations, and cleanup notes. Check
it before working on anything that might already have an upstream PR, and keep
it updated when PRs open or merge.

**Never open an upstream PR for the fork-local sync workflow** (commit
`92ce327`: `AGENTS.md`, `FORK-NOTES.md`, `scripts/audit-upstream.sh`,
`scripts/sync-upstream.sh`, `scripts/README.md`). Those files are fork-local
tooling with machine-specific paths — they never go back upstream. Only
genuine fixes/features (e.g. the security-audit commit `c215bc5` → PR #187,
the all-day-calendar commit `1a04235` → PR #188) are PR candidates; check
`FORK-NOTES.md` for what is already open.

## The sync rule — fetch upstream → FULL SECURITY AUDIT → merge

**Never merge upstream directly.** `git fetch upstream && git merge upstream/main`
is forbidden: a bad upstream change must never land on the fork unvetted.

The only supported path is the audit-gated sync script:

```bash
~/code/google-workspace-mcp/scripts/sync-upstream.sh          # merge + push
~/code/google-workspace-mcp/scripts/sync-upstream.sh --dry-run # do everything except push
```

It enforces, in order:

1. fast-forward local `main` to `origin/main`
2. `git fetch upstream`; exits early when there is nothing new
3. **Pre-merge audit** (`scripts/audit-upstream.sh --range HEAD..upstream/main`):
   static scan of the incoming diff — code-execution primitives
   (eval/Function/child_process/exec/spawn/vm), unexpected network hosts
   (Google API + npm/github/localhost allowlist), TLS-verification bypass,
   hardcoded credentials (incl. `GOOGLE_CLIENT_ID/SECRET`), base64 blobs,
   secrets in the incoming commits
4. Stage the merge (`git merge --no-commit --no-ff`)
5. **Post-merge audit on the merged tree** (`scripts/audit-upstream.sh
   --worktree`): `npm install`, `npm audit` vs a **zero** baseline (auto
   `npm audit fix`; fail if still above), **`make check`** — the repo's own
   full CI gate (typecheck, lint, gate checks, the whole test suite, build,
   smoke, smoke-orphan), lockfile hygiene (registry.npmjs.org only, no
   install scripts), no tracked credential files
6. Commit the merge (including any audit-fix lockfile changes)
7. MCP stdio smoke test on the built server
8. Push to the fork

**Any gate failure aborts before the merge is committed or pushed.** Failures
(and successes) notify via ntfy when `~/.config/gmail-inbox-watcher/config.json`
exists; the log lives at `~/.local/share/google-workspace-mcp/sync.log`.

Tuning: `AUDIT_MAX_HIGH` (default 0), `AUDIT_MAX_CRITICAL` (default 0) —
raise only for a documented, unreachable dev-only chain. `NPM_CACHE_DIR` if
the default npm cache is unwritable.

### Merge conflicts are normal — resolve by policy, never by guess

Upstream does **not** merge our PRs verbatim. It rebases, rewords, and often
layers **post-merge hardening** on top of the merge (the #187–#190 merge added
calendar all-day conversion fixes and drive paging/escaping/dedup after the PRs
landed). So a sync that touches anything we opened upstream will **conflict** at
step 4 — that is expected, not a failure, and the old assumption that "the fork
already carries the identical change so it merges cleanly" is wrong.

When the script aborts at step 4, resolve by hand **using the policy in
`FORK-NOTES.md` ("Conflict resolution policy")**, then finish the remaining gates
manually (same order, same gates):

```bash
git fetch upstream
./scripts/audit-upstream.sh --range HEAD..upstream/main   # must PASS (step 3)
git merge --no-commit --no-ff upstream/main               # step 4 — leaves conflicts for you
#   resolve every conflicted file per the policy, then:
make check                                                 # merged tree builds + passes its tests
./scripts/audit-upstream.sh --worktree                     # step 5 — must PASS
git add -A && git commit --no-edit && git push origin main # steps 6–8
```

Resolution policy (the live list of deviations is in `FORK-NOTES.md`):

1. **A documented local deviation always wins.** (`drive share` notify-by-default
   + `emailMessage`, `calendar sendUpdates`.) Keep the fork's side.
2. **Upstream's post-merge hardening of our own merged PRs is adopted.** It is
   upstream's improvement to code we originated — take their version (e.g.
   `setRole` requiring an explicit `role`, calendar `dateTime: null`).
3. **Net-new upstream changes are adopted wholesale.**

When a deviation and upstream hardening collide in the *same* hunk, keep the
deviation and re-apply the hardening's intent by hand. Always run `make check`
after resolving — it is the ground truth that the merge is coherent.

### Audit false positives: "no X / not X" is not a secret

The pre-merge secret scan (`audit-upstream.sh` check 1f) flags added lines
mentioning `token`/`secret`/`password` etc. It already negates obvious
declarations (`password: false`, `passwordless`, `no <THING>TOKEN`,
`no secret`) — e.g. upstream's `docs/release-runbook.md` line "no \`NPM_TOKEN\`,
no secret to rotate". If a sync blocks on a new false positive of this shape,
extend the same negation in `scripts/audit-upstream.sh` rather than bypassing
the gate; the goal is to keep real secrets flagged, not to whitelist everything.

## After merging / after any code change

- The MCP configs (`~/.config/opencode/opencode.jsonc`,
  `~/.dsh/profiles/web/cordis.patch.yml`) run `node
  /home/yusuf.abdi/code/google-workspace-mcp/build/index.js`. `build/` is
  generated (gitignored): rebuild with `make check` (or `make build`) and
  restart the MCP server before relying on it. The DSH web GUI hot-reloads
  the MCP config when `cordis.patch.yml` changes; opencode reads it at launch.

## Secrets & credentials

- OAuth client id/secret live in `~/.config/opencode/opencode.jsonc` and
  `~/.dsh/profiles/web/cordis.patch.yml` (mirrored); OAuth tokens live in
  `~/.local/share/google-workspace-mcp/credentials/` — **outside this repo**.
- Never commit credentials, `.env`, `*.token.json`, `config/gauth.json`,
  `config/accounts.json`, or `.mcp.json` (all gitignored — the audit gate
  checks nothing tracked appears).
- Account management is via the MCP itself: `manage_accounts` (list/status/
  scopes/authenticate). The consent warning is expected — it is Yusuf's own
  GCP OAuth app.
