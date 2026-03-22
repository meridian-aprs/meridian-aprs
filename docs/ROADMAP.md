# Roadmap

## Summary

| Milestone | Focus | Status |
|---|---|---|
| v0.1 — Foundation | Flutter scaffold, map, APRS-IS, station display with symbols | ✅ Complete |
| v0.2 — Packets | AX.25/APRS parser, packet log, message decoding | ✅ Complete |
| UI Foundation | Theme system, adaptive scaffold, core widgets, onboarding | ✅ Complete |
| v0.3 — TNC | KISS over USB serial, desktop first | ✅ Complete |
| v0.4 — BLE | KISS over BLE, mobile platforms | ✅ Complete |
| v0.5 — Beaconing | Transmit path, position beaconing, message sending | ⬜ Planned |
| v1.0 — Polish | UI refinement, settings, documentation, onboarding | ⬜ Planned |

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

Goal: Transmit position beacons and send messages.

- [ ] AX.25/APRS encoder (position, message types)
- [ ] APRS-IS login with callsign + passcode
- [ ] Position beacon UI (manual + interval)
- [ ] Message compose and send
- [ ] Message ACK handling
- [ ] Passcode stored in platform secure storage (not plaintext)

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
