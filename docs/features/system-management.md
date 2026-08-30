# System / Host / Update

Normative invariants for the System management surface. Plan history:
[`docs/plans/completed/2026-08-30-system-management-surface.md`](../plans/completed/2026-08-30-system-management-surface.md).
Architecture: authenticated dashboard REST only — **not** the push plugin/gateway.

## Scope

- **Host** — `GET /api/system/stats` (OS, versions, CPU/memory/disk, uptime)
- **Hermes update** — check / apply / receipt (`/api/hermes/update/*`); git Apply only
- **Gateway** — `POST /api/gateway/start|stop|restart` with confirmations
- **Apply config / env writes** — after Settings config quick-edits or API Key
  set/delete, offer the same gateway restart (Hermes applies many file-level edits
  only on next session or restart). In-session chat `config.set` stays immediate.
- **Operations** — doctor, security-audit, backup, prompt-size, dump, config-migrate
  via `POST /api/ops/*` + `actionStatus` poll
- **Banners** — unclean boot / suspected OOM from enriched `/api/status` when present

## Entry

Settings → **System** and More → **System** (list-hosted sheet, same pattern as Skills).
Optimistic `systemSupported`; first `/api/system/stats` 404/405 hides the entry.

## Invariants

- Capability-gate on 404/405 per section; missing System probe hides the entry.
- Install-wide APIs — **no** `?profile=` query.
- Update success across dashboard restart is proven by **update receipt**, not by a
  null `exit_code` on a wiped in-memory action registry.
- Non-updatable installs (Docker/Nix/package): show out-of-band command; never POST apply.
- Confirm Update / Stop / Restart / config-migrate via `ConfirmationDialogState` +
  `.bottomActionSheet`. Never auto-restart after a config/env write — always confirm.
- One background ops/update action at a time; surface tailed log lines in-ui.
- No invented REST `/reload`; CLI `/reload` is not auto-submitted as chat.
- Push notify path unchanged (generic body; no remote commands over APNs).

## Out of scope here

Shell-hook mutation, checkpoint prune, backup restore/upload, SSH, push architecture,
MCP/webhooks/messaging (see plan Phase S6+).
