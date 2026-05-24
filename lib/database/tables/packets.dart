import 'package:drift/drift.dart';

import '../../core/packet/aprs_packet.dart';

/// Enum mirroring the sealed [AprsPacket] hierarchy. Stored as text so that
/// adding new packet types in the future is non-breaking.
enum PacketTypeTag {
  position,
  weather,
  message,
  object,
  item,
  status,
  micE,
  unknown,
}

@DataClassName('PacketRow')
class Packets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get rawLine => text().named('raw_line')();
  TextColumn get packetType => text()
      .named('packet_type')
      .map(const EnumNameConverter(PacketTypeTag.values))();
  TextColumn get sourceCallsign => text().named('source_callsign')();
  TextColumn get destination => text().nullable()();
  IntColumn get receivedAt => integer().named('received_at')();
  BoolColumn get isOutgoing =>
      boolean().named('is_outgoing').withDefault(const Constant(false))();
  TextColumn get sourceChannel => text()
      .named('source_channel')
      .map(const EnumNameConverter(PacketSource.values))();
}
