# Meridian APRS — Future Features

Features tracked here are planned but not yet committed to a milestone. They graduate to `docs/ROADMAP.md` when formally scheduled.

---

## Security / Credentials

### Raw APRS-IS Filter String Editor
Allow power users to type a raw APRS-IS filter string (e.g. `p/KM4/WX4 r/39.0/-77.0/100`) instead of using the preset UI. Explicitly out of scope for v0.13 — the preset + pad/radius model covers the vast majority of use cases and a raw editor adds significant validation surface.

### Biometric Unlock
Gate app launch or credential access behind fingerprint / face ID on platforms that support it. Useful when sharing a device. Blocked on evaluating `local_auth` plugin compatibility with `flutter_secure_storage`'s existing Keychain configuration.

### Credential Export / Import
Allow operators to export their credential set (callsign, passcode, settings) as an encrypted backup and import on a new device. Higher-effort feature; not needed before v1.0. See ADR-047 for the SecureCredentialStore abstraction that would underpin this.

### Web Platform Credential Hardening
Web credential storage currently uses browser-encrypted IndexedDB via `flutter_secure_storage` — not backed by a hardware element. A future improvement is to expose an explicit "web credentials are not hardware-protected" warning dialog on first launch on web, and optionally require a user passphrase to encrypt the store. Deferred until web is a first-class target.

---

## Onboarding / Licensing

### "I Got My License" Transition Flow
Allow a user who completed onboarding as unlicensed to upgrade to licensed mode from Settings — sets `StationSettingsService.isLicensed = true`, re-enables TX, re-configures APRS-IS credentials with real callsign/passcode. Currently requires re-running onboarding or manual `isLicensed` toggle in a debug menu. See ADR-044.

### Address / Geocoder Search in Location Step
Add address search to the onboarding Location step (and Settings location picker) using a geocoding API (e.g., Nominatim, which is already used for station search in `StationSearchDelegate`). Deferred from v0.12 because no geocoder is integrated for position entry yet — only station callsign search.

---

## High Priority (v1.1 candidates)

### TCP KISS TNC
Connect to a software TNC (Dire Wolf, soundmodem, or similar) over TCP on the local network. Enables a common workflow where a radio is attached to a desktop or Raspberry Pi running a software TNC, and Meridian on a phone or tablet connects to it over Wi-Fi. Config: hostname/IP + port (Dire Wolf default: 8001). Uses the same `KissTncTransport` interface and `ConnectionRegistry` as BLE and Serial connections — only the transport layer is new. Available on all platforms except web (no raw TCP sockets in browser; would need WebSocket bridging). `ReconnectableMixin` handles Wi-Fi drops.

### Offline Map Tile Caching
Cache OSM/Stadia tiles locally for use without internet connectivity. The TileProvider abstraction introduced in v0.8 is designed to support this. Relevant for field use where connectivity is limited.

### QRZ / HamDB Callsign Lookup
Tap a station callsign to pull operator info (name, location, license class) from QRZ.com or HamDB. Requires QRZ XML subscription for full data; HamDB is free but limited.

### Geo-fence Alerts
Notify the operator when a tracked station enters or exits a defined geographic area.

### Weather Overlay
Display APRS weather station data as a map overlay. Includes WX symbol stations and optionally NWS data.

---

## Medium Priority

### APRS Message Threading
Group messages by callsign into conversation threads with full history. (Basic one-to-one messaging ships in v0.5; threading is a polish layer on top.)

### Message Read Receipts / ACK Display
Surface ACK packets as delivery confirmation in the message UI. Status indicators: sent, acked, failed.

### CQSRVR / ANSRVR group server integration
Server-side group messaging via `CQSRVR` (registered group subscriptions with confirmations) and `ANSRVR` (announcement-only broadcast). Orthogonal to the client-side group filter shipped in v0.17 — these enable cross-region group chatter without each station having to be heard by everyone else's iGate.

### Sorted bulletin board view
APRSIS32-style sorted bulletin board (by source, slot, or group) in addition to the chronological feed. Would complement the v0.17 bulletins tab for operators who primarily use bulletins as a document store rather than a notification stream.

### Per-bulletin digipeater path overrides
Let outgoing bulletins choose a path different from the advanced-mode `bulletin_path` default. Needed when a club bulletin should go `WIDE1-1,WIDE2-2` but a high-rate status bulletin should go RF-only with no WIDEs.

### Group message search
Full-text search across received group messages (`CQ`, `QST`, custom clubs). Requires SQLite migration (v0.15) to be efficient at scale.

### Announcement messages (distinct from bulletins)
APRS announcement messages share the bulletin wire format but differ in semantic intent (one-shot rather than retransmitted). Low priority — handling them as first-class distinct from bulletins is a nuance most clients skip.

### Heard-By / Path Analysis
Visual breakdown of which digipeaters and iGates heard a given packet. Useful for path optimization.

### RF Path Optimizer
Suggest optimal WIDE path settings based on local digipeater coverage and observed packet paths.

### Object / Item Creation
Allow operators to place APRS objects and items on the map and transmit them. (Object/item *display* is in v0.12; creation is a separate transmit-path feature.)

---

## Lower Priority / Exploratory

### Satellite Pass Prediction
Integrate orbital data (TLE) to predict APRS-capable satellite passes (ISS, ARISS events).

### APRS-IS Tier 2 Server Selection
Let operators manually select or pin a specific APRS-IS Tier 2 server rather than using `rotate.aprs2.net`.

### Directed Query Support
Send and respond to APRS directed queries (`?APRS?`, `?WX?`, etc.).

### Voice Alert Integration
Play an audio alert on incoming messages or tracked station events. Platform TTS or custom audio.

### Dark Sky / NWS Severe Weather Alerts
Surface NWS severe weather alerts relevant to the operator's location on the map.

### Cross-Platform Sync
Sync settings, filter presets, and station notes across devices via iCloud / Google Drive.

### Web Platform
Full web client via Flutter Web + WebSocket APRS-IS proxy. Web Serial and Web Bluetooth are Chromium-only — acceptable and documented.

---

## Deferred Integrations

### HamAlert / DX Cluster
Integration with HamAlert or DX Cluster for operator activity notifications beyond APRS.

### Winlink Gateway Display
Show nearby Winlink RMS gateways on the map as a convenience layer for hybrid operators.

---

## Deferred Infrastructure

### Feature Flags Infrastructure
A `lib/config/feature_flags.dart` surface for staged features — gated rollout, per-build flags for in-progress work, and a clean kill-switch path. Closed without implementation as #49 because no current consumer exists; the absence of a feature in flight made the seam premature. Re-graduates to a milestone when the first staged feature is scoped — Contacts, Digipeater, Weather, or Directed Queries are the most likely triggers.

### CallsignDisplay Seam
A centralized widget (or formatter) for rendering callsigns consistently across the app — base call vs full call, SSID badges, license-class adornments, and contact-aware presentation. Closed without implementation as #59 because it was a preemptive shotgun-risk hedge with no consumer. Re-graduates when the Contacts feature is formally scheduled, which is the first feature that adds enough new callsign-presentation surfaces to justify centralizing.

---

*Last updated: 2026-04-25*