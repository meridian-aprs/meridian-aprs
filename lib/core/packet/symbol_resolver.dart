/// Resolves APRS symbol table + code pairs to human-readable names.
///
/// APRS symbols are identified by two characters:
///   - [symbolTable]: '/' for the primary table, '\' for the alternate table,
///     or an overlay character (0-9, A-Z) for overlaid alternate-table symbols.
///   - [symbolCode]: a printable ASCII character identifying the icon within
///     the selected table.
///
/// Reference: APRS Protocol Reference 1.0.1, Chapter 20.
class SymbolResolver {
  SymbolResolver._();

  static const Map<String, String> _primary = {
    '!': 'Police Station',
    '#': 'Digipeater',
    '\$': 'Phone',
    '%': 'DX Cluster',
    '&': 'HF Gateway',
    "'": 'Aircraft (Small)',
    '-': 'House / Home Station',
    '.': 'X',
    '/': 'Dot',
    '<': 'Motorcycle',
    '=': 'Railroad Engine',
    '>': 'Car',
    '?': 'File Server',
    '@': 'Hurricane',
    'O': 'Balloon',
    'P': 'Police',
    'R': 'Recreational Vehicle',
    'S': 'Space Shuttle',
    'T': 'SSTV',
    'U': 'Bus',
    'W': 'NWS Site',
    'X': 'Helicopter',
    'Y': 'Yacht / Sailboat',
    '[': 'Jogger / Hiker',
    '^': 'Aircraft (Large)',
    '_': 'Weather Station',
    'a': 'Ambulance',
    'b': 'Bicycle',
    'd': 'Fire Department',
    'e': 'Horse / Equestrian',
    'f': 'Fire Truck',
    'g': 'Glider',
    'h': 'Hospital',
    'j': 'Jeep',
    'k': 'Truck',
    'r': 'Restaurant',
    's': 'Sailboat (Small)',
    'u': 'Semi Truck',
    'v': 'Van',
    'w': 'Water Station',
    'y': 'Yagi Antenna',
    'z': 'Shelter',
  };

  static const Map<String, String> _alternate = {
    '#': 'Overlay Digi',
    '-': 'HF Gateway',
    'a': 'ARRL / RAC',
  };

  static const String _fallback = 'Station';

  /// Returns a human-readable name for the given APRS symbol.
  ///
  /// [symbolTable] should be '/' (primary), '\' (alternate), or an overlay
  /// character. [symbolCode] is the printable ASCII icon selector.
  ///
  /// Returns [_fallback] ('Station') when the combination is not recognised.
  static String symbolName(String symbolTable, String symbolCode) {
    if (symbolTable == '/') {
      return _primary[symbolCode] ?? _fallback;
    }
    if (symbolTable == r'\') {
      return _alternate[symbolCode] ?? _fallback;
    }
    // Overlay characters select the alternate table with a numeric/alpha overlay.
    return _alternate[symbolCode] ?? _fallback;
  }

  /// Returns true when [symbolTable] + [symbolCode] is an explicitly recognised
  /// combination.
  static bool isKnown(String symbolTable, String symbolCode) {
    if (symbolTable == '/') return _primary.containsKey(symbolCode);
    if (symbolTable == r'\') return _alternate.containsKey(symbolCode);
    return _alternate.containsKey(symbolCode);
  }
}
