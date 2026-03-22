library;

import 'dart:async';
import 'dart:typed_data';

/// Thin abstraction over a single serial port connection.
///
/// The default implementation ([DefaultSerialPortAdapter]) delegates to
/// `flutter_libserialport`. Tests inject [FakeSerialPortAdapter].
abstract interface class SerialPortAdapter {
  /// Open the port for reading and writing.
  /// Returns true on success, false if the port could not be opened.
  bool open();

  /// Apply serial port configuration (baud rate, parity, etc.).
  void configure({
    required int baudRate,
    required int dataBits,
    required int stopBits,
    required String parity,
    required bool hardwareFlowControl,
  });

  /// A stream of raw bytes received from the port.
  /// The stream ends (onDone) when the port is closed or disconnected.
  Stream<Uint8List> get byteStream;

  /// Write raw bytes to the port.
  void write(Uint8List data);

  /// Close the port and release resources.
  void close();
}
