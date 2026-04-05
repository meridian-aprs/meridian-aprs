import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:http_cache_core/http_cache_core.dart';

import 'meridian_tile_provider.dart';

/// Stadia Maps tile provider with disk caching.
///
/// Serves `alidade_smooth` tiles in light mode and `alidade_smooth_dark` in
/// dark mode. An API key is required and must be passed at build time via
/// `--dart-define=STADIA_MAPS_API_KEY=<key>`.
///
/// Pass a [CacheStore] (e.g. [FileCacheStore]) to persist tiles across
/// sessions and avoid redundant requests to the Stadia Maps API.
class StadiaTileProvider implements MeridianTileProvider {
  final String apiKey;
  final CacheStore _cacheStore;

  StadiaTileProvider({required this.apiKey, required CacheStore cacheStore})
    : _cacheStore = cacheStore;

  // Lazily created and reused across builds to avoid creating a new Dio
  // HTTP client (and its keep-alive timers) on every widget rebuild.
  CachedTileProvider? _provider;

  @override
  String tileUrl(Brightness brightness) {
    final style = brightness == Brightness.dark
        ? 'alidade_smooth_dark'
        : 'alidade_smooth';
    return 'https://tiles.stadiamaps.com/tiles/$style/{z}/{x}/{y}.png?api_key=$apiKey';
  }

  @override
  TileProvider buildTileProvider() => _provider ??= CachedTileProvider(
    store: _cacheStore,
    // Serve from cache when offline; refresh after 30 days.
    maxStale: const Duration(days: 30),
    hitCacheOnNetworkFailure: true,
  );

  @override
  void dispose() {
    _provider?.dio.close(force: true);
    _provider = null;
  }
}
