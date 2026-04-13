/// Parses APRS WX field tokens from a comment/raw string.
/// Returns null if no WX tokens are found.
class WxData {
  WxData._();

  int? windDir;
  double? windSpeed;
  double? windGust;
  double? tempF;
  double? rainfall1h;
  double? rainfall24h;
  double? rainSinceMidnight;
  int? humidity;
  double? _pressureRaw; // tenths of mbar
  int? luminosity;

  static final _re = RegExp(
    r'c(\d{3})|s(\d{3})|g(\d{3})|t(-?\d{3})|r(\d{3})|p(\d{3})|P(\d{3})|h(\d{2})|b(\d{5})|L(\d{3,4})',
  );

  static WxData? parse(String text) {
    final matches = _re.allMatches(text).toList();
    if (matches.isEmpty) return null;
    final wx = WxData._();
    for (final m in matches) {
      if (m.group(1) != null) {
        wx.windDir = int.tryParse(m.group(1)!);
      } else if (m.group(2) != null) {
        wx.windSpeed = double.tryParse(m.group(2)!);
      } else if (m.group(3) != null) {
        wx.windGust = double.tryParse(m.group(3)!);
      } else if (m.group(4) != null) {
        wx.tempF = double.tryParse(m.group(4)!);
      } else if (m.group(5) != null) {
        wx.rainfall1h = double.tryParse(m.group(5)!);
      } else if (m.group(6) != null) {
        wx.rainfall24h = double.tryParse(m.group(6)!);
      } else if (m.group(7) != null) {
        wx.rainSinceMidnight = double.tryParse(m.group(7)!);
      } else if (m.group(8) != null) {
        wx.humidity = int.tryParse(m.group(8)!);
      } else if (m.group(9) != null) {
        wx._pressureRaw = double.tryParse(m.group(9)!);
      } else if (m.group(10) != null) {
        wx.luminosity = int.tryParse(m.group(10)!);
      }
    }
    return wx;
  }

  double? get tempC => tempF != null ? (tempF! - 32) * 5 / 9 : null;
  double? get pressureHpa => _pressureRaw != null ? _pressureRaw! / 10.0 : null;

  String? get windSummary {
    final hasDirSpeed = windDir != null || windSpeed != null;
    final hasGust = windGust != null && windGust! > 0;
    if (!hasDirSpeed && !hasGust) return null;
    final dir = windDir != null ? _compassDir(windDir!) : null;
    final speed = windSpeed != null ? '${windSpeed!.round()} mph' : null;
    final gust = hasGust ? 'gusts ${windGust!.round()} mph' : null;
    String dirSpeed = '';
    if (dir != null && speed != null) {
      dirSpeed = '$dir at $speed';
    } else if (speed != null) {
      dirSpeed = speed;
    } else if (dir != null) {
      dirSpeed = dir;
    }
    final parts = [if (dirSpeed.isNotEmpty) dirSpeed, ?gust];
    return parts.join(', ');
  }

  static String _compassDir(int deg) {
    const dirs = [
      'N',
      'NNE',
      'NE',
      'ENE',
      'E',
      'ESE',
      'SE',
      'SSE',
      'S',
      'SSW',
      'SW',
      'WSW',
      'W',
      'WNW',
      'NW',
      'NNW',
    ];
    return dirs[((deg + 11.25) / 22.5).floor() % 16];
  }
}
