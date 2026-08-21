# Fork notes — yabdi/google-workspace-mcp

Fork-local state that is **not** part of upstream
([`aaronsb/google-workspace-mcp`](https://github.com/aaronsb/google-workspace-mcp)).
Files at the repo root that upstream does not have (this file, `AGENTS.md`,
`scripts/sync-upstream.sh`, …) are fork-local: they never come from upstream
and never go back in an upstream sync.

## Open upstream pull requests

PRs opened from this fork back to upstream, awaiting review/merge.

| PR | Head branch | What it adds | Opened | Status |
|----|-------------|--------------|--------|--------|
| [aaronsb/google-workspace-mcp#187](https://github.com/aaronsb/google-workspace-mcp/pull/187) | `security-audit-fixes` | Dependency security audit: `npm audit` 17 → 0 — production-reachable patches within semver (fast-uri, ip-address, hono, body-parser, @hono/node-server via `@modelcontextprotocol/sdk`; postcss, nanoid via `sanitize-html`), dev toolchain `@typescript-eslint` 6 → 7 (clears the minimatch/flatted ReDoS chain without `--force`), pin `typescript@^5.9.3` in devDependencies (was an undeclared transitive — an unconstrained re-resolution can hoist the TS7 native preview and break `tsc`), `src/version.ts` stamp sync | 2026-08-19 | Open |
| [aaronsb/google-workspace-mcp#188](https://github.com/aaronsb/google-workspace-mcp/pull/188) | `feat/all-day-calendar-events` | All-day calendar events: `allDay: true` on `manage_calendar create`/`update` (Calendar API `date` fields, caller's inclusive end converted to the API's exclusive end date), `end` optional for all-day on create, timed ↔ all-day conversion on update, all-day display in `list`/`get`, scratchpad `calendar_event` support | 2026-08-19 | Open |

Both PRs are already live on this fork's `main` (commits `c215bc5` and
`1a04235`, pushed 2026-08-19) and running in the local MCP server.

**When upstream merges #187:** the fork already carries the identical change
(`c215bc5`), so the next audit-gated sync (`scripts/sync-upstream.sh`) merges
it cleanly. Then delete the remote and local `security-audit-fixes` branches
and drop the row above.

**When upstream merges #188:** the fork already carries the identical change
(`1a04235`), so the next audit-gated sync merges it cleanly. Then delete the
remote and local `feat/all-day-calendar-events` branches and drop the row
above.

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

## Local enhancements (additive, not yet upstream)

Net-new `manage_drive` capabilities ported from `~/code/gdrive-tools/scripts/gdrive.py`
(the standalone helper built because `manage_drive` could not create folders). These are
additive — they change no existing behavior, so they are clean candidates for an
upstream PR rather than a "deviation". They cover the gaps `gdrive-tools` existed to fill:

- **`createFolder`** — create a folder (optionally nested via `parentFolderId`).
  `files.create` with `mimeType: application/vnd.google-apps.folder`; `parents` sent as
  an array in the body.
- **`listFolder`** / **`tree`** — list a folder's children (non-trashed) and print a
  recursive tree with a file count (`files.list`).
- **`trash`** — recoverable removal (`files.update` with `trashed: true`), the safe
  alternative to the permanent `delete`.
- **`setRole`** — change an existing collaborator's role by email, resolved to the
  permission id first (`permissions.list` → `permissions.update`). Sends no notification.
- **`share` `emailMessage`** — optional message in the "shared with you" notification.

`files.create` and `permissions.update` are therefore newly exposed in
`docs/api-surface.md` (drive 14 → 16 of 64).

`manage_email archive` — save one message's headers + plain-text body to a workspace
markdown file (port of `~/code/gdrive-tools/scripts/archive_gmail.py`). Reads the message
and writes a LOCAL file; does not touch Gmail's INBOX label.

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
