# Fork notes — yabdi/google-workspace-mcp

Fork-local state that is **not** part of upstream
([`aaronsb/google-workspace-mcp`](https://github.com/aaronsb/google-workspace-mcp)).
Files at the repo root that upstream does not have (this file, `AGENTS.md`,
`scripts/sync-upstream.sh`, …) are fork-local: they never come from upstream
and never go back in an upstream sync.

## Merged upstream pull requests

All four PRs opened from this fork were merged upstream on 2026-08-21/22 and are
now live on this fork's `main` via the audit-gated sync (merge `3912bc9`).

| PR | Head branch | What it added | Merged |
|----|-------------|---------------|--------|
| [aaronsb/google-workspace-mcp#187](https://github.com/aaronsb/google-workspace-mcp/pull/187) | `security-audit-fixes` | Dependency security audit: `npm audit` 17 → 0 (fast-uri, ip-address, hono, body-parser, @hono/node-server via `@modelcontextprotocol/sdk`; postcss, nanoid via `sanitize-html`), dev `@typescript-eslint` 6 → 7, pin `typescript@^5.9.3`, `src/version.ts` stamp sync | 2026-08-22 |
| [aaronsb/google-workspace-mcp#188](https://github.com/aaronsb/google-workspace-mcp/pull/188) | `feat/all-day-calendar-events` | All-day calendar events: `allDay: true` on create/update, inclusive→exclusive end conversion, timed ↔ all-day conversion, all-day display, scratchpad `calendar_event` support | 2026-08-22 |
| [aaronsb/google-workspace-mcp#189](https://github.com/aaronsb/google-workspace-mcp/pull/189) | `feat/drive-folders` | Drive folders: `createFolder`, `listFolder`, `tree`, `trash`, `setRole` (exposes `files.create` and `permissions.update`) | 2026-08-22 |
| [aaronsb/google-workspace-mcp#190](https://github.com/aaronsb/google-workspace-mcp/pull/190) | `feat/gmail-archive` | `manage_email archive`: save headers + plain-text body to a workspace markdown file | 2026-08-22 |

Upstream layered **post-merge hardening** over these after merging (calendar
all-day conversion now derives the missing side / sends `dateTime: null` to clear
the old shape; drive `listChildren` pages to exhaustion and escapes query values;
`tree` caps depth and de-dups revisited folders; `setRole` requires an explicit
`role` instead of defaulting to reader). This fork's sync adopted all of that
hardening while keeping the two local deviations below.

The PR head branches (`security-audit-fixes`, `feat/all-day-calendar-events`,
`feat/drive-folders`, `feat/gmail-archive`) are deleted locally and remotely.

## Conflict resolution policy

When an audit-gated sync aborts on a merge conflict (`git merge --no-commit
--no-ff upstream/main`), resolve each conflicted file by these rules, in order:

1. **A documented local deviation always wins.** (`drive share` notify-by-default
   + `emailMessage`, `calendar sendUpdates`.) Keep the fork's side — the deviation
   is deliberate and upstream was not asked to adopt it.
2. **Upstream's post-merge hardening of our own merged PRs is adopted.** It is
   upstream's improvement to code we originated — take their version (e.g.
   `setRole` requiring an explicit `role`, calendar `dateTime: null` to clear the
   old shape, drive paging/escaping/dedup).
3. **Net-new upstream changes are adopted wholesale.**

When a deviation and upstream hardening collide in the *same* hunk, keep the
deviation and re-apply the hardening's intent by hand. After resolving, run
`make check` — it is the ground truth that the merge is coherent — then finish
the audit gates and push (see `AGENTS.md` "Merge conflicts are normal").

The first four PRs (#187–#190) all merged as reworked/squashed commits plus
post-merge hardening, so the "already carries the identical change, merges
cleanly" expectation was wrong; conflicts here are the norm, not a failure.

## Local deviations from upstream

Deliberate behavior changes this fork carries that upstream does not — and
that upstream should **not** be asked to adopt without discussion. If a future
audit-gated sync ever conflicts with one, the deviation wins; resolve the
conflict by hand and keep this note updated.

- **Drive `share` notifies by email by default.** Upstream sets
  `sendNotificationEmail=false` on every user/group share
  (`src/services/drive/patch.ts`), so the "X shared a document with you" email
  never goes out and the invitee is never told. This fork keeps Google's
  default (send), with an explicit `sendNotificationEmail: false` param on
  `manage_drive share` to opt out. Motivated by a real miss: Hamza was granted
  `writer` on a doc and never received the link.

## Former local enhancements (now upstream)

These were ported from `~/code/gdrive-tools/scripts/gdrive.py` and opened as
PRs #189/#190, now merged upstream and adopted in this fork via the sync
(merge `3912bc9`). No longer fork-local — they track upstream:

- `createFolder`, `listFolder`, `tree`, `trash`, `setRole` (drive) — now upstream,
  with upstream's post-merge hardening (paging, query escaping, depth cap, dedup,
  `setRole` requires an explicit `role`).
- `manage_email archive` — now upstream (PR #190).
- `share` `emailMessage` — merged into the local `share` deviation below (upstream
  did not adopt the `emailMessage` param or the notify-by-default behavior).

## Local feature (calendar `sendUpdates`, no upstream PR yet)

`manage_calendar create`/`update` and the scratchpad `calendar_event` adapter accept a
`sendUpdates` param (`all` | `externalOnly` | `none`) choosing who gets notification
emails about the event. Committed locally and kept in this fork; deliberately **not**
opened upstream yet.

## Never open an upstream PR for the fork-local sync workflow

Commit `92ce327 chore: audit-gated upstream sync workflow` — `AGENTS.md`,
`FORK-NOTES.md`, `scripts/audit-upstream.sh`, `scripts/sync-upstream.sh`,
`scripts/README.md` — is **fork-local tooling, never upstream material**.

**Rule: never open an upstream PR that includes those files or that commit.**
They reference Yusuf's machine (ntfy via the gmail-inbox-watcher config,
`~/.local/share/google-workspace-mcp/sync.log`, the npm-cache workaround for
this box's read-only `~/.npm`) and describe this fork's maintenance process —
none of it is something `aaronsb/google-workspace-mcp` would adopt. If
upstream ever wants an audit-gated sync, it must be written fresh for
upstream, not this fork's scripts.
