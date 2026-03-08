import 'package:flutter/material.dart';

/// A themed draggable bottom sheet with a visible drag handle.
///
/// Wrap any content in this widget and pass it to [showModalBottomSheet]
/// with `isScrollControlled: true` so the sheet can grow to [maxSize].
///
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => MeridianBottomSheet(child: MyContent()),
/// );
/// ```
class MeridianBottomSheet extends StatelessWidget {
  const MeridianBottomSheet({
    super.key,
    required this.child,
    this.initialSize = 0.4,
    this.minSize = 0.12,
    this.maxSize = 0.92,
  });

  final Widget child;

  /// Fraction of the screen height occupied when first shown.
  final double initialSize;

  /// Minimum fraction the sheet can be collapsed to.
  final double minSize;

  /// Maximum fraction the sheet can expand to.
  final double maxSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withAlpha(80),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // Scrollable content area
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
