# Hermes Mobile — Management surface port + sideload (Phase 0)

## Overview

Port ScarfGo’s **dashboard-API** management surfaces into hermes-mobile (HTTP/WS only)
and add an **unsigned IPA + AltStore/Feather** distribution path. Daily driver stays
hermes-mobile; we do **not** migrate the Scarf codebase or add SSH.

## Context

hermes-mobile already covers chat, sessions, profiles, push, slash, queue, branching,
and cron list/pause/resume/trigger. Missing management value lives on the Hermes web
dashboard REST API:
https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard

ScarfGo (`dylanl321/scarf`) is reference-only for Serve clients and IPA scripts —
adapt names/bundle IDs; do not import ScarfCore.

Repo identity: `dylanl321/hermes-mobile`. Bundle id stays `me.honcharenko.HermesMobile`.

## Locked distribution constants (Phase D)

| Item | Value |
|------|--------|
| Scheme / product | `HermesMobile` → `HermesMobile.app` |
| Workspace | `HermesMobile.xcworkspace` (Tuist-generated; gitignored) |
| Bundle id | `me.honcharenko.HermesMobile` |
| Source id | `me.honcharenko.HermesMobile.sideload` |
| Rolling tag | `hermes-mobile-sideload` |
| Source URL | `https://github.com/dylanl321/hermes-mobile/releases/download/hermes-mobile-sideload/source.json` |
| IPA names | `HermesMobile-<ver>-<build>-unsigned.ipa` + stable `HermesMobile.ipa` |
| `minOSVersion` | `18.0` |
| CI runner | `macos-26` |
| Icon | `HermesMobile/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` |
| Screenshots | `screenshots/framed/01_chat.png` … `05_connect.png` |

CI must `tuist install && tuist generate` before `xcodebuild`. No Apple signing secrets.

## Endpoint → client → feature → UI map

### Phase D — Unsigned IPA + Feather (no Hermes API)

| Artifact | Location |
|----------|----------|
| Package script | `scripts/package-ios-ipa.sh` |
| Source writer | `scripts/write-sideload-source.py` |
| Workflow | `.github/workflows/ios-unsigned-ipa.yml` |
| Docs | `altstore/README.md` + README pointer |

### Phase 1 — Skills

| API | Client | Feature | UI |
|-----|--------|---------|-----|
| `GET /api/skills` | `skills` | `SkillsFeature` (Settings child) | Installed list + toggles |
| `PUT /api/skills/toggle` | `toggleSkill` | same | Toggle rows |
| `GET /api/skills/hub/search` | `searchSkillHub` | same | Hub search |
| `POST .../hub/install\|uninstall\|update` + action poll | `skillHubAction` / `actionStatus` | same | Progress / error |

Gate: 404 → `skillsSupported = false`. Profile: omit `"default"` (`scopedProfileName`).

### Phase 2 — Cron CRUD

| API | Client | Feature | UI |
|-----|--------|---------|-----|
| `POST /api/cron/jobs` | `createCronJob` | `SessionListFeature` | Create sheet |
| `PUT /api/cron/jobs/{id}` | `updateCronJob` | same | Edit sheet |
| `DELETE /api/cron/jobs/{id}` | `deleteCronJob` | same | Confirmation + `.bottomActionSheet` |

Keep list/pause/resume/trigger. Profile scoping parity with existing cron list.

### Phase 3 — Config quick edits + model

| API | Client | Feature | UI |
|-----|--------|---------|-----|
| `GET/PUT /api/config` | `config` / `putConfig` | `SettingsFeature` | Quick edits (curated keys) |
| `GET /api/model/*`, `POST /api/model/set` | model REST methods | Settings | Model picker |

No raw YAML. Chat keeps gateway `model.options` / `config.set`.

### Phase 4 — Multi-server (client-only)

Persist `{ id, label, baseURL }` in Preferences; auth per server in Keychain.
Switch → teardown live chat slot (logout policy) + clear foreign push tap state.

### Phase 5 — Home ops strip

Enrich `ServerStatus` with memory/disk pressure; `GET /api/analytics/usage`;
compact strip on session list. Gate analytics on 404.

### Phase 6 — API Keys / Env

| API | Client | Feature | UI |
|-----|--------|---------|-----|
| `GET /api/env` | `env` | `EnvFeature` (Settings child) | Catalog by category; search / Set only / Advanced |
| `PUT /api/env` | `putEnv` | same | SecureField overwrite sheet |
| `DELETE /api/env` | `deleteEnv` | same | Confirmation + `.bottomActionSheet` |
| `POST /api/env/reveal` | `revealEnv` | same | Optional; soft-gate on 401/403/404/405; 30s auto-clear |

Gate: 404/405 → `envSupported = false`. Reveal soft-gate → `revealSupported = false`
(list + overwrite still work). Profile: omit `"default"`. Never log reveal values /
full `/api/env` bodies.

### Phase 6+ (still deferred)

MCP, webhooks, kanban, memory provider/reset, curator/logs, messaging/pairing,
credential pool.

**Follow-on (shipped):** System / Host / Hermes update / gateway / ops — see
[`completed/2026-08-30-system-management-surface.md`](completed/2026-08-30-system-management-surface.md)
(Phases S1–S4). Remaining admin (S6a–g) still deferred.

## Capability-gate strategy

Reuse `RESTError.isMissingEndpointVerdict` (404 or 405). Flip `*Supported` silently.
Auth 401 keeps existing reconnect / `ReauthFeature` paths.

## Explicitly out of scope

- SSH / Citadel / SFTP / `~/.hermes/` filesystem / ACP
- Scarf projects, templates, fleet, mini-apps, companion SSH
- Full MEMORY.md / USER.md editors
- Apple Developer / ASC signing secrets in CI
- Raw YAML config editor in v1
- Changing push gateway/plugin architecture

## Test plan

| Phase | Tests |
|-------|--------|
| D | Python writer dry-run; workflow present |
| 1 | Decode fixtures; toggle/hub reducers; 404 gate; snapshot |
| 2 | Create/edit/delete reducers; profile parity |
| 3 | PUT round-trip; unknown keys ignored; 404 gate |
| 4 | Store round-trip; switch clears chat + push tap |
| 5 | Pressure decode; analytics 404; ops strip snapshot |
| 6 | Env catalog decode; put/delete/reveal client; 404 gate; reveal soft-gate; Env list snapshot |

Every phase: `make test`.

## Ship order

1. This plan (Phase 0)
2. Phase D PR
3. Phase 1 PR
4. Phases 2 → 5 as separate focused change sets (may land together when sequential)

## Manual checklist (DoD)

Sideload install → login → skills toggle → hub install → cron create → config quick
edit → model set → API Keys list/set/delete → multi-server switch → status/analytics
visible. Older Hermes without routes: features hidden, chat still works.
