import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../theme/meridian_colors.dart';
import '../../../theme/theme_controller.dart';
import '../widgets/section_header.dart';

/// Seed color picker shown on all platforms.
///
/// On Android 12+ a "System" swatch appears first — selecting it re-enables
/// wallpaper-derived dynamic color. On all other platforms (iOS, desktop,
/// Android 11 and below) only the fixed seed swatches are shown.
class AppColorSection extends StatelessWidget {
  const AppColorSection({super.key});

  static const _swatches = [
    (label: 'Meridian Purple', color: MeridianColors.brandSeed),
    (label: 'Slate', color: Color(0xFF64748B)),
    (label: 'Indigo', color: Color(0xFF4F46E5)),
    (label: 'Rose', color: Color(0xFFE11D48)),
    (label: 'Amber', color: Color(0xFFD97706)),
    (label: 'Teal', color: Color(0xFF0D9488)),
    (label: 'Emerald', color: Color(0xFF059669)),
    (label: 'Sky', color: Color(0xFF0284C7)),
  ];

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();

    final controller = context.watch<ThemeController>();
    final outline = Theme.of(context).colorScheme.outline;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    final subtitle = controller.dynamicColorAvailable
        ? 'Tap a color to override wallpaper theming.'
        : 'Choose the app accent color.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('App Color'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  // "System" swatch — only on Android 12+ (dynamic color capable).
                  if (controller.dynamicColorAvailable)
                    _ColorSwatch(
                      label: 'System',
                      isSelected: controller.useDynamicColor,
                      outline: outline,
                      onTap: () =>
                          context.read<ThemeController>().setUseDynamicColor(),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              Color(0xFFEF4444),
                              Color(0xFFF59E0B),
                              Color(0xFF10B981),
                              Color(0xFF2563EB),
                              Color(0xFF7C3AED),
                              Color(0xFFEF4444),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Fixed seed swatches.
                  ..._swatches.map((swatch) {
                    final isSelected =
                        !controller.useDynamicColor &&
                        controller.seedColor.toARGB32() ==
                            swatch.color.toARGB32();
                    return _ColorSwatch(
                      label: swatch.label,
                      isSelected: isSelected,
                      outline: outline,
                      onTap: () => context.read<ThemeController>().setSeedColor(
                        swatch.color,
                      ),
                      child: ColoredBox(color: swatch.color),
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A 44×44 tappable circle swatch used in [AppColorSection].
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.label,
    required this.isSelected,
    required this.outline,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool isSelected;
  final Color outline;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipOval(child: SizedBox.expand(child: child)),
              if (isSelected)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: outline, width: 2.5),
                  ),
                ),
              if (isSelected)
                Icon(
                  Symbols.check,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
