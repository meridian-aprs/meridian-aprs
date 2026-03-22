import 'package:flutter/cupertino.dart';

import 'meridian_colors.dart';

/// Builds the iOS [CupertinoThemeData] for the given [brightness].
///
/// Uses fixed Meridian brand colors — no dynamic color or seed color on iOS.
/// San Francisco font is applied automatically by Flutter on iOS; no
/// [CupertinoTextThemeData] override is needed.
///
/// Light/dark switching is controlled by the [brightness] parameter, which
/// the app root resolves from [ThemeController.themeMode] before calling this
/// function. [CupertinoColors] system colors (e.g. systemBackground) resolve
/// automatically for the given brightness.
CupertinoThemeData buildIosTheme({required Brightness brightness}) {
  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: MeridianColors.primary,
  );
}
