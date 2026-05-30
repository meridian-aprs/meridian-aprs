/// Platform-conditional export for [ClassicBtTncTransport].
///
/// On platforms with `dart:io` (Android/desktop) this re-exports the real
/// implementation backed by the native RFCOMM bridge. On web the stub is used,
/// which throws [UnsupportedError]. The connection layer additionally gates
/// instantiation to Android via [ClassicBtConnection.isAvailable].
library;

export 'classic_bt_tnc_transport_stub.dart'
    if (dart.library.io) 'classic_bt_tnc_transport_impl.dart';
