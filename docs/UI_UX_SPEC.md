# Meridian APRS — UI/UX Specification
**Version:** 0.1 Draft  
**Status:** Planning  
**Audience:** Claude Code implementation agents, contributors

---

## 1. Design Philosophy

Meridian should feel like a **modern geospatial app that happens to do amateur radio** — not a radio tool that awkwardly has a map bolted on. The nearest design relatives are apps like Waze, Organic Maps, and Windy: map-centric, information-dense but not cluttered, and usable with one hand in the field.

**Core principles:**

- **Map is the canvas.** Everything else is an overlay or a sheet that slides over the map. The map never leaves.
- **Progressive disclosure.** New users see clean, approachable defaults. Advanced operators can dig into raw packets, filter strings, and KISS frame timing — but only when they ask for it.
- **One-handed field use.** FABs, bottom sheets, and reachable controls. Nothing important should require two hands or precise tapping in a small target.
- **State always persists.** Map position, connection profile, filters, message history — nothing is ever silently lost on restart.
- **Platform-native feel.** Adaptive layout: phone UI is full-screen map with sheets; tablet/desktop UI expands into a two-column layout. One codebase, two personalities.

---

## 2. Theme System

| Mode | Description |
|---|---|
| **Light** | Clean, high-contrast. Good for outdoors in daylight. |
| **Dark** | Deep background, reduced eye strain. Natural for shack/night use. |
| **Auto** | Follows system preference. **Default on first launch.** |

- User-configurable in Settings → Appearance
- Theme token system from day one — no hardcoded colors anywhere in the codebase
- Map tile style should match theme where possible (OSM standard for light, dark-mode OSM tiles for dark)

### Color Palette (Tokens)

```
Primary:       #2563EB  (Meridian Blue)
Primary Dark:  #1D4ED8
Accent:        #10B981  (Signal Green — for "connected", "received", active states)
Warning:       #F59E0B  (Amber — for degraded connection, stale data)
Danger:        #EF4444  (Red — errors, TX active indicator)
Surface Light: #FFFFFF / #F8FAFC
Surface Dark:  #0F172A / #1E293B
Text Light:    #0F172A
Text Dark:     #F1F5F9
```

---

## 3. Navigation Architecture

### Mobile (Phone)

Navigation is **implicit** — no persistent nav bar. The map is always the primary surface. Secondary views are accessed via:

- **FABs** (Floating Action Buttons) — primary actions
- **Bottom sheets** — station details, packet log, messages
- **Top app bar** — minimal: logo/title, connection status pill, settings icon
- **Swipe-up sheet** anchored at bottom — "nearby stations" quick list, collapsible

### Tablet & Desktop

A **persistent left rail** (72px collapsed, 240px expanded) replaces the FAB-only model:

```
┌─────────────────────────────────────────────────────┐
│  [≡] Meridian          [●Connected] [⚙]             │
├──────┬──────────────────────────────────────────────┤
│      │                                              │
│ Rail │              Map Canvas                      │
│      │                                              │
│ [🗺] │   [Station markers, trails, overlays]        │
│ [📋] │                                              │
│ [💬] │                        [FABs]                │
│ [📡] │                                              │
│      ├──────────────────────────────────────────────┤
│ [⚙] │  [Bottom panel: packet log or station list]  │
└──────┴──────────────────────────────────────────────┘
```

Rail icons (top to bottom):
1. Map (home)
2. Station List
3. Messages
4. Connection / TNC status
5. *(spacer)*
6. Settings (pinned to bottom)

### Responsive Breakpoints

| Width | Layout |
|---|---|
| < 600px | Mobile: full-screen map, FABs, bottom sheets |
| 600–1024px | Tablet: collapsed rail + map + bottom panel |
| > 1024px | Desktop: expanded rail + map + side panel |

---

## 4. Screen Inventory

### 4.1 Map View (Primary — always visible)

