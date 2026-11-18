// Location picker for notes (Instagram-style): opens straight away with a
// search box, "Where you are" (your neighbourhood), Areas nearby and Spots
// nearby with distance and address; typing searches places around you.
// Area names come from Google Places around you (the area most nearby
// places share), then the phone's geocoder, Phlio's server, OpenStreetMap.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/colors.dart';
import '../../../../shared/location/location_service.dart';
import '../../../../shared/location/places_api.dart';
import '../../../../shared/location/device_places.dart';
import '../../../../shared/location/google_places.dart';
import '../../../../shared/location/server_places.dart';

Future<Place?> pickNotePlace(BuildContext context, {String? selected}) => showModalBottomSheet<Place>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PhlioColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _NotePlacePicker(selected: selected),
    );

class _NotePlacePicker extends StatefulWidget {
  const _NotePlacePicker({this.selected});
  final String? selected;

  @override
  State<_NotePlacePicker> createState() => _NotePlacePickerState();
}

class _NotePlacePickerState extends State<_NotePlacePicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  double? lat, lng;
  Place? here;
  List<Place> areas = const [], spots = const [], results = const [];
  bool loading = true, searching = false;
  bool fromGoogle = false; // results from Google: show the attribution
  String? problem;
  int _query = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final pos = await currentPosition();
      lat = pos.latitude;
      lng = pos.longitude;
      // 1. Google Places around you: the area most nearby places share,
      //    plus the places themselves.
      final google = await googleNearby(lat!, lng!);
      if (google != null && (google.areas.isNotEmpty || google.spots.isNotEmpty)) {
        if (mounted) {
          setState(() {
            fromGoogle = true;
            here = google.areas.isEmpty ? null : google.areas.first;
            areas = google.areas.skip(1).toList();
            spots = google.spots;
          });
        }
        if (here != null) return;
      }
      // 2. The phone's geocoder, Phlio's server, then OpenStreetMap.
      final device = await deviceAreas(lat!, lng!);
      final server = device == null ? await serverAreas(lat!, lng!) : null;
      final named = device ?? server;
      if (named != null && named.isNotEmpty) {
        if (mounted) {
          setState(() {
            here = named.first;
            if (areas.isEmpty) areas = named.skip(1).toList();
          });
        }
      } else {
        final p = await areaName(lat!, lng!);
        final a = await nearbyAreas(lat!, lng!).catchError((Object _) => <Place>[]);
        if (mounted) {
          setState(() {
            here = p;
            areas = a;
          });
        }
      }
      if (spots.isEmpty) {
        final fromServer = await serverNearby(lat!, lng!, radius: 1000);
        final s = fromServer != null && fromServer.isNotEmpty
            ? fromServer
            : await nearbyPlaces(lat!, lng!, radius: 1000, limit: 25).catchError((Object _) => <Place>[]);
        if (mounted) setState(() => spots = s);
      }
    } on LocationProblem catch (e) {
      if (mounted) setState(() => problem = e.toString());
    } catch (_) {
      if (mounted) setState(() => problem = 'Could not find where you are.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() {
        results = const [];
        searching = false;
      });
      return;
    }
    setState(() => searching = true);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final id = ++_query;
      try {
        final found = await googleSearch(q, lat: lat, lng: lng) ??
            await serverSearch(q, lat: lat, lng: lng) ??
            await searchPlaces(q, lat: lat, lng: lng, box: .25);
        if (lat != null) {
          found.sort((a, b) => distanceMetres(lat!, lng!, a.lat, a.lng).compareTo(distanceMetres(lat!, lng!, b.lat, b.lng)));
        }
        if (mounted && id == _query) {
          setState(() {
            results = found;
            searching = false;
          });
        }
      } catch (_) {
        if (mounted && id == _query) setState(() => searching = false);
      }
    });
  }

  String _sub(Place p) {
    final parts = <String>[
      if (lat != null) formatDistance(distanceMetres(lat!, lng!, p.lat, p.lng)),
      if ((p.kind ?? '').isNotEmpty && p.kind != 'area') _cap(p.kind!),
      if (p.address.isNotEmpty) p.address,
    ];
    return parts.join(' · ');
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _tile(Place p, IconData icon, {Color? tint}) => ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: (tint ?? PhlioColors.textMuted).withValues(alpha: 0.16),
          child: Icon(icon, size: 20, color: tint ?? PhlioColors.textPrimary),
        ),
        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_sub(p),
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PhlioColors.textMuted, fontSize: 12.5)),
        trailing: widget.selected == p.name ? const Icon(Icons.check_rounded, color: Color(0xFF3897F0)) : null,
        onTap: () => Navigator.pop(context, p),
      );

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: PhlioColors.textMuted)),
      );

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final hereName = here?.name.toLowerCase();
    final shownAreas = areas.where((a) => a.name.toLowerCase() != hereName).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scroll) => Column(children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: PhlioColors.textMuted, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            const Expanded(child: Text('Add location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _search,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search locations',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        _onSearch('');
                      },
                    ),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        if (loading || searching) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
        Expanded(
          child: ListView(controller: scroll, padding: const EdgeInsets.only(bottom: 24), children: [
            if (problem != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(problem!, textAlign: TextAlign.center, style: const TextStyle(color: PhlioColors.textMuted)),
              ),
            if (query.length >= 2) ...[
              _header('Results'),
              for (final p in results) _tile(p, Icons.location_on_outlined),
              if (!searching && results.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No places found. Try another name.',
                      textAlign: TextAlign.center, style: TextStyle(color: PhlioColors.textMuted)),
                ),
            ] else ...[
              if (here != null) ...[
                _header('Where you are'),
                _tile(here!, Icons.my_location_rounded, tint: const Color(0xFF3897F0)),
              ],
              if (shownAreas.isNotEmpty) ...[
                _header('Areas nearby'),
                for (final a in shownAreas) _tile(a, Icons.location_city_rounded, tint: PhlioColors.brandViolet),
              ],
              if (spots.isNotEmpty) ...[
                _header('Spots nearby'),
                for (final p in spots) _tile(p, Icons.storefront_outlined),
              ],
              if (!loading && problem == null && here == null && areas.isEmpty && spots.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text("Couldn't load places nearby. Search for a place instead.",
                      textAlign: TextAlign.center, style: TextStyle(color: PhlioColors.textMuted)),
                ),
            ],
            if (fromGoogle)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Powered by Google',
                    textAlign: TextAlign.center, style: TextStyle(color: PhlioColors.textMuted, fontSize: 11)),
              ),
          ]),
        ),
      ]),
    );
  }
}
