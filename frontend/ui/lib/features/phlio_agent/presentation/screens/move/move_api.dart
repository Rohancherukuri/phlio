// Phlio Move — data, formatting and small shared widgets.
//
// Backend: backend/app/api/v1/activities.py.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:phlio/core/di/service_locator.dart';
import 'package:phlio/core/network/api_client.dart';
import 'package:phlio/design_system/colors.dart';
import 'package:phlio/design_system/typography.dart';

final moveDio = getIt<ApiClient>().dio;

/// Set when someone taps an activity post in Social: the Agent explore tab
/// then shows "View <name>'s activity" at the top.
final pendingActivityProvider = StateProvider<PendingActivity?>((ref) => null);

class PendingActivity {
  const PendingActivity({required this.id, required this.name, required this.title, this.imageUrl});
  final String id, name, title;
  final String? imageUrl;
}

const moveAccent = Color(0xFFFF8C5A);

class Sport {
  const Sport(this.id, this.label, this.group, this.icon, {this.distance = true, this.pace = false});
  final String id, label, group;
  final IconData icon;
  final bool distance, pace;
}

const sports = <Sport>[
  Sport('run', 'Run', 'Foot', Icons.directions_run_rounded, pace: true),
  Sport('trail_run', 'Trail Run', 'Foot', Icons.terrain_rounded, pace: true),
  Sport('walk', 'Walk', 'Foot', Icons.directions_walk_rounded, pace: true),
  Sport('hike', 'Hike', 'Foot', Icons.hiking_rounded, pace: true),
  Sport('wheelchair', 'Wheelchair', 'Foot', Icons.accessible_forward_rounded),
  Sport('ride', 'Ride', 'Cycle', Icons.directions_bike_rounded),
  Sport('mountain_bike', 'Mountain Bike Ride', 'Cycle', Icons.pedal_bike_rounded),
  Sport('gravel_ride', 'Gravel Ride', 'Cycle', Icons.landscape_rounded),
  Sport('ebike', 'E-Bike Ride', 'Cycle', Icons.electric_bike_rounded),
  Sport('handcycle', 'Handcycle', 'Cycle', Icons.accessible_rounded),
  Sport('swim', 'Swim', 'Water', Icons.pool_rounded, pace: true),
  Sport('kayak', 'Kayaking', 'Water', Icons.kayaking_rounded),
  Sport('rowing', 'Rowing', 'Water', Icons.rowing_rounded, pace: true),
  Sport('surf', 'Surfing', 'Water', Icons.surfing_rounded, distance: false),
  Sport('weight_training', 'Weight Training', 'Strength', Icons.fitness_center_rounded, distance: false),
  Sport('workout', 'Workout', 'Strength', Icons.sports_gymnastics_rounded, distance: false),
  Sport('hiit', 'HIIT', 'Strength', Icons.bolt_rounded, distance: false),
  Sport('yoga', 'Yoga', 'Strength', Icons.self_improvement_rounded, distance: false),
  Sport('ski', 'Ski', 'Winter', Icons.downhill_skiing_rounded),
  Sport('snowboard', 'Snowboard', 'Winter', Icons.snowboarding_rounded),
  Sport('football', 'Football', 'Sports', Icons.sports_soccer_rounded, distance: false),
  Sport('cricket', 'Cricket', 'Sports', Icons.sports_cricket_rounded, distance: false),
  Sport('badminton', 'Badminton', 'Sports', Icons.sports_tennis_rounded, distance: false),
  Sport('tennis', 'Tennis', 'Sports', Icons.sports_tennis_rounded, distance: false),
  Sport('basketball', 'Basketball', 'Sports', Icons.sports_basketball_rounded, distance: false),
  Sport('climbing', 'Rock Climbing', 'Sports', Icons.terrain_rounded, distance: false),
  Sport('dance', 'Dance', 'Sports', Icons.music_note_rounded, distance: false),
];

Sport sportOf(String? id) => sports.firstWhere((s) => s.id == id, orElse: () => sports.first);

String fmtDuration(num seconds) {
  final s = seconds.round();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}

