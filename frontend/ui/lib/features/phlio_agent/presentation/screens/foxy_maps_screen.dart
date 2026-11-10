// Foxy Maps — "Ask Maps" from the Agent wheel. Ask in plain words
// ("good coffee near me", "badminton courts", "where's the nearest ATM?")
// and Foxy answers on the map: matching places are pinned, listed in a
// swipeable carousel with distance, and one tap gets directions.
//
// Uses the same free OpenStreetMap services as location sharing
// (Overpass for categories nearby, Nominatim for anything else); the map
// is Google Maps with Phlio's dark style.
//
// Fast path: one Overpass query per ask (raced across mirrors), results
// cached for 10 minutes per area, your last known position used at once
// while GPS refines it, and Nominatim as a fallback if Overpass is down.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../shared/location/location_service.dart';
import '../../../../shared/location/location_share_screen.dart' show phlioMapStyle;
import '../../../../shared/location/places_api.dart';

/// Answers per (category, ~1 km area), kept 10 minutes.
final _cache = <String, (DateTime, List<Place>, int)>{};

/// A kind of place people ask about, as OpenStreetMap tags.
class _Category {
  const _Category(this.label, this.emoji, this.words, this.filters);
  final String label;
  final String emoji;
  final List<String> words;
  final List<String> filters; // Overpass tag filters, e.g. '[amenity=cafe]'
}

const _categories = [
  _Category('cafés', '☕', ['coffee', 'cafe', 'café', 'tea'], ['[amenity=cafe]']),
  _Category('places to eat', '🍽️', ['food', 'eat', 'restaurant', 'lunch', 'dinner', 'breakfast', 'biryani', 'pizza'], ['[amenity=restaurant]', '[amenity=fast_food]']),
  _Category('hospitals & clinics', '🏥', ['hospital', 'doctor', 'clinic', 'emergency', 'medical'], ['[amenity=hospital]', '[amenity=clinic]', '[amenity=doctors]', '[healthcare=hospital]', '[healthcare=clinic]']),
  _Category('pharmacies', '💊', ['pharmacy', 'medicine', 'chemist', 'medical store'], ['[amenity=pharmacy]', '[healthcare=pharmacy]']),
  _Category('ATMs & banks', '🏧', ['atm', 'bank', 'cash'], ['[amenity=atm]', '[amenity=bank]']),
  _Category('fuel stations', '⛽', ['petrol', 'fuel', 'gas station', 'diesel', 'ev charging', 'charging'], ['[amenity=fuel]', '[amenity=charging_station]']),
  _Category('sports & courts', '🏸', ['badminton', 'court', 'sports', 'turf', 'football', 'cricket', 'tennis', 'swimming'], ['[leisure=sports_centre]', '[leisure=pitch]', '[leisure=swimming_pool]']),
  _Category('gyms', '🏋️', ['gym', 'fitness', 'workout', 'yoga'], ['[leisure=fitness_centre]']),
  _Category('parks', '🌳', ['park', 'garden', 'walk', 'jog'], ['[leisure=park]', '[leisure=garden]']),
  _Category('groceries', '🛒', ['grocery', 'groceries', 'supermarket', 'vegetables', 'kirana'], ['[shop=supermarket]', '[shop=convenience]', '[shop=greengrocer]']),
  _Category('malls & shopping', '🛍️', ['mall', 'shopping', 'clothes'], ['[shop=mall]', '[shop=department_store]', '[shop=clothes]']),
  _Category('hotels & stays', '🏨', ['hotel', 'stay', 'hostel', 'room'], ['[tourism=hotel]', '[tourism=guest_house]', '[tourism=hostel]']),
  _Category('things to do', '🎡', ['things to do', 'visit', 'attraction', 'museum', 'fun', 'weekend', 'tourist'], ['[tourism=attraction]', '[tourism=museum]', '[tourism=viewpoint]', '[leisure=amusement_arcade]']),
  _Category('cinemas', '🎬', ['movie', 'cinema', 'theatre', 'film'], ['[amenity=cinema]', '[amenity=theatre]']),
  _Category('places of worship', '🛕', ['temple', 'church', 'mosque', 'gurudwara', 'worship'], ['[amenity=place_of_worship]']),
];