The core experience. Everything layers on top of this.

**Map canvas:**
- OpenStreetMap tiles via `flutter_map`
- Station markers rendered as APRS symbol icons (standard APRS symbol table)
- Tapping a marker opens the Station Detail Sheet (see §4.3)
- Long-press on map → "Place Object" (future, v0.5+)
- Trail lines for mobile stations (configurable length)
- "My position" marker with accuracy ring

**Top app bar (minimal):**
```
[☰ or back]    Meridian         [● APRS-IS]  [⚙]
```
- Connection status pill: green (connected), amber (connecting/degraded), red (disconnected)
- Tapping the status pill opens the Connection Sheet

**FAB cluster (bottom-right, above system nav):**
```
        [📍 Beacon]   ← primary FAB (large)
   [🔍]   [⬆ center]
```
- **Beacon FAB** (primary, large): Send a position report / toggle auto-beaconing. Active state turns Danger Red with pulse animation while TX is live.
- **Search FAB**: Opens callsign search sheet
- **Center FAB**: Re-center map on my position

**Bottom anchor sheet (collapsed by default):**
- Drag handle at top
- Collapsed state (~80px): shows "N stations nearby" + connection summary
- Half-expanded: scrollable station list sorted by last heard
- Full-expanded: full station list with filter controls

**Map controls (left side, mid-screen):**
- Zoom +/−
- Map type toggle (street / satellite / topo) — future

---

### 4.2 Station List Sheet

Accessible via: bottom sheet swipe-up, or rail icon on tablet/desktop.

**List item anatomy:**
```
[Symbol Icon]  W1ABC-9                    [2m ago]
               Mobile → 45 mph / 287°
               "En route to field day site"
```

- Symbol icon rendered from APRS symbol table
- Callsign + SSID (bold)
- Relative timestamp ("2m ago", "just now", "23m ago")
- Subtitle: decoded packet type summary (position + speed/course, weather, message, etc.)
- Comment text if present, truncated to 1 line
- Tapping opens Station Detail Sheet

**Filter bar (top of list):**
- Quick filter chips: All · Mobile · Weather · Objects · Messages
- Search field (filters list live as you type)

---

### 4.3 Station Detail Sheet

Opens as a **modal bottom sheet** (mobile) or **side panel** (desktop) when a marker or list item is tapped.

**Header:**
```
[Symbol]  W1ABC-9           [★ Favorite]  [✕]
          Last heard: 2 minutes ago
          via WIDE1-1,WIDE2-1
```

**Body sections (scrollable):**

1. **Position card** — lat/lon, grid square, altitude if available. "Show on map" button.
2. **Motion card** (if mobile) — speed, course, with a small compass rose widget.
3. **Comment** — full comment text, selectable.
4. **Station info** — operator name (from APRS-IS lookup), if available.
5. **Packet history** — last N raw packets, expandable per-packet to see full decode.
6. **Actions row:**
   - [Send Message] — opens Message Compose sheet
   - [Track] — keeps map centered on this station
   - [Copy Callsign]
   - [View on aprs.fi] — opens in browser

**Design note:** default view shows the human-readable cards. Raw packet data is one tap deeper — not presented first.

---

### 4.4 Packet Log Sheet

Accessible via: rail icon, or swipe-up sheet tab on mobile.

A live scrolling list of decoded packets.

**Log item anatomy:**
```
[Symbol]  W1ABC-9    Position          14:23:07
          45.123°N 122.456°W  · 45 mph · 287°
          [APRS-IS]
```

- Source badge: `[APRS-IS]` or `[RF]` (colored differently)
- Decoded type label: Position / Message / Weather / Object / Status / Unknown
- Timestamp
- Tapping expands inline to show raw packet string

**Controls:**
- Pause/resume scroll toggle
- Clear log button
- Filter by type chips (same as station list)
- "Show raw only" toggle for advanced operators

---

