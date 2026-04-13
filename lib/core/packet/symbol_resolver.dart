/// Resolves APRS symbol table + code pairs to human-readable names.
///
/// APRS symbols are identified by two characters:
///   - [symbolTable]: '/' for the primary table, '\' for the alternate table,
///     or an overlay character (0-9, A-Z) for overlaid alternate-table symbols.
///   - [symbolCode]: a printable ASCII character identifying the icon within
///     the selected table.
///
/// Reference: APRS Protocol Reference 1.0.1, Chapter 20 + symbolsX.txt.
class SymbolResolver {
  SymbolResolver._();

  static const Map<String, String> _primary = {
    '!': 'Police / Sheriff',
    '#': 'Digipeater',
    '\$': 'Phone',
    '%': 'DX Cluster',
    '&': 'HF Gateway',
    "'": 'Aircraft (Small)',
    '(': 'Mobile Satellite Station',
    ')': 'Wheelchair',
    '*': 'Snowmobile',
    '+': 'Red Cross',
    ',': 'Boy Scouts',
    '-': 'House / Home Station',
    '.': 'X / Dot',
    '/': 'Dot',
    ':': 'Fire',
    ';': 'Campground / Portable Ops',
    '<': 'Motorcycle',
    '=': 'Railroad Engine',
    '>': 'Car',
    '?': 'File Server',
    '@': 'Storm (Forecast)',
    'A': 'Aid Station',
    'B': 'BBS / PBBS',
    'C': 'Canoe',
    'E': 'Eyeball / Event',
    'F': 'Farm Vehicle / Tractor',
    'G': 'Grid Square',
    'H': 'Hotel',
    'I': 'TCP/IP Network Station',
    'K': 'School',
    'L': 'PC User',
    'M': 'MacAPRS',
    'N': 'NTS Station',
    'O': 'Balloon',
    'P': 'Police',
    'R': 'Recreational Vehicle',
    'S': 'Space Shuttle',
    'T': 'SSTV',
    'U': 'Bus',
    'V': 'ATV',
    'W': 'NWS Site',
    'X': 'Helicopter',
    'Y': 'Yacht / Sailboat',
    'Z': 'WinAPRS',
    '[': 'Human / Person',
    '^': 'Aircraft (Large)',
    '_': 'Weather Station',
    'a': 'Ambulance',
    'b': 'Bicycle',
    'c': 'Incident Command Post',
    'd': 'Fire Department',
    'e': 'Horse / Equestrian',
    'f': 'Fire Truck',
    'g': 'Glider',
    'h': 'Hospital',
    'i': 'IOTA (Islands on the Air)',
    'j': 'Jeep',
    'k': 'Truck',
    'l': 'Laptop',
    'm': 'Mic-E Repeater',
    'n': 'Node',
    'o': 'EOC',
    'p': 'Rover / Dog',
    'r': 'Repeater',
    's': 'Ship / Power Boat',
    't': 'Truck Stop',
    'u': 'Semi Truck',
    'v': 'Van',
    'w': 'Water Station',
    'x': 'xAPRS (Unix)',
    'y': 'Yagi Antenna',
    'z': 'Shelter',
  };

  static const Map<String, String> _alternate = {
    '!': 'Emergency',
    '#': 'Overlay Digi',
    '\$': 'Bank / ATM',
    '&': 'IGate / Gateway',
    "'": 'Crash / Incident',
    '(': 'Cloudy',
    '+': 'Church',
    '-': 'House (HF)',
    '.': 'Ambiguous',
    '<': 'Advisory (WX Flag)',
    '@': 'Hurricane / Tropical Storm',
    'C': 'Coast Guard',
    'D': 'Depot',
    'E': 'Smoke',
    'H': 'Haze / Hazard',
    'I': 'Rain Shower',
    'K': 'Kenwood HT',
    'L': 'Lighthouse',
    'M': 'MARS',
    'N': 'Navigation Buoy',
    'O': 'Balloon / Rocket (Overlay)',
    'P': 'Parking',
    'Q': 'Earthquake',
    'R': 'Restaurant',
    'S': 'Satellite / Pacsat',
    'T': 'Thunderstorm',
    'U': 'Sunny',
    'V': 'VORTAC Nav Aid',
    'W': 'NWS Site',
    'X': 'Pharmacy',
    '_': 'WX Site (Digi)',
    'a': 'ARRL / RAC',
    'c': 'CD Triangle / RACES / SATERN',
    'd': 'DX Spot',
    'e': 'Sleet',
    'f': 'Funnel Cloud',
    'g': 'Gale Flags',
    'h': 'Ham Store',
    'j': 'Work Zone',
    'k': 'Special Vehicle (4x4)',
    'r': 'Restrooms',
    's': 'Ship / Boat (Overlay)',
    't': 'Tornado',
    'u': 'Truck (Overlay)',
    'v': 'Van (Overlay)',
    'w': 'Flooding',
    'x': 'Wreck / Obstruction',
    'y': 'Skywarn',
    'z': 'Shelter (Overlay)',
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
