# Meridian APRS — Capabilities

A consolidated reference of what Meridian can do today, organized by user-facing feature area. Use this as project context when planning future work — it answers "what's already shipped?" without searching the codebase or guessing.

> **Maintenance:** This document is generated and maintained by Claude Code as part of milestone close-out. When a milestone changes user-visible capabilities or platform behavior, update this file alongside `ROADMAP.md` and `DECISIONS.md`. Source of truth is the codebase, not aspiration — partially implemented or untested capabilities are flagged explicitly.

**Last updated:** 2026-04-26 (v0.18 Foundations shipped; v0.19 Performance next)

---

## 1. Connectivity / Transports

Three concurrent transports, each modeled as a `MeridianConnection` and registered with a single `ConnectionRegistry`. The registry is the single source of truth for connection state and available transports per platform.

| Transport | Platforms | Status |
|---|---|---|
| APRS-IS (direct TCP) | Android, iOS, macOS, Windows, Linux | Shipped (v0.1) |
| APRS-IS (WebSocket proxy) | Web | Architectural placeholder; proxy server not yet deployed |
| BLE TNC | Android, iOS | Shipped (v0.4); validated on common BLE-UART hardware |
| USB Serial TNC | macOS, Windows, Linux | Shipped (v0.3); Linux validated, macOS / Windows pending physical testing |

- **APRS-IS:** server `rotate.aprs2.net:14580`; user-overridable host/port; passcode in platform secure storage; viewport-adaptive bounding-box filter (`b/`) with 25 % padding and 50 km minimum radius
- **BLE TNC:** scan + connect from in-app sheet; Mobilinkd-compatible UART-over-BLE GATT profile; MTU-negotiated chunking; auto-reconnect via `ReconnectableMixin`
- **USB Serial TNC:** static preset registry of common TNC hardware; runtime KISS configuration
- **TX routing:** unconditional priority Serial > BLE > APRS-IS (ADR-029, ADR-051) — no per-message override
- **Per-connection beaconing toggle:** each connection has its own `beacon_enabled_<id>` preference

### Explicit non-support
- Classic Bluetooth SPP — planned v0.21 (not supported on iOS due to platform restriction)
- TCP KISS TNC (server software TNCs over LAN) — tracked in `FUTURE_FEATURES.md`
- AFSK soft-modem (audio over phone speaker / mic) — no plans
- AGW packet engine, KISS-over-IP variants beyond standard KISS-over-TCP

---

## 2. Packet Support

Pure-Dart parser dispatching on the APRS Data Type Identifier byte. Sealed `AprsPacket` hierarchy; parser never throws — falls back to `UnknownPacket` on error.

### Parsed and displayed
- **PositionPacket** — uncompressed and compressed; with/without timestamp; with/without messaging
- **MicEPacket** — Mic-E status, position, ambiguity, telemetry; vendor prefix/suffix decoded per spec
- **MessagePacket** — direct messages, ACKs, REJs; message-ID format `{NNN`
- **ObjectPacket** — APRS objects with live/killed flag
- **ItemPacket** — APRS items
- **StatusPacket** — text status reports
- **WeatherPacket** — weather report fields parsed and surfaced on station detail

### Parsed but minimally surfaced
- Capability flags (e.g., messaging-capable indicator on station sheet)
- Path / digipeater list

### Encoded for transmit
- Position (uncompressed, with/without messaging)
- Message + ACK + REJ
- Bulletins (group / named, with retransmission scheduling)
- Beacons via `BeaconingService`

### Explicit non-support
- Object / Item *creation* — display only (creation tracked in `FUTURE_FEATURES.md`)
- Telemetry packets (`T#`) — parsed as `UnknownPacket` today
- DX-cluster packets, NMEA passthrough, raw GPS sentences

### AX.25 Layer
- Pure-Dart UI-frame decoder; sealed `Ax25ParseResult` (`Ax25Ok` / `Ax25Err`); never throws
- Pure-Dart UI-frame encoder

### KISS Layer
- Pure-Dart KISS framer (stateful streaming + static encode)
- Standard KISS framing only — no extended KISS commands beyond TNC init/exit
- Hardware command `0x06` (SETHARDWARE) is intentionally never sent — interaction with some BLE TNCs is destabilizing

---

## 3. Map

