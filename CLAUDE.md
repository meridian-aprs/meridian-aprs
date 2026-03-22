# Meridian APRS — Project Brief for Claude Code Agents

**Tagline:** APRS for the Modern Ham
**Repo:** https://github.com/epasch/meridian-aprs
**Domains:** meridianaprs.com / meridianaprs.app
**License:** GPL v3

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (stable channel) |
| Map | flutter_map + OpenStreetMap tiles |
| BLE | flutter_blue_plus |
| Serial/USB | flutter_libserialport |
| APRS-IS | Direct TCP to `rotate.aprs2.net:14580` (WebSocket proxy on web) |
| Packet parsing | Pure Dart (no FFI for core logic) |

---

## Architecture Layers

```
UI Layer          →  lib/ui/, lib/screens/
Service Layer     →  lib/services/
Packet Core       →  lib/core/packet/, lib/core/ax25/
Transport Core    →  lib/core/transport/
Platform Channels →  platform-specific code (android/, ios/, etc.)
```

Each layer depends only on layers below it. The Packet Core has no platform dependencies — it is pure Dart and must remain so.

**Transport strategy by platform:**
- Mobile (iOS/Android): APRS-IS TCP, KISS/BLE
- Desktop (Linux/macOS/Windows): APRS-IS TCP, KISS/USB serial
- Web: APRS-IS via WebSocket proxy (direct TCP not available in browser)

See `docs/ARCHITECTURE.md` for full detail.

---

## Milestone Roadmap

| Milestone | Focus |
|---|---|
| v0.1 — Foundation | Flutter scaffold, map rendering, APRS-IS connection, basic station display |
| v0.2 — Packets | AX.25/APRS parser, packet log view, message decoding |
| v0.3 — TNC | KISS over USB serial, desktop platforms first |
| v0.4 — BLE | KISS over BLE, mobile platforms |
| v0.5 — Beaconing | Transmit path, position beaconing, message sending |
| v1.0 — Polish | UI refinement, settings, documentation, onboarding |

**Current status: v0.3 TNC merged. Three-tier platform theme architecture complete — Android (M3 Expressive + Dynamic Color), iOS (Cupertino, pending iOS simulator validation), Desktop (M3 static brand). All three tiers implemented; desktop branch at app root active on Linux/macOS/Windows.**

See `docs/ROADMAP.md` for per-milestone task breakdowns.

---

## Reference Projects

These are used as **logic references only**. Do not copy code from them.

| Project | Language | Notes |
|---|---|---|
| Dire Wolf | C | TNC, AX.25, APRS decoding reference |
| APRSDroid | Kotlin/Java | Android APRS client, connection model reference |
| aprslib | Python | Clean APRS parser — logic reference |
| Xastir | C | Feature-complete APRS client, comprehensive packet type coverage |

---

## GitHub Workflow Conventions

**Branch naming:**
- `feat/<short-description>` — new features
- `fix/<short-description>` — bug fixes
- `docs/<short-description>` — documentation only
- `infra/<short-description>` — CI, tooling, repo config

**Labels:** Use the full label taxonomy (Type + Area + Priority + Status). Every issue and PR should have at least one label from each of Type and Status.

**Milestones:** Assign every issue and PR to the appropriate milestone.

---

## Agent Team

Project-scoped sub-agents are defined in `.claude/agents/`. Delegate to them by name:

| Agent | When to use |
|---|---|
| `meridian-core` | Cross-cutting architectural decisions, ADR logging, CLAUDE.md updates, refactoring that spans multiple layers |
| `meridian-packet` | AX.25 and APRS packet parsing, decoding, encoding — `lib/core/packet/`, `lib/core/ax25/`, `test/packet/` |
| `meridian-transport` | APRS-IS TCP, KISS/USB serial, KISS/BLE, transport abstractions — `lib/core/transport/` |
| `meridian-ui` | All UI work — screens, widgets, map integration, design system — `lib/ui/`, `lib/screens/` |
| `meridian-infra` | CI/CD, GitHub configuration, tooling, automation — `.github/` |

---

## Docs Maintenance

Keep these files current as the project evolves:

- `docs/ARCHITECTURE.md` — update when layers or platform strategy changes
- `docs/DECISIONS.md` — add an ADR for every significant architectural decision
- `docs/ROADMAP.md` — mark tasks complete, add tasks as scope clarifies

---

## Rules for All Agents

- No credentials, API keys, or sensitive info in any committed file
- No copying code from reference projects — logic reference only
- Pure Dart for all packet core logic (no FFI in `lib/core/`)
- Follow existing Flutter/Dart conventions in the codebase
- Run `flutter analyze` and `flutter test` before considering any task done

---

## UI Components Inventory

### Theme System (`lib/theme/`) — Three-Tier Platform Architecture

All three tiers fully implemented. iOS pending simulator validation.

| File | Class | Description |
|---|---|---|
| `meridian_colors.dart` | `MeridianColors` | Brand color constants: `primary`, `primaryDark`, `signal`, `warning`, `danger` |
| `theme_controller.dart` | `ThemeController` | ChangeNotifier for `themeMode` + `seedColor`; persists both to SharedPreferences |
| `android_theme.dart` | `buildAndroidTheme()` | Builds Android ThemeData pair; uses `DynamicColorBuilder` schemes or seed fallback; applies M3 Expressive via `m3e_design` |
| `ios_theme.dart` | `buildIosTheme()` | Returns `CupertinoThemeData` for given brightness; `primaryColor` = Meridian Blue; structurally complete, pending iOS simulator validation |
| `desktop_theme.dart` | `buildDesktopTheme()` | Returns M3 static brand ThemeData pair; fixed `MeridianColors.primary` seed; no dynamic color; Windows/macOS/Linux |

