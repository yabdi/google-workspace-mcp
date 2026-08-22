# Fork workflow — audit-gated upstream sync

This fork (`yabdi/google-workspace-mcp`) tracks upstream
`aaronsb/google-workspace-mcp` under a hard rule:

> **fetch upstream → full security audit → merge** — never the other way
> around, and never a bare `git merge upstream/main`.

Two scripts implement it (see also `AGENTS.md` at the repo root):

## `audit-upstream.sh` — the audit gate (standalone or as a gate)

Runs the automated portion of the full security audit. Every check prints
PASS/FAIL; exits non-zero if any fails.

| Mode | What it scans |
|---|---|
| `--range BASE..HEAD` | Static scan of the **incoming diff** (no working-tree changes needed) — run *before* merging. Code-execution primitives (eval / `new Function` / child_process / exec / spawn / vm), unexpected network hosts (Google API + npm/github/localhost/example.com allowlist — anything else is a review item), TLS-verification bypass, hardcoded credentials (incl. `GOOGLE_CLIENT_ID/SECRET`), long base64 blobs, secret material in the incoming commits |
| `--worktree` | Supply-chain + **full CI gate** on the current working tree (run *after* `git merge --no-commit`): `npm install`, `npm audit` vs a **zero** baseline (auto `npm audit fix`; fail if still above), **`make check`** — the repo's own full gate (typecheck, lint, gate checks, the whole test suite, build, smoke, smoke-orphan), lockfile hygiene (registry.npmjs.org only, no install scripts), no tracked credential files |
| (no flag) | Both |

Tuning (env): `AUDIT_MAX_HIGH` (default **0** — the fork is audited to zero),
`AUDIT_MAX_CRITICAL` (default 0), `NPM_CACHE_DIR` (default
`${TMPDIR:-/tmp}/npm-cache-gws` — `~/.npm` is a read-only mount on this box,
so npm needs a writable cache).

## `sync-upstream.sh` — the merge pipeline

```bash
./scripts/sync-upstream.sh            # fetch → audit → merge → commit → smoke → push
./scripts/sync-upstream.sh --dry-run  # everything except the push
```

Pipeline:

1. fast-forward local `main` to the fork's `origin/main`
2. `git fetch upstream`; exit early when nothing new
3. **Pre-merge audit gate** — `audit-upstream.sh --range HEAD..upstream/main`
4. stage the merge — `git merge --no-commit --no-ff upstream/main`
5. **Post-merge audit gate** — `audit-upstream.sh --worktree` on the merged
   tree (this is where `npm audit fix` may adjust the lockfile, and where
   `make check` proves the merged tree builds and passes its own tests)
6. commit the merge (incl. any audit-fix lockfile changes)
7. MCP stdio smoke test on the built server
8. push to the fork

**Any gate failure aborts before the merge is committed/pushed** (the staged
merge is aborted). Failures and successes notify via ntfy when
`~/.config/gmail-inbox-watcher/config.json` exists; otherwise the log is
`~/.local/share/google-workspace-mcp/sync.log`.

### Merge conflicts are the norm, not a failure

Upstream rebases/reworks our PRs and layers post-merge hardening on top, so a
sync that touches anything we opened upstream **conflicts at step 4**. When the
script aborts there, resolve by hand using the policy in `FORK-NOTES.md`
("Conflict resolution policy"), then finish the remaining gates in the same
order:

```bash
./scripts/audit-upstream.sh --range HEAD..upstream/main   # step 3 — must PASS
git merge --no-commit --no-ff upstream/main               # step 4 — leaves conflicts for you
#   resolve every conflicted file per the policy, then:
make check                                                 # merged tree builds + passes tests
./scripts/audit-upstream.sh --worktree                     # step 5 — must PASS
git add -A && git commit --no-edit && git push origin main # steps 6–8
```

### Audit false positives: "no X / not X" is not a secret

The pre-merge secret scan (check 1f) negates obvious "there is no secret here"
declarations: `password: false`, `passwordless`, `no <THING>TOKEN`, `no secret`.
If a sync blocks on a new false positive of this shape (e.g. a release runbook
saying "no `NPM_TOKEN`"), extend that same negation in `audit-upstream.sh`
rather than bypassing the gate.

## How the server is launched

- The MCP configs (`~/.config/opencode/opencode.jsonc` →
  `mcp.google-workspace`, `~/.dsh/profiles/web/cordis.patch.yml` →
  `mcp-google-workspace`) run `node
  /home/yusuf.abdi/code/google-workspace-mcp/build/index.js` with
  `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` in the environment.
- `build/` is generated (gitignored): `make check` (or `make build`) produces
  it. Rebuild + restart the MCP after merging upstream. OAuth tokens live in
  `~/.local/share/google-workspace-mcp/credentials/` and survive rebuilds /
  restarts / launcher changes.
