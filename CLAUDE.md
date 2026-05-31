# Meridian APRS — Project Brief for Claude Code Agents

**Tagline:** APRS for the Modern Ham
**Repo:** https://github.com/epasch/meridian-aprs
**Domains:** meridianaprs.com / meridianaprs.app
**License:** GPL v3

This file is the durable **index** for agents — rules, conventions, and pointers. It deliberately does **not** mirror the code, the file layout, or the roadmap, because those rot. For current state, read the source of truth directly:

| Question | Authoritative source |
|---|---|
| What does Meridian do today? | `docs/CAPABILITIES.md` |
| How is it structured? | `docs/ARCHITECTURE.md` |
| Why was it built this way? | `docs/DECISIONS.md` (ADRs) |
| What's planned, and in what order? | `docs/ROADMAP.md` |
| What's deferred past v1.0? | `docs/FUTURE_FEATURES.md` |
| What's the file / symbol layout? | the code itself (+ `docs/ARCHITECTURE.md`) |

When you change behavior, **update those docs and point at them** — don't re-describe them here.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (stable channel) |
| Map | flutter_map + OpenStreetMap tiles |
| BLE | universal_ble (BSD-3-Clause; replaced flutter_blue_plus per ADR-068, after the v2 GPL-incompatibility of ADR-065) |
| Serial/USB | flutter_libserialport |
| APRS-IS | Direct TCP to `rotate.aprs2.net:14580` (WebSocket proxy on web) |
| Packet parsing | Pure Dart (no FFI for core logic) |
| Persistence | drift / SQLite (`meridian.db`) for structured data; SharedPreferences for flat settings (ADR-067) |
| Android background | flutter_foreground_task (foreground service keepalive) |
| Permissions | permission_handler (background location, notifications) |

Full dependency rationale and the platform transport matrix live in `docs/ARCHITECTURE.md`.

---

## Architecture Layers

```text
UI Layer          →  lib/ui/, lib/screens/
Service Layer     →  lib/services/
Persistence       →  lib/database/ (drift/SQLite — DAOs, tables)
Packet Core       →  lib/core/packet/, lib/core/ax25/
Transport Core    →  lib/core/transport/
Platform Channels →  android/, ios/, linux/, macos/, windows/, web/
```

Each layer depends only on layers below it. The **Packet Core is pure Dart** — no platform imports, no FFI — and must remain so, so it runs identically on all six platforms including web.

**Transport strategy by platform:**
- Mobile (iOS/Android): APRS-IS TCP, KISS/BLE
- Desktop (Linux/macOS/Windows): APRS-IS TCP, KISS/USB serial
- Web: APRS-IS via WebSocket proxy (browsers cannot open raw TCP)

---

## Current Status

**v0.21 shipped on Android (Classic Bluetooth SPP — native RFCOMM channel, ADR-069; hardware-validated on a TH-D75; desktop deferred). Next: v0.22 — Polish & A11y.**

The full milestone list, per-task breakdowns, and completion state live in `docs/ROADMAP.md`; architectural decisions in `docs/DECISIONS.md` (ADRs 001–068). Do not duplicate that state here.

> v0.15 / v0.16 milestone numbers are retired (the historical "Battery & Performance" / "Bug Triage" milestones) and are not reused.

---

## Rules for All Agents

- No credentials, API keys, or sensitive info in any committed file.
- **Reference projects are logic references only — never copy code from them.** Do not name external reference projects in shipped code, comments, ADRs, or docs; attribution lives solely on the dedicated licensing page.
- Pure Dart for all packet core logic (no FFI in `lib/core/`).
- Follow the existing Flutter/Dart conventions already in the codebase.
- Run `flutter analyze` and `flutter test` before considering any task done; run `dart format .` before committing or opening a PR.

---

## Conventions

- `TODO(ios)` — marks `MaterialPageRoute` calls that should become `CupertinoPageRoute` once the iOS theme is validated.

**Branches:** `feat/` (features), `fix/` (bug fixes), `docs/` (documentation), `infra/` (CI/tooling/repo config). One logical unit of work per branch; feature work never lands directly on `main`.

**PRs:** open against `main` with a description and a test-coverage summary. `main` must always pass CI (format → analyze → test).

**Issues & PRs:** use the full label taxonomy (Type + Area + Priority + Status — at least one Type and one Status each), and assign every issue and PR to its milestone.

---

## Docs Maintenance

Keep these current as the project evolves — they are the source of truth this file points to:

- `docs/ARCHITECTURE.md` — update when layers or platform strategy change
- `docs/DECISIONS.md` — add an ADR for every significant architectural decision
- `docs/ROADMAP.md` — mark tasks complete; add tasks as scope clarifies
- `docs/FUTURE_FEATURES.md` — graduate items to `ROADMAP.md` when they get a milestone; add new items as they surface
- `docs/CAPABILITIES.md` — the authoritative "what does Meridian do today?" reference; update at every milestone close-out alongside ROADMAP and DECISIONS

---

## Local Development

### Map Tiles
Stadia Maps serves the map tiles and requires an API key. The key is never committed — see `.env.example` for the template.

```bash
flutter run --dart-define=STADIA_MAPS_API_KEY=your_key_here
```

For CI/CD, set `STADIA_MAPS_API_KEY` as a GitHub Actions secret.

---

## Project Agents

Project-specific Claude Code sub-agents may live locally in `.claude/agents/` (gitignored — not part of the repo). They are optional helpers; nothing in the workflow depends on them being present.
