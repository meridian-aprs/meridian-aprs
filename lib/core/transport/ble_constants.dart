/// GATT service / characteristic UUIDs for the BLE-KISS TNC families
/// Meridian supports.
///
/// Two non-overlapping UUID families exist in the wild:
///
///   - **`aprs-specs` BLE-KISS API** ("standard" family, post-2023). Used by
///     Mobilinkd TNC3/TNC4, PicoAPRS v4, B.B. Link adapter, RPC ESP32 trackers,
///     CA2RXU LoRa trackers and any device that follows the spec.
///     Reference: https://github.com/hessu/aprs-specs/blob/master/BLE-KISS-API.md
///
///   - **Benshi / older `bluetoothle-tnc` family** (BTECH UV-Pro, Vero VR-N76,
///     VR-N7500, Radioddity GA-5WB). KISS available on UV-Pro firmware ≥ 0.7.11
///     once the user enables KISS mode in the radio menu.
///     Reference: https://github.com/ge0rg/bluetoothle-tnc/blob/master/Bluetooth-LE-TNC.md
///
/// KISS framing on the wire is identical between both families — only the GATT
/// plumbing differs.
library;

// ---------------------------------------------------------------------------
// Family A — aprs-specs BLE-KISS API (Mobilinkd, PicoAPRS, B.B. Link, ...)
// ---------------------------------------------------------------------------

/// Service UUID for the standard BLE-KISS API.
const kBleKissServiceUuid = '00000001-ba2a-46c9-ae49-01b0961f68bb';

/// Characteristic the host writes KISS frames to (write w/ response).
const kBleKissWriteCharUuid = '00000002-ba2a-46c9-ae49-01b0961f68bb';

/// Characteristic the TNC notifies KISS frames on (subscribe / notify).
const kBleKissNotifyCharUuid = '00000003-ba2a-46c9-ae49-01b0961f68bb';

// ---------------------------------------------------------------------------
// Family B — Benshi / older bluetoothle-tnc family (BTECH UV-Pro, VR-N76, ...)
// ---------------------------------------------------------------------------

/// Service UUID for the Benshi/BTECH KISS-over-BLE family.
const kBenshiKissServiceUuid = '0000ca10-6fb0-4d48-b931-073ed111081b';

/// Characteristic the host writes KISS frames to (write).
const kBenshiKissWriteCharUuid = '00000001-6fb0-4d48-b931-073ed111081b';

/// Characteristic the TNC notifies KISS frames on (subscribe / notify).
const kBenshiKissNotifyCharUuid = '00000002-6fb0-4d48-b931-073ed111081b';

// ---------------------------------------------------------------------------
// Deprecated aliases — kept for one release to ease in-flight PR churn.
// ---------------------------------------------------------------------------

@Deprecated(
  'Use kBleKissServiceUuid (renamed to reflect the aprs-specs '
  'standard, which is shared by Mobilinkd, PicoAPRS, B.B. Link, etc.)',
)
const kMobilinkdServiceUuid = kBleKissServiceUuid;

@Deprecated(
  'Use kBleKissNotifyCharUuid (note: "Tx" / "Rx" naming was '
  'inverted relative to the host\'s perspective in the old constants — '
  '"Tx" was the notify characteristic the host listens on)',
)
const kMobilinkdTxCharUuid = kBleKissNotifyCharUuid;

@Deprecated(
  'Use kBleKissWriteCharUuid (note: "Tx" / "Rx" naming was '
  'inverted relative to the host\'s perspective in the old constants — '
  '"Rx" was the write characteristic the host writes to)',
)
const kMobilinkdRxCharUuid = kBleKissWriteCharUuid;

// ---------------------------------------------------------------------------
// Family enum + resolver
// ---------------------------------------------------------------------------

/// Which BLE-KISS GATT family a device implements.
enum BleKissFamily {
  /// `aprs-specs` BLE-KISS API. Mobilinkd, PicoAPRS, B.B. Link, RPC, CA2RXU.
  aprsSpecs,

  /// Older `bluetoothle-tnc` family. BTECH UV-Pro, Vero VR-N76 / VR-N7500,
  /// Radioddity GA-5WB.
  benshi,
}

/// Profile for a BLE-KISS family — the three UUIDs the transport needs.
class BleKissProfile {
  const BleKissProfile({
    required this.family,
    required this.serviceUuid,
    required this.writeCharUuid,
    required this.notifyCharUuid,
  });

  final BleKissFamily family;
  final String serviceUuid;

  /// Characteristic the host writes KISS frames to.
  final String writeCharUuid;

  /// Characteristic the host subscribes to for incoming KISS frames.
  final String notifyCharUuid;

  static const aprsSpecs = BleKissProfile(
    family: BleKissFamily.aprsSpecs,
    serviceUuid: kBleKissServiceUuid,
    writeCharUuid: kBleKissWriteCharUuid,
    notifyCharUuid: kBleKissNotifyCharUuid,
  );

  static const benshi = BleKissProfile(
    family: BleKissFamily.benshi,
    serviceUuid: kBenshiKissServiceUuid,
    writeCharUuid: kBenshiKissWriteCharUuid,
    notifyCharUuid: kBenshiKissNotifyCharUuid,
  );

  static const all = [aprsSpecs, benshi];

  static BleKissProfile forFamily(BleKissFamily family) {
    return all.firstWhere((p) => p.family == family);
  }
}

/// Resolve a BLE-KISS family from a list of advertised service UUIDs.
///
/// Matching is case-insensitive — different BLE stacks normalize UUID strings
/// differently. Returns `null` when no advertised UUID matches a known family.
BleKissFamily? bleKissFamilyForServiceUuids(Iterable<String> advertisedUuids) {
  final lower = advertisedUuids.map((u) => u.toLowerCase()).toSet();
  for (final profile in BleKissProfile.all) {
    if (lower.contains(profile.serviceUuid.toLowerCase())) {
      return profile.family;
    }
  }
  return null;
}
