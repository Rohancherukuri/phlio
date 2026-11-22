// Places in Phlio Social explore, Instagram-style.
//
//   [ExplorePlaces]  the "Places" tab of explore search: every place that
//                    matches — the ones people tagged on Phlio first (cover
//                    photo + how many posts), then Google Maps / OpenStreetMap
//                    results — each with a pin, its name and address.
//   [PlaceScreen]    tap a place: a full-screen map centred on it with its pin
//                    and a "Name · See more" bubble. Around it, photos people
//                    posted nearby sit on the map; move the map and "Search
//                    this area" loads the posts there. The sheet at the
//                    bottom grows into the place's page: name, address,
//                    distance, Directions / Share / Save, who posted there,
//                    and its posts in Top and Recent.
//
// Backend: GET /explore/places/search | /posts | /area, PUT /saved
// (backend/app/api/v1/explore_places.py).

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../shared/content/memory_photo.dart';
import '../../../../shared/location/location_message.dart' show openInMaps;
import '../../../../shared/location/location_service.dart';
import '../../../../shared/location/location_share_screen.dart' show phlioMapStyle;
import '../../../../shared/location/places_api.dart' as osm;

Dio get _dio => getIt<ApiClient>().dio;

/// Your position, once (null when location is off or denied).
Future<Position?> _here() async {
  try {
    return await Geolocator.getLastKnownPosition() ?? await currentPosition();
  } catch (_) {
    return null;
  }
}

String _distance(num? metres) {
  if (metres == null) return '';
  if (metres < 1000) return '${metres.round()} m';
  final km = metres / 1000;
  return km < 100 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}

// -- search results ------------------------------------------------------------------------------

class ExplorePlaces extends StatefulWidget {
  const ExplorePlaces({required this.query, super.key});
  final String query;
  @override
  State<ExplorePlaces> createState() => _ExplorePlacesState();
}

class _ExplorePlacesState extends State<ExplorePlaces> {
  Position? _pos;
  Future<List<Map<String, dynamic>>>? _results;

  @override
  void initState() {
    super.initState();
    _here().then((p) {
      if (!mounted) return;
      _pos = p;
      _search();
    });
    _search();
  }

  @override
  void didUpdateWidget(ExplorePlaces old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _search();
  }

  void _search() {
    final q = widget.query.trim();
    setState(() => _results = q.isEmpty ? null : _find(q));
  }

  Future<List<Map<String, dynamic>>> _find(String q) async {
    final lat = _pos?.latitude, lng = _pos?.longitude;
    var items = <Map<String, dynamic>>[];
    var external = 'none';
    try {
      final res = await _dio.get('/explore/places/search', queryParameters: {
        'q': q,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      });
      final body = res.data as Map;
      items = [for (final x in (body['items'] as List)) (x as Map).cast<String, dynamic>()];
      external = '${body['external']}';
    } catch (_) {
      external = 'unavailable';
    }
    // No Google on this server: OpenStreetMap fills in the map results.
    if (external != 'google' && q.length >= 2) {
      try {
        for (final p in await osm.searchPlaces(q, lat: lat, lng: lng)) {
          if (items.any((x) => Geolocator.distanceBetween(p.lat, p.lng, (x['lat'] as num).toDouble(), (x['lng'] as num).toDouble()) < 80)) {
            continue;
          }
          items.add({
            'id': '${p.lat},${p.lng}',
            'name': p.name,
            'address': p.address,
            'lat': p.lat,
            'lng': p.lng,
            'posts': 0,
            'source': 'osm',
            if (lat != null && lng != null) 'distance': Geolocator.distanceBetween(lat, lng, p.lat, p.lng),
          });
        }
      } catch (_) {}
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    if (results == null) return _Empty(onMap: () => _openMap(context, null));
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: results,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('No places found for “${widget.query}”.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          itemCount: items.length,
          itemBuilder: (_, i) => _PlaceTile(place: items[i], index: i),
        );
      },
    );
  }

  void _openMap(BuildContext context, Map<String, dynamic>? place) async {
    final p = place ?? (_pos == null ? null : {'name': 'Near you', 'address': '', 'lat': _pos!.latitude, 'lng': _pos!.longitude, 'nearby': true});
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turn on location to see what’s happening nearby.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaceScreen(place: p)));
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onMap});
  final VoidCallback onMap;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 1.5)),
              child: const Icon(Icons.location_on_outlined, size: 36),
            ),
            const SizedBox(height: 14),
            const Text('Search places', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Find cafés, spots and cities, and see what people posted there.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onMap, icon: const Icon(Icons.map_outlined), label: const Text('Explore the map')),
          ]),
        ),
      );
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({required this.place, required this.index});
  final Map<String, dynamic> place;
  final int index;
  @override
  Widget build(BuildContext context) {
    final cover = place['cover'] as Map?;
    final posts = (place['posts'] as num?)?.toInt() ?? 0;
    final address = '${place['address'] ?? ''}';
    final distance = _distance(place['distance'] as num?);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + 40 * index.clamp(0, 10)),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child)),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaceScreen(place: place)));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
              clipBehavior: Clip.antiAlias,
              child: cover != null && cover['media_kind'] != 'video'
                  ? MemoryPhoto('${cover['image_url']}')
                  : const Icon(Icons.location_on_outlined, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${place['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                if (address.isNotEmpty || distance.isNotEmpty)
                  Text([if (address.isNotEmpty) address, if (distance.isNotEmpty) distance].join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54)),
              ]),
            ),
            if (posts > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: PhlioColors.brandViolet.withValues(alpha: .16), borderRadius: BorderRadius.circular(12)),
                child: Text('$posts post${posts == 1 ? '' : 's'}',
                    style: const TextStyle(color: PhlioColors.brandViolet, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
      ),
    );
  }
}

