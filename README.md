<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/wordmarks/wordmark-horizontal-primary-dark.png">
    <img src="assets/wordmarks/wordmark-horizontal-primary.png" alt="Meridian APRS" height="120">
  </picture>
</p>

> **APRS for the Modern Ham.**

Meridian is an open-source, cross-platform APRS client built with Flutter. It brings Automatic Packet Reporting System to a clean, modern interface — whether you're tracking stations on a map, messaging other operators, or beaconing your position via a TNC or APRS-IS.

[![Build](https://img.shields.io/github/actions/workflow/status/epasch/meridian-aprs/ci.yml?branch=main&style=flat-square)](https://github.com/epasch/meridian-aprs/actions)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue?style=flat-square)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter)](https://flutter.dev)
![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-lightgrey?style=flat-square)

---

## Brand

<img src="assets/icons/reference-master-1024.png" alt="Meridian icon" width="128">

Primary brand color: `#4D1D8C` — a saturated, warm-leaning purple. Icon assets live in `assets/icons/`; platform launcher icons are generated from there via `dart run flutter_launcher_icons`.

---

## Screenshots

> 📸 *Screenshots coming soon.*

---

## Features

- **Live map** — Real-time station positions on Stadia Maps tiles, with track history, time filtering, marker clustering, and station-type filters
- **APRS-IS** — Direct connection to the APRS Internet Service network
- **KISS TNC** — USB serial and Bluetooth LE TNC support
- **Full packet parsing** — AX.25/APRS decoder in pure Dart (Mic-E, objects, messages, weather, and more)
- **Position beaconing** — SmartBeaconing™, fixed interval, and manual transmit modes
- **APRS messaging** — One-to-one messaging with retry and ACK handling, plus groups (CQ/QST/ALL/custom) and bulletins (BLN0–9 + named)
- **Notifications** — Background notifications and in-app banners for incoming messages
- **Durable storage** — Stations, messages, and packet log persist across restarts (SQLite)
- **Secure credentials** — APRS-IS passcode stored in the platform keystore
- **Native UI** — Material 3 on Android, Cupertino on iOS, adaptive desktop layouts
- **Background beaconing** — Keeps your position transmitting even when the app is backgrounded, on both Android (foreground service) and iOS (background location + Live Activity)

---

## Supported Platforms

| Platform | Status |
|----------|--------|
| Android  | ✅ Supported |
| iOS      | ✅ Supported |
| macOS    | ✅ Supported |
| Windows  | ✅ Supported |
| Linux    | ✅ Supported |
| Web      | ⚠️ Partial — APRS-IS via WebSocket proxy; Web Serial and Web Bluetooth are Chromium-only |

> **Web credential note:** On the web platform, the APRS-IS passcode is stored in browser-encrypted IndexedDB (via the Web Crypto API) rather than a hardware-backed keystore. This offers lower tamper-resistance than native OS keystores on Android, iOS, macOS, Windows, and Linux. The web platform is a secondary target.

---

## Licensing Notice

> ⚠️ A valid amateur radio license is required to **transmit** — both over RF and via APRS-IS. APRS-IS packets can be gated to RF by iGates, so the same rules apply. Receiving and monitoring packets is open to everyone — no license needed. Know the rules in your region before transmitting.

---

## Hardware Compatibility

Meridian has been tested with the following hardware:

| Device | Connection | Platform | Status |
|--------|------------|----------|--------|
| Mobilinkd TNC4 | Bluetooth LE | Android, iOS | ✅ Tested |
| Mobilinkd TNC4 | USB Serial | Linux | ✅ Tested |

Beyond the tested devices above, Meridian auto-recognizes a range of known BLE-KISS hardware — Mobilinkd TNC3/TNC4, PicoAPRS, B.B. Link, BTECH UV-Pro, Vero VR-N76/VR-N7500, Radioddity GA-5WB, and ESP32-based KISS TNCs — surfacing friendly model names during Bluetooth setup.

Additional TNC hardware will be tested and added as the project matures. If you've tested Meridian with other hardware, feel free to open an issue.

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel, 3.x or later)
- Dart SDK (bundled with Flutter)
- A connected APRS-IS account or a KISS TNC (e.g. Mobilinkd TNC4)

### Clone and Run

```bash
git clone https://github.com/epasch/meridian-aprs.git
cd meridian-aprs
flutter pub get
flutter run --dart-define=STADIA_MAPS_API_KEY=your_key_here
```

> A free [Stadia Maps](https://stadiamaps.com) API key is required for map tiles. See `.env.example` for setup instructions.

To target a specific platform:

```bash
flutter run --dart-define=STADIA_MAPS_API_KEY=your_key_here -d macos
flutter run --dart-define=STADIA_MAPS_API_KEY=your_key_here -d android
flutter run --dart-define=STADIA_MAPS_API_KEY=your_key_here -d linux
```

### Build

```bash
flutter build apk          # Android
flutter build ios          # iOS (requires macOS + Xcode)
flutter build macos        # macOS
flutter build windows      # Windows
flutter build linux        # Linux
```

---

## Roadmap

| Milestone | Status |
|-----------|--------|
| v0.1 – v0.19 — Foundation through performance | ✅ Complete |
| v0.20 — BLE plugin replacement (GPL-compatible) | 🔜 Next |
| v0.21 — Classic Bluetooth SPP | 🔜 Planned |
| v0.22 — Polish & accessibility | 🔜 Planned |
| v1.0 — Launch (signing, store submission) | 🔜 Planned |

This is a highlights view. See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the full milestone breakdown.

---

## Credits & Acknowledgements

- **APRS device identification data** — [aprsorg/aprs-deviceid](https://github.com/aprsorg/aprs-deviceid) by Heikki Hannikainen (OH7LZB) and contributors, licensed under [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0/).
- **Inter typeface** — by Rasmus Andersson, licensed under [SIL Open Font License](https://scripts.sil.org/OFL).

---

## License

Meridian APRS is licensed under the [GNU General Public License v3.0](LICENSE).

---

## Links

- [meridianaprs.com](https://meridianaprs.com)
- [meridianaprs.app](https://meridianaprs.app)
- [Issue Tracker](https://github.com/epasch/meridian-aprs/issues)
- [Discussions](https://github.com/epasch/meridian-aprs/discussions)

---

*73 de Meridian* 📻