// Places in Social explore search. Search anything ("kukatpally", "cooking")
// and, when places match, a live map card appears above the results with
// those places as photo markers. Tap it to open the full map
// (PlaceMapScreen, shared/location/place_map.dart): photos people posted
// there, "Search this area", and the place's page with Top / Recent posts.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../design_system/colors.dart';
import '../../../../shared/location/location_share_screen.dart' show phlioMapStyle;
import '../../../../shared/location/place_map.dart';

class ExplorePlacesCard extends StatefulWidget {
  const ExplorePlacesCard({required this.query, super.key});
  final String query;
  @override
  State<ExplorePlacesCard> createState() => _ExplorePlacesCardState();
}

class _ExplorePlacesCardState extends State<ExplorePlacesCard> {
  List<Map<String, dynamic>> _places = [];
  final _icons = <String, BitmapDescriptor>{};
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(ExplorePlacesCard old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _search();
  }

  Future<void> _search() async {
    final q = widget.query.trim();
    final request = ++_request;
    if (q.length < 2) {
      if (_places.isNotEmpty) setState(() => _places = []);
      return;
    }
    final here = await placesHere();
    final found = await searchPhlioPlaces(q, lat: here?.latitude, lng: here?.longitude);
    if (!mounted || request != _request) return;
    setState(() {
      _places = found.take(12).toList();
      _icons.clear();
    });
    for (final p in _places.take(6)) {
      final cover = p['cover'] as Map?;
      final posts = (p['posts'] as num?)?.toInt() ?? 0;
      final icon = await placeMarker(
        label: '${p['name']}',
        photoUrl: cover != null && cover['media_kind'] != 'video' ? '${cover['image_url']}' : null,
        more: posts > 1 ? posts - 1 : 0,
        big: identical(p, _places.first),
      );
      if (!mounted || request != _request) return;
      setState(() => _icons['${p['id']}'] = icon);
    }
  }

  void _open([int index = 0]) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaceMapScreen(places: _places, selected: index, title: widget.query.trim()),
    ));
  }

  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: _places.isEmpty ? const SizedBox(width: double.infinity) : _card(),
      );

  Widget _card() {
    final first = _places.first;
    final shown = _places.take(6).toList();
    final posts = _places.fold<int>(0, (a, p) => a + ((p['posts'] as num?)?.toInt() ?? 0));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: GestureDetector(
        onTap: _open,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 190,
            child: Stack(fit: StackFit.expand, children: [
              IgnorePointer(
                child: GoogleMap(
                  key: ValueKey(first['id']),
                  liteModeEnabled: true,
                  initialCameraPosition: CameraPosition(target: placeLatLng(first), zoom: shown.length > 1 ? 12 : 14.5),
                  style: phlioMapStyle,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  myLocationButtonEnabled: false,
                  markers: {
                    for (final p in shown)
                      Marker(
                        markerId: MarkerId('${p['id']}'),
                        position: placeLatLng(p),
                        icon: _icons['${p['id']}'] ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
                        anchor: Offset(.5, _icons['${p['id']}'] == null ? 1 : markerAnchorY(_icons['${p['id']}']!)),
                      ),
                  },
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [.45, 1],
                    colors: [Colors.transparent, Color(0xEE080E16)],
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('${first['name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white)),
                      Text(
                        [
                          '${_places.length} place${_places.length == 1 ? '' : 's'}',
                          if (posts > 0) '$posts post${posts == 1 ? '' : 's'}',
                        ].join(' · '),
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(color: PhlioColors.brandViolet, borderRadius: BorderRadius.circular(20)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.map_rounded, size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text('See on map', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
