import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/packet/aprs_packet.dart';
import '../services/station_service.dart';
import '../ui/widgets/packet_detail_sheet.dart';

/// All filterable packet type labels shown in the filter bar.
enum _PacketFilter {
  all('ALL'),
  pos('POS'),
  msg('MSG'),
  wx('WX'),
  obj('OBJ'),
  item('ITEM'),
  status('STATUS'),
  micE('MIC-E');

  const _PacketFilter(this.label);
  final String label;
}

/// Full-screen real-time scrolling log of decoded APRS packets.
///
/// Receives [StationService] from the caller so it shares the same live
/// connection — no second TCP session is opened.
class PacketLogScreen extends StatelessWidget {
  const PacketLogScreen({super.key, required this.service});

  final StationService service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Packet Log')),
      body: PacketLogBody(service: service),
    );
  }
}

/// Embeddable packet log body — filter bar + scrolling packet list.
///
/// Used by [PacketLogScreen] (full-screen push) and desktop side panel.
class PacketLogBody extends StatefulWidget {
  const PacketLogBody({super.key, required this.service});

  final StationService service;

  @override
  State<PacketLogBody> createState() => _PacketLogBodyState();
}

class _PacketLogBodyState extends State<PacketLogBody> {
  /// Rolling buffer mirroring [StationService.recentPackets].
  final List<AprsPacket> _packets = [];

  _PacketFilter _filter = _PacketFilter.all;

  final _scrollController = ScrollController();
  StreamSubscription<AprsPacket>? _subscription;

  /// Whether the user has scrolled up (away from the bottom).
  bool _userScrolledUp = false;

  static final _timeFmt = DateFormat('HH:mm:ss');

  @override
  void initState() {
    super.initState();

    // Seed from the rolling buffer so the list isn't empty on entry.
    _packets.addAll(widget.service.recentPackets);

    // Listen for new packets.
    _subscription = widget.service.packetStream.listen(_onPacket);

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onPacket(AprsPacket packet) {
    if (!mounted) return;
    setState(() {
      // Newest first — mirror StationService ordering.
      _packets.insert(0, packet);
      if (_packets.length > 500) _packets.removeRange(500, _packets.length);
    });

    // Auto-scroll only when the user hasn't scrolled up.
    if (!_userScrolledUp && _scrollController.hasClients) {
      // The list is newest-first so "newest" is at index 0 — top of the list.
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // Consider the user to have scrolled up when they are not at the top
    // (newest) item.
    _userScrolledUp = _scrollController.offset > 40;
  }

  List<AprsPacket> get _filtered {
    if (_filter == _PacketFilter.all) return _packets;
    return _packets.where((p) => _matchesFilter(p, _filter)).toList();
  }

  static bool _matchesFilter(AprsPacket p, _PacketFilter f) {
    return switch (f) {
      _PacketFilter.all => true,
      _PacketFilter.pos => p is PositionPacket,
      _PacketFilter.msg => p is MessagePacket,
      _PacketFilter.wx => p is WeatherPacket,
      _PacketFilter.obj => p is ObjectPacket,
      _PacketFilter.item => p is ItemPacket,
      _PacketFilter.status => p is StatusPacket,
      _PacketFilter.micE => p is MicEPacket,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;

    return Column(
      children: [
        _FilterBar(
          selected: _filter,
          onChanged: (f) => setState(() {
            _filter = f;
            _userScrolledUp = false;
          }),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No packets yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _PacketRow(
                    packet: filtered[index],
                    timeFmt: _timeFmt,
                    onTap: () =>
                        showPacketDetailSheet(context, filtered[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filter bar
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onChanged});

  final _PacketFilter selected;
  final ValueChanged<_PacketFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: _PacketFilter.values
            .map(
              (f) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(f.label),
                  selected: selected == f,
                  onSelected: (_) => onChanged(f),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Packet row
// ---------------------------------------------------------------------------

class _PacketRow extends StatelessWidget {
  const _PacketRow({
    required this.packet,
    required this.timeFmt,
    required this.onTap,
  });

  final AprsPacket packet;
  final DateFormat timeFmt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final typeLabel = _typeLabel(packet);
    final summary = _summary(packet);
    final timeStr = timeFmt.format(packet.receivedAt.toLocal());

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timestamp
            SizedBox(
              width: 68,
              child: Text(
                timeStr,
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            // Type chip
            _TypeBadge(label: typeLabel, colorScheme: colorScheme),

            const SizedBox(width: 8),

            // Callsign + summary
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    packet.source,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (summary.isNotEmpty)
                    Text(
                      summary,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(AprsPacket p) {
    return switch (p) {
      PositionPacket() => 'POS',
      MessagePacket() => 'MSG',
      WeatherPacket() => 'WX',
      ObjectPacket() => 'OBJ',
      ItemPacket() => 'ITEM',
      StatusPacket() => 'STATUS',
      MicEPacket() => 'MIC-E',
      UnknownPacket() => '???',
    };
  }

  static String _summary(AprsPacket p) {
    return switch (p) {
      PositionPacket() => '${_latStr(p.lat)}, ${_lonStr(p.lon)}',
      MessagePacket() => '\u2192 ${p.addressee}: ${p.message}',
      WeatherPacket() => _wxSummary(p),
      ObjectPacket() =>
        '${p.objectName} @ ${_latStr(p.lat)}, ${_lonStr(p.lon)}',
      ItemPacket() => '${p.itemName} @ ${_latStr(p.lat)}, ${_lonStr(p.lon)}',
      StatusPacket() => p.status,
      MicEPacket() =>
        '${_latStr(p.lat)}, ${_lonStr(p.lon)} \u2022 ${p.micEMessage}',
      UnknownPacket() =>
        p.rawLine.length > 40
            ? '${p.rawLine.substring(0, 40)}\u2026'
            : p.rawLine,
    };
  }

  static String _latStr(double lat) {
    final dir = lat >= 0 ? 'N' : 'S';
    return '${lat.abs().toStringAsFixed(3)}\u00b0 $dir';
  }

  static String _lonStr(double lon) {
    final dir = lon >= 0 ? 'E' : 'W';
    return '${lon.abs().toStringAsFixed(3)}\u00b0 $dir';
  }

  static String _wxSummary(WeatherPacket p) {
    final parts = <String>[];
    if (p.temperature != null) {
      final f = p.temperature!.toStringAsFixed(0);
      parts.add('$f \u00b0F');
    }
    if (p.windSpeed != null) {
      parts.add('${p.windSpeed!.toStringAsFixed(0)} mph wind');
    }
    if (p.humidity != null) {
      parts.add('${p.humidity}% RH');
    }
    return parts.isEmpty ? 'Weather' : parts.join(' / ');
  }
}

// ---------------------------------------------------------------------------
// Type badge
// ---------------------------------------------------------------------------

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.colorScheme});

  final String label;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
