# Meridian APRS — Roadmap

Each milestone represents a shippable increment with a focused scope. Features deferred beyond v1.0 are tracked in `docs/FUTURE_FEATURES.md`.

---

## Status

| Milestone | Focus | Status |
|---|---|---|
| v0.1 — Foundation | Flutter scaffold, map rendering, APRS-IS connection, basic station display | ✅ Complete |
| v0.2 — Packets | AX.25/APRS parser, packet log view, symbol rendering | ✅ Complete |
| v0.3 — TNC | KISS over USB serial, desktop platforms first | ✅ Complete |
| v0.4 — BLE | KISS over BLE, mobile platforms; KissTncTransport interface; TransportManager | ✅ Complete |
| v0.5 — Beaconing & Messaging | Manual/Auto/SmartBeaconing, one-to-one APRS messaging with retry, RF/APRS-IS TX toggle, My Station settings | ✅ Complete |
| v0.6 — Connection UI | Connection screen overhaul, segmented APRS-IS/BLE TNC/Serial TNC tabs, map polish | ✅ Complete |
| v0.7 — Android Background | MeridianConnectionService foreground service, persistent notification, bg packet capture + beaconing, auto-reconnect | ✅ Complete |
| v0.8 — Platform Parity | iOS Cupertino audit, Stadia Maps tile swap (TileProvider abstraction) | ✅ Complete |
| v0.9 — iOS Background | iOS background beaconing — background location + Live Activity | ✅ Complete |
| v0.10 — Map Experience | Viewport-adaptive APRS-IS filter, configurable time filter, track history polylines, map filters UI | ✅ Complete |
| v0.11 — Notifications | Background notifications, in-app banner system, notification preferences | ✅ Complete |
| v0.12 — Onboarding | BLE pairing flow in onboarding, APRS-IS connection before map, GPS centering on first launch, symbol picker + comment + location setup | ✅ Complete |
| v0.13 — Security | Passcode secure storage, APRS-IS filter configuration | ✅ Complete |
| v0.14 — Base-Callsign Matching | Capture-always cross-SSID message matching, addressee badges, conversation grouping | ✅ Complete |
| v0.17 — Groups & Bulletins | APRS group messaging (CQ/QST/ALL/custom), bulletins (BLN0-9 + named), matcher precedence, messaging tab restructure | ✅ Complete |
| v0.18 — Foundations | Architecture, testing, and dependency foundations that unblock subsequent performance, polish, and launch work | ✅ Complete |
| v0.19 — Performance | Performance pass — Selector adoption, MapScreen rebuild fix, ListView hygiene, SQLite spike, battery / memory / throughput baselines | — |
| v0.20 — Polish & A11y | Pre-launch polish — accessibility audit, iOS adaptive widget consistency, screen refactors, remaining widget tests | — |
| v0.21 — Classic Bluetooth SPP | Classic Bluetooth SPP transport for KISS TNCs on Android, Linux, Windows, macOS (iOS excluded by platform restriction) | — |
| v0.22 — Offline Maps | Offline tile caching for portable / field / SAR use without cell service, layered onto the existing `MeridianTileProvider` abstraction | — |
| v1.0 — Launch | Final release pipeline — Android signing, iOS App Group, release-build CI, physical-device validation, tocall bump, store submission | — |

> **v0.15 and v0.16 numbers are skipped.** They were used historically as the "Battery & Performance" and "Bug Triage" milestones; the 2026-04-25 reorganization split that scope across v0.18/v0.19/v0.20 and the numbers are not reused.

---

## Milestone Detail

### ~~v0.9 — iOS Background Beaconing~~ ✅

Bring iOS to parity with Android's background beaconing capability.

- ✅ Background location permission handling (`_IosBackgroundLocationPrompt` in settings, `IosBackgroundService._requestBackgroundLocationIfNeeded`)
- ✅ Background packet capture while app is backgrounded (`voip` + `bluetooth-central` UIBackgroundModes keep process alive)
- ✅ Position beaconing while backgrounded (`location` UIBackgroundMode + "Always" permission; `BeaconingService` continues on main isolate)
- ✅ Live Activity for persistent status on the Dynamic Island / Lock Screen (`live_activities` package, `MeridianLiveActivity` extension)
- ✅ Auto-reconnect for APRS-IS and BLE TNC transports in background (`ReconnectableMixin` on both connection types)

