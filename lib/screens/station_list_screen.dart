import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/packet/station.dart';
import '../services/station_service.dart';
import '../ui/widgets/station_info_sheet.dart';
import '../ui/widgets/station_list_tile.dart';
import '../ui/widgets/station_search_delegate.dart';

/// Full-screen station list showing all currently heard APRS stations.
///
/// Receives [StationService] from the caller so it shares the same live
/// connection — no second TCP session is opened.
///
/// [onShowOnMap], when provided, adds a "Show on map" button to each station's
/// info sheet. The callback receives the selected station so the caller can
/// pan the map to it and switch to the map tab.
class StationListScreen extends StatelessWidget {
  const StationListScreen({super.key, required this.service, this.onShowOnMap});

  final StationService service;
  final void Function(Station)? onShowOnMap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stations'),
        actions: [
          IconButton(
            icon: const Icon(Symbols.search),
            tooltip: 'Search stations',
            onPressed: () => _openSearch(context),
          ),
        ],
      ),
      body: StationListBody(service: service, onShowOnMap: onShowOnMap),
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    final station = await showSearch<Station?>(
      context: context,
      delegate: StationSearchDelegate(stations: service.currentStations),
    );
    if (station != null && context.mounted) {
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => StationInfoSheet(
          station: station,
          onShowOnMap: onShowOnMap != null ? () => onShowOnMap!(station) : null,
        ),
      );
    }
  }
}

/// Embeddable station list body — live-updating list of heard stations.
///
/// Seeds the initial list from [StationService.currentStations] and listens
/// to [StationService.stationUpdates] for incremental changes. The list is
/// sorted newest-heard first.
class StationListBody extends StatefulWidget {
  const StationListBody({super.key, required this.service, this.onShowOnMap});

  final StationService service;
  final void Function(Station)? onShowOnMap;

  @override
  State<StationListBody> createState() => _StationListBodyState();
}

class _StationListBodyState extends State<StationListBody> {
  List<Station> _stations = [];
  late final StreamSubscription<Map<String, Station>> _subscription;

  @override
  void initState() {
    super.initState();

    // Seed from the current snapshot so the list isn't empty on entry.
    _stations = widget.service.currentStations.values.toList();
    _sortStations();

    // Listen for live updates.
    _subscription = widget.service.stationUpdates.listen(_onStationsUpdated);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  void _onStationsUpdated(Map<String, Station> stations) {
    if (!mounted) return;
    setState(() {
      _stations = stations.values.toList();
      _sortStations();
    });
  }

  void _sortStations() {
    _stations.sort((a, b) => b.lastHeard.compareTo(a.lastHeard));
  }

  void _showInfo(BuildContext context, Station station) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => StationInfoSheet(
        station: station,
        onShowOnMap: widget.onShowOnMap != null
            ? () => widget.onShowOnMap!(station)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_stations.isEmpty) {
      return Center(
        child: Text(
          'No stations heard yet',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _stations.length,
      itemBuilder: (context, index) {
        final station = _stations[index];
        return StationListTile(
          station: station,
          onTap: () => _showInfo(context, station),
        );
      },
    );
  }
}
