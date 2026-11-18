// Place names from Phlio's server (Google Maps Platform behind
// /api/v1/places, key kept server-side). Google knows Indian neighbourhoods
// far better than OpenStreetMap (e.g. KPHB Colony, which OSM labels
// "APHB Colony"), so callers try these first and fall back to the
// OpenStreetMap helpers in places_api.dart when they return null
// (server not configured, API disabled, offline).

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import 'location_service.dart';

List<Place> _places(Object? data) => [
      for (final p in ((data as Map?)?['items'] as List? ?? const []))
        Place(
          lat: ((p as Map)['lat'] as num).toDouble(),
          lng: (p['lng'] as num).toDouble(),
          name: '${p['name']}',
          address: '${p['address'] ?? ''}',
          kind: p['kind'] as String?,
        ),
    ];

Future<List<Place>?> _get(String path, Map<String, Object?> query) async {
  try {
    final res = await getIt<ApiClient>()
        .dio
        .get<dynamic>(path, queryParameters: {for (final e in query.entries) if (e.value != null) e.key: e.value});
    return _places(res.data);
  } catch (_) {
    return null;
  }
}

/// Area names for the point, most specific first ("KPHB Colony", "Kukatpally", "Hyderabad").
Future<List<Place>?> serverAreas(double lat, double lng) => _get('/places/area', {'lat': lat, 'lng': lng});

/// Named spots nearby, nearest first.
Future<List<Place>?> serverNearby(double lat, double lng, {int radius = 800}) =>
    _get('/places/nearby', {'lat': lat, 'lng': lng, 'radius': radius});

/// Text search around the point.
Future<List<Place>?> serverSearch(String q, {double? lat, double? lng}) =>
    _get('/places/search', {'q': q, 'lat': lat, 'lng': lng});
