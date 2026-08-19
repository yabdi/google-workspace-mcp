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
| [aaronsb/google-workspace-mcp#188](https://github.com/aaronsb/google-workspace-mcp/pull/188) | `feat/all-day-calendar-events` | All-day calendar events: `allDay: true` on `manage_calendar create`/`update` (Calendar API `date` fields, caller's inclusive end converted to the API's exclusive end date), `end` optional for all-day on create, timed ↔ all-day conversion on update, all-day display in `list`/`get`, scratchpad `calendar_event` support | 2026-08-19 | Open |

This feature is already live on this fork's `main` (commit `1a04235`, pushed
2026-08-19) and running in the local MCP server.

**When upstream merges it:** the fork already carries the identical change, so
the next audit-gated sync (`scripts/sync-upstream.sh`) should merge it cleanly.
Then delete the remote and local `feat/all-day-calendar-events` branches and
drop the row above.
