# Roadmap

## Summary

| Milestone | Goal |
|---|---|
| ~~v0.1 — Foundation~~ | ~~Flutter scaffold, map, APRS-IS, station display with symbols~~ ✓ |
| ~~v0.2 — Packets~~ | ~~AX.25/APRS parser, packet log, message decoding~~ ✓ |
| ~~UI Foundation~~ | ~~Theme system, adaptive scaffold, core widgets, onboarding~~ ✓ |
| ~~v0.3 — TNC~~ | ~~KISS over USB serial, desktop first~~ ✓ |
| ~~v0.4 — BLE~~ | ~~KISS over BLE, mobile platforms~~ ✓ |
| ~~v0.5 — Beaconing~~ | ~~Transmit path, position beaconing, message sending~~ ✓ |
| ~~v0.6~~ | ~~Connection UI + Map Polish~~ ✓ |
| ~~v0.7~~ | ~~Android Background Beaconing (foreground service + persistent notification)~~ ✓ |
| **v0.8** | Cross-platform parity pass (iOS Cupertino audit, OSM tile swap) |
| **v0.9** | iOS Background Beaconing (background location + Live Activity) |
| **v0.10** | Map filters + station profiles + track history + cluster markers + object/item display + altitude in position packets |
| **v0.11** | Background notifications + in-app banner system |
| **v0.12** | Security & connectivity (passcode secure storage, APRS-IS filter config) |
| **v0.13** | Battery & performance optimization pass |
| **v1.0** | Final polish + store submission |

---

## v0.1 — Foundation

Goal: A working app that connects to APRS-IS, receives packets, and plots stations on a map.

- [x] Flutter project created and pushed to GitHub
- [x] GitHub repo configured (labels, milestones, templates, CI)
- [x] CI pipeline running (flutter format, analyze, test)
- [x] `flutter_map` integrated with OSM tile layer
- [x] APRS-IS TCP connection established (`rotate.aprs2.net:14580`)
- [x] Basic station position parsing (plain/compressed lat/lon)
- [x] Station markers rendered on map
- [x] Station info panel (callsign, symbol, last heard)
- [x] APRS symbol extraction (symbolTable, symbolCode, comment) from position packets
- [x] SymbolResolver — maps table+code to human-readable name
- [x] Symbol-appropriate marker icons on map
- [x] Tap-to-show station info bottom sheet

---

## v0.2 — Packets

Goal: Comprehensive APRS packet parsing and a packet log view.

- [x] Full APRS parser with `AprsPacket` sealed class hierarchy (PositionPacket, WeatherPacket, MessagePacket, ObjectPacket, ItemPacket, StatusPacket, MicEPacket, UnknownPacket)
- [x] All DTI types supported: `!`, `=`, `/`, `@`, `;`, `)`, `:`, `_`, `>`, `` ` ``, `'`
- [x] Packet log screen (real-time scrolling, type filter chips, tap-to-detail)
- [x] PacketDetailSheet — full decoded field view with selectable raw packet line
- [x] AprsSymbolWidget — abstract symbol rendering widget, replaces inline symbolIcon helpers
- [x] StationService updated: `packetStream` + `recentPackets` (500-packet rolling buffer)
- [x] Unit test coverage: 92 tests passing (69 parser tests + existing suite)
- [ ] ~~Message thread view~~ — deferred to v0.3+

---

## UI Foundation

Goal: A complete design system, adaptive layouts, core widget library, settings screen, and first-launch onboarding flow — across all three platform form factors.

- [x] Theme system (token colors, light/dark/auto, ThemeProvider, SharedPreferences persistence)
- [x] Adaptive scaffold (MobileScaffold, TabletScaffold, DesktopScaffold, ResponsiveLayout)
- [x] MeridianMap widget — encapsulates flutter_map configuration, theme-aware tile URL
- [x] Core widget library (MeridianStatusPill, MeridianBottomSheet, StationListTile, BeaconFAB, CallsignField)
- [x] Settings screen shell (Appearance section functional — theme switching works; all other sections stubbed)
- [x] Onboarding flow (3-screen PageView, first-launch gated via SharedPreferences)
- [x] MapScreen updated to use ResponsiveLayout; service lifecycle remains in MapScreen
- [x] Three-tier platform theme architecture — Android (M3 Expressive + Dynamic Color), iOS (Cupertino), Desktop (M3 static brand) — all tiers complete

---

## v0.3 — TNC

Goal: Connect to a hardware TNC via KISS over USB serial on desktop.

- [x] KISS framing encode/decode (`KissFramer` — pure Dart)
- [x] AX.25 frame decoding (`Ax25Parser` — pure Dart)
- [x] USB serial transport via `flutter_libserialport` (`SerialKissTransport`)
- [x] TNC preset system (`TncPreset` / `TncConfig`) — provides the foundation for v0.4 BLE presets
- [x] Port selection UI (list available serial ports; `ConnectionSheet`)
- [x] Connection status indicator (TNC + APRS-IS dual pills)
- [x] Packets received via TNC appear on map/log
- [x] Linux, macOS, Windows targeted

