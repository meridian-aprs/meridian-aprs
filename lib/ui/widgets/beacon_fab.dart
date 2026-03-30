import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/beaconing_service.dart';
import '../../theme/meridian_colors.dart';

/// A large FAB that represents the beacon transmit action.
///
/// - Idle/manual: primary blue background, broadcasting icon.
/// - Active ([isBeaconing] == true): pulsing danger red, mode label.
///
/// The hero tag is fixed to `'beacon_fab'` to avoid conflicts in scaffolds
/// that show multiple FABs.
class BeaconFAB extends StatefulWidget {
  const BeaconFAB({
    super.key,
    required this.isBeaconing,
    required this.onTap,
    this.mode = BeaconMode.manual,
    this.lastBeaconAt,
    this.onLongPress,
  });

  final bool isBeaconing;
  final Future<void> Function() onTap;
  final BeaconMode mode;
  final DateTime? lastBeaconAt;

  /// Called when a long-press fires.
  final Future<void> Function()? onLongPress;

  @override
  State<BeaconFAB> createState() => _BeaconFABState();
}

class _BeaconFABState extends State<BeaconFAB>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;

  Timer? _agoTimer;
  DateTime? _lastLongPress;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnim = Tween<double>(
      begin: 0.92,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));
    _syncAnimation();
    _startAgoTimer();
  }

  @override
  void didUpdateWidget(BeaconFAB old) {
    super.didUpdateWidget(old);
    if (old.isBeaconing != widget.isBeaconing) _syncAnimation();
    if (old.lastBeaconAt != widget.lastBeaconAt) _startAgoTimer();
  }

  void _syncAnimation() {
    if (widget.isBeaconing) {
      _animCtrl.repeat(reverse: true);
    } else {
      _animCtrl.stop();
      _animCtrl.value = 0;
    }
  }

  void _startAgoTimer() {
    _agoTimer?.cancel();
    if (widget.lastBeaconAt != null) {
      _agoTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _agoTimer?.cancel();
    super.dispose();
  }

  String get _label {
    if (!widget.isBeaconing) return 'Beacon';
    return switch (widget.mode) {
      BeaconMode.auto => 'Beaconing (Auto)',
      BeaconMode.smart => 'Beaconing (Smart)',
      BeaconMode.manual => 'Beaconing',
    };
  }

  String get _tooltip => switch (widget.mode) {
    BeaconMode.manual => 'Manual beacon',
    BeaconMode.auto => 'Auto beacon',
    BeaconMode.smart => 'SmartBeaconing™',
  };

  String? _agoText() {
    if (widget.lastBeaconAt == null) return null;
    final diff = DateTime.now().difference(widget.lastBeaconAt!);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  Future<void> _handleTap() async {
    if (_isSending) return;
    HapticFeedback.mediumImpact();
    setState(() => _isSending = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _handleLongPress() async {
    if (widget.onLongPress == null || _isSending) return;
    final now = DateTime.now();
    if (_lastLongPress != null &&
        now.difference(_lastLongPress!) < const Duration(seconds: 30)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait 30 seconds between manual beacons.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    _lastLongPress = now;
    HapticFeedback.mediumImpact();
    setState(() => _isSending = true);
    try {
      await widget.onLongPress!();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = widget.isBeaconing
        ? MeridianColors.danger
        : colorScheme.primary;
    final fgColor = widget.isBeaconing ? Colors.white : colorScheme.onPrimary;

    final ago = _agoText();

    return ScaleTransition(
      scale: widget.isBeaconing
          ? _scaleAnim
          : const AlwaysStoppedAnimation(1.0),
      child: Semantics(
        label: widget.isBeaconing ? 'Stop beaconing' : 'Start beacon',
        button: true,
        child: Tooltip(
          message: _tooltip,
          child: GestureDetector(
            onLongPress: widget.onLongPress != null ? _handleLongPress : null,
            child: FloatingActionButton.extended(
              heroTag: 'beacon_fab',
              backgroundColor: bgColor,
              foregroundColor: fgColor,
              onPressed: _isSending ? null : _handleTap,
              icon: _isSending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(fgColor),
                      ),
                    )
                  : Icon(
                      widget.isBeaconing
                          ? Symbols.wifi_tethering
                          : Symbols.podcasts,
                    ),
              label: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_label),
                  if (ago != null)
                    Text(
                      ago,
                      style: TextStyle(
                        fontSize: 10,
                        color: fgColor.withAlpha(180),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
