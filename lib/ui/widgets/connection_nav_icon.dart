import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../services/background_service_manager.dart';
import '../../services/station_service.dart';
import '../../services/tnc_service.dart';
import '../../theme/meridian_colors.dart';

/// Reactive navigation icon that reflects combined APRS-IS + TNC connection
/// state and Android background service keepalive status.
///
/// Uses [Selector2] to rebuild only on status changes — not on every packet
/// ingested by [StationService]. A separate [Selector] wraps the outer layer
/// to also respond to [BackgroundServiceState] without rebuilding on
/// unrelated provider notifications.
///
/// States:
/// - Any transport connected → filled router icon, [MeridianColors.signal]
/// - Any transport in error  → filled router icon, [MeridianColors.warning]
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
        return Selector2<
          StationService,
          TncService,
          (ConnectionStatus, ConnectionStatus)
        >(
          selector: (_, ss, tnc) =>
              (ss.currentConnectionStatus, tnc.currentStatus),
          builder: (context, statuses, _) {
            final (aprsStatus, tncStatus) = statuses;
            return _buildIcon(context, aprsStatus, tncStatus, bgState);
          },
        );
      },
    );
  }

  Widget _buildIcon(
    BuildContext context,
    ConnectionStatus aprsStatus,
    ConnectionStatus tncStatus,
    BackgroundServiceState bgState,
  ) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    final anyConnected =
        aprsStatus == ConnectionStatus.connected ||
        tncStatus == ConnectionStatus.connected;
    final anyError =
        aprsStatus == ConnectionStatus.error ||
        tncStatus == ConnectionStatus.error;
    final anyConnecting =
        aprsStatus == ConnectionStatus.connecting ||
        tncStatus == ConnectionStatus.connecting ||
        aprsStatus == ConnectionStatus.reconnecting ||
        tncStatus == ConnectionStatus.reconnecting ||
        aprsStatus == ConnectionStatus.waitingForDevice ||
        tncStatus == ConnectionStatus.waitingForDevice;

    Widget icon;
    if (anyConnected) {
      icon = Icon(Symbols.router, fill: 1, color: MeridianColors.signal);
    } else if (anyError) {
      icon = Icon(Symbols.router, fill: 1, color: MeridianColors.warning);
    } else if (anyConnecting) {
      icon = Icon(Symbols.router, fill: 0, color: MeridianColors.warning);
    } else {
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
