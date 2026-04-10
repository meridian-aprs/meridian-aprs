import 'package:flutter/material.dart';

import '../../core/transport/aprs_transport.dart' show ConnectionStatus;
import '../../theme/meridian_colors.dart';

/// A compact status indicator pill for the top app bar.
///
/// Shows a colored dot and a label reflecting the current [ConnectionStatus].
/// The dot pulses with a [FadeTransition] while [ConnectionStatus.connecting].
///
/// Always satisfies the 44×44 px minimum tap target via internal padding.
class MeridianStatusPill extends StatefulWidget {
  const MeridianStatusPill({
    super.key,
    required this.status,
    required this.label,
    this.onTap,
  });

  final ConnectionStatus status;
  final String label;
  final VoidCallback? onTap;

  @override
  State<MeridianStatusPill> createState() => _MeridianStatusPillState();
}

class _MeridianStatusPillState extends State<MeridianStatusPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(MeridianStatusPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.status == ConnectionStatus.connecting ||
        widget.status == ConnectionStatus.reconnecting ||
        widget.status == ConnectionStatus.waitingForDevice) {
      _animController.repeat(reverse: true);
    } else {
      _animController.stop();
      _animController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  static String _stateLabel(ConnectionStatus s) => switch (s) {
    ConnectionStatus.connected => 'Connected',
    ConnectionStatus.connecting => 'Connecting',
    ConnectionStatus.reconnecting => 'Reconnecting',
    ConnectionStatus.waitingForDevice => 'Searching\u2026',
    ConnectionStatus.disconnected => 'Disconnected',
    ConnectionStatus.error => 'Error',
  };

  Color _dotColor() {
    switch (widget.status) {
      case ConnectionStatus.connected:
        return MeridianColors.signal;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
      case ConnectionStatus.waitingForDevice:
        return MeridianColors.warning;
      case ConnectionStatus.disconnected:
        return MeridianColors.danger;
      case ConnectionStatus.error:
        return MeridianColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dot = FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: _dotColor()),
      ),
    );

    return Semantics(
      label:
          'Connection status: ${widget.label} — ${_stateLabel(widget.status)}',
      button: widget.onTap != null,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          // Minimum 44×44 tap target.
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              dot,
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
