import 'package:flutter/widgets.dart';

/// A widget that renders an APRS symbol from the hessu/aprs-symbols sprite
/// sheets (https://github.com/hessu/aprs-symbols).
///
/// APRS symbols are identified by a [symbolTable] character ('/' for the
/// primary table, '\' for the alternate) and a [symbolCode] character.
///
/// The sprite sheets are 16 columns × 6 rows at 64 px per cell.  Symbol
/// position is derived directly from the ASCII code of [symbolCode]:
///
///   pos = codeUnit − 33   (covers printable ASCII 33–126)
///   col = pos % 16
///   row = pos ÷ 16
///
/// Overlay symbols (symbolTable is a digit 0–9 or uppercase letter A–Z) are
/// rendered using the alternate-table base symbol with the overlay character
/// drawn as white bold text centered on top of the icon.
class AprsSymbolWidget extends StatelessWidget {
  const AprsSymbolWidget({
    super.key,
    required this.symbolTable,
    required this.symbolCode,
    this.size = 24.0,
  });

  /// APRS symbol table identifier: '/' (primary) or '\' (alternate).
  final String symbolTable;

  /// APRS symbol code — a single printable ASCII character.
  final String symbolCode;

  /// Rendered size in logical pixels. Both width and height are set to this
  /// value.
  final double size;

  static const int _kCols = 16;
  static const int _kRows = 6;

  /// Returns true when [symbolTable] is an overlay character (digit 0–9 or
  /// uppercase letter A–Z) rather than a standard table selector ('/' or '\').
  bool get _isOverlaySymbol {
    if (symbolTable.isEmpty) return false;
    final c = symbolTable.codeUnitAt(0);
    return (c >= 48 && c <= 57) || (c >= 65 && c <= 90);
  }

  @override
  Widget build(BuildContext context) {
    final int pos = symbolCode.isNotEmpty
        ? (symbolCode.codeUnitAt(0) - 33).clamp(0, 93)
        : 0;
    final int col = pos % _kCols;
    final int row = pos ~/ _kCols;

    // Overlay symbols use the alternate table sheet as their base image.
    final String sheet = symbolTable == '/'
        ? 'assets/aprs_symbols/aprs-symbols-64-0.png'
        : 'assets/aprs_symbols/aprs-symbols-64-1.png';

    // Stack + Positioned is used here instead of ClipRect + Align because Align
    // passes loosed constraints to its child, capping the image at the parent
    // size. Positioned with explicit width/height gives the image tight
    // constraints at the full sprite-sheet size, and Stack clips the overflow.
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: -col * size,
            top: -row * size,
            width: size * _kCols,
            height: size * _kRows,
            child: Image.asset(
              sheet,
              filterQuality: FilterQuality.medium,
              fit: BoxFit.fill,
            ),
          ),
          if (_isOverlaySymbol)
            Center(
              child: Text(
                symbolTable,
                style: TextStyle(
                  fontSize: size * 0.55,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFFFFFFF),
                  height: 1.0,
                  shadows: const [
                    Shadow(color: Color(0x89000000), blurRadius: 2),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
