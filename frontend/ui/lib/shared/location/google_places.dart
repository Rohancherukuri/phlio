// Google Places (New) straight from the phone, for Notes locations.
//
// Uses the Maps key already in the Android manifest (MAPS_API_KEY in
// android/local.properties), read through the `phlio/maps_identity`
// channel in MainActivity together with the package name and signing
// SHA-1 that Google checks for Android-restricted keys. Needs "Places API
// (New)" enabled for that key. No Phlio server involved.
//
// The neighbourhood ("KPHB Colony") is worked out from the address parts
// of the places around you: the area name most of them share wins. That is
// much more reliable here than reverse-geocoding a single GPS point.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'location_service.dart';
import 'places_api.dart' show distanceMetres;

const _channel = MethodChannel('phlio/maps_identity');
Map<String, String>? _identity;
final _http = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 12)));

const _fields = 'places.displayName,places.location,places.shortFormattedAddress,places.formattedAddress,'
    'places.primaryTypeDisplayName,places.addressComponents';

/// Area types, most specific first.
const _areaTypes = ['neighborhood', 'sublocality_level_3', 'sublocality_level_2', 'sublocality_level_1', 'sublocality'];

Future<Map<String, String>?> _headers() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    _identity ??= Map<String, String>.from(await _channel.invokeMapMethod<String, String>('get') ?? const {});
  } catch (_) {
    return null;
  }
  final id = _identity!;
  if ((id['key'] ?? '').isEmpty) return null;
  return {
    'X-Goog-Api-Key': id['key']!,
    'X-Goog-FieldMask': _fields,
    'X-Android-Package': id['package'] ?? '',
    'X-Android-Cert': id['sha1'] ?? '',
    'Content-Type': 'application/json',
  };
}

/// What Google returned around a point: area names (best first) and spots.
class GoogleNearby {
  const GoogleNearby(this.areas, this.spots);
  final List<Place> areas;
  final List<Place> spots;
}

List<Place> _spots(Map body, double? lat, double? lng) {
  final out = <Place>[];
  for (final p in (body['places'] as List? ?? const []).cast<Map>()) {
    final loc = p['location'] as Map?;
    final name = (p['displayName'] as Map?)?['text'] as String?;
    if (name == null || loc == null) continue;
    out.add(Place(
      lat: (loc['latitude'] as num).toDouble(),
      lng: (loc['longitude'] as num).toDouble(),
      name: name,
      address: '${p['shortFormattedAddress'] ?? p['formattedAddress'] ?? ''}',
      kind: (p['primaryTypeDisplayName'] as Map?)?['text'] as String?,
    ));
  }
  if (lat != null && lng != null) {
    out.sort((a, b) => distanceMetres(lat, lng, a.lat, a.lng).compareTo(distanceMetres(lat, lng, b.lat, b.lng)));
  }
  return out;
}

/// Area names shared by the places in [body], most specific level that
/// enough places agree on first.
List<Place> _areas(Map body, double lat, double lng) {
  final places = (body['places'] as List? ?? const []).cast<Map>();
  final counts = <String, Map<String, int>>{for (final t in _areaTypes) t: {}};
  final city = <String, int>{};
  for (final p in places) {
    for (final c in (p['addressComponents'] as List? ?? const []).cast<Map>()) {
      final types = (c['types'] as List? ?? const []).cast<String>();
      final name = '${c['longText'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      for (final t in _areaTypes) {
        if (types.contains(t)) counts[t]![name] = (counts[t]![name] ?? 0) + 1;
      }
      if (types.contains('locality')) city[name] = (city[name] ?? 0) + 1;
    }
  }
  final cityName = city.entries.isEmpty ? '' : (city.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
  final ranked = <Place>[];
  final seen = <String>{};
  final enough = places.isEmpty ? 1 : (places.length * 0.25).ceil().clamp(1, 4);
  // Pass 1: names enough places share, most specific level first.
  // Pass 2: everything else, by how many places mention it.
  for (final pass in [1, 2]) {
    for (final t in _areaTypes) {
      final entries = counts[t]!.entries.toList()..sort((a, b) => b.value - a.value);
      for (final e in entries) {
        if (pass == 1 && e.value < enough) continue;
        if (!seen.add(e.key.toLowerCase())) continue;
        ranked.add(Place(lat: lat, lng: lng, name: e.key, address: cityName == e.key ? '' : cityName, kind: 'area'));
      }
    }
  }
  return ranked;
}

/// Places around the point (nearest first) and the area names they share.
Future<GoogleNearby?> googleNearby(double lat, double lng, {double radius = 600}) async {
  final headers = await _headers();
  if (headers == null) return null;
  try {
    final res = await _http.post<dynamic>('https://places.googleapis.com/v1/places:searchNearby',
        options: Options(headers: headers),
        data: {
          'maxResultCount': 20,
          'rankPreference': 'DISTANCE',
          'languageCode': 'en',
          'locationRestriction': {
            'circle': {
              'center': {'latitude': lat, 'longitude': lng},
              'radius': radius,
            },
          },
        });
    final body = res.data as Map;
    return GoogleNearby(_areas(body, lat, lng), _spots(body, lat, lng));
  } catch (e) {
    if (kDebugMode && e is DioException) {
      debugPrint('Google Places unavailable: ${e.response?.statusCode} ${e.response?.data}');
    }
    return null;
  }
}

/// Text search around the point.
Future<List<Place>?> googleSearch(String q, {double? lat, double? lng}) async {
  final headers = await _headers();
  if (headers == null) return null;
  try {
    final res = await _http.post<dynamic>('https://places.googleapis.com/v1/places:searchText',
        options: Options(headers: headers),
        data: {
          'textQuery': q,
          'maxResultCount': 20,
          'languageCode': 'en',
          if (lat != null && lng != null)
            'locationBias': {
              'circle': {
                'center': {'latitude': lat, 'longitude': lng},
                'radius': 20000.0,
              },
            },
        });
    return _spots(res.data as Map, lat, lng);
  } catch (_) {
    return null;
  }
}
