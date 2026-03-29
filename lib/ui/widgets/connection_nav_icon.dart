import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../services/station_service.dart';
import '../../services/tnc_service.dart';
import '../../theme/meridian_colors.dart';

/// Reactive navigation icon that reflects combined APRS-IS + TNC connection
/// state.
///
/// Uses [Selector2] to rebuild only on status changes — not on every packet
/// ingested by [StationService].
///
/// States:
/// - Any transport connected → filled router icon, [MeridianColors.signal]
/// - Any transport in error  → filled router icon, [MeridianColors.warning]
/// - Any transport connecting → outlined router icon, [MeridianColors.warning]
/// - All disconnected         → outlined router icon, muted
class ConnectionNavIcon extends StatelessWidget {
  const ConnectionNavIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector2<
      StationService,
      TncService,
      (ConnectionStatus, ConnectionStatus)
    >(
      selector: (_, ss, tnc) => (ss.currentConnectionStatus, tnc.currentStatus),
      builder: (context, statuses, _) {
        final (aprsStatus, tncStatus) = statuses;
        return _buildIcon(context, aprsStatus, tncStatus);
      },
    );
  }

  Widget _buildIcon(
    BuildContext context,
    ConnectionStatus aprsStatus,
    ConnectionStatus tncStatus,
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
        tncStatus == ConnectionStatus.connecting;

    if (anyConnected) {
      return Icon(Symbols.router, fill: 1, color: MeridianColors.signal);
    }
    if (anyError) {
      return Icon(Symbols.router, fill: 1, color: MeridianColors.warning);
    }
    if (anyConnecting) {
      return Icon(Symbols.router, fill: 0, color: MeridianColors.warning);
    }
    return Icon(Symbols.router, fill: 0, color: muted);
  }
}
