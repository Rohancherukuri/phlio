// Location sharing — the "Send location" screen.
//
// Laid out like the familiar messenger flow, in Phlio colours:
//
//   ┌ ←  Send location                 🔍  ⟳ ┐
//   │            Google map  (pin, ⤢, ◎)     │
//   │ 📡 Share live location                 │   DMs only
//   │ ◎  Send your current location          │
//   │    Accurate to 8 metres                │
//   │ Recent      …places you've sent…        │
//   │ Nearby places …nearest first…           │
//   └─────────────────────────────────────────┘
//
// Panning the map moves the centre pin; the top row then sends that pin
// instead of your GPS fix, and the nearby list follows the pin. Search
// (Nominatim) replaces the list with results. The screen pops a
// [LocationPick]: a [PlacePick] to send once, or a [LivePick] to start live
// sharing for 15 min / 1 h / 8 h.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import 'location_service.dart';
import 'places_api.dart';

/// What the person chose on the send-location screen.
sealed class LocationPick {
  const LocationPick();
}

/// Send this place once.
class PlacePick extends LocationPick {
  const PlacePick(this.place, {this.accuracy});
  final Place place;

  /// Metres, when it's a GPS fix.
  final double? accuracy;
}

/// Share live location for [minutes], starting at [from].
class LivePick extends LocationPick {
  const LivePick(this.minutes, this.from);
  final int minutes;
  final Position from;
}

/// Opens the send-location screen. [allowLive] shows "Share live location".
Future<LocationPick?> openLocationShare(BuildContext context, {bool allowLive = false}) =>
    Navigator.of(context, rootNavigator: true).push<LocationPick>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LocationShareScreen(allowLive: allowLive),
    ));

/// Night map styling so the map sits in Phlio's dark surfaces.
const phlioMapStyle = '''
[
 {"elementType":"geometry","stylers":[{"color":"#111925"}]},
 {"elementType":"labels.text.fill","stylers":[{"color":"#858d9e"}]},
 {"elementType":"labels.text.stroke","stylers":[{"color":"#080e16"}]},
 {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#303a4a"}]},
 {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#182231"}]},
 {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#13312f"}]},
 {"featureType":"road","elementType":"geometry","stylers":[{"color":"#202a3a"}]},
 {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3a3550"}]},
 {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#a3a9b7"}]},
 {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#182231"}]},
 {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0b1a2e"}]}
]
''';

class LocationShareScreen extends StatefulWidget {
  const LocationShareScreen({super.key, this.allowLive = false});
  final bool allowLive;

  @override
  State<LocationShareScreen> createState() => _LocationShareScreenState();
}

class _LocationShareScreenState extends State<LocationShareScreen> {
  GoogleMapController? _map;
  Position? _fix;
  String? _problem;

  /// Where the centre pin is (null until the map moves off your fix).
  LatLng? _pin;
  Place? _pinPlace;
  LatLng? _centre;

  List<Place> _nearby = const [];
  bool _loadingNearby = false;
  List<Place>? _results; // search results replace the list
  bool _searching = false;
  final _query = TextEditingController();
  bool _fullscreen = false;
  Timer? _idle;
  bool _programmaticMove = false;

  @override
  void initState() {
    super.initState();
    unawaited(_locate());
  }

  @override
  void dispose() {
    _idle?.cancel();
    _query.dispose();
    _map?.dispose();
    super.dispose();
  }

