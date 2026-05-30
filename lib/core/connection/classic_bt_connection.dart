/// Platform-conditional export for [ClassicBtConnection].
///
/// On platforms with `dart:io` the real implementation is used; on web the
/// stub is exported, which throws [UnsupportedError]. Instantiation is further
/// gated to Android via [ClassicBtConnection.isAvailable].
library;

export 'classic_bt_connection_stub.dart'
    if (dart.library.io) 'classic_bt_connection_impl.dart';
