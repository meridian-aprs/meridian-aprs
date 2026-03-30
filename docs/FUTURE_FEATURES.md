# Future Features

Ideas and enhancements beyond the current milestone scope. Not committed to any release.

---

## Messaging

- **Group / bulletin messages** — APRS bulletin (`BLN`) and announcement (`BLN0`–`BLN9`) support; display in a separate Bulletins tab
- **Message search / archive** — local SQLite persistence of message history; search by callsign or keyword
- **Threaded replies** — link messages to a conversation with reply quoting, like a basic chat

---

## Beaconing

- **SmartBeaconing map overlay** — show the beacon path on the map with breadcrumb dots, fading with age
- **Compressed position encoding** — APRS compressed format for shorter packets on RF
- **Object / item TX** — create and transmit APRS objects and items (weather stations, repeaters, nets)

---

## Connection & Transport

- **TCP KISS TNC** — TCP KISS transport (e.g., Direwolf running on a network host)
- **Soundcard TNC** — integrate a pure-Dart or platform-native AFSK modem for RF TX/RX without dedicated hardware
- **Multi-server support** — failover between APRS-IS tier-2 servers

---

## Map & Stations

- **Weather overlays** — display weather station data (WX) on map with colour-coded temperature / wind
- **Offline tiles** — cache map tiles for offline use (MBTiles or similar)

---

## Platform & Polish

- **iPad multi-window** — support split-screen and Slide Over on iPad
- **macOS menu bar** — native menu bar integration for connection management
- **Keyboard shortcuts** — compose, send, beacon actions via keyboard on desktop
- **Localisation** — i18n framework; initial target: EN, DE, JA