### 4.5 Messages View

Accessible via: rail icon or FAB (future — v0.5+).

iMessage-style conversation UI per callsign.

```
┌─────────────────────────────────┐
│  ← Messages                     │
│─────────────────────────────────│
│  W1ABC-9                   now  │
│  KD9XYZ-7              12m ago  │
│─────────────────────────────────│
```

Tapping a conversation:
```
┌─────────────────────────────────┐
│  ← W1ABC-9                  [i] │
│─────────────────────────────────│
│                  Hello, copy?   │ ← sent (right, primary color)
│  Copy that, 73!                 │ ← received (left, surface)
│─────────────────────────────────│
│  [Type a message...]      [Send]│
└─────────────────────────────────┘
```

- Message bubbles with delivery acknowledgment state (sent / acked / failed)
- "ACK" badge appears when remote station confirms receipt

---

### 4.6 Connection Sheet

Opened by tapping the status pill in the top bar.

**Sections:**

1. **APRS-IS** — server (rotate.aprs2.net), port, callsign, passcode, filter string. Connect / Disconnect button. Status indicator.
2. **TNC** — BLE device picker or USB serial port selector. KISS configuration (TX delay, persistence). Connect / Disconnect.
3. **Active connection summary** — packets received this session, uptime.

**Design note:** callsign and passcode are entered once during onboarding and pre-filled here. The filter string has a helper: a plain-language builder ("Show stations within [50] km of my position") that generates the raw filter string, with an "Edit raw" toggle for power users.

---

### 4.7 Settings

Single unified settings screen. Grouped sections:

| Section | Settings |
|---|---|
| **Appearance** | Theme (Light / Dark / Auto), Map style, Symbol size |
| **My Station** | Callsign, SSID, Symbol, Comment, Overlay |
| **Beaconing** | Smart beaconing on/off, interval, speed thresholds, path (WIDE1-1 etc.) |
| **Connection** | Default APRS-IS server, default filter, TNC auto-connect |
| **Display** | Station timeout (hide stations older than N minutes), trail length, show unpositioned stations |
| **Notifications** | Message alerts, direct-message callsign alert |
| **Account** | Sign in / Sign up (see §7), sync preferences |
| **About** | Version, licenses, GitHub link, feedback |

---

### 4.8 Onboarding Flow

First-launch only. Three screens, skippable after screen 1.

**Screen 1 — Welcome:**
> "APRS for the Modern Ham."
> Meridian connects you to the APRS network — live station tracking, messaging, and beaconing from one app.
> [Get Started] [I know APRS, skip setup]

**Screen 2 — Your Callsign:**
- Callsign field + SSID picker (dropdown 0–15 with labels: "0 = primary, 9 = mobile, 7 = handheld…")
- APRS-IS passcode field with "What's this?" inline explainer
- "Calculate passcode" link (opens mini web view or external link)

**Screen 3 — Connect:**
- APRS-IS (default, pre-selected, zero config)
- TNC via BLE (shows BLE scan)
- TNC via USB (shows port picker, desktop only)
- [Start Listening] → lands on Map View, connected

---

## 5. Component Library (Flutter)

Key reusable components Claude Code should build as standalone widgets:

| Component | Description |
|---|---|
| `MeridianStatusPill` | Connection status indicator with color + label |
| `StationMarker` | APRS symbol rendered on map, with optional label |
| `StationListTile` | List item for station list and nearby sheet |
| `StationDetailSheet` | Full station info modal/panel |
| `PacketLogTile` | Single packet log row, expandable |
| `ConnectionSheet` | APRS-IS + TNC connection panel |
| `BeaconFAB` | Animated beacon button with TX state |
| `MeridianBottomSheet` | Base draggable bottom sheet with handle |
| `CallsignField` | Validated text field for callsign entry |
| `AprsFilterBuilder` | Plain-language → raw filter string helper |
| `ThemeProvider` | App-level theme state (light/dark/auto) |

