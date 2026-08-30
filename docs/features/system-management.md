# System / Host / Update (# management track)

Normative invariants for the System management surface. Full phase map:
[`docs/plans/2026-08-30-system-management-surface.md`](../plans/2026-08-30-system-management-surface.md).
Architecture: authenticated dashboard REST only — **not** the push plugin/gateway.

## Scope (shipped incrementally)

- **Host** — `GET /api/system/stats` (OS, versions, CPU/memory/disk, uptime)
- **Hermes update** — check / apply / receipt (`/api/hermes/update/*`); git Apply only
- **Gateway** — `POST /api/gateway/start|stop|restart` with confirmations
- **Operations** — doctor, security-audit, backup, prompt-size, dump, config-migrate
  via `POST /api/ops/*` + `actionStatus` poll
- **Banners** — unclean boot / suspected OOM from enriched `/api/status` when present

## Invariants

- Capability-gate on 404/405 per section; missing System probe hides the entry.
- Install-wide APIs — **no** `?profile=` query.
- Update success across dashboard restart is proven by **update receipt**, not by a
  null `exit_code` on a wiped in-memory action registry.
- Non-updatable installs (Docker/Nix/package): show out-of-band command; never POST apply.
- Confirm Update / Stop / Restart / config-migrate via `ConfirmationDialogState` +
  `.bottomActionSheet`.
- One background ops/update action at a time; surface tailed log lines in-ui.
- Push notify path unchanged (generic body; no remote commands over APNs).

## Out of scope here

Shell-hook mutation, checkpoint prune, backup restore/upload, SSH, push architecture,
MCP/webhooks/messaging (see plan Phase S6+).