const _suggestions = [
  'Good coffee near me',
  'Badminton courts nearby',
  'Nearest ATM',
  'Hospitals around me',
  'Things to do this weekend',
  'Petrol pump',
];

class FoxyMapsScreen extends StatefulWidget {
  const FoxyMapsScreen({super.key});

  @override
  State<FoxyMapsScreen> createState() => _FoxyMapsScreenState();
}

class _FoxyMapsScreenState extends State<FoxyMapsScreen> {
  final _ask = TextEditingController();
  final _cards = PageController(viewportFraction: 0.86);
  GoogleMapController? _map;
  LatLng? _me;
  String? _locError;
  bool _searching = false;
  String? _answer;
  String? _question;
  List<Place> _results = const [];
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _ask.dispose();
    _cards.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    // Last known position straight away (instant), then a fresh GPS fix.
    if (_me == null) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted && _me == null) {
          setState(() => _me = LatLng(last.latitude, last.longitude));
          unawaited(_map?.moveCamera(CameraUpdate.newLatLngZoom(_me!, 15)));
        }
      } catch (_) {}
    }
    try {
      final p = await currentPosition();
      if (!mounted) return;
      setState(() {
        _me = LatLng(p.latitude, p.longitude);
        _locError = null;
      });
      unawaited(_map?.animateCamera(CameraUpdate.newLatLngZoom(_me!, 15)));
    } on LocationProblem catch (e) {
      if (mounted) setState(() => _locError = e.message);
    } catch (_) {
      if (mounted) setState(() => _locError = 'Couldn\'t find where you are.');
    }
  }

  _Category? _categoryFor(String q) {
    final lower = q.toLowerCase();
    _Category? best;
    var bestLength = 0;
    for (final c in _categories) {
      for (final w in c.words) {
        if (lower.contains(w) && w.length > bestLength) {
          best = c;
          bestLength = w.length;
        }
      }
    }
    return best;
  }

  Future<List<Place>> _overpass(_Category c, LatLng at, int radius) async {
    final parts = [
      for (final f in c.filters) 'nwr(around:$radius,${at.latitude},${at.longitude})$f[name];',
    ].join();
    final elements = await overpassElements('[out:json][timeout:12];($parts);out center 120;');
    final seen = <String>{};
    final out = <Place>[];
    for (final e in elements) {
      final tags = (e['tags'] as Map?) ?? const {};
      final name = tags['name'] as String?;
      final centre = (e['center'] as Map?) ?? e;
      if (name == null || centre['lat'] == null || !seen.add(name.toLowerCase())) continue;
      out.add(Place(
        lat: (centre['lat'] as num).toDouble(),
        lng: (centre['lon'] as num).toDouble(),
        name: name,
        address: [tags['addr:street'], tags['addr:suburb'] ?? tags['addr:city']].whereType<String>().join(', '),
        kind: '${tags['amenity'] ?? tags['healthcare'] ?? tags['leisure'] ?? tags['shop'] ?? tags['tourism'] ?? ''}'.replaceAll('_', ' '),
      ));
    }
    return out;
  }

  /// Places of [c] near [at]: one query (6 km), widened to 20 km only if
  /// that finds fewer than 3; cached per area. Falls back to Nominatim
  /// if every Overpass server is down. Returns the places and the radius.
  Future<(List<Place>, int)> _nearby(_Category c, LatLng at) async {
    final key = '${c.label}|${at.latitude.toStringAsFixed(2)},${at.longitude.toStringAsFixed(2)}';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 10)) {
      return (hit.$2, hit.$3);
    }
    var radius = 6000;
    List<Place> places;
    try {
      places = await _overpass(c, at, radius);
      if (places.length < 3) {
        radius = 20000;
        places = await _overpass(c, at, radius);
      }
    } catch (_) {
      // Overpass unavailable: ask Nominatim for the category's main word.
      radius = 20000;
      places = await searchPlaces(c.words.first, lat: at.latitude, lng: at.longitude, bounded: true, box: .2);
    }
    _cache[key] = (DateTime.now(), places, radius);
    return (places, radius);
  }

  Future<void> _submit([String? text]) async {
    final q = (text ?? _ask.text).trim();
    if (q.isEmpty || _searching) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    _ask.text = q;
    setState(() {
      _searching = true;
      _question = q;
      _answer = null;
    });
    final at = _me ?? const LatLng(17.385, 78.4867);
    try {
      final category = _categoryFor(q);
      var places = <Place>[];
      var radius = 6000;
      if (category != null) {
        (places, radius) = await _nearby(category, at);
      } else {
        // Anything else: nearby first, then anywhere.
        final cleaned = q.replaceAll(RegExp(r'\b(near me|nearby|around me|nearest|closest)\b', caseSensitive: false), '').trim();
        places = await searchPlaces(cleaned.isEmpty ? q : cleaned,
            lat: at.latitude, lng: at.longitude, bounded: true);
        if (places.isEmpty) {
          places = await searchPlaces(cleaned.isEmpty ? q : cleaned, lat: at.latitude, lng: at.longitude);
        }
      }
      double dist(Place p) => distanceMetres(at.latitude, at.longitude, p.lat, p.lng);
      places = [...places]..sort((a, b) => dist(a).compareTo(dist(b)));
      places = places.take(20).toList();
      final answer = places.isEmpty
          ? 'I couldn\'t find ${category?.label ?? 'that'} near you${_me == null ? ' (I don\'t know where you are yet — tap the location button)' : ''}. Try different words.'
          : category != null
              ? '${category.emoji} I found ${places.length} ${category.label} within ${formatDistance(radius.toDouble())}. '
                  'Closest: ${places.first.name}, ${formatDistance(dist(places.first))} away.'
              : '📍 Here\'s what I found for "$q" — ${places.first.name} is ${formatDistance(dist(places.first))} away.';
      if (!mounted) return;
      setState(() {
        _results = places;
        _selected = 0;
        _answer = answer;
      });
      if (places.isNotEmpty) {
        _fitAll(at, places);
        if (_cards.hasClients) _cards.jumpToPage(0);
      }
    } catch (_) {
      if (mounted) setState(() => _answer = 'Maps is having trouble right now — check your connection and try again.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _fitAll(LatLng me, List<Place> places) {
    var s = me.latitude, n = me.latitude, w = me.longitude, e = me.longitude;
    for (final p in places.take(8)) {
      s = math.min(s, p.lat);
      n = math.max(n, p.lat);
      w = math.min(w, p.lng);
      e = math.max(e, p.lng);
    }
    _map?.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e)), 80));
  }

  void _focus(int i) {
    if (i < 0 || i >= _results.length) return;
    setState(() => _selected = i);
    final p = _results[i];
    _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(p.lat, p.lng), 16));
  }

  Future<void> _directions(Place p) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lng}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: me ?? const LatLng(17.385, 78.4867), zoom: me == null ? 11 : 15),
            style: phlioMapStyle,
            myLocationEnabled: me != null,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            padding: EdgeInsets.only(bottom: _results.isEmpty ? 190 : 330),
            onMapCreated: (c) {
              _map = c;
              if (_me != null) c.moveCamera(CameraUpdate.newLatLngZoom(_me!, 15));
            },
            markers: {
              for (var i = 0; i < _results.length; i++)
                Marker(
                  markerId: MarkerId('p$i'),
                  position: LatLng(_results[i].lat, _results[i].lng),
                  icon: BitmapDescriptor.defaultMarkerWithHue(i == _selected ? BitmapDescriptor.hueViolet : BitmapDescriptor.hueOrange),
                  zIndex: i == _selected ? 2 : 1,
                  onTap: () {
                    _focus(i);
                    if (_cards.hasClients) {
                      _cards.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                    }
                  },
                ),
            },
          ),
        ),
        // Top bar.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Row(children: [
              _Glass(
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const Spacer(),
              _Glass(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.map_rounded, color: Color(0xFF6FD6B5), size: 18),
                    const SizedBox(width: 6),
                    Text('Foxy Maps', style: PhlioTypography.bodyStrong.copyWith(color: Colors.white)),
                  ]),
                ),
              ),
              const Spacer(),
              _Glass(
                child: IconButton(
                  tooltip: 'My location',
                  icon: const Icon(Icons.my_location_rounded, color: Colors.white),
                  onPressed: _locate,
                ),
              ),
            ]),
          ),
        ),
        // Bottom: answer, place cards, ask bar.
        Align(
          alignment: Alignment.bottomCenter,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_results.isNotEmpty)
              SizedBox(
                height: 122,
                child: PageView.builder(
                  controller: _cards,
                  itemCount: _results.length,
                  onPageChanged: _focus,
                  itemBuilder: (context, i) => _PlaceCard(
                    place: _results[i],
                    distance: me == null ? null : distanceMetres(me.latitude, me.longitude, _results[i].lat, _results[i].lng),
                    selected: i == _selected,
                    onDirections: () => _directions(_results[i]),
                  ),
                ),
              ),
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: EdgeInsets.fromLTRB(14, 14, 14, 12 + bottom),
              decoration: const BoxDecoration(
                color: Color(0xF2141A24),
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: _answer == null && !_searching
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _locError ?? 'Ask about places near you — I\'ll find them on the map.',
                            style: PhlioTypography.body.copyWith(color: _locError != null ? PhlioColors.danger : PhlioColors.textSecondary),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const FoxyAvatar(size: 30),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _searching
                                  ? Text('Looking around for "${_question ?? ''}"…',
                                      style: PhlioTypography.body.copyWith(color: PhlioColors.textSecondary))
                                  : Text(_answer!, style: PhlioTypography.body.copyWith(color: Colors.white, height: 1.35)),
                            ),
                          ]),
                        ),
                ),
                SizedBox(
                  height: 34,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final s in _suggestions)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(s, style: PhlioTypography.caption.copyWith(color: Colors.white)),
                          backgroundColor: const Color(0xFF222A38),
                          side: BorderSide.none,
                          shape: const StadiumBorder(),
                          onPressed: () => _submit(s),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 50,
                  padding: const EdgeInsets.only(left: 14, right: 4),
                  decoration: BoxDecoration(color: const Color(0xFF222A38), borderRadius: BorderRadius.circular(999)),
                  child: Row(children: [
                    ShaderMask(
                      shaderCallback: (r) => PhlioColors.brandGradient.createShader(r),
                      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _ask,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _submit,
                        style: PhlioTypography.bodyLarge.copyWith(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Ask Maps…',
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _searching ? null : () => _submit(),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: PhlioColors.brandGradient),
                          child: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: PhlioColors.textOnBrand),
                                )
                              : const Icon(Icons.arrow_upward_rounded, color: PhlioColors.textOnBrand),
                        ),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: const Color(0xCC141A24), borderRadius: BorderRadius.circular(999)),
        child: child,
      );
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.distance, required this.selected, required this.onDirections});

  final Place place;
  final double? distance;
  final bool selected;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: EdgeInsets.fromLTRB(5, selected ? 0 : 8, 5, selected ? 0 : 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xF2141A24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? PhlioColors.brandViolet : Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: PhlioTypography.title.copyWith(color: Colors.white)),
            const SizedBox(height: 3),
            Text(
              [
                if ((place.kind ?? '').isNotEmpty) '${place.kind![0].toUpperCase()}${place.kind!.substring(1)}',
                if (distance != null) formatDistance(distance!),
              ].join(' · '),
              style: PhlioTypography.caption.copyWith(color: PhlioColors.textSecondary),
            ),
            if (place.address.isNotEmpty)
              Text(place.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
          ]),
        ),
        const SizedBox(width: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onDirections,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFF6FD6B5), borderRadius: BorderRadius.circular(16)),
              child: const Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.directions_rounded, color: Color(0xFF0B1A14)),
                Text('Go', style: TextStyle(color: Color(0xFF0B1A14), fontWeight: FontWeight.w800, fontSize: 12)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
