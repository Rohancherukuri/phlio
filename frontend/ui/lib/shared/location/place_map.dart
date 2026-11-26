// Places on the map, Instagram-style — shared by Social explore search and
// Foxy Maps ("Ask Maps").
//
//   [PlaceMapScreen]   a full-screen map of places: each is a round photo
//                      (the newest post made there) with a little tail and
//                      its name under it ("+2 more" when several posts sit
//                      together); places with no posts yet get a pin bubble.
//                      The chosen place is drawn bigger. Move the map and
//                      "Search this area" loads what people posted there.
//                      The sheet at the bottom is the place's page.
//   [PlaceSheetBody]   the page itself: photo, name, address, distance,
//                      Directions / Share / Save, who posted there, and the
//                      posts in Top and Recent.
//   [showPlaceSheet]   the same page as a bottom sheet over another map
//                      (Foxy Maps).
//   [placeMarker]      draws those photo / pin markers.
//
// Backend: GET /explore/places/search | /posts | /area, PUT /saved
// (backend/app/api/v1/explore_places.py).

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../content/memory_photo.dart';
import 'location_message.dart' show openInMaps;
import 'location_service.dart';
import 'location_share_screen.dart' show phlioMapStyle;
import 'places_api.dart' as osm;
import 'place_share.dart' show showPlaceShare;

Dio get _dio => getIt<ApiClient>().dio;

/// Your position, once (null when location is off or denied).
Future<Position?> placesHere() async {
  try {
    return await Geolocator.getLastKnownPosition() ?? await currentPosition();
  } catch (_) {
    return null;
  }
}

String placeDistance(num? metres) {
  if (metres == null) return '';
  if (metres < 1000) return '${metres.round()} m';
  final km = metres / 1000;
  return km < 100 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}

LatLng placeLatLng(Map p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());