| Capability | Detail |
|---|---|
| Tile rendering | `flutter_map` 8.x with a pluggable `MeridianTileProvider` abstraction |
| Online tile provider | Stadia Maps (`alidade_smooth` / `alidade_smooth_dark`); requires `STADIA_MAPS_API_KEY` via `--dart-define` |
| Offline tile provider | Not implemented (planned v0.22) |
| Station rendering | One marker per station; APRS symbol via `AprsSymbolWidget` (Material icons today; sprite sheet at v1.0) |
| Marker clustering | Not implemented (deferred) |
| Track history | Per-station `TimestampedPosition` list (capped 500); polylines rendered, time-window-bounded |
| Time filter | Configurable stale-station prune; default 60 min; hard-cut prune every 60 s |
| Viewport-adaptive APRS-IS filter | `b/` bounding box from visible map bounds; 25 % padding, 50 km minimum radius; 500 ms debounce on camera idle (ADR-033) |
| Filter UI | Filter FAB (mobile) / toolbar button (tablet, desktop); active-filter chip on map surface |
| Station search | `StationSearchDelegate` with Nominatim-powered place search and pan |
| Location picker | Standalone screen used in onboarding when GPS denied |

---

## 4. Messaging

| Capability | Detail |
|---|---|
| Direct messages | One-to-one APRS messaging with retry; spec §14 backoff `[30, 60, 120, 240, 480]` s |
| ACK / REJ | Sent and received; ACK is exact-callsign-match only |
| Cross-SSID matching | Capture-always: any message addressed to any SSID of operator's base callsign is persisted (ADR-054) |
| `showOtherSsids` | Default off; controls conversation list / thread visibility; non-destructive |
| `notifyOtherSsids` | Default off (gated by `showOtherSsids`); controls cross-SSID notifications |
| Addressee badge | Subdued chip on bubbles when `addressee ≠ currentStation` |
| Conversation grouping | Threads with 2+ SSIDs of the same base callsign render under a non-collapsible group header with aggregated unread count |
| Groups | `ALL` / `CQ` / `QST` seeded idempotently + custom; per-group `notify` / `matchMode` / `replyMode` (ADR-056) |
| Bulletins | `BLN0`–`BLN9` general and `BLN*NAME` named; receive store with `(source, addressee)` upsert and retention sweeper |
| Outgoing bulletins | Fixed-interval retransmission + initial pulse + max lifetime (ADR-057); main-isolate scheduler + parallel 30 s background-isolate timer |
| Bulletin distance filter | Client-side haversine vs operator manual position; RF + named groups never distance-filtered |
| APRS-IS group filter | `g/BLN0..9` always; `g/BLN*NAME` per enabled subscription (ADR-058); rebuilt on subscription change |
| Matcher precedence | Bulletin → Direct → Group (ADR-055) — load-bearing for ACK correctness |
| Messaging tabs | Direct / Groups / Bulletins via platform-adaptive segmented control (ADR-059) |
| Compose | 67-character body cap; CallsignField with regex validation |
| TX gating | Hard-blocked when `isLicensed == false`; APRS-IS uses `N0CALL/-1` silently for unlicensed users |

---

## 5. Beaconing & TX

| Capability | Detail |
|---|---|
| Beacon modes | `manual`, `auto` (fixed interval), `smart` (SmartBeaconing™) |
| SmartBeaconing | Adaptive rate via speed + heading-change threshold; `turnSlope` units = degrees·mph (ADR-021) |
| GPS source | `geolocator` package (foreground); platform background-location permission for backgrounded beaconing |
| Per-connection enable | `conn.beaconingEnabled` toggle; persisted as `beacon_enabled_<id>` |
| TX routing | Unconditional Serial > BLE > APRS-IS (ADR-029, ADR-051); no per-message override |
| Tocall | `APMDN0` (v0.x); `APMDN?` allocated for v1.0; `APMDNZ` reserved for dev/nightly |
| Manual beacon | One-tap via `BeaconFAB` while in `manual` mode |
| Long-press cooldown | Cooldown guard on `BeaconFAB` to prevent accidental rapid send |
| Status display | "Xm ago" since last beacon on FAB label |
| Object / Item TX | Not supported (display only) |

---

## 6. Station Management

- Real-time station list driven by `StationService` packetStream
- 500-packet rolling buffer in memory
- Full-screen station list screen
- Station detail sheet with summary (callsign, symbol, comment, last heard, capabilities)
- Per-station track history (capped at 500 timestamped positions, time-filter-bounded)
- Station search by callsign + place
- No persistent station database yet (SQLite/drift evaluation scheduled for v0.19)

---

## 7. Background Operation

| Platform | Strategy |
|---|---|
| Android | `flutter_foreground_task` foreground service; persistent notification; auto-reconnect; background packet RX + beaconing in a separate isolate (ADR-025, ADR-061) |
| iOS | Main isolate continues in background (ADR-032); `voip` + `bluetooth-central` + `location` `UIBackgroundModes`; Live Activity for Dynamic Island / Lock Screen status (ADR-030, ADR-031) |
| macOS | App keeps running while foregrounded; no background-specific lifecycle |
| Windows | Same |
| Linux | Same |
| Web | No background; tab-bound |

