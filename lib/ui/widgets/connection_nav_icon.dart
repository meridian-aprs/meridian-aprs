import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../core/connection/connection_registry.dart';
import '../../services/background_service_manager.dart';
import '../../theme/meridian_colors.dart';

/// Reactive navigation icon that reflects combined connection state and
/// Android background service keepalive status.
///
/// Uses [Selector] on [ConnectionRegistry] to rebuild only when
/// [aggregateStatus] changes. A separate outer [Selector] responds to
/// [BackgroundServiceState] changes.
///
/// States:
/// - Any transport connected  → filled router icon, [MeridianColors.signal]
/// - Any transport in error   → filled router icon, [MeridianColors.warning]
/// - Any transport connecting → outlined router icon, [MeridianColors.warning]
/// - All disconnected         → outlined router icon, muted
///
/// When the Android background service is [BackgroundServiceState.running] or
/// [BackgroundServiceState.reconnecting], a small badge dot is overlaid on the
/// icon to indicate the keepalive is active.
class ConnectionNavIcon extends StatelessWidget {
  const ConnectionNavIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<BackgroundServiceManager, BackgroundServiceState>(
      selector: (_, bsm) => bsm.state,
      builder: (context, bgState, _) {
        return Selector<ConnectionRegistry, ConnectionStatus>(
          selector: (_, registry) => registry.aggregateStatus,
          builder: (context, status, _) {
            return _buildIcon(context, status, bgState);
          },
        );
      },
    );
  }

  Widget _buildIcon(
    BuildContext context,
    ConnectionStatus status,
    BackgroundServiceState bgState,
  ) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    Widget icon;
    switch (status) {
      case ConnectionStatus.connected:
        icon = Icon(Symbols.router, fill: 1, color: MeridianColors.signal);
      case ConnectionStatus.error:
        icon = Icon(Symbols.router, fill: 1, color: MeridianColors.warning);
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
      case ConnectionStatus.waitingForDevice:
        icon = Icon(Symbols.router, fill: 0, color: MeridianColors.warning);
      case ConnectionStatus.disconnected:
        icon = Icon(Symbols.router, fill: 0, color: muted);
    }

    // Overlay a badge dot when the Android foreground keepalive is active.
    final bgActive =
        bgState == BackgroundServiceState.running ||
        bgState == BackgroundServiceState.reconnecting;
    if (!bgActive) return icon;

    final badgeColor = bgState == BackgroundServiceState.reconnecting
        ? MeridianColors.warning
        : MeridianColors.signal;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
