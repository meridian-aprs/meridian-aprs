library;

import 'dart:typed_data';

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
    config.dispose();
  }

  @override
  Stream<Uint8List> get byteStream {
    _reader ??= SerialPortReader(_port);
    return _reader!.stream;
  }

  @override
  void write(Uint8List data) => _port.write(data);

  @override
  void close() {
    _reader?.close();
    _reader = null;
    _port.close();
    _port.dispose();
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