⚠️ **Apple Developer Portal prerequisite:** App Group `group.com.meridianaprs.meridianAprs` must be created and enabled on both `com.meridianaprs.meridianAprs` and `com.meridianaprs.meridianAprs.MeridianLiveActivity` before Live Activities function.

---

### ~~v0.10 — Map Experience~~ ✅

Make the map functional at real-world scale with adaptive data fetching, time-bounded display, and track history.

- ✅ Viewport-adaptive APRS-IS server-side filter — bounding box (`b/`) derived from visible map bounds with 25% padding and a 50 km minimum floor; replaces fixed 100/150 km radius filters; 500ms debounce on camera idle
- ✅ Configurable time filter for stale station pruning — default 1 hr, hard-cut (stations older than the window are removed from the map and station list); prune runs every 60s and immediately on setting change
- ✅ Track history per station ��� `TimestampedPosition` list per station (capped at 500 entries); position history polylines on the map, bounded by the active time filter window
- ✅ Map filters UI — time window picker and show/hide tracks toggle, accessible from the map screen via a filter FAB (mobile) or toolbar button (tablet/desktop); active filter chip shown on map surface when non-default window is set; Map section in Settings screen with time filter picker

---

### ~~v0.11 — Notifications~~ ✅
Keep operators informed when Meridian is in the background.

- ✅ `NotificationService` — main-isolate dispatch to `flutter_local_notifications` (Android/iOS/macOS) and `local_notifier` (Windows/Linux)
- ✅ Four notification channels registered: `messages`, `alerts`, `nearby`, `system`
- ✅ Android `BigTextStyle` single + `InboxStyle` grouped (3+ conversations) notifications
- ✅ Android inline reply via `RemoteInput` action; terminated-app replies via SharedPreferences outbox
- ✅ iOS inline reply via `UNTextInputAction` / `DarwinNotificationCategory`; foreground delivery via `presentAlert: true`
- ✅ `InAppBannerOverlay` at app root — slide-in banner with callsign/preview/timestamp; full-width mobile, 320 px top-right desktop
- ✅ Banner suppressed when `MessageThreadScreen` for that callsign is active
- ✅ `NotificationPreferences` model — per-channel enabled/sound/vibration, persisted to SharedPreferences, default-on for messages+alerts
- ✅ Notifications settings section — per-channel toggles with sound/vibration sub-toggles (mobile only)
- ✅ Cold-start navigation via `getNotificationAppLaunchDetails()` post-frame
- ✅ Global `navigatorKey` wired to all three `MaterialApp`/`CupertinoApp` variants
- ✅ Nav badge persistence verified (no-op: `unreadCount` was already serialized in `MessageService`)
- ✅ Unit tests: `NotificationPreferences` round-trip, banner dispatch logic, inline reply routing, reply outbox drain
- ✅ ADRs 035–038 in `docs/DECISIONS.md`

---

### ~~v0.12 — Onboarding Improvements~~ ✅

Made the first-launch experience complete and self-sufficient.

- ✅ 7-step onboarding flow: Welcome → License Status → Callsign+SSID → Location → Station Identity → Connection → Beaconing
- ✅ BLE TNC selection in onboarding triggers BLE pairing flow (`BleScannerSheet` reused)
- ✅ APRS-IS selection initiates connection before landing on map
- ✅ GPS permission request in Location step; `LocationPickerScreen` fallback if denied
- ✅ Symbol picker and comment field (36-char cap) in Station Identity step
- ✅ `isLicensed` field added to `StationSettingsService`; unlicensed path skips callsign + beaconing steps
- ✅ `TxService` hard-rejects TX when `isLicensed == false`; `AprsIsConnection` uses N0CALL/-1
- ✅ Messaging compose/reply disabled when unlicensed
- ✅ `SymbolPickerDialog` extracted to `lib/ui/widgets/` for reuse across onboarding and settings
- ✅ Existing-user migration guard: pre-v0.12 users with callsign set skip onboarding
- ✅ Persistence unification: all fields committed via `StationSettingsService` setters immediately on advance
- ✅ ADRs 042–045 in `docs/DECISIONS.md`

---

