import 'dart:async';
import 'dart:typed_data';

import 'package:meridian_aprs/core/transport/aprs_transport.dart'
    show ConnectionStatus;
import 'package:meridian_aprs/core/transport/kiss_tnc_transport.dart';

/// Fully controllable [KissTncTransport] for use in connection layer tests.
class FakeKissTncTransport extends KissTncTransport {
  // sync: true so events fire synchronously in tests without needing
  // extra await/flushMicrotasks calls.
  final _frameController = StreamController<Uint8List>.broadcast(sync: true);
  final _stateController = StreamController<ConnectionStatus>.broadcast(
    sync: true,
  );

  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool disconnectCalled = false;
  bool connectThrows = false;
  bool backgroundConnectCalled = false;
  final List<Uint8List> sentFrames = [];

  @override
  Stream<Uint8List> get frameStream => _frameController.stream;

  @override
  Stream<ConnectionStatus> get connectionState => _stateController.stream;

  @override
  ConnectionStatus get currentStatus => _status;

  @override
  bool get isConnected => _status == ConnectionStatus.connected;

  @override
  Future<void> connect() async {
    _setStatus(ConnectionStatus.connecting);
    if (connectThrows) {
      _setStatus(ConnectionStatus.error);
      throw Exception('FakeKissTncTransport: connect failed');
    }
    _setStatus(ConnectionStatus.connected);
  }

  @override
  Future<void> connectBackground() async {
    backgroundConnectCalled = true;
    await connect();
  }

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    _setStatus(ConnectionStatus.disconnected);
  }

  @override
  Future<void> sendFrame(Uint8List ax25Frame) async {
    if (!isConnected) throw StateError('FakeKissTncTransport: not connected');
    sentFrames.add(ax25Frame);
  }

  // ---------------------------------------------------------------------------
  // Test helpers
  // ---------------------------------------------------------------------------

  void simulateFrame(Uint8List frame) => _frameController.add(frame);

  void simulateUnexpectedDisconnect() => _setStatus(ConnectionStatus.error);

  void _setStatus(ConnectionStatus s) {
    _status = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  Future<void> close() async {
    await _frameController.close();
    await _stateController.close();
  }
}
