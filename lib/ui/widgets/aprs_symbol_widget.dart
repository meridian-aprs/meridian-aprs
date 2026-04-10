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
/// Overlay symbols (symbolTable is a digit or letter rather than '\') are
/// shown using the alternate-table base symbol; overlay character rendering
/// is a future improvement.
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

  @override
  Widget build(BuildContext context) {
    final int pos = symbolCode.isNotEmpty
        ? (symbolCode.codeUnitAt(0) - 33).clamp(0, 93)
        : 0;
    final int col = pos % _kCols;
    final int row = pos ~/ _kCols;

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
        ],
      ),
    );
  }
}