### ~~v0.13 — Security~~ ✅

Harden credential handling and network filtering.

- ✅ `SecureCredentialStore` abstraction backed by `flutter_secure_storage` — Android `EncryptedSharedPreferences`, iOS/macOS Keychain, Windows Credential Manager, Linux libsecret, web encrypted IndexedDB
- ✅ APRS-IS passcode migrated from plaintext SharedPreferences to platform secure storage; `_keyPasscode` removed from `StationSettingsService`
- ✅ `ConnectionCredentials` value object introduced in Connection Core — removes `StationSettingsService` upward-layer import from `AprsIsConnection` (audit #45)
- ✅ `LatLngBox` replaces `LatLngBounds` in `AprsIsConnection.updateFilter` — removes `flutter_map` UI-layer dependency from Connection Core (audit #45)
- ✅ `AprsIsFilterConfig` / `AprsIsFilterPreset` model — Local / Regional / Wide / Custom presets; pad fraction + minimum radius; no station-window (client-side time filter covers that)
- ✅ APRS-IS Filter Settings section (`lib/screens/settings/sections/aprs_is_filter_section.dart`) — `SegmentedButton` preset selector + collapsible Advanced sliders
- ✅ `SettingsScreen` section split — 1,823-line file extracted to per-section files in `lib/screens/settings/sections/` (audit #42)
- ✅ `TxTransportPref` enum fully removed — `TxService` routing is unconditional Serial > BLE > APRS-IS per ADR-029; per-message IS/RF toggle removed from `MessageThreadScreen` (audit #48)
- ✅ Android foreground service `foregroundServiceType` aligned with ADR-025 — `connectedDevice` added alongside `dataSync|location`; `FOREGROUND_SERVICE_CONNECTED_DEVICE` permission declared (audit #44)
- ✅ ADRs 047–052 in `docs/DECISIONS.md`

---

### v0.14 — Base-Callsign Message Matching

Operators running multiple SSID stations can receive and display messages addressed to any SSID of their callsign.

- Capture-always architecture: all messages to any SSID of the operator's base callsign are persisted regardless of display preferences
- `showOtherSsids` toggle (default off) — controls conversation list and thread visibility; toggling is instant and non-destructive
- `notifyOtherSsids` toggle (default off, dependent on `showOtherSsids`) — controls OS notifications for cross-SSID messages
- Cross-SSID notification copy: `W1ABC-9 → your -7: <body>` makes the mismatch explicit
- Addressee badge on incoming bubbles when `addressee ≠ currentStation` — subdued chip showing `→ -7`
- Conversation-list grouping by base callsign when 2+ threads share a base call — non-collapsible group headers with aggregated unread count
- ACK behavior unchanged: exact-match only, always; cross-SSID messages are never ACKed
- New Settings → Messaging category with both toggles and live-interpolated helper text
- `stripSsid` / `normalizeCallsign` utilities in `lib/core/callsign/` (APRS `-0` equivalence handled)
- ADR-054 in `docs/DECISIONS.md`

---

### v0.17 — Groups & Bulletins

Protocol-complete APRS messaging — group messages (`CQ`, `QST`, `ALL`, custom clubs) and bulletins (`BLN0`–`BLN9` general, `BLN*NAME` named), with a matcher precedence that keeps ACK correctness intact. See `docs/milestones/v0.17-groups-and-bulletins.md` for the per-PR breakdown.

- Addressee matcher with load-bearing precedence order **Bulletin → Direct → Group** (ADR-055) — a direct message to a specific SSID must always resolve as direct even when the group name happens to be a prefix of that callsign
- Group subscriptions (built-in `ALL`/`CQ`/`QST` seeded idempotently, plus custom) with per-group `notify` / `matchMode` / `replyMode` — pure client-side filter, no server protocol
- Bulletin receive store with `(source, addressee)`-keyed upsert, retention sweeper, transport union (`RF` ∪ `APRS-IS`)
- Outgoing bulletins with fixed-interval retransmission + initial pulse + max lifetime (ADR-057); edit body resets count; edit interval-only does not
- `BulletinScheduler` on the main isolate with an injectable clock; parallel 30 s bulletin timer in the background isolate reads `OutgoingBulletin` list from prefs each tick
- Messaging tab split into Direct / Groups / Bulletins via platform-adaptive segmented control (ADR-059); shared `ChatBubble` widget for visual parity across direct + group surfaces
- APRS-IS filter extension (ADR-058): `g/BLN0..9` always, `g/BLN*NAME` per enabled subscription, filter-rebuild on subscription change
- Client-side bulletin distance filter (haversine) against operator manual position; RF + named groups never distance-filtered
- New notification channels (built-in groups, custom groups, general bulletins, subscribed bulletin groups, expired) with broadcast-noisy defaults muted and explicit-subscribe defaults on
- ADRs 055 (matcher precedence), 056 (group architecture), 057 (bulletin transmission), 058 (filter + notifications), 059 (tab restructure), 060 (FGS type revert)

---

### v0.18 — Foundations

Architecture, testing, and dependency foundations that unblock the subsequent performance, polish, and launch work. Nothing here is user-visible on its own; all of it removes friction or risk from later milestones.

- ✅ Inject `Clock` abstraction so time-dependent logic is deterministic in tests (#43)
- ✅ Service-level test coverage for `BeaconingService` (#52)
- ✅ Service-level test coverage for `TxService` Serial > BLE > APRS-IS routing hierarchy (#60)
- ✅ BeaconFAB widget regression guard — pin start/stop semantics in auto/smart modes, long-press cooldown, "Xm ago" label (#86, split from #53)
- ✅ Dependency upgrade: `flutter_local_notifications` v18 → v21 paired with `desugar_jdk_libs` refresh (#54, absorbed #66)
- ✅ Pin `flutter_blue_plus` to v1.x — v2 is proprietary-licensed and GPL-incompatible (ADR-065, #55); replacement plugin tracked as a pre-1.0 blocker (#114)
- ✅ CI platform matrix — add Android / iOS / macOS / Windows builds alongside the existing Linux-debug build (#50)
- ✅ Architecture cleanup: remove double subscription to `conn.lines` between `main.dart` and `ConnectionRegistry` (#56)

---

### v0.19 — Performance

Performance pass — measurable baselines and the structural fixes that move the needle. Battery, memory, and packet throughput each get a baseline so v1.0 has a defensible "good enough" answer.

- MapScreen rebuild fix — stop the entire scaffold from rebuilding on every packet (#51)
- Selector convention — establish the `Selector<>` pattern across `Provider`-driven UI rather than the current single-site usage (#57)
- Non-builder `ListView` sweep — convert eager-inflate sites in SettingsScreen, PacketDetailSheet, and the PacketLogScreen filter bar (#58, absorbed #64)
- SQLite / drift evaluation spike — decision doc on persistence for stations, packets, and (follow-on) bulletins (#87)
- Background service battery drain — profiling report on Android + iOS, plus go/no-go on optimization sub-tasks (#88)
- Memory audit — stress-test station count target (5k stable), identify allocation hotspots, document baseline (#89)
- Packet processing throughput — establish baseline at ≥5 packets/second sustained, identify bottlenecks (#90)

---

### v0.20 — Polish & A11y

Pre-launch polish. The same surfaces being touched for accessibility and adaptive-widget cleanup are the ones that need pinning widget tests, so this milestone co-locates all three.

- Semantics audit — only 3 annotations exist in the codebase today; pass over all interactive widgets (#61)
- Adaptive widget consistency — `Switch.adaptive` / `CircularProgressIndicator.adaptive` etc. across iOS-rendered surfaces (#62)
- MapScreen helper extraction — `MapScreen.build()` is ~380 lines; extract helpers (#65)
- Widget tests — one-per-screen pass for PacketLogScreen, ConnectionScreen, MapScreen, Settings, Messaging tabs (#91, sibling of #86 in v0.18)

---

### v0.21 — Classic Bluetooth SPP

Add Classic Bluetooth SPP as a fourth transport alongside APRS-IS, BLE TNC, and Serial TNC. Unlocks a meaningful slice of installed-base hardware — APRS-capable HTs and mobiles with built-in or add-on classic Bluetooth, and older Bluetooth-equipped TNCs that predate BLE.

**Critical platform caveat — must be documented in this milestone's scope and in an ADR:** iOS does not allow third-party apps to speak Classic Bluetooth SPP to non-MFi-certified accessories. This is a platform restriction, not a Meridian limitation. Practical impact:

- Android, Linux, Windows, macOS — Classic BT SPP is implementable
- iOS — not possible from the app; iOS users with classic-BT-only hardware need an external BLE↔Classic bridge

Tooling notes:

- The current BLE library is BLE-only — does not cover classic SPP
- Android: existing third-party packages exist but are lightly maintained; a platform channel may be cleaner
- Desktop: each platform needs its own classic-BT integration
- An ADR will document the chosen approach and the iOS exclusion

Deliverables:

- New `ClassicBtTncTransport` implementing `KissTncTransport`, registered as a `MeridianConnection` peer of BLE / Serial
- Pairing UI in the Connection screen, parallel to `BleScannerSheet`
- Reuse of existing KISS framing, AX.25 decode, beaconing, and `ReconnectableMixin`
- Per-platform integration covering Android first, then Linux / Windows / macOS
- ADR documenting the platform-channel strategy and the iOS exclusion
- Settings copy / connection screen messaging that explains the iOS limitation rather than hiding it

---

### v0.22 — Offline Maps

Cache map tiles locally for portable / field / SAR use without cell service. The existing `MeridianTileProvider` abstraction was designed forward-looking for this — the current online provider stays as-is and the offline implementation sits alongside it as a separate provider rather than replacing it.

Deliverables:

- New offline `MeridianTileProvider` implementation — tile-storage format and rendering strategy to be decided and recorded in an ADR
- Per-region cache management UI — pick a bounding region, pick zoom range, download, see disk usage, evict
- Settings → Map → Offline section for cache policy, download status, and storage cap
- Online / offline provider selection logic — fall back to cached tiles when network is unreachable; user toggle to force offline
- Cache schema versioned so format changes don't silently corrupt user storage
- ADR documenting the tile-format and storage-location choice per platform
- Documentation entry in CAPABILITIES.md once shipped

---

### v1.0 — Launch

The release milestone — release pipeline, store readiness, and final field validation. No new features.

- Android release signing config (replace debug keystore + gitignored `key.properties`) (#46)
- iOS Live Activity App Group portal setup — `group.com.meridianaprs.meridianAprs` on both Runner and `MeridianLiveActivity` bundle IDs (#47)
- Release-build CI — ProGuard/R8/archive validation for Android and iOS (#63)
- Physical iPhone 16 Pro validation — Cupertino tier visual audit, iOS background beaconing, Live Activity, BLE TNC pairing (#92)
- Real-world Smart Beaconing drive test — validate cadence under mixed-speed driving, tune defaults if needed (#93)
- Tocall bump — `APMDN0` → next-tier `APMDN?` allocation as v1.0 ships (see Pending Items)
- Final CI/CD and release pipeline review; App Store + Play Store submission

> **v0.15 and v0.16 numbers are skipped** — see Status table.

---

## Backlog / Deferred

Items that were filed as issues but deferred without scheduling. Each is tracked in `docs/FUTURE_FEATURES.md` and re-graduates to a milestone when its trigger condition is met.

- **Feature flags scaffold** (formerly #49) — staged-feature configuration via `lib/config/feature_flags.dart`. Re-graduates when the first staged feature is scoped (Contacts, Digipeater, Weather, or Directed Queries).
- **CallsignDisplay seam** (formerly #59) — preemptive seam to centralize callsign rendering. Re-graduates when the Contacts feature is scheduled.

---

## Pending Items

- **Tocall:** `APMDN?` allocated via `aprsorg/aprs-deviceid` (2026-04-19, Hessu OH7LZB). `APMDN0` is the active tocall for v0.x. All `TODO(tocall)` markers removed; `AprsIdentity.tocall` is the canonical definition.
- **macOS/Windows serial TNC testing:** Deferred from v0.4. Still pending physical hardware validation.
- **Stadia Maps tier:** Free tier in use (non-commercial OSS). Upgrade to paid tier when monetization begins.
- **APRS Symbol Icon Set:** Deferred from v0.10. Standalone `meridian-aprs-symbols` repo (CC BY 4.0) — style guide, SVG generation, Figma polish, sprite sheets, integration into Meridian. Schedule TBD.

---

*Last updated: 2026-04-26*