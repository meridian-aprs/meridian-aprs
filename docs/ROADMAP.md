# Roadmap

## Summary

| Milestone | Focus | Status |
|---|---|---|
| v0.1 — Foundation | Flutter scaffold, map, APRS-IS, basic station display | 🔵 In Progress |
| v0.2 — Packets | AX.25/APRS parser, packet log, message decoding | ⬜ Planned |
| v0.3 — TNC | KISS over USB serial, desktop first | ⬜ Planned |
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
- [ ] Station info panel (callsign, symbol, last heard)

---

## v0.2 — Packets

Goal: Comprehensive APRS packet parsing and a packet log view.

- [ ] Full AX.25 frame parser (address, control, PID, info)
- [ ] APRS info field parser: position (all formats), message, object, item, weather, telemetry, status
- [ ] Packet log screen (raw + decoded view)
- [ ] Message thread view
- [ ] Unit test coverage for parser (Dire Wolf/aprslib test vectors)

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