  /// Gets a GPS fix, recentres and reloads nearby places.
  Future<void> _locate() async {
    setState(() => _problem = null);
    try {
      final p = await currentPosition();
      if (!mounted) return;
      setState(() {
        _fix = p;
        _pin = null;
        _pinPlace = null;
        _centre = LatLng(p.latitude, p.longitude);
      });
      _programmaticMove = true;
      await _map?.animateCamera(CameraUpdate.newLatLngZoom(_centre!, 17));
      unawaited(_loadNearby(p.latitude, p.longitude));
    } on LocationProblem catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } catch (_) {
      if (mounted) setState(() => _problem = "Couldn't find your location. Try again.");
    }
  }

  Future<void> _loadNearby(double lat, double lng) async {
    setState(() => _loadingNearby = true);
    try {
      final list = await nearbyPlaces(lat, lng);
      if (mounted) setState(() => _nearby = list);
    } catch (_) {
      // Nearby is a nice-to-have; the current-location row still works.
    } finally {
      if (mounted) setState(() => _loadingNearby = false);
    }
  }

  /// After the map settles: if it moved off the fix, the pin becomes the place.
  void _onIdle() {
    _idle?.cancel();
    final c = _centre;
    if (c == null) return;
    if (_programmaticMove) {
      _programmaticMove = false;
      return;
    }
    _idle = Timer(const Duration(milliseconds: 450), () async {
      final fix = _fix;
      final moved = fix == null || distanceMetres(fix.latitude, fix.longitude, c.latitude, c.longitude) > 25;
      setState(() {
        _pin = moved ? c : null;
        _pinPlace = null;
      });
      if (!moved) return;
      unawaited(_loadNearby(c.latitude, c.longitude));
      final place = await reverseGeocode(c.latitude, c.longitude);
      if (mounted && _pin == c) setState(() => _pinPlace = place);
    });
  }

  Future<void> _search(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    setState(() => _results = null);
    try {
      final c = _centre;
      final list = await searchPlaces(q, lat: c?.latitude, lng: c?.longitude);
      if (mounted) setState(() => _results = list);
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    }
  }

  void _send(Place p, {double? accuracy}) {
    LocationHistory.instance.add(p);
    Navigator.pop(context, PlacePick(p, accuracy: accuracy));
  }

  Future<void> _sendCurrent() async {
    final pin = _pin;
    if (pin != null) {
      _send(_pinPlace ?? Place(lat: pin.latitude, lng: pin.longitude, name: 'Pinned location'));
      return;
    }
    final fix = _fix;
    if (fix == null) return _locate();
    final place = await reverseGeocode(fix.latitude, fix.longitude);
    if (!mounted) return;
    _send(
      Place(
        lat: fix.latitude,
        lng: fix.longitude,
        name: 'My location',
        address: place == null ? '' : [place.name, place.address].where((s) => s.isNotEmpty).join(', '),
      ),
      accuracy: fix.accuracy,
    );
  }

  Future<void> _shareLive() async {
    final fix = _fix;
    if (fix == null) return _locate();
    final minutes = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: PhlioColors.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Share live location', style: PhlioTypography.title),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'They\'ll see where you are, updated as you move, while Phlio is open. You can stop any time.',
              style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted),
            ),
          ),
          for (final (m, label) in const [(15, '15 minutes'), (60, '1 hour'), (480, '8 hours')])
            ListTile(
              leading: const Icon(Icons.timer_outlined, color: PhlioColors.domainRooms),
              title: Text(label, style: PhlioTypography.body),
              onTap: () => Navigator.pop(sheet, m),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (minutes != null && mounted) Navigator.pop(context, LivePick(minutes, fix));
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: PhlioColors.background,
      appBar: AppBar(
        backgroundColor: PhlioColors.background,
        foregroundColor: PhlioColors.textPrimary,
        titleSpacing: 0,
        title: _searching
            ? TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                style: PhlioTypography.body,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Search places',
                  hintStyle: PhlioTypography.body.copyWith(color: PhlioColors.textMuted),
                ),
              )
            : Text('Send location', style: PhlioTypography.headline),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searching = !_searching;
              _results = null;
              _query.clear();
            }),
          ),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: _locate),
        ],
      ),
      body: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          height: _fullscreen ? h * .72 : h * .36,
          child: _mapView(),
        ),
        Expanded(child: _list()),
      ]),
    );
  }

  Widget _mapView() {
    final start = _centre ?? const LatLng(17.385, 78.4867);
    return Stack(children: [
      Positioned.fill(
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: start, zoom: _centre == null ? 11 : 17),
          style: phlioMapStyle,
          myLocationEnabled: _fix != null,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          onMapCreated: (c) {
            _map = c;
            final centre = _centre;
            if (centre != null) {
              _programmaticMove = true;
              unawaited(c.moveCamera(CameraUpdate.newLatLngZoom(centre, 17)));
            }
          },
          onCameraMove: (p) => _centre = p.target,
          onCameraIdle: _onIdle,
          markers: {
            for (final p in _results ?? const <Place>[])
              Marker(
                markerId: MarkerId('${p.lat},${p.lng}'),
                position: LatLng(p.lat, p.lng),
                infoWindow: InfoWindow(title: p.name, snippet: p.address, onTap: () => _send(p)),
              ),
          },
        ),
      ),
      // Centre pin (where "Send pinned location" points).
      IgnorePointer(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 36),
            child: Icon(Icons.location_on_rounded,
                size: 40, color: _pin == null ? PhlioColors.brandViolet.withValues(alpha: .55) : PhlioColors.brandPink),
          ),
        ),
      ),
      if (_problem != null)
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Material(
            color: PhlioColors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Icon(Icons.location_off_outlined, color: PhlioColors.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_problem!, style: PhlioTypography.caption)),
                TextButton(
                  onPressed: () async {
                    if (_problem!.contains('Settings')) {
                      await Geolocator.openAppSettings();
                    } else if (_problem!.contains('services')) {
                      await Geolocator.openLocationSettings();
                    } else {
                      await _locate();
                    }
                  },
                  child: const Text('Fix'),
                ),
              ]),
            ),
          ),
        ),
      Positioned(
        left: 12,
        top: _problem == null ? 12 : null,
        bottom: _problem == null ? null : 12,
        child: _roundButton(
          _fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          _fullscreen ? 'Smaller map' : 'Bigger map',
          () => setState(() => _fullscreen = !_fullscreen),
        ),
      ),
      Positioned(right: 12, bottom: 12, child: _roundButton(Icons.my_location_rounded, 'My location', _locate)),
    ]);
  }

  Widget _roundButton(IconData icon, String tip, VoidCallback onTap) => Material(
        color: PhlioColors.surfaceElevated,
        shape: const CircleBorder(),
        elevation: 3,
        child: IconButton(tooltip: tip, icon: Icon(icon, color: PhlioColors.textPrimary), onPressed: onTap),
      );

  Widget _list() {
    final results = _results;
    if (_searching && _query.text.isNotEmpty && results == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final fix = _fix;
    final from = _pin ?? (fix == null ? null : LatLng(fix.latitude, fix.longitude));
    String? away(Place p) => from == null ? null : formatDistance(distanceMetres(from.latitude, from.longitude, p.lat, p.lng));

    if (results != null) {
      return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        _header(results.isEmpty ? 'No places found' : 'Results'),
        for (final p in results) _placeTile(p, Icons.place_outlined, onTap: () => _send(p), trailing: away(p)),
      ]);
    }

    return AnimatedBuilder(
      animation: LocationHistory.instance,
      builder: (context, _) {
        final recent = LocationHistory.instance.items.take(5).toList();
        return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          if (widget.allowLive)
            _actionTile(
              icon: Icons.sensors_rounded,
              colour: PhlioColors.domainRooms,
              title: 'Share live location',
              onTap: _shareLive,
            ),
          _actionTile(
            icon: _pin == null ? Icons.my_location_rounded : Icons.push_pin_rounded,
            colour: PhlioColors.brandViolet,
            title: _pin == null ? 'Send your current location' : 'Send pinned location',
            subtitle: _pin != null
                ? (_pinPlace == null
                    ? 'Finding address…'
                    : [_pinPlace!.name, _pinPlace!.address].where((s) => s.isNotEmpty).join(' · '))
                : fix == null
                    ? (_problem ?? 'Finding you…')
                    : 'Accurate to ${fix.accuracy.round()} metres',
            onTap: _sendCurrent,
          ),
          if (recent.isNotEmpty) ...[
            _header('Recent', action: TextButton(onPressed: LocationHistory.instance.clear, child: const Text('Clear'))),
            for (final (p, at) in recent)
              _placeTile(p, Icons.history_rounded, onTap: () => _send(p), trailing: away(p), when: at),
          ],
          _header(_pin == null ? 'Nearby places' : 'Near the pin',
              action: _loadingNearby
                  ? const Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null),
          if (_nearby.isEmpty && !_loadingNearby)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(fix == null && _pin == null ? 'Nearby places show once we find you.' : 'Nothing named nearby.',
                  style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
            ),
          for (final p in _nearby) _placeTile(p, _iconFor(p.kind), onTap: () => _send(p), trailing: away(p)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text('Places © OpenStreetMap contributors',
                style: PhlioTypography.caption.copyWith(color: PhlioColors.textDisabled, fontSize: 11)),
          ),
        ]);
      },
    );
  }

  Widget _header(String text, {Widget? action}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 4, 4),
        child: Row(children: [
          Expanded(child: Text(text, style: PhlioTypography.label.copyWith(color: PhlioColors.textMuted))),
          if (action != null) action,
        ]),
      );

  Widget _actionTile({
    required IconData icon,
    required Color colour,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) =>
      ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: colour.withValues(alpha: .18),
          child: Icon(icon, color: colour),
        ),
        title: Text(title, style: PhlioTypography.bodyStrong.copyWith(color: colour)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
      );

  Widget _placeTile(Place p, IconData icon, {required VoidCallback onTap, String? trailing, DateTime? when}) {
    final sub = [
      if (p.address.isNotEmpty) p.address else if ((p.kind ?? '').isNotEmpty) p.kind!,
      if (when != null) _ago(when),
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: PhlioColors.surfaceElevated,
        child: Icon(icon, color: PhlioColors.textSecondary, size: 20),
      ),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: PhlioTypography.body),
      subtitle: sub.isEmpty
          ? null
          : Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
      trailing: trailing == null
          ? null
          : Text(trailing, style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  static IconData _iconFor(String? kind) => switch (kind ?? '') {
        'cafe' || 'coffee' => Icons.local_cafe_outlined,
        'restaurant' || 'fast food' || 'food court' => Icons.restaurant_outlined,
        'place of worship' || 'temple' => Icons.temple_hindu_outlined,
        'hospital' || 'clinic' || 'pharmacy' || 'doctors' => Icons.local_hospital_outlined,
        'school' || 'college' || 'university' => Icons.school_outlined,
        'bank' || 'atm' => Icons.account_balance_outlined,
        'fuel' => Icons.local_gas_station_outlined,
        'supermarket' || 'convenience' || 'mall' => Icons.local_grocery_store_outlined,
        'apartments' || 'residential' || 'house' => Icons.apartment_outlined,
        'park' || 'garden' || 'playground' => Icons.park_outlined,
        'hotel' || 'guest house' => Icons.hotel_outlined,
        _ => Icons.place_outlined,
      };
}