String fmtShortDuration(num seconds) {
  final s = seconds.round();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

String fmtKm(num meters) => (meters / 1000).toStringAsFixed(2);

String fmtPace(num? secondsPerKm) {
  if (secondsPerKm == null || secondsPerKm <= 0 || secondsPerKm > 3600) return '-:--';
  final s = secondsPerKm.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String fmtWhen(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${months[d.month - 1]} ${d.day}, ${d.year} · $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// Metres between two [lat, lng] points.
double haversine(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = (lat2 - lat1) * math.pi / 180, dl = (lng2 - lng1) * math.pi / 180;
  final h = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(h)));
}

/// Draws a route (list of [lat, lng]) fitted into the box, on a quiet grid.
class RoutePainter extends CustomPainter {
  RoutePainter(this.route, {this.color = moveAccent, this.grid = true, this.stroke = 4, this.progress = 1});

  final List<List<double>> route;
  final Color color;
  final bool grid;
  final double stroke;

  /// 0…1: how much of the route is drawn (the "replay" animation).
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (grid) {
      final g = Paint()
        ..color = Colors.white.withValues(alpha: .045)
        ..strokeWidth = 1;
      for (double x = 0; x < size.width; x += 26) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), g);
      }
      for (double y = 0; y < size.height; y += 26) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
      }
    }
    if (route.length < 2) return;
    final lats = route.map((p) => p[0]);
    final lngs = route.map((p) => p[1]);
    final minLat = lats.reduce(math.min), maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min), maxLng = lngs.reduce(math.max);
    final k = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final spanX = math.max((maxLng - minLng) * k, 1e-6), spanY = math.max(maxLat - minLat, 1e-6);
    final pad = size.shortestSide * .14;
    final scale = math.min((size.width - 2 * pad) / spanX, (size.height - 2 * pad) / spanY);
    final ox = (size.width - spanX * scale) / 2, oy = (size.height - spanY * scale) / 2;
    Offset xy(List<double> p) => Offset(ox + (p[1] - minLng) * k * scale, size.height - (oy + (p[0] - minLat) * scale));
    final path = Path()..moveTo(xy(route.first).dx, xy(route.first).dy);
    for (final p in route.skip(1)) {
      final o = xy(p);
      path.lineTo(o.dx, o.dy);
    }
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final s = xy(route.first), e = xy(route.last);
    if (progress < 1) {
      // Faint full route underneath, the drawn part on top, and a head dot.
      canvas.drawPath(path, Paint()
        ..color = color.withValues(alpha: .14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
      final metrics = path.computeMetrics().toList();
      final total = metrics.fold<double>(0, (a, m) => a + m.length);
      var left = total * progress.clamp(0.0, 1.0);
      Offset? head;
      for (final m in metrics) {
        final take = math.min(left, m.length);
        if (take <= 0) break;
        canvas.drawPath(m.extractPath(0, take), line);
        head = m.getTangentForOffset(take)?.position;
        left -= take;
      }
      canvas.drawCircle(s, stroke + 2, Paint()..color = PhlioColors.success);
      if (head != null) {
        canvas.drawCircle(head, stroke + 4, Paint()..color = Colors.white);
        canvas.drawCircle(head, stroke + 1.5, Paint()..color = color);
      }
      return;
    }
    canvas.drawPath(path, line);
    canvas.drawCircle(s, stroke + 2, Paint()..color = PhlioColors.success);
    canvas.drawCircle(e, stroke + 3, Paint()..color = Colors.white);
    canvas.drawCircle(
        e,
        stroke + 3,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(RoutePainter old) => old.route != route || old.color != color || old.progress != progress;
}

/// A big number with a small label underneath.
class MoveStat extends StatelessWidget {
  const MoveStat({required this.value, required this.label, this.align = CrossAxisAlignment.start, this.big = false, super.key});

  final String value, label;
  final CrossAxisAlignment align;
  final bool big;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: align, mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: (big ? PhlioTypography.displayMedium : PhlioTypography.title)
                .copyWith(fontFeatures: const [FontFeature.tabularFigures()], color: PhlioColors.textPrimary)),
        const SizedBox(height: 2),
        Text(label, style: PhlioTypography.caption),
      ]);
}

/// The three headline stats for an activity row / card.
List<(String, String)> headlineStats(Map a) {
  final sport = sportOf(a['sport'] as String?);
  final moving = (a['moving_s'] as num?) ?? 0;
  final dist = (a['distance_m'] as num?) ?? 0;
  if (!sport.distance || dist < 50) {
    return [
      (fmtShortDuration(moving), 'Time'),
      ('${a['calories'] ?? 0}', 'Calories'),
      ('${a['kudos_count'] ?? 0}', 'Kudos'),
    ];
  }
  return [
    ('${fmtKm(dist)} km', 'Distance'),
    sport.pace ? ('${fmtPace(a['pace_s_per_km'] as num?)} /km', 'Pace') : ('${a['speed_kmh'] ?? 0} km/h', 'Speed'),
    (fmtShortDuration(moving), 'Time'),
  ];
}
