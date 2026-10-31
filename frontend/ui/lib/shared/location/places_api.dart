// Location sharing — place names, nearby places and search.
//
// Uses OpenStreetMap's free services, so nothing extra needs a key or
// billing (the map itself is Google Maps):
//
// * Nominatim — address of a point (reverse) and place search.
// * Overpass  — named places around a point (shops, cafes, temples,
//   apartments…), nearest first.
//
// Both ask apps to identify themselves; requests carry a Phlio user agent.

import 'dart:math' as math;

import 'package:dio/dio.dart';

import 'location_service.dart';

final _http = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 20),
  headers: {'User-Agent': 'Phlio/1.0 (location sharing)'},
));

/// Short address from Nominatim's parts: "376, Hyderabad, 500085, TS, IN".
String _address(Map a) {
  final parts = <String>[
    for (final k in ['house_number', 'road', 'neighbourhood', 'suburb', 'city', 'town', 'village', 'postcode'])
      if (a[k] is String && (a[k] as String).isNotEmpty) a[k] as String,
    if (a['ISO3166-2-lvl4'] is String) (a['ISO3166-2-lvl4'] as String).split('-').last,
    if (a['country_code'] is String) (a['country_code'] as String).toUpperCase(),
  ];
  return parts.toSet().join(', ');
}

/// Name and address of the point (null if unknown / offline).
Future<Place?> reverseGeocode(double lat, double lng) async {
  try {
    final res = await _http.get('https://nominatim.openstreetmap.org/reverse',
        queryParameters: {'lat': lat, 'lon': lng, 'format': 'jsonv2', 'addressdetails': 1, 'zoom': 18});
    final j = res.data as Map;
    final a = (j['address'] as Map?) ?? const {};
    final name = (j['name'] as String?)?.isNotEmpty == true
        ? j['name'] as String
        : '${a['road'] ?? a['neighbourhood'] ?? a['suburb'] ?? 'Dropped pin'}';
    return Place(lat: lat, lng: lng, name: name, address: _address(a));
  } catch (_) {
    return null;
  }
}

/// Places matching [query], biased towards [near].
Future<List<Place>> searchPlaces(String query, {double? lat, double? lng}) async {
  final res = await _http.get('https://nominatim.openstreetmap.org/search', queryParameters: {
    'q': query,
    'format': 'jsonv2',
    'addressdetails': 1,
    'limit': 15,
    if (lat != null && lng != null) 'viewbox': '${lng - .3},${lat + .3},${lng + .3},${lat - .3}',
  });
  return [
    for (final j in (res.data as List).cast<Map>())
      Place(
        lat: double.parse('${j['lat']}'),
        lng: double.parse('${j['lon']}'),
        name: '${j['name'] ?? (j['display_name'] as String? ?? '').split(',').first}',
        address: _address((j['address'] as Map?) ?? const {}),
        kind: j['type'] as String?,
      )
  ];
}

/// Named places within [radius] metres, nearest first (at most [limit]).
Future<List<Place>> nearbyPlaces(double lat, double lng, {int radius = 500, int limit = 25}) async {
  final query = '[out:json][timeout:15];('
      'nwr(around:$radius,$lat,$lng)[name][amenity];'
      'nwr(around:$radius,$lat,$lng)[name][shop];'
      'nwr(around:$radius,$lat,$lng)[name][tourism];'
      'nwr(around:$radius,$lat,$lng)[name][leisure];'
      'nwr(around:$radius,$lat,$lng)[name][building];'
      ');out center 80;';
  final res = await _http.post('https://overpass-api.de/api/interpreter',
      data: {'data': query}, options: Options(contentType: Headers.formUrlEncodedContentType));
  final places = <Place>[];
  final seen = <String>{};
  for (final e in ((res.data as Map)['elements'] as List).cast<Map>()) {
    final tags = (e['tags'] as Map?) ?? const {};
    final name = tags['name'] as String?;
    final c = (e['center'] as Map?) ?? e;
    if (name == null || c['lat'] == null || !seen.add(name.toLowerCase())) continue;
    final street = [tags['addr:housenumber'], tags['addr:street'], tags['addr:city'], tags['addr:postcode']]
        .whereType<String>()
        .join(', ');
    places.add(Place(
      lat: (c['lat'] as num).toDouble(),
      lng: (c['lon'] as num).toDouble(),
      name: name,
      address: street,
      kind: '${tags['amenity'] ?? tags['shop'] ?? tags['tourism'] ?? tags['leisure'] ?? tags['building'] ?? ''}'.replaceAll('_', ' '),
    ));
  }
  places.sort((a, b) => distanceMetres(lat, lng, a.lat, a.lng).compareTo(distanceMetres(lat, lng, b.lat, b.lng)));
  return places.take(limit).toList();
}

/// Great-circle distance in metres.
double distanceMetres(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180, dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// "120 m" / "1.4 km".
String formatDistance(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