---

## 6. Adaptive Layout Strategy

Flutter implementation approach:

```dart
// Pseudo-structure
Widget build(BuildContext context) {
  final width = MediaQuery.of(context).size.width;

  if (width < 600) {
    return MobileScaffold();      // FABs + bottom sheets
  } else if (width < 1024) {
    return TabletScaffold();      // Collapsed rail + bottom panel
  } else {
    return DesktopScaffold();     // Expanded rail + side panel
  }
}
```

- All three scaffolds share the same Map canvas widget
- Panels/sheets are the same content widgets, just placed differently
- `NavigationRail` (tablet/desktop) vs implicit FAB navigation (mobile)

---

## 7. Account System & Cross-Device Sync (Future — v1.x)

Designed now, implemented later. The architecture should accommodate this from day one even if the backend doesn't exist yet.

### What gets synced (free tier):
- Callsign / SSID / symbol / comment
- Connection profiles (APRS-IS server, filter)
- Favorite stations (starred callsigns)
- App preferences (theme, display settings)

### What could be premium:
- **Message history** — full inbox/outbox across devices
- **Station history** — longer packet history retention (e.g., 30-day archive)
- **Custom overlays** — saved map layers, custom object sets
- **Multiple station profiles** — home station vs. mobile vs. portable
- **Push notifications** — message alerts when app is backgrounded (requires backend)

### Auth approach:
- Email + password, or "Sign in with Apple" / Google (platform-appropriate)
- Passcode stored in device keychain (never synced to server)
- Sync via lightweight REST API + Meridian backend (TBD stack)
- Local-first: app works fully offline/without account; sync is additive

### UI placeholders now:
- Settings → Account section: "Sign in to sync your preferences across devices" with sign-in CTA
- No account features gated at v0.x — section is present but dormant

---

## 8. Key UX Decisions & Rationale

| Decision | Rationale |
|---|---|
| Map-always, no tab switching away from map | Matches how operators actually use APRS — always want situational awareness |
| Bottom sheets instead of separate screens | Keeps map context visible while viewing station detail |
| Progressive disclosure for raw packets | New users shouldn't be confronted with AX.25 frames; experts can always get there |
| Plain-language filter builder | APRS-IS filter syntax (`r/lat/lon/km`) is opaque; translate it for beginners |
| Status pill instead of modal connection dialogs | Connection state should be ambient, not intrusive |
| Auto theme default | Best first-launch experience on both iOS (light) and Android (varies) |
| Callsign passcode never synced | Security — passcode is derived from callsign, should stay on-device |
| Smart beaconing on by default | Better APRS network citizenship than fixed-interval; correct default for mobile operators |

---

## 9. Accessibility

- All interactive elements meet 44×44pt minimum tap target
- Color is never the sole indicator of state (always paired with icon or label)
- System font scaling supported — layouts tested at up to 200% text size
- Screen reader labels on all custom widgets (`Semantics` wrappers)
- High contrast mode respects system setting

---

## 10. Handoff Notes for Claude Code

When implementing this spec:

1. **Start with `ThemeProvider` and the token color system** before building any UI. All colors must come from the theme, never hardcoded.
2. **Build the adaptive scaffold first** (`MobileScaffold`, `TabletScaffold`, `DesktopScaffold`) with placeholder content, then fill in real widgets.
3. **`MeridianBottomSheet`** is the most-reused component — build it early and well.
4. **Map widget** should be isolated in its own widget (`MeridianMap`) with a clean interface so transport/service layers can push station updates to it without coupling.
5. **Account/sync features** — add the Settings → Account section with a disabled/placeholder state. Don't wire up any backend. Just preserve the slot.
6. The `StationDetailSheet` and `PacketLogTile` components should accept model objects (`AprsStation`, `AprsPacket`) defined in the Packet Core layer — don't design the UI around raw strings.
