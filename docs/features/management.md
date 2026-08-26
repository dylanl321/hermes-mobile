# Management surfaces

Dashboard REST management features ported from the Hermes web dashboard API.
Chat, sessions, push, and slash commands stay on the existing gateway/REST paths;
these surfaces extend `HermesRESTClient` only — **no SSH**.

Required Hermes: a recent agent with the web dashboard (`hermes dashboard`) and the
management routes documented at
[Web Dashboard](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard).
Older agents that 404 a route hide that feature; the rest of the app keeps working.

## Skills (Settings → Skills)

| API | Behavior |
|-----|----------|
| `GET /api/skills` | Installed list |
| `PUT /api/skills/toggle` | Enable / disable |
| `GET /api/skills/hub/search` | Hub search |
| `POST /api/skills/hub/install\|uninstall\|update` | Backgrounded; poll `/api/actions/{name}/status` |

Capability: first list 404 → hide Skills entry. Profile: omit `?profile=` for default.

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

## Privacy

Never log passwords, env reveal values, webhook secrets, or full `/api/env` /
config bodies.

## Sideload distribution

Unsigned IPA + AltStore/Feather source: see [`altstore/README.md`](../../altstore/README.md).
