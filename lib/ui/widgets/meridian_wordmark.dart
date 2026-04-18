import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Meridian APRS wordmark lockup (icon + text, locked proportions).
///
/// Use the named constructors for the intended context:
/// - [MeridianWordmark.horizontal] — default; about screens, README, docs
/// - [MeridianWordmark.stacked] — square/portrait contexts; onboarding welcome
/// - [MeridianWordmark.horizontalMono] — monochrome black; print-like contexts
/// - [MeridianWordmark.horizontalMonoWhite] — monochrome white; dark surfaces
/// - [MeridianWordmark.stackedMono] — monochrome stacked
///
/// Supply [height] or [width]; the SVG scales proportionally.
class MeridianWordmark extends StatelessWidget {
  final String _assetPath;
  final double? height;
  final double? width;
  final String _semanticLabel;

  const MeridianWordmark.horizontal({super.key, this.height, this.width})
    : _assetPath = 'assets/wordmarks/wordmark-horizontal-primary.svg',
      _semanticLabel = 'Meridian APRS';

  const MeridianWordmark.stacked({super.key, this.height, this.width})
    : _assetPath = 'assets/wordmarks/wordmark-stacked-primary.svg',
      _semanticLabel = 'Meridian APRS';

  const MeridianWordmark.horizontalMono({super.key, this.height, this.width})
    : _assetPath = 'assets/wordmarks/wordmark-horizontal-mono-black.svg',
      _semanticLabel = 'Meridian APRS';

  const MeridianWordmark.horizontalMonoWhite({
    super.key,
    this.height,
    this.width,
  }) : _assetPath = 'assets/wordmarks/wordmark-horizontal-mono-white.svg',
       _semanticLabel = 'Meridian APRS';

  const MeridianWordmark.stackedMono({super.key, this.height, this.width})
    : _assetPath = 'assets/wordmarks/wordmark-stacked-mono-black.svg',
      _semanticLabel = 'Meridian APRS';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _assetPath,
      height: height,
      width: width,
      semanticsLabel: _semanticLabel,
    );
  }
}
