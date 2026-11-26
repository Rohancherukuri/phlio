// Sharing a place with friends inside Phlio.
//
//  * [showPlaceShare]  the usual share sheet (people, groups, rooms, plus
//                      Copy link / WhatsApp / More outside Phlio). Inside
//                      Phlio the place is sent as `phlio://place?...`.
//  * [parsePlaceShare] reads that link back out of a message.
//  * [PlaceShareCard]  the card in DMs, groups and Rooms: photo (or a small
//                      map), name, address; tap it to open the place on the
//                      map with its page (posts, Directions, Save).
//
// Backend: POST /explore/places/share (backend/app/api/v1/explore_places.py).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/config/app_config.dart';
import '../../core/network/media_cache.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../content/content_surface.dart' show showEndpointShare;
import 'location_share_screen.dart' show phlioMapStyle;
import 'place_map.dart';

final _placeLink = RegExp(r'phlio://place\?(\S+)');

String _mapsUrl(double lat, double lng) => 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

/// Opens the share sheet for [place] (`name`, `lat`, `lng`, optional
/// `address` and `cover`, the shape the place map uses).
Future<void> showPlaceShare(BuildContext context, Map<String, dynamic> place) {
  final lat = (place['lat'] as num).toDouble(), lng = (place['lng'] as num).toDouble();
  // On the map a place's `cover` is its newest post (a map); a shared card
  // keeps just the picture's url.
  final raw = place['cover'] ?? place['cover_url'];
  final cover = raw is Map ? (raw['media_kind'] == 'video' ? null : raw['image_url']) : raw;
  final query = Uri(queryParameters: {
    'name': '${place['name'] ?? 'Place'}',
    'lat': '$lat',
    'lng': '$lng',
    if ('${place['address'] ?? ''}'.isNotEmpty) 'address': '${place['address']}',
    if (cover is String && cover.isNotEmpty) 'cover': cover,
  }).query;
  return showEndpointShare(
    context,
    endpoint: '/explore/places/share?$query',
    link: _mapsUrl(lat, lng),
    quote: '📍 ${place['name'] ?? 'Place'}',
  );
}

/// The place in a `phlio://place?...` message, or null. The picture is
/// under `cover_url` (the map's own `cover` is a post, loaded from the API).
Map<String, dynamic>? parsePlaceShare(String text) {
  final m = _placeLink.firstMatch(text);
  if (m == null) return null;
  final q = Uri.splitQueryString(m.group(1)!);
  final lat = double.tryParse(q['lat'] ?? ''), lng = double.tryParse(q['lng'] ?? '');
  if (lat == null || lng == null) return null;
  return {
    'name': q['name'] ?? 'Place',
    'lat': lat,
    'lng': lng,
    if ((q['address'] ?? '').isNotEmpty) 'address': q['address'],
    if ((q['cover'] ?? '').isNotEmpty) 'cover_url': q['cover'],
  };
}

/// Opens [place] full screen on the map, with its page in the sheet.
void openSharedPlace(BuildContext context, Map<String, dynamic> place) {
  HapticFeedback.selectionClick();
  Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    builder: (_) => PlaceMapScreen(places: [place], title: '${place['name']}'),
  ));
}

class PlaceShareCard extends StatelessWidget {
  const PlaceShareCard({required this.place, this.mine = false, this.width = 250, super.key});
  final Map<String, dynamic> place;
  final bool mine;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cover = place['cover_url'] as String?;
    final address = '${place['address'] ?? ''}';
    return SizedBox(
      width: width,
      child: Material(
        color: PhlioColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openSharedPlace(context, place),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: 128,
              child: Stack(fit: StackFit.expand, children: [
                if (cover != null)
                  phlioNetworkImage(AppConfig.mediaUrl(cover),
                      fit: BoxFit.cover, errorBuilder: (_, __, ___) => _LiteMap(place))
                else
                  _LiteMap(place),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: PhlioColors.background.withValues(alpha: .78), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.place_rounded, size: 14, color: PhlioColors.brandViolet),
                      const SizedBox(width: 4),
                      Text('Place', style: PhlioTypography.caption.copyWith(color: PhlioColors.textPrimary, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${place['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: PhlioTypography.bodyStrong),
                if (address.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(address,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
                  ),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.map_outlined, size: 15, color: PhlioColors.brandViolet),
                  const SizedBox(width: 5),
                  Text('View on map',
                      style: PhlioTypography.caption.copyWith(color: PhlioColors.brandViolet, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LiteMap extends StatelessWidget {
  const _LiteMap(this.place);
  final Map<String, dynamic> place;

  @override
  Widget build(BuildContext context) {
    final at = placeLatLng(place);
    return IgnorePointer(
      child: GoogleMap(
        key: ValueKey('${at.latitude},${at.longitude}'),
        liteModeEnabled: true, // Android: a static bitmap, cheap in chat lists
        initialCameraPosition: CameraPosition(target: at, zoom: 15),
        style: phlioMapStyle,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        myLocationButtonEnabled: false,
        markers: {
          Marker(markerId: const MarkerId('place'), position: at, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet)),
        },
      ),
    );
  }
}