// -- the map + place page ------------------------------------------------------------------------

class PlaceScreen extends StatefulWidget {
  const PlaceScreen({required this.place, super.key});
  final Map<String, dynamic> place;
  @override
  State<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends State<PlaceScreen> {
  final _sheet = DraggableScrollableController();
  GoogleMapController? _map;
  late Map<String, dynamic> _place = widget.place;
  Map<String, dynamic>? _info;
  List<Map<String, dynamic>> _posts = [];
  bool _top = true, _loading = true, _moved = false, _saved = false;
  Position? _pos;
  LatLng? _camera;
  List<Map> _areaPlaces = [];
  final _icons = <String, BitmapDescriptor>{};

  static const _collapsed = .16, _half = .5, _full = .94;

  LatLng get _at => LatLng((_place['lat'] as num).toDouble(), (_place['lng'] as num).toDouble());
  bool get _nearby => _place['nearby'] == true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadArea(_at);
    _here().then((p) {
      if (mounted) setState(() => _pos = p);
    });
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _dio.get('/explore/places/posts', queryParameters: {
        'lat': _at.latitude,
        'lng': _at.longitude,
        if (!_nearby) 'name': '${_place['name']}',
        'sort': _top ? 'top' : 'recent',
      });
      final body = res.data as Map;
      if (!mounted) return;
      setState(() {
        _info = (body['place'] as Map).cast<String, dynamic>();
        _saved = _info!['saved'] == true;
        _posts = [for (final x in (body['items'] as List)) (x as Map).cast<String, dynamic>()];
      });
    } catch (_) {
      if (mounted) setState(() => _posts = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadArea(LatLng at) async {
    try {
      final res = await _dio.get('/explore/places/area', queryParameters: {'lat': at.latitude, 'lng': at.longitude, 'radius_km': 8});
      final places = ((res.data as Map)['places'] as List).cast<Map>();
      if (!mounted) return;
      setState(() {
        _areaPlaces = places;
        _moved = false;
      });
      for (final p in places) {
        final cover = p['cover'] as Map?;
        if (cover == null || cover['media_kind'] == 'video' || _icons.containsKey('${p['id']}')) continue;
        unawaited(_photoMarker('${cover['image_url']}').then((icon) {
          if (icon != null && mounted) setState(() => _icons['${p['id']}'] = icon);
        }));
      }
    } catch (_) {}
  }

  /// A round photo with a white rim and a little tail, like Instagram's map.
  Future<BitmapDescriptor?> _photoMarker(String url) async {
    try {
      final res = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(res.data!), targetWidth: 180);
      final image = (await codec.getNextFrame()).image;
      const size = 168.0, rim = 9.0, tail = 18.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final c = const Offset(size / 2, size / 2);
      canvas.drawCircle(c + const Offset(0, 4), size / 2 - 2, Paint()
        ..color = Colors.black38
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      final path = Path()
        ..moveTo(size / 2 - 14, size - 8)
        ..lineTo(size / 2, size + tail - 4)
        ..lineTo(size / 2 + 14, size - 8)
        ..close();
      canvas.drawPath(path, Paint()..color = Colors.white);
      canvas.drawCircle(c, size / 2 - 4, Paint()..color = Colors.white);
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: size / 2 - 4 - rim)));
      final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      final side = src.shortestSide;
      canvas.drawImageRect(
        image,
        Rect.fromCenter(center: src.center, width: side, height: side),
        Rect.fromCircle(center: c, radius: size / 2 - 4 - rim),
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      final png = await (await recorder.endRecording().toImage(size.toInt(), (size + tail).toInt())).toByteData(format: ui.ImageByteFormat.png);
      return BitmapDescriptor.bytes(png!.buffer.asUint8List(), width: 56);
    } catch (_) {
      return null;
    }
  }

