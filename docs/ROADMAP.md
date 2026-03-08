# Roadmap

## Summary

| Milestone | Focus | Status |
|---|---|---|
| v0.1 — Foundation | Flutter scaffold, map, APRS-IS, station display with symbols | ✅ Complete |
| v0.2 — Packets | AX.25/APRS parser, packet log, message decoding | ✅ Complete |
| v0.3 — TNC | KISS over USB serial, desktop first | ▶ In Progress |
| v0.4 — BLE | KISS over BLE, mobile platforms | ⬜ Planned |
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

## v0.3 — TNC

Goal: Connect to a hardware TNC via KISS over USB serial on desktop.

- [ ] KISS framing encode/decode
- [ ] USB serial transport via `flutter_libserialport`
- [ ] Port selection UI (list available serial ports)
- [ ] Connection status indicator
- [ ] Packets received via TNC appear on map/log
- [ ] Linux, macOS, Windows tested

---

## v0.4 — BLE

Goal: Connect to a BLE-capable TNC (e.g. Mobilinkd) on mobile.

- [ ] BLE transport via `flutter_blue_plus`
- [ ] BLE device scan and pairing UI
- [ ] KISS over BLE characteristic read/write
- [ ] iOS and Android tested
- [ ] Reconnect handling

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
