/// Mobilinkd UART-over-BLE GATT service UUID constants.
///
/// These are public so they can be used by both the transport implementation
/// and UI code (e.g., BLE scanner filtering by service UUID).
const kMobilinkdServiceUuid = '00000001-ba2a-46c9-ae49-01b0961f68bb';
const kMobilinkdTxCharUuid = '00000003-ba2a-46c9-ae49-01b0961f68bb'; // notify
const kMobilinkdRxCharUuid = '00000002-ba2a-46c9-ae49-01b0961f68bb'; // write