---

## v0.4 — BLE

Goal: Connect to a BLE-capable TNC (e.g. Mobilinkd) on mobile. Extends the `TncPreset` system established in v0.3.

- [x] `KissTncTransport` abstract interface — raw AX.25 byte contract shared by serial and BLE
- [x] `TransportManager` — lifecycle holder for the active transport; bridges `frameStream` and `connectionState`
- [x] `SerialKissTransport` refactored to implement `KissTncTransport` (APRS parsing moved to service layer)
- [x] `BleTncTransport` — BLE KISS TNC via `flutter_blue_plus`; MTU negotiation; KISS chunking; `KissFramer` reassembly
- [x] `TncService` updated — owns `TransportManager`; parses AX.25 frames via `AprsParser.parseFrame`; exposes `connectBle()`
- [x] BLE device scan and pairing UI (`BleScannerSheet`)
- [x] `ConnectionSheet` updated — BLE section for iOS/Android, serial section for desktop
- [x] `MobileScaffold` — TNC status pill enabled on non-web mobile; dynamic `TransportType` label
- [x] Settings screen — BLE TNC section for iOS/Android
- [x] Onboarding — BLE TNC option card enabled on iOS/Android
- [x] Android BLE permissions (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`)
- [x] iOS Bluetooth usage descriptions (`NSBluetoothAlwaysUsageDescription`)
- [x] Tests: `BleTncTransport`, `TransportManager`, `TncService` (141 tests total)
- [ ] Physical device validation — iOS + Android with Mobilinkd TNC4 (pending hardware test)

---

## v0.5 — Beaconing

Goal: Transmit position beacons and send/receive APRS messages.

- [x] `AprsEncoder` — pure Dart APRS-IS text encoder (position, message, ACK, REJ)
- [x] `Ax25Encoder` — pure Dart AX.25 UI frame encoder (round-trips with `Ax25Parser`)
- [x] `SmartBeaconing` — pure Dart SmartBeaconing™ algorithm (interval + turn trigger)
- [x] `StationSettingsService` — My Station prefs (callsign, SSID, symbol, comment) with ChangeNotifier
- [x] `TxService` — global TX transport router (auto/APRS-IS/TNC preference, TNC disconnect events)
- [x] `BeaconingService` — Manual / Auto / SmartBeaconing™ modes, GPS via geolocator
- [x] `MessageService` — threaded conversations, APRS §14 retry scheduler, ACK/REJ handling, duplicate detection
- [x] Settings — My Station section (callsign, SSID, symbol, comment), Beaconing section (mode, interval, SmartBeaconing params, TX transport toggle)
- [x] BeaconFAB — last-beacon timestamp, mode label, long-press cooldown guard
- [x] Messages screens — thread list (`MessagesScreen`), chat thread (`MessageThreadScreen`), compose sheet
- [x] Scaffold nav — Messages destination wired on all three scaffolds; unread badge
- [x] TNC disconnect/reconnect banners in `MapScreen`
- [x] GPS platform permissions (Android, iOS, macOS)
- [x] Tests: 252 passing (encoder, AX.25 encoder, SmartBeaconing, MessageService, widget test)
- [ ] APRS-IS login with callsign + passcode (passcode field is in onboarding; TX auth deferred to v1.0)
- [ ] Passcode stored in platform secure storage — deferred to v1.0
- [ ] Physical device validation — TX beacon on APRS-IS + TNC (pending)

---

## v0.6 — Connection UI & Map Polish

Goal: Promote Connection to a first-class navigation destination; targeted map improvements.

**Status: Complete**

### feat/v0.6-connection-screen
- [x] `ConnectionNavIcon` widget — reactive nav icon (Selector2, signal/warning/muted)
- [x] `ConnectionScreen` — full-screen destination replacing `ConnectionSheet` modal
  - Active Connections section (APRS-IS + TNC cards, TX badge, Disconnect)
  - Platform-adaptive segmented control (CupertinoSlidingSegmentedControl/SegmentedButton)
  - APRS-IS tab (read-only server info, connect/disconnect)
  - BLE TNC tab (BleScannerSheet inline, lazy instantiation; connected state: "Connected — disconnect from the card above")
  - Serial TNC tab (port/baud/connect — desktop only)
- [x] Mobile: 5th nav destination (Connection); status pill taps navigate to tab
- [x] Tablet: Connection converted from transient sheet to real IndexedStack destination
- [x] Desktop: Connection converted from transient sheet to real destination; `_ConnectionStatusChip` in AppBar replaces dual status pills
- [x] `TncService.availablePorts()` wrapped in try-catch (safe in test environments without libserialport)
- [x] Widget test updated (StationService added to provider tree)
- [ ] Physical device validation

### feat/v0.6-map-polish
- [x] "Not connected" nudge chip overlay on map (AnimatedOpacity, tap → ConnectionScreen)
- [x] Station marker tap targets: 36 → 44 px
- [x] Connection screen UX: duplicate Disconnect buttons removed; BLE back-arrow fix (`showBackButton` param)
- [x] Callsign search — `StationSearchDelegate` (`SearchDelegate<Station?>`); Nominatim geocoding; `showSearch` integration; map pan on result
- [x] Center-on-location FAB — GPS on mobile/tablet via geolocator; desktop falls back to `LocationPickerScreen` address picker
- [x] `BeaconFAB` loading spinner while sending (`Future<void> onTap`, `_isSending` state)
- [x] Location button loading spinner on all three scaffold tiers
- [x] TX transport selector reflects effective transport (falls back when TNC disconnected, not stored preference)
- [x] TNC section removed from Settings screen (Connection screen is canonical)
- [x] `connection_sheet.dart` deleted (orphaned dead code)

---

## v0.7 — Android Background Beaconing

Goal: Keep transport connections and beaconing alive when Meridian is backgrounded on Android.

- [x] `flutter_foreground_task` + `permission_handler` added to pubspec.yaml
- [x] `android/app/build.gradle.kts` — minSdk bumped to 21
- [x] `AndroidManifest.xml` — `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `ACCESS_BACKGROUND_LOCATION`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED` permissions; foreground service element
- [x] `MeridianConnectionTask` (`lib/services/meridian_connection_task.dart`) — minimal `TaskHandler` (background isolate heartbeat, no app logic)
- [x] `BackgroundServiceManager` (`lib/services/background_service_manager.dart`) — ChangeNotifier; lifecycle + notification content + `BackgroundServiceState` enum; injectable `ForegroundServiceApi` for testing
- [x] `lib/main.dart` — `FlutterForegroundTask.initCommunicationPort()` + `BackgroundServiceManager.initOptions()` before `runApp`; `BackgroundServiceManager` in provider tree
- [x] `ConnectionScreen` — Android-only background service card (toggle + status pill + error message); reconnecting banner at top
- [x] `ConnectionNavIcon` — badge dot overlay when service is running/reconnecting
- [x] `test/services/background_service_manager_test.dart` — 15 unit tests (state machine, notification content, non-Android guard)
- [x] `widget_test.dart` — `BackgroundServiceManager` added to provider tree
- [x] ADR-025 (unified service via flutter_foreground_task) + ADR-026 (ACCESS_BACKGROUND_LOCATION flow)
- [ ] Physical Android device validation (see test checklist in prompt)

---

## v0.8 — Cross-Platform Parity

Goal: Replace public OSM tile URLs with Stadia Maps and complete the first real iOS Cupertino audit on physical hardware.

### Workstream A — Stadia Maps Tile Swap
- [x] `lib/map/meridian_tile_provider.dart` — abstract `MeridianTileProvider` interface
- [x] `lib/map/stadia_tile_provider.dart` — concrete `StadiaTileProvider` (`alidade_smooth` / `alidade_smooth_dark`)
- [x] `lib/config/app_config.dart` — `AppConfig.stadiaMapsApiKey` via `String.fromEnvironment`
- [x] `lib/screens/map_screen.dart` — wired to `StadiaTileProvider`; brightness resolved in `build()`
- [x] `lib/ui/layout/meridian_map.dart` — CartoDB subdomain + brightness-boost artifacts removed; `RichAttributionWidget` added for OSM/Stadia attribution
- [x] `.env.example` — developer key template (`.env` gitignored)
- [x] `CLAUDE.md` — Local Development section added
- [x] `.github/workflows/ci.yml` — `--dart-define=STADIA_MAPS_API_KEY` added to test + build steps
- [x] ADR-027 (tile provider decision)
- [ ] Physical device validation: light/dark tiles on Android, iOS, desktop

### Workstream B — iOS Cupertino Audit
- [x] `lib/ui/utils/platform_route.dart` — `buildPlatformRoute<T>()` helper (CupertinoPageRoute on iOS, MaterialPageRoute elsewhere)
- [x] All `TODO(ios): CupertinoPageRoute` sites resolved: `messages_screen.dart`, `settings_screen.dart` (×2), `compose_message_sheet.dart`, `station_info_sheet.dart`
- [x] `SwitchListTile` → `SwitchListTile.adaptive` (connection screen ×2, settings notifications stub)
- [x] `CircularProgressIndicator` → `CircularProgressIndicator.adaptive` across all scaffold/widget spinners (BLE scanner, mobile/tablet/desktop scaffold, connection screen, location picker, map connecting banner)
- [x] ADR-028 (iOS platform routing pattern)
- [ ] Discovery pass on iPhone 16 Pro — document punch list
- [ ] Settings → Appearance validation on iOS
- [ ] Safe area + Dynamic Island verification on iPhone 16 Pro
- [ ] Full re-test on iPhone 16 Pro

---

## v1.0 — Polish

Goal: Release-quality app with full onboarding and documentation.

- [ ] Settings screen (callsign, passcode, filter, map preferences)
- [ ] Onboarding flow (first-launch setup)
- [ ] App icon and splash screen (all platforms)
- [ ] APRS-IS server filter configuration
- [ ] Dark mode support
- [ ] User-facing documentation / help
- [ ] App Store / Play Store listings
- [ ] 1.0 release tag
