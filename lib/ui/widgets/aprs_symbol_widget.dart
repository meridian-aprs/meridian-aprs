import 'package:flutter/material.dart';

/// A widget that renders an APRS symbol as a Material icon.
///
/// APRS symbols are identified by a [symbolTable] character ('/' for the
/// primary table, '\' for the alternate) and a [symbolCode] character.
///
/// This widget abstracts symbol rendering so the underlying approach (Material
/// icons, custom sprites, APRS symbol sheet bitmaps, etc.) can be swapped
/// without touching call sites.
class AprsSymbolWidget extends StatelessWidget {
  const AprsSymbolWidget({
    super.key,
    required this.symbolTable,
    required this.symbolCode,
    this.size = 24.0,
    this.color,
  });

  /// APRS symbol table identifier: '/' (primary) or '\' (alternate).
  final String symbolTable;

  /// APRS symbol code — a single printable ASCII character.
  final String symbolCode;

  /// Rendered size in logical pixels.
  final double size;

  /// Icon color. Defaults to the ambient [IconTheme] color when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(_iconData(symbolCode), size: size, color: color);
  }

  /// Maps an APRS symbol code to the best available Material icon.
  static IconData iconDataForSymbol(String symbolCode) => _iconData(symbolCode);
}

IconData _iconData(String symbolCode) {
  switch (symbolCode) {
    case '-':
      return Icons.home;
    case '>':
      return Icons.directions_car;
    case 'k':
    case 'u':
      return Icons.local_shipping;
    case 'U':
      return Icons.directions_bus;
    case 'a':
      return Icons.local_hospital;
    case 'X':
      return Icons.flight;
    case "'":
    case '^':
      return Icons.flight;
    case 'O':
      return Icons.circle_outlined;
    case '_':
      return Icons.wb_cloudy;
    case 'b':
      return Icons.directions_bike;
    case 'h':
      return Icons.local_hospital;
    case 'f':
    case 'd':
      return Icons.local_fire_department;
    case '<':
      return Icons.two_wheeler;
    case 'Y':
    case 's':
      return Icons.sailing;
    case 'P':
    case '!':
      return Icons.local_police;
    case '[':
      return Icons.directions_walk;
    case '#':
      return Icons.cell_tower;
    default:
      return Icons.location_on;
  }
}
