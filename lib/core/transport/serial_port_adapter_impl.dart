library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'serial_port_adapter.dart';

/// Production [SerialPortAdapter] backed by `flutter_libserialport`.
class DefaultSerialPortAdapter implements SerialPortAdapter {
  DefaultSerialPortAdapter(String portName) : _port = SerialPort(portName);

  final SerialPort _port;
  SerialPortReader? _reader;

  @override
  bool open() => _port.openReadWrite();

  @override
  void configure({
    required int baudRate,
    required int dataBits,
    required int stopBits,
    required String parity,
    required bool hardwareFlowControl,
  }) {
    final config = SerialPortConfig()
      ..baudRate = baudRate
      ..bits = dataBits
      ..stopBits = stopBits
      ..parity = _parityConstant(parity);
    if (hardwareFlowControl) {
      config.setFlowControl(SerialPortFlowControl.rtsCts);
    } else {
      config.setFlowControl(SerialPortFlowControl.none);
    }
    _port.config = config;
    // Do NOT call config.dispose() here. The SerialPort implementation stores
    // the reference in _config and disposes it in port.dispose(). Calling
    // dispose() here would cause a double-free when the port is later closed,
    // manifesting as `free(): invalid pointer` on physical disconnect.
  }

  @override
  Stream<Uint8List> get byteStream {
    _reader ??= SerialPortReader(_port);
    return _reader!.stream;
  }

  @override
  void write(Uint8List data) {
    final written = _port.write(data);
    debugPrint('SerialPortAdapter: write ${data.length}b → wrote ${written}b');
    if (written != data.length) {
      // sp_nonblocking_write returned fewer bytes than requested — the serial
      // tx buffer was full or the port is in an error state. Treat as a write
      // error so the caller (SerialKissTransport.sendFrame) can trigger
      // disconnect and the exception propagates to the message/beacon layer.
      throw Exception('Serial write incomplete: $written/${data.length} bytes');
    }
  }

  @override
  void close() {
    // Close the OS file descriptor first. On Linux this causes any thread
    // blocked in read() on this fd to return EBADF immediately, allowing the
    // native SerialPortReader thread to exit its loop before we try to free
    // its resources. Reversing this order (reader first) leaves the thread
    // mid-read when libserialport frees the buffer → heap corruption crash.
    try {
      _port.close();
    } catch (_) {}
    try {
      _reader?.close();
    } catch (_) {
      // Reader may already be closed after a physical disconnect.
    }
    _reader = null;
    try {
      _port.dispose();
    } catch (_) {}
  }

  int _parityConstant(String parity) {
    switch (parity) {
      case 'odd':
        return SerialPortParity.odd;
      case 'even':
        return SerialPortParity.even;
      default:
        return SerialPortParity.none;
    }
  }
}
