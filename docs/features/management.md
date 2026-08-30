# Management surfaces

Dashboard REST management features ported from the Hermes web dashboard API.
Chat, sessions, push, and slash commands stay on the existing gateway/REST paths;
these surfaces extend `HermesRESTClient` only — **no SSH**.

Required Hermes: a recent agent with the web dashboard (`hermes dashboard`) and the
management routes documented at
[Web Dashboard](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard).
Older agents that 404 a route hide that feature; the rest of the app keeps working.

## Skills (More / Settings → Skills)

| API | Behavior |
|-----|----------|
| `GET /api/skills` | Installed list |
| `PUT /api/skills/toggle` | Enable / disable |
| `GET /api/skills/hub/search` | Hub search |
| `POST /api/skills/hub/install\|uninstall\|update` | Backgrounded; poll `/api/actions/{name}/status` |

Capability: first list 404 → hide Skills entry. Profile: omit `?profile=` for default.
Entry points: session-list **More** → Skills, Settings → Skills (dismisses Settings and
presents the same list-hosted sheet). Enabled skills also appear as `/` slash routes in
chat (invocation only — not the management hub).

## API Keys (Settings → API Keys)

Manage the agent host’s `~/.hermes/.env` (API keys and related credentials) via the
dashboard Keys surface. Values in the list are **redacted**; the app never stores agent
secrets in Keychain (Keychain stays `AuthSession` only).

| API | Behavior |
|-----|----------|
| `GET /api/env` | Catalog: set/unset, redacted preview, description, category, advanced |
| `PUT /api/env` | Set / overwrite `{"key","value"}` (empty submit is a client no-op) |
| `DELETE /api/env` | Remove `{"key"}` |
| `POST /api/env/reveal` | Unredact one key (optional; soft-gated) |

Capability: first list 404/405 → hide API Keys. Profile: omit `?profile=` for default.
Filters (local): search by key name, **Set only**, and **Show advanced** (advanced keys
hidden by default). Reveal uses the same `AuthSession` as other REST; on 401/403/404/405
the Reveal button is hidden for that agent and overwrite remains available (some agents
only allow reveal from the web SPA). Revealed plaintext lives only in ephemeral edit
state — shown in a disabled `SecureField` (no copy), auto-clears after ~30s or on dismiss;
429 surfaces a rate-limit banner. Never log reveal values or full `/api/env` bodies.
Writes apply to new sessions; a running process may need a gateway restart (planned
System “Restart gateway to apply” offer after save — see
[`system-management.md`](system-management.md)). CLI `/reload` remains host-side only.

## Workspaces (More / Settings → Workspaces)

Read-mostly browser for project folders on the agent host, using the desktop remote
filesystem rail (`/api/fs/*`). Roots are **client-derived** from distinct session
`cwd` values (plus `GET /api/fs/default-cwd`); there is no server workspace catalog.

| API | Behavior |
|-----|----------|
| `GET /api/fs/default-cwd` | Seed / capability probe |
| `GET /api/fs/list?path=` | Directory listing (`error: ENOENT\|…` soft-fails) |
| `GET /api/fs/read-text?path=` | Text preview (size-capped) |
| `GET /api/fs/read-data-url?path=` | Image / binary payload |

Capability: first definitive 404/405 → hide Workspaces (More, Settings, session/group
context **Open workspace**, chat `⋯` **Open workspace**). Profile: omit `?profile=` for
default. Entry points: More → **Workspaces**, Settings → **Workspaces**, session/group
context **Open workspace**, chat menu **Open workspace** when the live session has a
`cwd`.

Privacy: never log file bodies or data URLs; path strings only in UI state. Mutations
(upload / mkdir / delete) and the managed `/api/files` CRUD rail are out of scope here.

## Cron CRUD (session list)

Create / edit sheets and delete confirmation on top of existing list, pause, resume,
and trigger. APIs: `POST/PUT/DELETE /api/cron/jobs`.

## Config quick edits + model (Settings)

Curated `config.yaml` keys via `GET/PUT /api/config` (no raw YAML editor):

- `model.default` / `model.provider`
- `approvals.mode` or `agent.approval_mode` when present
- `display.show_cost` / `show_reasoning` / `streaming`
- `agent.max_turns` / `agent.max_iterations` when present

Default model picker uses `GET /api/model/options` and `POST /api/model/set`.
Chat still uses gateway `model.options` / `config.set` for in-session changes.

## Multi-server (client-only)

Saved `{ id, label, baseURL }` in Preferences; auth per server in Keychain.
Onboarding lists saved servers; Settings → **Switch server** tears down the live chat
slot (logout policy for UI) but keeps other servers’ credentials.

## Home ops strip (session list)

Enriched `GET /api/status` (gateway + memory/disk pressure) and
`GET /api/analytics/usage?days=`. Compact strip under the Sessions header.
Analytics 404 → hide usage only.

## System / Host / Update

Host stats, Hermes self-update (check / apply / receipt), gateway lifecycle, and
Operations actions (doctor, audit, backup, …). Authenticated dashboard REST only —
not the push plugin. Invariants: [`system-management.md`](system-management.md).

Entry: Settings → **System**, More → **System**. After config quick-edit or API Key
save/delete, offer confirmed gateway restart when supported.

## Privacy

Never log passwords, env reveal values, webhook secrets, full `/api/env` /
config bodies, or workspace file contents / data URLs from `/api/fs`.

## Sideload distribution

Unsigned IPA + AltStore/Feather source: see [`altstore/README.md`](../../altstore/README.md).