- **Layered defences for APRS-IS background RX (Android):** read-side idle watchdog, `SO_KEEPALIVE`, FGS heartbeat, 30 s background reconnect (ADR-061, Issue #76)
- **Background notifications:** delivered while app is backgrounded on Android, iOS, macOS; ✅ Android, ⚠ Issue #76 active for some APRS-IS scenarios
- **Live Activity (iOS):** structurally implemented; ⚠ requires App Group `group.com.meridianaprs.meridianAprs` setup in Apple Developer Portal before functioning (v1.0 task #47)

---

## 8. Notifications

Nine notification channels, persisted preferences, per-channel sound / vibration toggles.

| Channel | Default | Triggers |
|---|---|---|
| `messages` | On | Incoming direct messages |
| `alerts` | On | Connection / TX-path failure events |
| `nearby` | Off | Stations entering operator vicinity (currently inert; geo-fence tracked in `FUTURE_FEATURES.md`) |
| `system` | Off | Service lifecycle events |
| `groupsBuiltin` | Off | `ALL` / `CQ` / `QST` activity (broadcast-noisy by default) |
| `groupsCustom` | On | User-subscribed group activity |
| `bulletinsGeneral` | Off | Untargeted `BLN*` (broadcast-noisy by default) |
| `bulletinsSubscribed` | On | `BLN*NAME` for subscribed group names |
| `bulletinExpired` | On | Expiry of operator's outgoing bulletins |

- **In-app banner overlay** at app root — slide-in for 4 s, swipe-up dismiss, tap → message thread; full-width on mobile, top-right 320 px on desktop (ADR-036)
- **Inline reply** — Android via `RemoteInput`, iOS via `UNTextInputAction`; desktop inline reply not implemented (ADR-038)
- **Cold-start navigation** from a tapped notification routes directly to the relevant thread
- **Suppression** — banner is suppressed when `MessageThreadScreen` for the same callsign is already foregrounded
- **Backends** — `flutter_local_notifications` on Android / iOS / macOS; `local_notifier` on Windows / Linux

---

## 9. UI / Theming

Three-tier platform-adaptive theme system.

| Tier | Surface | Detail |
|---|---|---|
| Android | Material 3 Expressive (`m3e_design`) | Dynamic Color via `DynamicColorBuilder`; Meridian Purple seed fallback |
| iOS | Cupertino | `CupertinoThemeData`, Meridian Purple primary; structurally complete, pending physical-device validation |
| Desktop (macOS, Windows, Linux) | Static Material 3 | Fixed `MeridianColors.brandSeed`; no dynamic color |

- **Theme controller** persists `themeMode` and `seedColor` to SharedPreferences
- **Brand assets** auto-switch light / dark variant based on brightness (`MeridianIcon`, `MeridianWordmark`)
- **Wordmark** has horizontal and stacked layouts; mono variants explicit / fixed
- **Responsive layout** at 600 px and 1024 px breakpoints — `MobileScaffold`, `TabletScaffold`, `DesktopScaffold` (ADR-011)
- **Bottom-sheet patterns** via `MeridianBottomSheet`; status pill via `MeridianStatusPill`
- **Adaptive widgets** — `Switch.adaptive`, `CircularProgressIndicator.adaptive`; full audit pending (v0.20 #62)
- **iOS routing** — `buildPlatformRoute<T>()` switches `CupertinoPageRoute` vs `MaterialPageRoute` (ADR-028)

---

## 10. Security

- **`SecureCredentialStore`** abstraction backed by `flutter_secure_storage` — Android `EncryptedSharedPreferences`, iOS / macOS Keychain, Windows Credential Manager, Linux libsecret, web encrypted IndexedDB (ADR-047)
- **APRS-IS passcode** stored in platform secure storage — never SharedPreferences
- **`ConnectionCredentials`** value object — connection core never imports `StationSettingsService` directly (ADR-048)
- **Stadia Maps API key** — read from `--dart-define=STADIA_MAPS_API_KEY` at build; never committed; CI uses GitHub Actions secret
- **No telemetry** — no analytics SDK, no crash reporter, no remote logging
- **Web credentials** — encrypted IndexedDB but not hardware-backed; explicit warning UX deferred (`FUTURE_FEATURES.md`)

### Explicit non-support
- Biometric unlock — deferred (`FUTURE_FEATURES.md`)
- Credential export / import — deferred
- Per-launch passphrase — deferred

---

## 11. Settings

Master/detail Scaffold at ≥ 840 dp; push-nav at < 840 dp (ADR-053). Ten categories.

| Category | Highlights |
|---|---|
| My Station | Callsign, SSID, symbol, comment, location, licensed status |
| Beaconing | Mode, interval, SmartBeaconing parameters |
| Connections | Per-transport configuration; APRS-IS server override; APRS-IS filter preset |
| Map | Time filter window, show-tracks toggle, tile-provider selector |
| Notifications | Per-channel enabled / sound / vibration |
| Messaging | `showOtherSsids`, `notifyOtherSsids` cross-SSID toggles |
| History | Track-history retention controls |
| Appearance | Theme mode, seed color, light/dark assets |
| Advanced | Gated by `AdvancedModeController` (`advanced_user_mode_enabled`); exposes power-user toggles |
| About | Build version, license, attributions |

- **Advanced User Mode** — when enabled, surfaces power-user settings; "On" pill indicator on category list
- **Onboarding** — 7-step flow on first launch (Welcome → License → Callsign → Location → Identity → Connection → Beaconing); existing-user migration guard skips returning users

---

## 12. Platform Support Matrix

Y = supported, P = partial / pending validation, — = not supported.

| Capability | Android | iOS | macOS | Windows | Linux | Web |
|---|---|---|---|---|---|---|
| APRS-IS RX | Y | Y | Y | Y | Y | P (proxy not deployed) |
| BLE TNC | Y | Y | — | — | — | — |
| USB Serial TNC | — | — | P | P | Y | — |
| Classic BT SPP | Planned v0.21 | — (platform restriction) | Planned v0.21 | Planned v0.21 | Planned v0.21 | — |
| TX (beacon + message) | Y | Y | Y | Y | Y | P (depends on transport) |
| Background packet RX | Y | Y | — | — | — | — |
| Background beaconing | Y | Y | — | — | — | — |
| Live Activity | — | P (App Group setup pending) | — | — | — | — |
| Persistent notification | Y (FGS) | — (banner only) | — | — | — | — |
| In-app banner | Y | Y | Y | Y | Y | Y |
| Inline reply from notification | Y | Y | — | — | — | — |
| Dynamic Color | Y (Android 12+) | — | — | — | — | — |
| Map (online tiles) | Y | Y | Y | Y | Y | Y |
| Map (offline tiles) | Planned v0.22 | Planned v0.22 | Planned v0.22 | Planned v0.22 | Planned v0.22 | — |
| Secure credential storage | Y | Y | Y | Y | Y | P (no hardware element) |

---

## 13. Known Limitations / Explicit Non-Support

### Tracked, planned, deferred
- **Classic Bluetooth SPP** — v0.21
- **Offline maps** — v0.22
- **TCP KISS TNC** — `FUTURE_FEATURES.md`
- **Inter-app API** — `FUTURE_FEATURES.md`
- **NMEA-GPS bridge** for radios with internal TNCs — `FUTURE_FEATURES.md`
- **Object / Item creation** — `FUTURE_FEATURES.md` (display works)
- **Geo-fence alerts, weather overlay, callsign lookup, satellite pass prediction** — `FUTURE_FEATURES.md`
- **CQSRVR / ANSRVR server-side groups** — `FUTURE_FEATURES.md`
- **Sorted bulletin board** — `FUTURE_FEATURES.md`
- **Group message search** — needs persistence; `FUTURE_FEATURES.md`

### Not planned
- **AFSK soft-modem** (audio TNC via phone speaker / mic) — out of scope; hardware TNC required
- **Voice / repeater integration** — Meridian is data-mode only
- **HF / WSPR / digital-mode bridging** — out of scope
- **Built-in DX cluster / log integration** — out of scope (could surface via Inter-app API)

### Platform constraints
- **iOS Classic BT SPP** — blocked by Apple's MFi requirement; bridge hardware required for users with classic-BT-only radios
- **Web USB Serial / Web Bluetooth** — Chromium-only, deferred until web is a first-class target
- **Web TCP** — browsers don't expose raw TCP; APRS-IS over WebSocket proxy required
- **iOS background isolate** — Meridian uses the main isolate (ADR-032); no Android-style FGS available

---

## 14. Open Issues with Active User Impact

- **#76 Android background APRS-IS RX** — layered defences in place (ADR-061); ongoing observation. Symptom: silent stalls in APRS-IS read after long backgrounding.

---

## 15. Reference Inventory

- **Architecture overview:** `docs/ARCHITECTURE.md`
- **Decisions:** `docs/DECISIONS.md` (ADR-001 through ADR-061)
- **Roadmap:** `docs/ROADMAP.md`
- **Future features:** `docs/FUTURE_FEATURES.md`
- **Theming strategy:** `docs/THEME_PLATFORM_STRATEGY.md`
- **UI/UX spec:** `docs/UI_UX_SPEC.md`
- **Audit history:** `docs/AUDITS.md`

---

*This document should be reviewed and updated at every milestone close-out alongside `ROADMAP.md` and `DECISIONS.md`.*
