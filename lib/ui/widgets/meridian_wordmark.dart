import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Meridian APRS wordmark lockup (icon + text, locked proportions).
///
/// Primary variants ([horizontal], [stacked]) adapt automatically to the
/// ambient theme brightness — primary colors on light, white-mono on dark.
/// Explicit mono variants are fixed regardless of brightness.
///
/// Supply [height] or [width]; the SVG scales proportionally.
class MeridianWordmark extends StatelessWidget {
  final _WordmarkStyle _style;
  final double? height;
  final double? width;

  const MeridianWordmark.horizontal({super.key, this.height, this.width})
    : _style = _WordmarkStyle.horizontal;

  const MeridianWordmark.stacked({super.key, this.height, this.width})
    : _style = _WordmarkStyle.stacked;

  const MeridianWordmark.horizontalMono({super.key, this.height, this.width})
    : _style = _WordmarkStyle.horizontalMono;

  const MeridianWordmark.horizontalMonoWhite({
    super.key,
    this.height,
    this.width,
  }) : _style = _WordmarkStyle.horizontalMonoWhite;

  const MeridianWordmark.stackedMono({super.key, this.height, this.width})
    : _style = _WordmarkStyle.stackedMono;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      _style.asset(isDark),
      height: height,
      width: width,
      semanticsLabel: 'Meridian APRS',
      colorFilter: _style.colorFilter(isDark),
    );
  }
}

enum _WordmarkStyle {
  horizontal,
  stacked,
  horizontalMono,
  horizontalMonoWhite,
  stackedMono;

  String asset(bool isDark) => switch (this) {
    _WordmarkStyle.horizontal =>
      isDark
          ? 'assets/wordmarks/wordmark-horizontal-mono-white.svg'
          : 'assets/wordmarks/wordmark-horizontal-primary.svg',
    // No white-stacked SVG asset — use primary + white ColorFilter in dark mode.
    _WordmarkStyle.stacked => 'assets/wordmarks/wordmark-stacked-primary.svg',
    _WordmarkStyle.horizontalMono =>
      'assets/wordmarks/wordmark-horizontal-mono-black.svg',
    _WordmarkStyle.horizontalMonoWhite =>
      'assets/wordmarks/wordmark-horizontal-mono-white.svg',
    _WordmarkStyle.stackedMono =>
      'assets/wordmarks/wordmark-stacked-mono-black.svg',
  };

  ColorFilter? colorFilter(bool isDark) => switch (this) {
    _WordmarkStyle.stacked =>
      isDark ? const ColorFilter.mode(Colors.white, BlendMode.srcIn) : null,
    _ => null,
  };
}
