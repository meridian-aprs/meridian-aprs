/// Plain lat/lon bounding-box value type.
///
/// The Connection Core previously imported `package:flutter_map` for
/// [LatLngBounds] so [AprsIsConnection.updateFilter] could read `.north`,
/// `.south`, `.east`, `.west`. That pulled a UI-layer dependency into
/// `lib/core/`, breaking the layer rule in `CLAUDE.md`.
///
/// [LatLngBox] is a pure Dart value type with the same four accessors. The UI
/// converts its `LatLngBounds` to this shape at the boundary before calling
/// [AprsIsConnection.updateFilter].
library;

class LatLngBox {
  const LatLngBox({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  final double north;
  final double south;
  final double east;
  final double west;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLngBox &&
          other.north == north &&
          other.south == south &&
          other.east == east &&
          other.west == west;

  @override
  int get hashCode => Object.hash(north, south, east, west);

  @override
  String toString() => 'LatLngBox(N=$north, S=$south, E=$east, W=$west)';
}
