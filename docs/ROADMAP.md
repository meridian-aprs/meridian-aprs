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
| v0.11 — Map Filters & Stations | Map filters, station profiles | — |
| v0.12 — Map Enhancement | Track history, cluster markers, object/item display, altitude in position packets | — |
| v0.13 — Onboarding | BLE pairing flow in onboarding, APRS-IS connection before map, GPS centering on first launch, symbol picker + comment + location setup | — |
| v0.14 — Notifications | Background notifications, in-app banner system, notification preferences | — |
| v0.15 — Security | Passcode secure storage, APRS-IS filter configuration | — |
| v0.16 — Performance | Battery & performance optimization pass (motivated by background service drain) | — |
| v0.17 — Bug Triage | Dedicated triage and bugfix pass before final polish | — |
| v1.0 — Launch | Final polish, all-platform store submission (iOS App Store, Google Play, macOS, Windows, Linux) | — |

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

### v0.11 — Map Filters & Station Profiles
Core usability features that make the map manageable at scale.

- Filter by station type, symbol, distance, path, and more
- Named filter presets (save and recall)
- Station profile view — packet history, path info, heard-by digipeaters, message log
- Map tap → station profile flow

---

### v0.12 — Map Enhancement
Deeper map capabilities for tracking and situational awareness.

- Track history — display position history trails for stations
- Cluster markers at low zoom levels
- Object and item packet display
- Altitude field in outgoing position packets

---

### v0.13 — Onboarding Improvements
Make the first-launch experience complete and self-sufficient.

- BLE TNC selection in onboarding triggers BLE pairing flow
- APRS-IS selection initiates connection before landing on map
- Map centers on current GPS location (or manual coordinates) on first launch
- Onboarding: add symbol picker, comment field, and location setup steps

---

### v0.14 — Notifications
Keep operators informed when Meridian is in the background.

- Background notifications for incoming APRS messages
- In-app banner system for alerts
- Notification preferences screen

---

### v0.15 — Security
Harden credential handling and network filtering.

- Passcode stored in platform secure storage (Keychain / Keystore)
- APRS-IS server-side filter configuration UI

---

### v0.16 — Battery & Performance
Optimize for real-world sustained use.

- Profile and reduce background service battery drain
- Packet processing efficiency review
- Memory usage audit for large station counts
- Evaluate migrating station/packet persistence from SharedPreferences JSON blobs to SQLite (via `drift`): current flat-JSON approach is fine for hundreds of stations but will not scale to large history windows or dense RF environments; SQLite enables indexed bounding-box queries and avoids loading the full dataset into RAM on startup

---

### v0.17 — Bug Triage
Dedicated milestone for clearing the bug backlog before final polish.

- Triage all open `bug` issues
- Fix confirmed bugs prioritized by severity
- Regression test pass across platforms

---

### v1.0 — Launch
The release milestone. No new features — quality, stability, and store readiness only.

- Final UI polish pass across all platforms
- README and public documentation
- App Store (iOS) and Google Play submission
- macOS, Windows, Linux packaging
- Final CI/CD and release pipeline review

---

## Pending Items

- **Tocall:** `APMDNx` allocation filed via `aprsorg/aprs-deviceid`. Placeholder `APZMDN` with `TODO(tocall)` in use until confirmed.
- **macOS/Windows serial TNC testing:** Deferred from v0.4. Still pending physical hardware validation.
- **Stadia Maps tier:** Free tier in use (non-commercial OSS). Upgrade to paid tier when monetization begins.
- **APRS Symbol Icon Set:** Deferred from v0.10. Standalone `meridian-aprs-symbols` repo (CC BY 4.0) — style guide, SVG generation, Figma polish, sprite sheets, integration into Meridian. Schedule TBD.

---

*Last updated: 2026-04-11*