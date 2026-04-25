import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/beaconing_service.dart';
import '../../services/station_settings_service.dart';

/// Resolves the operator's current location for distance / bearing display.
///
/// Resolution order:
/// 1. Manual coordinates if [LocationSource.manual] is selected and set.
/// 2. Latest GPS fix from [BeaconingService.lastKnownLocation].
/// 3. Null when nothing is available — callers should hide distance UI.
///
/// Reads via [BuildContext.watch] so widgets rebuild when either source
/// changes (manual coord update, GPS fix update, source switch).
LatLng? resolveOperatorLocation(BuildContext context) {
  final settings = context.watch<StationSettingsService>();
  if (settings.locationSource == LocationSource.manual &&
      settings.hasManualPosition) {
    return LatLng(settings.manualLat!, settings.manualLon!);
  }
  final beaconing = context.watch<BeaconingService>();
  return beaconing.lastKnownLocation;
}