/// Places matching [q]: tagged on Phlio first, then Google Maps — or
/// OpenStreetMap when the server has no Google key.
Future<List<Map<String, dynamic>>> searchPhlioPlaces(String q, {double? lat, double? lng}) async {
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
  if (external != 'google' && q.trim().length >= 2) {
    try {
      for (final p in await osm.searchPlaces(q, lat: lat, lng: lng)) {
        if (items.any((x) => Geolocator.distanceBetween(p.lat, p.lng, (x['lat'] as num).toDouble(), (x['lng'] as num).toDouble()) < 80)) {
          continue;
        }
        items.add({
          'id': '${p.lat.toStringAsFixed(5)},${p.lng.toStringAsFixed(5)}',
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

/// Places people posted from around [at] (grouped, each with a cover post).
Future<List<Map<String, dynamic>>> areaPlaces(LatLng at, {double radiusKm = 8}) async {
  try {
    final res = await _dio.get('/explore/places/area',
        queryParameters: {'lat': at.latitude, 'lng': at.longitude, 'radius_km': radiusKm});
    return [for (final x in ((res.data as Map)['places'] as List)) (x as Map).cast<String, dynamic>()];
  } catch (_) {
    return [];
  }
}

// -- markers ---------------------------------------------------------------------------------------

final _photoCache = <String, ui.Image>{};
final _markerCache = <String, BitmapDescriptor>{};

Future<ui.Image?> _photo(String url) async {
  final hit = _photoCache[url];
  if (hit != null) return hit;
  try {
    final res = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(res.data!), targetWidth: 220);
    final image = (await codec.getNextFrame()).image;
    if (_photoCache.length > 80) _photoCache.clear();
    return _photoCache[url] = image;
  } catch (_) {
    return null;
  }
}

/// A round photo (or a pin when there's none) with a white rim, a tail, and
/// the place's name under it — the anchor is the tail's tip, so pass
/// `anchor: const Offset(.5, markerAnchorY)`.
Future<BitmapDescriptor> placeMarker({
  required String label,
  String? photoUrl,
  int more = 0,
  bool big = false,
}) async {
  final cacheKey = '$label|$photoUrl|$more|$big';
  final hit = _markerCache[cacheKey];
  if (hit != null) return hit;
  final image = photoUrl == null ? null : await _photo(photoUrl);
  const px = 3.0; // drawn at 3x, shown at logical size
  final d = (big ? 74.0 : 52.0) * px; // photo circle
  const rim = 4.0 * px, tail = 7.0 * px, width = 150.0 * px;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final cx = width / 2, cy = d / 2 + 2 * px;
  final c = Offset(cx, cy);
  // Shadow, tail, rim.
  canvas.drawCircle(c + const Offset(0, 2 * px), d / 2, Paint()
    ..color = Colors.black.withValues(alpha: .45)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4 * px));
  canvas.drawPath(
    Path()
      ..moveTo(cx - 6 * px, cy + d / 2 - 3 * px)
      ..lineTo(cx, cy + d / 2 + tail)
      ..lineTo(cx + 6 * px, cy + d / 2 - 3 * px)
      ..close(),
    Paint()..color = Colors.white,
  );
  canvas.drawCircle(c, d / 2, Paint()..color = Colors.white);
  final inner = Rect.fromCircle(center: c, radius: d / 2 - rim);
  if (image != null) {
    canvas.save();
    canvas.clipPath(Path()..addOval(inner));
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final side = src.shortestSide;
    canvas.drawImageRect(image, Rect.fromCenter(center: src.center, width: side, height: side), inner,
        Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  } else {
    canvas.drawCircle(c, d / 2 - rim, Paint()..color = const Color(0xFF1B2230));
    final icon = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.location_on_rounded.codePoint),
        style: TextStyle(fontSize: d * .5, fontFamily: Icons.location_on_rounded.fontFamily, package: Icons.location_on_rounded.fontPackage, color: PhlioColors.brandViolet),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    icon.paint(canvas, c - Offset(icon.width / 2, icon.height / 2));
  }
  // Name (and "+N more") under the tail, with a dark halo so it reads on any map.
  final text = more > 0 ? '$label\n+$more more' : label;
  TextPainter painter(Paint? stroke) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: 12.5 * px,
            fontWeight: FontWeight.w800,
            height: 1.15,
            foreground: stroke,
            color: stroke == null ? Colors.white : null,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: width);
  final halo = painter(Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.5 * px
    ..strokeJoin = StrokeJoin.round
    ..color = const Color(0xE6080E16));
  final fill = painter(null);
  final ty = cy + d / 2 + tail + 2 * px;
  halo.paint(canvas, Offset(cx - halo.width / 2, ty));
  fill.paint(canvas, Offset(cx - fill.width / 2, ty));
  final height = (ty + fill.height + 4 * px).ceil();
  final png = await (await recorder.endRecording().toImage(width.toInt(), height)).toByteData(format: ui.ImageByteFormat.png);
  final descriptor = BitmapDescriptor.bytes(png!.buffer.asUint8List(), width: width / px, height: height / px);
  if (_markerCache.length > 200) _markerCache.clear();
  // Remember where the tail ends, for the anchor.
  _anchors[descriptor] = (cy + d / 2 + tail) / height;
  return _markerCache[cacheKey] = descriptor;
}

final _anchors = Expando<double>();

/// Vertical anchor (0–1) for a descriptor made by [placeMarker].
double markerAnchorY(BitmapDescriptor icon) => _anchors[icon] ?? 1;

// -- the full-screen map ------------------------------------------------------------------------------

class PlaceMapScreen extends StatefulWidget {
  const PlaceMapScreen({required this.places, this.selected = 0, this.title, super.key});

  /// Places to show (search results); the [selected] one opens in the sheet.
  final List<Map<String, dynamic>> places;
  final int selected;
  final String? title;

  @override
  State<PlaceMapScreen> createState() => _PlaceMapScreenState();
}

class _PlaceMapScreenState extends State<PlaceMapScreen> {
  final _sheet = DraggableScrollableController();
  final _bodyKey = GlobalKey<PlaceSheetBodyState>();
  GoogleMapController? _map;
  late List<Map<String, dynamic>> _places = [...widget.places];
  late Map<String, dynamic> _place = widget.places[widget.selected];
  final _icons = <String, BitmapDescriptor>{};
  Position? _pos;
  LatLng? _camera;
  bool _moved = false, _searching = false;

  static const _small = .2, _half = .46, _full = .94;

  @override
  void initState() {
    super.initState();
    _paint();
    _loadArea(placeLatLng(_place));
    placesHere().then((p) {
      if (mounted) setState(() => _pos = p);
    });
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  String _id(Map p) => '${p['id'] ?? '${p['lat']},${p['lng']}'}';

  /// Draws every place's marker (the selected one big).
  Future<void> _paint() async {
    for (final p in [..._places]) {
      final cover = p['cover'] as Map?;
      final photo = cover != null && cover['media_kind'] != 'video' ? '${cover['image_url']}' : null;
      final posts = (p['posts'] as num?)?.toInt() ?? 0;
      final big = _id(p) == _id(_place);
      final icon = await placeMarker(label: '${p['name']}', photoUrl: photo, more: posts > 1 ? posts - 1 : 0, big: big);
      if (!mounted) return;
      setState(() => _icons['${_id(p)}|$big'] = icon);
    }
  }

  Future<void> _loadArea(LatLng at) async {
    setState(() => _searching = true);
    final found = await areaPlaces(at);
    if (!mounted) return;
    setState(() {
      for (final p in found) {
        final dup = _places.any((x) => Geolocator.distanceBetween((x['lat'] as num).toDouble(), (x['lng'] as num).toDouble(),
                (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()) < 60);
        if (!dup) _places.add(p);
      }
      _moved = false;
      _searching = false;
    });
    await _paint();
  }

  void _select(Map<String, dynamic> p) {
    HapticFeedback.selectionClick();
    setState(() => _place = p);
    _map?.animateCamera(CameraUpdate.newLatLng(placeLatLng(p)));
    _bodyKey.currentState?.show(p);
    _paint();
    if (_sheet.isAttached && _sheet.size < _half) {
      _sheet.animateTo(_half, duration: const Duration(milliseconds: 360), curve: Curves.easeOutCubic);
    }
  }

  Future<void> _myLocation() async {
    final p = _pos ?? await placesHere();
    if (!mounted) return;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location is off for Phlio.')));
      return;
    }
    setState(() => _pos = p);
    _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(p.latitude, p.longitude), 14));
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final height = MediaQuery.sizeOf(context).height;
    final markers = <Marker>{};
    for (final p in _places) {
      final big = _id(p) == _id(_place);
      final icon = _icons['${_id(p)}|$big'] ?? _icons['${_id(p)}|${!big}'];
      markers.add(Marker(
        markerId: MarkerId(_id(p)),
        position: placeLatLng(p),
        icon: icon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        anchor: Offset(.5, icon == null ? 1 : markerAnchorY(icon)),
        zIndex: big ? 3 : 1,
        onTap: () => _select(p),
      ));
    }
    return Scaffold(
      backgroundColor: PhlioColors.background,
      body: Stack(children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: placeLatLng(_place), zoom: 14.5),
            style: phlioMapStyle,
            myLocationEnabled: _pos != null,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            padding: EdgeInsets.only(bottom: height * _small),
            markers: markers,
            onMapCreated: (c) => _map = c,
            onCameraMove: (cam) => _camera = cam.target,
            onCameraIdle: () {
              final cam = _camera;
              if (cam == null || _moved) return;
              final at = placeLatLng(_place);
              if (Geolocator.distanceBetween(cam.latitude, cam.longitude, at.latitude, at.longitude) > 700) {
                setState(() => _moved = true);
              }
            },
          ),
        ),
        Positioned(
          top: top + 8,
          left: 16,
          right: 16,
          child: Row(children: [
            MapRoundButton(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).maybePop()),
            Expanded(
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                  child: _moved || _searching
                      ? MapPill(
                          key: const ValueKey('area'),
                          text: _searching ? 'Searching…' : 'Search this area',
                          onTap: _searching
                              ? null
                              : () {
                                  final cam = _camera;
                                  if (cam != null) _loadArea(cam);
                                },
                        )
                      : widget.title == null
                          ? const SizedBox.shrink()
                          : MapPill(key: const ValueKey('title'), text: widget.title!, icon: Icons.search_rounded, onTap: null),
                ),
              ),
            ),
            MapRoundButton(icon: Icons.near_me_outlined, onTap: _myLocation),
          ]),
        ),
        DraggableScrollableSheet(
          controller: _sheet,
          initialChildSize: _half,
          minChildSize: _small,
          maxChildSize: _full,
          snap: true,
          snapSizes: const [_small, _half, _full],
          builder: (context, scroll) => DecoratedBox(
            decoration: const BoxDecoration(
              color: PhlioColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20)],
            ),
            child: PlaceSheetBody(
              key: _bodyKey,
              place: _place,
              scroll: scroll,
              position: _pos,
              onClose: () => _sheet.animateTo(_small, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The place's page as a draggable bottom sheet over another screen.
Future<void> showPlaceSheet(BuildContext context, Map<String, dynamic> place, {Position? position}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => DraggableScrollableSheet(
        initialChildSize: .55,
        minChildSize: .3,
        maxChildSize: .95,
        expand: false,
        builder: (context, scroll) => DecoratedBox(
          decoration: const BoxDecoration(
            color: PhlioColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: PlaceSheetBody(place: place, scroll: scroll, position: position, onClose: () => Navigator.pop(sheet)),
        ),
      ),
    );

// -- the place's page ----------------------------------------------------------------------------------

class PlaceSheetBody extends StatefulWidget {
  const PlaceSheetBody({required this.place, required this.scroll, this.position, this.onClose, super.key});
  final Map<String, dynamic> place;
  final ScrollController scroll;
  final Position? position;
  final VoidCallback? onClose;
  @override
  State<PlaceSheetBody> createState() => PlaceSheetBodyState();
}

class PlaceSheetBodyState extends State<PlaceSheetBody> {
  late Map<String, dynamic> _place = widget.place;
  Map<String, dynamic>? _info;
  List<Map<String, dynamic>> _posts = [];
  bool _top = true, _loading = true, _saved = false;
  int _request = 0;

  LatLng get _at => placeLatLng(_place);

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Switch to another place (a marker was tapped).
  void show(Map<String, dynamic> place) {
    setState(() {
      _place = place;
      _info = null;
      _posts = [];
    });
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() => _loading = true);
    try {
      final res = await _dio.get('/explore/places/posts', queryParameters: {
        'lat': _at.latitude,
        'lng': _at.longitude,
        'name': '${_place['name']}',
        'sort': _top ? 'top' : 'recent',
      });
      if (!mounted || request != _request) return;
      final body = res.data as Map;
      setState(() {
        _info = (body['place'] as Map).cast<String, dynamic>();
        _saved = _info!['saved'] == true;
        _posts = [for (final x in (body['items'] as List)) (x as Map).cast<String, dynamic>()];
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _posts = []);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
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
    } catch (_) {
      if (mounted) setState(() => _saved = !next);
    }
  }

  @override
  Widget build(BuildContext context) => CustomScrollView(controller: widget.scroll, slivers: [
        SliverToBoxAdapter(child: _header()),
        SliverToBoxAdapter(child: _tabs()),
        if (_loading && _posts.isEmpty)
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
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: .8),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _PostTile(post: _posts[i], onTap: () => _openPost(_posts[i])),
              childCount: _posts.length,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ]);

  Widget _header() {
    final info = _info;
    final posts = (info?['posts'] as num?)?.toInt() ?? (_place['posts'] as num?)?.toInt() ?? 0;
    final people = ((info?['people'] as List?) ?? const []).cast<Map>();
    final pos = widget.position;
    final distance = pos == null ? null : Geolocator.distanceBetween(pos.latitude, pos.longitude, _at.latitude, _at.longitude);
    final cover = _posts.isNotEmpty ? _posts.first : _place['cover'] as Map?;
    final address = '${_place['address'] ?? info?['address'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 1.5)),
            clipBehavior: Clip.antiAlias,
            child: cover != null && cover['media_kind'] != 'video'
                ? MemoryPhoto('${cover['image_url']}')
                : const Icon(Icons.location_on_rounded, size: 30, color: PhlioColors.brandViolet),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_place['name']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              if (address.isNotEmpty)
                Text(address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              Text([if (distance != null) placeDistance(distance), '$posts post${posts == 1 ? '' : 's'}'].join(' · '),
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ]),
          ),
          if (widget.onClose != null)
            IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded, size: 26), onPressed: widget.onClose),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: _ActionButton(
              label: 'Directions',
              filled: true,
              onTap: () => openInMaps(_at.latitude, _at.longitude),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionButton(
              label: 'Share',
              // To friends, groups or Rooms as a place card (or outside Phlio).
              onTap: () => showPlaceShare(context, _place),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionButton(
              label: _saved ? 'Saved' : 'Save',
              icon: _saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              onTap: _toggleSave,
            ),
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
                    child: PhlioAvatar(
                        name: '${p['display_name'] ?? p['username']}', imageUrl: p['avatar_url'] as String?, size: 26, showMomentRing: false),
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
        padding: const EdgeInsets.only(top: 12),
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
            leading: PhlioAvatar(
                name: '${author['display_name'] ?? author['username'] ?? ''}', imageUrl: author['avatar_url'] as String?, size: 38, showMomentRing: false),
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onTap, this.icon, this.filled = false});
  final String label;
  final IconData? icon;
  final bool filled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: filled ? PhlioColors.brandViolet : Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[Icon(icon, size: 18, color: filled ? Colors.white : null), const SizedBox(width: 5)],
              Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: filled ? Colors.white : null)),
            ]),
          ),
        ),
      );
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
          if (post['media_kind'] == 'video') const Positioned(top: 6, right: 6, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22)),
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

class MapRoundButton extends StatelessWidget {
  const MapRoundButton({required this.icon, required this.onTap, super.key});
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
          child: SizedBox(width: 50, height: 50, child: Icon(icon, size: 22)),
        ),
      );
}

class MapPill extends StatelessWidget {
  const MapPill({required this.text, required this.onTap, this.icon, super.key});
  final String text;
  final IconData? icon;
  final VoidCallback? onTap;
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
              Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
          ),
        ),
      );
}
