import 'package:flutter/cupertino.dart';

import 'meridian_colors.dart';

/// Builds the iOS [CupertinoThemeData] for the given [brightness].
///
/// [primaryColor] sets the app tint color (buttons, links, active controls).
/// Defaults to [MeridianColors.primary]. Pass [ThemeController.seedColor] to
/// honour the user's color preference from the App Color picker.
///
/// San Francisco font is applied automatically by Flutter on iOS; no
/// [CupertinoTextThemeData] override is needed.
///
/// Light/dark switching is controlled by the [brightness] parameter, which
/// the app root resolves from [ThemeController.themeMode] before calling this
/// function. [CupertinoColors] system colors (e.g. systemBackground) resolve
/// automatically for the given brightness.
CupertinoThemeData buildIosTheme({
  required Brightness brightness,
  Color primaryColor = MeridianColors.primary,
}) {
  return CupertinoThemeData(brightness: brightness, primaryColor: primaryColor);
}