  void _select(Map p) {
    HapticFeedback.selectionClick();
    setState(() => _place = {'name': p['name'], 'address': p['address'], 'lat': p['lat'], 'lng': p['lng'], 'posts': p['posts']});
    _map?.animateCamera(CameraUpdate.newLatLng(_at));
    _load();
    _sheet.animateTo(_half, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  Future<void> _toggleSave() async {
    final next = !_saved;
    HapticFeedback.lightImpact();
    setState(() => _saved = next);
    try {
      await _dio.put('/explore/places/saved', data: {
        'lat': _at.latitude,
        'lng': _at.longitude,
        'name': '${_place['name']}',
        'address': '${_place['address'] ?? ''}',
        'saved': next,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next ? 'Place saved' : 'Removed from saved')));
      }
    } catch (_) {
      if (mounted) setState(() => _saved = !next);
    }
  }

  Future<void> _myLocation() async {
    final p = _pos ?? await _here();
    if (p == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location is off for Phlio.')));
      }
      return;
    }
    setState(() => _pos = p);
    _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(p.latitude, p.longitude), 14));
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final markers = <Marker>{
      if (!_nearby)
        Marker(
          markerId: const MarkerId('place'),
          position: _at,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          onTap: () => _sheet.animateTo(_half, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic),
        ),
      for (final p in _areaPlaces)
        Marker(
          markerId: MarkerId('area-${p['id']}'),
          position: LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
          icon: _icons['${p['id']}'] ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
          anchor: const Offset(.5, 1),
          infoWindow: InfoWindow(title: '${p['name']}', snippet: '${p['posts']} post${p['posts'] == 1 ? '' : 's'}'),
          onTap: () => _select(p),
        ),
    };
    return Scaffold(
      backgroundColor: PhlioColors.background,
      body: Stack(children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: _at, zoom: _nearby ? 13 : 16),
            style: phlioMapStyle,
            myLocationEnabled: _pos != null,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            padding: EdgeInsets.only(bottom: MediaQuery.sizeOf(context).height * _collapsed),
            markers: markers,
            onMapCreated: (c) => _map = c,
            onCameraMove: (cam) => _camera = cam.target,
            onCameraIdle: () {
              final cam = _camera;
              if (cam != null && Geolocator.distanceBetween(cam.latitude, cam.longitude, _at.latitude, _at.longitude) > 600 && !_moved) {
                setState(() => _moved = true);
              }
            },
          ),
        ),
        // Top bar: back · "Search this area" · my location.
        Positioned(
          top: top + 8,
          left: 16,
          right: 16,
          child: Row(children: [
            _RoundButton(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop()),
            Expanded(
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                  child: _moved
                      ? _Pill(
                          key: const ValueKey('area'),
                          text: 'Search this area',
                          onTap: () {
                            final cam = _camera;
                            if (cam != null) _loadArea(cam);
                          },
                        )
                      : _Pill(
                          key: const ValueKey('loc'),
                          icon: _pos == null ? Icons.warning_amber_rounded : Icons.near_me_rounded,
                          iconColor: _pos == null ? const Color(0xFFFF9F5A) : PhlioColors.brandViolet,
                          text: _pos == null ? 'Device location off' : 'Places near ${_nearby ? 'you' : 'here'}',
                          onTap: _myLocation,
                        ),
                ),
              ),
            ),
            _RoundButton(icon: Icons.my_location_rounded, onTap: _myLocation),
          ]),
        ),
        // "Name · See more" over the pin.
        if (!_nearby)
          Align(
            alignment: Alignment(0, -.06 - _collapsed),
            child: IgnorePointer(
              ignoring: false,
              child: GestureDetector(
                onTap: () => _sheet.animateTo(_half, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic),
                child: Container(
                  margin: const EdgeInsets.only(top: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: PhlioColors.surface,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 14, offset: Offset(0, 4))],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${_place['name']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const Text('See more', style: TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
          ),
        DraggableScrollableSheet(
          controller: _sheet,
          initialChildSize: _collapsed,
          minChildSize: _collapsed,
          maxChildSize: _full,
          snap: true,
          snapSizes: const [_collapsed, _half, _full],
          builder: (context, scroll) => DecoratedBox(
            decoration: const BoxDecoration(
              color: PhlioColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20)],
            ),
            child: CustomScrollView(controller: scroll, slivers: [
              SliverToBoxAdapter(child: _header()),
              SliverToBoxAdapter(child: _tabs()),
              if (_loading)
                const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())))
              else if (_posts.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Text('No posts here yet. Share an Experience with this place and it shows up here.',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
                  ),
                )
              else
                SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: .8),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _PostTile(post: _posts[i], onTap: () => _openPost(_posts[i])),
                    childCount: _posts.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _header() {
    final info = _info;
    final posts = (info?['posts'] as num?)?.toInt() ?? (_place['posts'] as num?)?.toInt() ?? 0;
    final people = ((info?['people'] as List?) ?? const []).cast<Map>();
    final distance = _pos == null ? null : Geolocator.distanceBetween(_pos!.latitude, _pos!.longitude, _at.latitude, _at.longitude);
    final cover = _posts.isNotEmpty ? _posts.first : null;
    final address = '${_place['address'] ?? info?['address'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 1.5)),
            clipBehavior: Clip.antiAlias,
            child: cover != null && cover['media_kind'] != 'video'
                ? MemoryPhoto('${cover['image_url']}')
                : const Icon(Icons.location_on_rounded, size: 30, color: PhlioColors.brandViolet),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_place['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              if (address.isNotEmpty) Text(address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
              Text(
                [if (distance != null) _distance(distance), '$posts post${posts == 1 ? '' : 's'}'].join(' · '),
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ]),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => _sheet.animateTo(_collapsed, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => openInMaps(_at.latitude, _at.longitude),
              icon: const Icon(Icons.directions_rounded, size: 18),
              label: const Text('Directions'),
            ),
          ),
          const SizedBox(width: 8),
          _CircleAction(
            icon: Icons.send_rounded,
            tooltip: 'Share',
            onTap: () => SharePlus.instance.share(ShareParams(
              text: '${_place['name']}\nhttps://www.google.com/maps/search/?api=1&query=${_at.latitude},${_at.longitude}',
            )),
          ),
          const SizedBox(width: 8),
          _CircleAction(
            icon: _saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            tooltip: _saved ? 'Saved' : 'Save',
            color: _saved ? PhlioColors.brandViolet : null,
            onTap: _toggleSave,
          ),
        ]),
        if (people.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(children: [
            SizedBox(
              width: 22.0 + (people.length.clamp(1, 4) - 1) * 16,
              height: 26,
              child: Stack(children: [
                for (final (i, p) in people.take(4).indexed)
                  Positioned(
                    left: i * 16,
                    child: PhlioAvatar(name: '${p['display_name'] ?? p['username']}', imageUrl: p['avatar_url'] as String?, size: 26, showMomentRing: false),
                  ),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Posted here by ${people.take(2).map((p) => p['username']).join(', ')}${people.length > 2 ? ' and ${people.length - 2} more' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _tabs() => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          for (final (label, top) in const [('Top', true), ('Recent', false)])
            Expanded(
              child: InkWell(
                onTap: () {
                  if (_top == top) return;
                  setState(() => _top = top);
                  _load();
                },
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(label,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _top == top ? Colors.white : Colors.white54)),
                  ),
                  AnimatedContainer(duration: const Duration(milliseconds: 220), height: 2, color: _top == top ? Colors.white : Colors.white12),
                ]),
              ),
            ),
        ]),
      );

  void _openPost(Map<String, dynamic> post) {
    final author = (post['author'] as Map?) ?? const {};
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialog) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: PhlioAvatar(name: '${author['display_name'] ?? author['username'] ?? ''}', imageUrl: author['avatar_url'] as String?, size: 38, showMomentRing: false),
            title: Text('${author['display_name'] ?? author['username'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${(post['place'] as Map)['name']}'),
            trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(dialog)),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: MemoryPhoto('${post['image_url']}',
                  isVideo: post['media_kind'] == 'video', filter: post['filter'] as String?, filterSpec: post['filter_spec'], autoplay: true),
            ),
          ),
          if ('${post['caption'] ?? ''}'.isNotEmpty)
            Padding(padding: const EdgeInsets.all(12), child: Text('${post['caption']}', style: const TextStyle(color: Colors.white))),
        ]),
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post, required this.onTap});
  final Map<String, dynamic> post;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Stack(fit: StackFit.expand, children: [
          MemoryPhoto('${post['image_url']}', isVideo: post['media_kind'] == 'video', filter: post['filter'] as String?, filterSpec: post['filter_spec']),
          if (post['media_kind'] == 'video')
            const Positioned(top: 6, right: 6, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22)),
          if (((post['reactions'] as num?) ?? 0) > 0)
            Positioned(
              left: 6,
              bottom: 6,
              child: Row(children: [
                const Icon(Icons.favorite_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 3),
                Text('${post['reactions']}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ]),
            ),
        ]),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: PhlioColors.surface,
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: Colors.black54,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 48, height: 48, child: Icon(icon, size: 22)),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.onTap, this.icon, this.iconColor, super.key});
  final String text;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: PhlioColors.surface,
        shape: const StadiumBorder(),
        elevation: 6,
        shadowColor: Colors.black54,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 18, color: iconColor), const SizedBox(width: 6)],
              Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, required this.tooltip, required this.onTap, this.color});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white.withValues(alpha: .08),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 46, height: 46, child: Icon(icon, color: color, size: 22)),
          ),
        ),
      );
}
