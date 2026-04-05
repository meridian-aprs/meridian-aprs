# Meridian APRS — Future Features

Features tracked here are planned but not yet committed to a milestone. They graduate to `docs/ROADMAP.md` when formally scheduled.

---

## High Priority (v1.1 candidates)

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

### Group / Bulletin Messages
Send and receive APRS bulletin and group messages (`BLN`, `NWS`, etc.). Explicitly deferred from v0.5 scope.

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

*Last updated: 2026-04-05*