### Layout System (`lib/ui/layout/`)

| File | Class | Description |
|---|---|---|
| `meridian_map.dart` | `MeridianMap` | Encapsulates flutter_map; accepts `mapController`, `markers`, `tileUrl` |
| `mobile_scaffold.dart` | `MobileScaffold` | Full-screen map + FAB cluster + bottom sheets (< 600 px) |
| `tablet_scaffold.dart` | `TabletScaffold` | Collapsed NavigationRail + map + bottom panel (600–1024 px) |
| `desktop_scaffold.dart` | `DesktopScaffold` | Extended NavigationRail (240 px) + map + side panel (> 1024 px) |
| `responsive_layout.dart` | `ResponsiveLayout` | Selects scaffold by `MediaQuery` width; breakpoints 600 px and 1024 px |

### Widget Library (`lib/ui/widgets/`)

| File | Class | Description |
|---|---|---|
| `aprs_symbol_widget.dart` | `AprsSymbolWidget` | APRS symbol rendering; Material icons now, sprite sheet at v1.0 |
| `beacon_fab.dart` | `BeaconFAB` | Large FAB; idle=primary blue, beaconing=danger red + pulse animation |
| `callsign_field.dart` | `CallsignField` | Validated callsign TextFormField; regex + inline error |
| `meridian_bottom_sheet.dart` | `MeridianBottomSheet` | Draggable bottom sheet with drag handle; theming wrapper |
| `meridian_status_pill.dart` | `MeridianStatusPill` | Connection status pill; green/amber/red dot + label; pulsing on connecting |
| `packet_detail_sheet.dart` | `PacketDetailSheet` | Full decoded packet field view + selectable raw line |
| `station_info_sheet.dart` | `StationInfoSheet` | Station summary bottom sheet (callsign, symbol, comment, last heard) |
| `station_list_tile.dart` | `StationListTile` | ListTile for station list; symbol + callsign + relative timestamp |

### Screens (`lib/screens/`)

| File | Class | Description |
|---|---|---|
| `map_screen.dart` | `MapScreen` | Root screen; owns StationService lifecycle; delegates to ResponsiveLayout |
| `packet_log_screen.dart` | `PacketLogScreen` | Real-time packet list; type filter chips; tap → PacketDetailSheet |
| `settings_screen.dart` | `SettingsScreen` | Settings screen; Appearance (theme) functional; all others stubbed |
| `onboarding/onboarding_screen.dart` | `OnboardingScreen` | 3-page PageView; shown on first launch; saves onboarding_complete flag |
| `onboarding/onboarding_welcome_page.dart` | `OnboardingWelcomePage` | Page 1: logo, tagline, Get Started / skip |
| `onboarding/onboarding_callsign_page.dart` | `OnboardingCallsignPage` | Page 2: CallsignField, SSID picker, passcode field |
| `onboarding/onboarding_connect_page.dart` | `OnboardingConnectPage` | Page 3: APRS-IS / BLE / USB option cards, Start Listening |
| `connection_sheet.dart` | `ConnectionSheet` | Two-section connection management sheet (APRS-IS status + TNC preset/port/connect); replaces stubs in all three scaffolds |

---

## Service Layer (`lib/services/`, `lib/core/transport/`, `lib/core/ax25/`)

### Transport and TNC files (v0.3+)

| File | Class / Symbol | Description |
|---|---|---|
| `lib/core/transport/tnc_preset.dart` | `TncPreset` | Immutable static preset model + `TncPreset.all` registry of known TNC hardware |
| `lib/core/transport/tnc_config.dart` | `TncConfig` | Runtime serial + KISS configuration; `fromPreset` factory; `toPrefsMap`/`fromPrefsMap` for SharedPreferences persistence |
| `lib/core/transport/kiss_framer.dart` | `KissFramer` | Pure Dart KISS framer; stateful `addBytes` stream processor; static `encode` method |
| `lib/core/ax25/ax25_parser.dart` | `Ax25Parser` | Pure Dart AX.25 UI frame decoder; sealed `Ax25ParseResult` (`Ax25Ok` \| `Ax25Err`); never throws |
| `lib/core/transport/serial_kiss_transport.dart` | `SerialKissTransport` | Implements `AprsTransport`; platform-conditional export; desktop only (Linux/macOS/Windows) |
| `lib/services/tnc_service.dart` | `TncService` | ChangeNotifier; owns `SerialKissTransport` lifecycle; bridges decoded lines to `StationService.ingestLine` |

---

## Branching & PR Conventions

- All feature work happens on feature branches, never directly on `main`
- Branch naming: `feat/<short>`, `fix/<short>`, `docs/<short>`, `infra/<short>`
- v0.1 feature branches: `feature/v0.1-scaffold`, `feature/packet-core-tests`, `feature/aprs-is-connection`
- One logical unit of work per branch
- PRs to `main` with description + test coverage summary
- `main` must always pass CI (format, analyze, test)
