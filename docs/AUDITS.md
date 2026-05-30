# Meridian APRS — Audit Setup

**Purpose:** This document describes the protocol-correctness audit system used
to verify that Meridian's APRS implementation matches the published spec and
real-world vendor behavior. Audits are research-only — they surface findings
with severity ratings but never modify code.

---

## The `aprs-auditor` agent

A project-scoped Claude Code sub-agent. Its definition lives locally at
`.claude/agents/aprs-auditor.md` (gitignored — not committed to the repo, so it
won't be present on a fresh clone). Invoke it when:

- Adding or modifying packet parser / encoder logic in `lib/core/packet/` or
  `lib/core/ax25/`.
- Suspected vendor-specific behavior isn't covered.
- Milestone gate before shipping new packet-type support.
- Scheduled audit pass (e.g. v0.15 bug triage).

The agent fetches primary sources on every run and names them explicitly in the
report, so the audit is auditable. It never trusts `aprs101.pdf` alone
(superseded — see `https://how.aprs.works/aprs101-pdf-is-obsolete/`).

### Oracles the agent consults

| Source | Role |
|---|---|
| `wb2osz/aprsspec` (APRS12b/c, Understanding-APRS-Packets, Symbols, Digipeater-Algorithm) | Current APRS 1.2 draft + errata |
| `aprs.org/aprs12/mic-e-types.txt` | Mic-E device type-byte table |
| `hessu/aprs-deviceid` `tocalls.yaml` | Canonical device prefix/suffix registry |
| Dire Wolf `decode_aprs.c`, `deviceid.c` | Reference decoder oracle |
| aprslib `mice.py`, parsing modules | Clean-reference Python parser |
| Xastir | Feature-complete APRS client — breadth reference |

---

## Audit categories

Audits split along packet type and protocol layer. Each category has its own
spec section and vendor quirks, so each is a distinct audit pass.

### Decoder audits (packet parser in `lib/core/packet/aprs_parser.dart`)

One pass per APRS data type:

- **Mic-E** — destination-field lat + message bits; info-field lon/course/speed;
  telemetry and device-ID suffixes in comment.
- **Compressed position** — base-91 lat/lon, course/speed/range, compression
  type byte.
- **Uncompressed position** — all 4 DTI variants (`!`, `=`, `@`, `/`),
  timestamp formats (DHMz, HMS, MDHM), ambiguity spaces.
- **Messages** — `:` format, ack/rej, 3-digit message ID, `:BLNn     :`
  bulletins.
- **Objects & Items** — `;` and `)` DTIs, live/killed flag, naming rules.
- **Weather** — standalone `_` reports and position-embedded weather.
- **Telemetry** — `T#nnn` data frames and `PARM.`/`UNIT.`/`EQNS.`/`BITS.`
  metadata frames.
- **Status** — `>` DTI with optional timestamp/Maidenhead.
- **NMEA raw** — `$GPGGA` / `$GPRMC` / `$GPGLL` embedded sentences.

### Registry / lookup audits

Data-file correctness — oracle is `aprs-deviceid/tocalls.yaml`, not the APRS
spec. Different flavor of audit (check labels, not decoding logic).

- **Device ID resolver** — `lib/core/packet/device_resolver.dart` — Mic-E
  prefix/suffix pairs, tocall prefix table.
- **Symbol table** — primary, overlay, and alternate tables; symbol code ↔
  icon mapping.

### Frame-layer audits (below APRS)

- **AX.25 UI frame parser** — `lib/core/ax25/ax25_parser.dart` — address
  encoding, control/PID, SSID bits, has-been-repeated bit on each path entry.
- **KISS framing** — `lib/core/transport/kiss_framer.dart` — FEND/FESC
  escapes, TNC port nibble in command byte.

### Encoder audits (transmit correctness — separate from decode)

- **Position beacon encoder** — `lib/core/packet/aprs_encoder.dart` —
  compressed and uncompressed, symbol placement, timestamp formats.
- **Message encoder** — callsign padding to 9 chars, ID format (`{NNN`, no
  closing brace).
- **AX.25 frame builder** — `lib/core/ax25/ax25_encoder.dart` — path
  decrementing, SSID encoding, final-address bit.
- **Smart Beaconing** — `lib/core/beaconing/smart_beaconing.dart` — math
  against Hamish Moffatt's original algorithm (units: `turnSlope` =
  degrees·mph, NOT km/h).

### System-level audits (lower priority — post-v1.0)

- **APRS-IS filter syntax** — `filter r/lat/lon/dist`, `p/prefix`, `b/call`,
  etc.; server command set.
- **Digipeater path handling** — `WIDEn-N` semantics, how paths render in the
  UI after multiple hops.

---

## Running an audit

From the main agent:

```
Agent({
  description: "Audit <category>",
  subagent_type: "aprs-auditor",
  prompt: "Audit <category> in <file>. Fetch <sources>. Verify <specific claims>.
  Report findings with severity ratings. Research-only — do not modify code."
})
```

Give the agent a tight scope. A single-category audit is cheaper and surfaces
fewer false positives than a "audit everything" sweep. Name the exact file and
the specific claims to verify.

### Severity ratings (agent output)

- **CRITICAL / HIGH** — correctness bug that corrupts decoded data or produces
  wrong-on-wire packets. Block ship.
- **MEDIUM** — edge-case misbehavior or spec-drift that works in the common
  case. Fix in current milestone if cheap.
- **LOW** — cosmetic, documentation, or forward-compatibility nit. Defer.

The agent will call out when a fix would require spec-reversing existing tests
(i.e. tests that codify the wrong answer). Treat these specially — the test
and the code must be changed together.

---

## Audit workflow

1. Invoke the auditor with a tight scope.
2. Apply HIGH/CRITICAL fixes + update tests that lock in wrong behavior.
3. Re-run the auditor to confirm the fix (common for corrections to pass but
   introduce secondary drift — a verification pass catches this cheaply).
4. For MEDIUM/LOW findings that are out-of-scope, capture them as GitHub
   issues with the auditor's exact severity label and oracle references.
5. Commit audit-driven fixes with `audit:` or `fix(audit):` prefix in the
   commit message and cite the oracle in the body.

---

## Historical audit passes

- **v0.12 — Mic-E decoder (three passes, 2026-04-19).**
  - Pass 1: surfaced destination-char Custom/Standard bit conflation,
    `isUpperLetter` flag drift, and `>IDENT` suffix overreach.
  - Pass 2: verified Pass-1 fixes sound but surfaced reversed Custom
    message-bit table (custBits=0b111 mapped to "Custom-6" — spec says
    "Custom-0") and no-spec-basis `>IDENT` branch.
  - Pass 3: verified fixes sound + flagged 6 pre-existing device-ID
    registry bugs (B1–B6 in `DeviceResolver`) — scheduled for v0.15 triage.
