// Neighbourhood names from the phone's own geocoder: Android's Geocoder
// (Google's data) and Apple's on iOS, through the `geocoding` plugin. No
// API key, no Phlio server needed, and it names Indian neighbourhoods
// properly (KPHB Colony, which OpenStreetMap calls "APHB Colony").

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geo;

import 'location_service.dart';

bool get _supported =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Area names for the point, most specific first, or null if the phone
/// can't tell (no geocoder, offline).
Future<List<Place>?> deviceAreas(double lat, double lng) async {
  if (!_supported) return null;
  try {
    await geo.setLocaleIdentifier('en_US');
    final marks = await geo.placemarkFromCoordinates(lat, lng).timeout(const Duration(seconds: 8));
    final out = <Place>[];
    final seen = <String>{};
    void add(String? name, String? city) {
      final n = name?.trim() ?? '';
      // Skip blanks, plus-codes ("7J9W+2Q") and bare numbers.
      if (n.isEmpty || RegExp(r'^[0-9A-Z]{4}\+[0-9A-Z]{2,}').hasMatch(n) || RegExp(r'^\d+$').hasMatch(n)) return;
      if (!seen.add(n.toLowerCase())) return;
      out.add(Place(lat: lat, lng: lng, name: n, address: city != null && city != n ? city : '', kind: 'area'));
    }

    for (final m in marks) {
      add(m.subLocality, m.locality);
    }
    for (final m in marks) {
      add(m.locality, m.administrativeArea);
    }
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}
