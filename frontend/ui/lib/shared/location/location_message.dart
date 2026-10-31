// Location sharing — how locations travel in messages and how they look.
//
// Locations are sent as ordinary message text so every client (and older
// app versions) can read them — a maps link always works:
//
//   📍 Ratnadeep Supermarket                 a place, sent once
//   Road No. 1, Hyderabad, 500085
//   https://maps.google.com/?q=17.44120,78.38070
//
//   📡 Live location                         live, until it ends
//   https://maps.google.com/?q=17.44120,78.38070
//   phlio-live:live_location:3f9c…
//
// [parseLocationMessage] turns that text back into a [SharedLocation];
// [LocationMessageCard] and [LiveLocationCard] draw it in a chat bubble.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import 'location_service.dart';
import 'location_share_screen.dart' show phlioMapStyle;

/// A location found in a message.
class SharedLocation {
  const SharedLocation({required this.lat, required this.lng, this.name = '', this.address = '', this.liveId});
  final double lat, lng;
  final String name, address;

  /// Set for live locations: the server session to follow.
  final String? liveId;
  bool get isLive => liveId != null;
}

String _mapsLink(double lat, double lng) =>
    'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

/// Message text for a place sent once.
String placeMessage(Place p) => [
      '📍 ${p.name}',
      if (p.address.isNotEmpty) p.address,
      _mapsLink(p.lat, p.lng),
    ].join('\n');

/// Message text for a live location session.
String liveMessage(String sessionId, double lat, double lng) =>
    '📡 Live location\n${_mapsLink(lat, lng)}\nphlio-live:$sessionId';

final _coords = RegExp(r'maps\.google\.com/\?q=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)');
final _live = RegExp(r'phlio-live:(\S+)');

/// The location in [text], or null if it isn't a location message.
SharedLocation? parseLocationMessage(String? text) {
  if (text == null) return null;
  final t = text.trim();
  if (!t.startsWith('📍') && !t.startsWith('📡')) return null;
  final m = _coords.firstMatch(t);
  if (m == null) return null; // older text-only shares stay as text
  final lines = t.split('\n');
  final name = lines.first.replaceFirst(RegExp(r'^(📍|📡)\s*'), '');
  final address = lines.length > 2 && !lines[1].contains('maps.google.com') ? lines[1] : '';
  return SharedLocation(
    lat: double.parse(m.group(1)!),
    lng: double.parse(m.group(2)!),
    name: name,
    address: address,
    liveId: _live.firstMatch(t)?.group(1),
  );
}

/// Opens the point in Google Maps (app if installed, else browser).
Future<void> openInMaps(double lat, double lng) => launchUrl(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
      mode: LaunchMode.externalApplication,
    );

/// Small, non-interactive map preview with a pin.
class _MapPreview extends StatelessWidget {
  const _MapPreview(this.lat, this.lng, {this.live = false});
  final double lat, lng;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final at = LatLng(lat, lng);
    return SizedBox(
      height: 140,
      child: IgnorePointer(
        child: GoogleMap(
          key: ValueKey('$lat,$lng'),
          liteModeEnabled: true, // Android: a static bitmap, cheap in lists
          initialCameraPosition: CameraPosition(target: at, zoom: 15.5),
          style: phlioMapStyle,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          myLocationButtonEnabled: false,
          markers: {
            Marker(
              markerId: const MarkerId('here'),
              position: at,
              icon: BitmapDescriptor.defaultMarkerWithHue(live ? BitmapDescriptor.hueCyan : BitmapDescriptor.hueViolet),
            ),
          },
        ),
      ),
    );
  }
}

/// Chat bubble content for a place sent once.
class LocationMessageCard extends StatelessWidget {
  const LocationMessageCard(this.location, {super.key, this.width = 240});
  final SharedLocation location;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Material(
            color: PhlioColors.surfaceElevated,
            child: InkWell(
              onTap: () => openInMaps(location.lat, location.lng),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                _MapPreview(location.lat, location.lng),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(location.name.isEmpty ? 'Location' : location.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: PhlioTypography.bodyStrong),
                    if (location.address.isNotEmpty)
                      Text(location.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.map_outlined, size: 14, color: PhlioColors.brandViolet),
                      const SizedBox(width: 4),
                      Text('Open in Maps',
                          style: PhlioTypography.caption.copyWith(color: PhlioColors.brandViolet, fontWeight: FontWeight.w700)),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
}

/// Chat bubble content for a live location: follows the session every 10 s.
class LiveLocationCard extends StatefulWidget {
  const LiveLocationCard(this.location, {super.key, required this.mine, this.width = 240});
  final SharedLocation location;

  /// Sent by me — shows "Stop sharing" while it's live.
  final bool mine;
  final double width;

  @override
  State<LiveLocationCard> createState() => _LiveLocationCardState();
}

class _LiveLocationCardState extends State<LiveLocationCard> {
  late double _lat = widget.location.lat, _lng = widget.location.lng;
  DateTime? _until, _updated;
  bool _active = true;
  bool _gone = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final j = (await getIt<ApiClient>().dio.get('/messaging/live/${widget.location.liveId}')).data as Map;
      if (!mounted) return;
      setState(() {
        _lat = (j['lat'] as num).toDouble();
        _lng = (j['lng'] as num).toDouble();
        _until = DateTime.tryParse('${j['until']}')?.toLocal();
        _updated = DateTime.tryParse('${j['updated_at']}')?.toLocal();
        _active = j['active'] == true;
      });
      if (!_active) _poll?.cancel();
    } catch (_) {
      // 404 (not shared with me / removed) → show as ended; offline → retry.
      if (mounted && _until == null) setState(() => _gone = true);
    }
  }

  Future<void> _stop() async {
    await LiveLocationSharer.instance.stop(widget.location.liveId!);
    await _refresh();
  }

  String _clock(DateTime t) =>
      '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';

  @override
  Widget build(BuildContext context) {
    final live = _active && !_gone;
    final status = live
        ? (_until == null ? 'Live' : 'Live until ${_clock(_until!)}')
        : 'Live location ended';
    final seen = _updated == null ? null : DateTime.now().difference(_updated!);
    return SizedBox(
      width: widget.width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: PhlioColors.surfaceElevated,
          child: InkWell(
            onTap: () => openInMaps(_lat, _lng),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Opacity(opacity: live ? 1 : .45, child: _MapPreview(_lat, _lng, live: live)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Row(children: [
                  Icon(Icons.sensors_rounded, size: 18, color: live ? PhlioColors.domainRooms : PhlioColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(status,
                          style: PhlioTypography.bodyStrong
                              .copyWith(color: live ? PhlioColors.domainRooms : PhlioColors.textSecondary)),
                      if (live && seen != null)
                        Text(seen.inMinutes < 1 ? 'Updated just now' : 'Updated ${seen.inMinutes} min ago',
                            style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
                    ]),
                  ),
                ]),
              ),
              if (live && widget.mine)
                TextButton.icon(
                  onPressed: _stop,
                  style: TextButton.styleFrom(foregroundColor: PhlioColors.danger),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('Stop sharing'),
                )
              else
                const SizedBox(height: 6),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Picks the right card for a location message.
Widget locationCard(SharedLocation l, {required bool mine, double width = 240}) =>
    l.isLive ? LiveLocationCard(l, mine: mine, width: width) : LocationMessageCard(l, width: width);
