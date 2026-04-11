import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/connection/connection_registry.dart';

import '../../helpers/fake_meridian_connection.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

FakeMeridianConnection _aprsIs() => FakeMeridianConnection(
  id: 'aprs_is',
  displayName: 'APRS-IS',
  type: ConnectionType.aprsIs,
);

FakeMeridianConnection _ble() => FakeMeridianConnection(
  id: 'ble_tnc',
  displayName: 'BLE TNC',
  type: ConnectionType.bleTnc,
);

FakeMeridianConnection _serial({bool available = true}) =>
    FakeMeridianConnection(
      id: 'serial_tnc',
      displayName: 'USB TNC',
      type: ConnectionType.serialTnc,
      available: available,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late ConnectionRegistry registry;

  setUp(() => registry = ConnectionRegistry());

  tearDown(() => registry.dispose());

  // -------------------------------------------------------------------------
  // Registration
  // -------------------------------------------------------------------------

  group('registration', () {
    test('all returns registered connections', () {
      final a = _aprsIs();
      final b = _ble();
      registry.register(a);
      registry.register(b);
      expect(registry.all, [a, b]);
    });

    test('available filters by isAvailable', () {
      registry.register(_aprsIs());
      registry.register(_serial(available: false));
      expect(registry.available, hasLength(1));
      expect(registry.available.first.id, 'aprs_is');
    });

    test('byId returns correct connection', () {
      final a = _aprsIs();
      registry.register(a);
      expect(registry.byId('aprs_is'), same(a));
      expect(registry.byId('ble_tnc'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Connected state
  // -------------------------------------------------------------------------

  group('connected / isAnyConnected', () {
    test('isAnyConnected is false when all disconnected', () {
      registry.register(_aprsIs());
      registry.register(_ble());
      expect(registry.isAnyConnected, isFalse);
    });

    test('isAnyConnected is true when one connection is connected', () {
      final a = _aprsIs();
      final b = _ble();
      registry.register(a);
      registry.register(b);
      a.setStatus(ConnectionStatus.connected);
      expect(registry.isAnyConnected, isTrue);
    });

    test('connected list reflects current state', () {
      final a = _aprsIs();
      final b = _ble();
      registry.register(a);
      registry.register(b);
      b.setStatus(ConnectionStatus.connected);
      expect(registry.connected, [b]);
    });
  });

  // -------------------------------------------------------------------------
  // aggregateStatus
  // -------------------------------------------------------------------------

  group('aggregateStatus', () {
    test('disconnected when empty', () {
      expect(registry.aggregateStatus, ConnectionStatus.disconnected);
    });

    test('connected takes highest priority', () {
      final a = _aprsIs();
      final b = _ble();
      registry.register(a);
      registry.register(b);
      a.setStatus(ConnectionStatus.error);
      b.setStatus(ConnectionStatus.connected);
      expect(registry.aggregateStatus, ConnectionStatus.connected);
    });

    test('reconnecting takes priority over error', () {
      final a = _aprsIs();
      final b = _ble();
      registry.register(a);
      registry.register(b);
      a.setStatus(ConnectionStatus.error);
      b.setStatus(ConnectionStatus.reconnecting);
      expect(registry.aggregateStatus, ConnectionStatus.reconnecting);
    });

    test('error takes priority over disconnected', () {
      final a = _aprsIs();
      registry.register(a);
      a.setStatus(ConnectionStatus.error);
      expect(registry.aggregateStatus, ConnectionStatus.error);
    });

    test('disconnected when all disconnected', () {
      final a = _aprsIs();
      final b = _ble();
      registry.register(a);
      registry.register(b);
      expect(registry.aggregateStatus, ConnectionStatus.disconnected);
    });
  });

  // -------------------------------------------------------------------------
  // notifyListeners propagation
  // -------------------------------------------------------------------------

  group('notifyListeners propagation', () {
    test('registry notifies when a connection changes state', () {
      final a = _aprsIs();
      registry.register(a);
      int notifyCount = 0;
      registry.addListener(() => notifyCount++);
      a.setStatus(ConnectionStatus.connected);
      expect(notifyCount, 1);
    });

    test('registry notifies when beaconing is toggled', () async {
      final a = _aprsIs();
      registry.register(a);
      int notifyCount = 0;
      registry.addListener(() => notifyCount++);
      await a.setBeaconingEnabled(false);
      expect(notifyCount, 1);
    });
  });

  // -------------------------------------------------------------------------
  // Merged lines stream
  // -------------------------------------------------------------------------

  group('lines stream', () {
    test(
      'emits lines from all registered connections with source tag',
      () async {
        final a = _aprsIs();
        final b = _ble();
        registry.register(a);
        registry.register(b);

        final received = <({String line, ConnectionType source})>[];
        registry.lines.listen(received.add);

        a.simulateLine('W1AW>APZMDN:!test');
        b.simulateLine('W2XY>APZMDN:!test2');
        await Future<void>.delayed(Duration.zero);

        expect(received, hasLength(2));
        expect(
          received.where((e) => e.source == ConnectionType.aprsIs),
          hasLength(1),
        );
        expect(
          received.where((e) => e.source == ConnectionType.bleTnc),
          hasLength(1),
        );
      },
    );

    test('line from aprs_is connection has aprsIs source', () async {
      final a = _aprsIs();
      registry.register(a);

      ({String line, ConnectionType source})? received;
      registry.lines.listen((e) => received = e);

      a.simulateLine('W1AW>APZMDN:!test');
      await Future<void>.delayed(Duration.zero);

      expect(received?.source, ConnectionType.aprsIs);
      expect(received?.line, 'W1AW>APZMDN:!test');
    });
  });

  // -------------------------------------------------------------------------
  // loadAllSettings
  // -------------------------------------------------------------------------

  test(
    'loadAllSettings calls loadPersistedSettings on every connection',
    () async {
      final a = _aprsIs();
      final b = _ble();
      registry.register(a);
      registry.register(b);
      await registry.loadAllSettings();
      expect(a.settingsLoaded, isTrue);
      expect(b.settingsLoaded, isTrue);
    },
  );

  // -------------------------------------------------------------------------
  // dispose
  // -------------------------------------------------------------------------

  test(
    'dispose removes listeners and does not crash on subsequent state changes',
    () async {
      final a = _aprsIs();
      registry.register(a);
      // Dispose and replace so tearDown does not double-dispose
      registry.dispose();
      registry =
          ConnectionRegistry(); // tearDown will dispose this fresh instance

      // State changes on the old connection must not crash after listener was removed
      expect(() => a.setStatus(ConnectionStatus.connected), returnsNormally);
      await a.dispose();
    },
  );
}
