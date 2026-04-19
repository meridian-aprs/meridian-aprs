import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../services/notification_service.dart';

/// Onboarding step — notification permission request (Android/iOS/macOS only).
///
/// Presents context about what Meridian notifies about before triggering the
/// OS permission dialog. "Not now" advances without requesting — the user can
/// enable notifications later in System Settings.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

enum _NotifState { initial, requesting, granted, denied }

class _NotificationsPageState extends State<NotificationsPage> {
  _NotifState _state = _NotifState.initial;

  @override
  void initState() {
    super.initState();
    _checkExistingStatus();
  }

  /// On Android, pre-populate the state if the permission was already decided
  /// (e.g. granted by BackgroundServiceManager during BLE connection). This
  /// avoids showing "Enable" when it was already granted and avoids redundantly
  /// triggering the OS dialog again.
  Future<void> _checkExistingStatus() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;
    final status = await Permission.notification.status;
    if (!mounted) return;
    if (status.isGranted) {
      setState(() => _state = _NotifState.granted);
    } else if (status.isPermanentlyDenied) {
      setState(() => _state = _NotifState.denied);
    }
  }

  Future<void> _onEnable() async {
    setState(() => _state = _NotifState.requesting);
    final granted = await context
        .read<NotificationService>()
        .requestNotificationPermissions();
    if (mounted) {
      setState(() => _state = granted ? _NotifState.granted : _NotifState.denied);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stay informed',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Meridian can notify you about activity on the APRS network '
              'even when the app is in the background.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            _buildChannelList(theme, colorScheme),
            const SizedBox(height: 32),
            _buildStateWidget(theme, colorScheme),

            const Spacer(),

            if (_state == _NotifState.initial ||
                _state == _NotifState.requesting) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      _state == _NotifState.requesting ? null : _onEnable,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _state == _NotifState.requesting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Enable Notifications'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: widget.onNext,
                  child: const Text('Not now'),
                ),
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: widget.onNext,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Next'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelList(ThemeData theme, ColorScheme colorScheme) {
    const channels = [
      (Icons.message_outlined, 'Messages', 'Direct messages from other operators'),
      (Icons.warning_amber_outlined, 'Alerts', 'APRS bulletins and NWS alerts'),
      (Icons.radio_outlined, 'Nearby stations', 'Activity from stations around you'),
      (Icons.settings_outlined, 'Connection status', 'Connection changes and errors'),
    ];

    return Column(
      children: channels
          .map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(c.$1, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.$2,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        c.$3,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildStateWidget(ThemeData theme, ColorScheme colorScheme) {
    switch (_state) {
      case _NotifState.initial:
      case _NotifState.requesting:
        return const SizedBox.shrink();

      case _NotifState.granted:
        return Row(
          children: [
            Icon(Icons.check_circle_outline, color: colorScheme.primary),
            const SizedBox(width: 12),
            Text(
              'Notifications enabled.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
              ),
            ),
          ],
        );

      case _NotifState.denied:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_off_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  'Notifications off for now.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'You can enable them later in System Settings.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
    }
  }
}
