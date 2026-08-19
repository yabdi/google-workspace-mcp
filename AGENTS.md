# AGENTS.md — google-workspace-mcp fork

This is a fork of [`aaronsb/google-workspace-mcp`](https://github.com/aaronsb/google-workspace-mcp),
cloned at `~/code/google-workspace-mcp`, run **locally** as the Gmail /
Workspace MCP for Yusuf (opencode + DeepSeek Harness). Remotes: `origin` =
`yabdi/google-workspace-mcp`, `upstream` = aaronsb.

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

Manual equivalent (when you must go step-by-step — same gates, same order):

```bash
git fetch upstream
./scripts/audit-upstream.sh --range HEAD..upstream/main   # must PASS
git merge --no-commit --no-ff upstream/main
./scripts/audit-upstream.sh --worktree                    # must PASS
git add -A && git commit --no-edit && git push origin main
```

Tuning: `AUDIT_MAX_HIGH` (default 0), `AUDIT_MAX_CRITICAL` (default 0) —
raise only for a documented, unreachable dev-only chain. `NPM_CACHE_DIR` if
the default npm cache is unwritable.

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
