import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Meridian APRS wordmark lockup (icon + text, locked proportions).
///
/// Primary variants ([horizontal], [stacked]) adapt automatically to the
/// ambient theme brightness — dark-mode SVG variants swap in when
/// `Theme.of(context).brightness == Brightness.dark`. The dark SVGs use
/// brand tone 80 (#C8B0E8) on transparent backgrounds, following M3 convention.
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
    final asset = _style.assetFor(isDark);
    return SvgPicture.asset(
      asset,
      height: height,
      width: width,
      semanticsLabel: 'Meridian APRS',
    );
  }
}

enum _WordmarkStyle {
  horizontal,
  stacked,
  horizontalMono,
  horizontalMonoWhite,
  stackedMono;

  String assetFor(bool isDark) {
    final dark = _darkAsset;
    if (isDark && dark != null) return dark;
    return _lightAsset;
  }

  String get _lightAsset => switch (this) {
    _WordmarkStyle.horizontal =>
      'assets/wordmarks/wordmark-horizontal-primary.svg',
    _WordmarkStyle.stacked => 'assets/wordmarks/wordmark-stacked-primary.svg',
    _WordmarkStyle.horizontalMono =>
      'assets/wordmarks/wordmark-horizontal-mono-black.svg',
    _WordmarkStyle.horizontalMonoWhite =>
      'assets/wordmarks/wordmark-horizontal-mono-white.svg',
    _WordmarkStyle.stackedMono =>
      'assets/wordmarks/wordmark-stacked-mono-black.svg',
  };

  String? get _darkAsset => switch (this) {
    _WordmarkStyle.horizontal =>
      'assets/wordmarks/wordmark-horizontal-primary-dark.svg',
    _WordmarkStyle.stacked =>
      'assets/wordmarks/wordmark-stacked-primary-dark.svg',
    _ => null,
  };
}
