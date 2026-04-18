import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../screens/message_thread_screen.dart';
import '../../theme/meridian_colors.dart';
import '../utils/platform_route.dart';

/// Payload carried by a single in-app notification banner.
class BannerPayload {
  const BannerPayload({
    required this.callsign,
    required this.text,
    required this.timestamp,
  });

  final String callsign;
  final String text;
  final DateTime timestamp;
}

/// Controls the [InAppBannerOverlay] from outside the widget tree.
///
/// Holds the currently visible banner (if any). [NotificationService] calls
/// [show] after dispatching a system notification; the overlay widget reacts
/// via ChangeNotifier.
class InAppBannerController extends ChangeNotifier {
  BannerPayload? _current;

  BannerPayload? get current => _current;

  /// Show a banner for the message from [callsign].
  ///
  /// If a banner is already showing it is replaced immediately.
  void show(String callsign, String text) {
    _current = BannerPayload(
      callsign: callsign,
      text: text,
      timestamp: DateTime.now(),
    );
    notifyListeners();
  }

  /// Dismiss the currently visible banner.
  void dismiss() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }
}

/// Wraps [child] with a slide-in notification banner anchored at the top (or
/// top-right on wide screens).
///
/// Insert this widget around the responsive scaffold so the banner appears on
/// every screen without per-screen wiring.
class InAppBannerOverlay extends StatefulWidget {
  const InAppBannerOverlay({
    super.key,
    required this.controller,
    required this.child,
  });

  final InAppBannerController controller;
  final Widget child;

  @override
  State<InAppBannerOverlay> createState() => _InAppBannerOverlayState();
}

class _InAppBannerOverlayState extends State<InAppBannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Offset> _slide;

  BannerPayload? _payload;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));

    widget.controller.addListener(_onControllerChange);
  }

  @override
  void didUpdateWidget(InAppBannerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    _dismissTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    final next = widget.controller.current;
    if (next == null) {
      _dismiss();
    } else {
      setState(() => _payload = next);
      _anim.forward(from: 0);
      _dismissTimer?.cancel();
      _dismissTimer = Timer(const Duration(seconds: 4), _autoDismiss);
    }
  }

  void _autoDismiss() {
    if (!mounted) return;
    _dismiss();
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    _anim.reverse().then((_) {
      if (mounted) setState(() => _payload = null);
    });
    widget.controller.dismiss();
  }

  void _onTap() {
    final payload = _payload;
    if (payload == null) return;
    _dismiss();
    Navigator.of(context).push(
      buildPlatformRoute(
        (_) => MessageThreadScreen(peerCallsign: payload.callsign),
      ),
    );
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (details.primaryVelocity != null && details.primaryVelocity! < -200) {
      _dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width > 1024 && !kIsWeb;

    return Stack(
      children: [
        widget.child,
        if (_payload != null)
          Positioned(
            top: isWide ? 16 : 0,
            right: isWide ? 16 : 0,
            left: isWide ? null : 0,
            child: SafeArea(
              child: isWide
                  ? SizedBox(width: 320, child: _buildBanner(context))
                  : _buildBanner(context),
            ),
          ),
      ],
    );
  }

  Widget _buildBanner(BuildContext context) {
    final payload = _payload!;
    final theme = Theme.of(context);
    final preview = payload.text.length > 60
        ? '${payload.text.substring(0, 60)}…'
        : payload.text;
    final elapsed = DateTime.now().difference(payload.timestamp);
    final timeLabel = elapsed.inSeconds < 10
        ? 'Just now'
        : elapsed.inMinutes < 1
        ? '${elapsed.inSeconds}s ago'
        : '${elapsed.inMinutes}m ago';

    return SlideTransition(
      position: _slide,
      child: GestureDetector(
        onTap: _onTap,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left accent bar.
                    Container(width: 4, color: MeridianColors.primary),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    payload.callsign,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    preview,
                                    style: theme.textTheme.bodySmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              timeLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
