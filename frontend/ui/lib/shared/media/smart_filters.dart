// Snapchat-style smart filters for Moments and snaps.
//
// A [FilterSpec] is the colour look / effect the app already draws live
// (phlio_look) plus up to six info overlays captured when you take the
// photo: time, date, weather, place, speed, battery, day and greeting. Each
// overlay has a style, colour, position, size and rotation, so you can move
// and restyle it; the whole spec is stored with the moment or snap
// (`filter_spec`) and drawn live, so it stays editable after posting.
//
//   * [SmartFilterLayer] draws a spec's overlays over any media.
//   * [openSmartFilterEditor] (smart_filter_editor.dart) edits one.
//   * [captureOverlayData] reads the clock, GPS, weather and battery.
//
// Backend: backend/app/api/v1/smart_filters.py.

import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../location/device_places.dart';
import '../location/google_places.dart';
import '../location/location_service.dart';
import '../location/places_api.dart' show areaName;

/// Overlay kinds and their styles (same lists as the server).
const smartOverlayStyles = <String, List<String>>{
  'time': ['bold', 'lcd', 'pill'],
  'date': ['stamp', 'card', 'script'],
  'weather': ['big', 'pill', 'retro'],
  'place': ['banner', 'pill', 'outline'],
  'speed': ['gauge', 'pill'],
  'battery': ['icon', 'pill'],
  'day': ['script', 'sticker'],
  'greeting': ['gradient', 'pill'],
};

const smartOverlayInfo = <String, (String, IconData)>{
  'time': ('Time', Icons.schedule_rounded),
  'date': ('Date', Icons.calendar_today_rounded),
  'weather': ('Weather', Icons.wb_sunny_rounded),
  'place': ('Place', Icons.location_on_rounded),
  'speed': ('Speed', Icons.speed_rounded),
  'battery': ('Battery', Icons.battery_charging_full_rounded),
  'day': ('Day', Icons.today_rounded),
  'greeting': ('Greeting', Icons.waving_hand_rounded),
};

const smartOverlayColors = [
  Color(0xFFFFFFFF),
  Color(0xFF111318),
  Color(0xFFFFD166),
  Color(0xFFFF8A3D),
  Color(0xFFFF4D8D),
  Color(0xFF8D78FF),
  Color(0xFF4CC9F0),
  Color(0xFF39D98A),
];

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
Color _color(Object? hex) {
  if (hex is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) {
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }
  return Colors.white;
}

class SmartOverlay {
  SmartOverlay({
    required this.type,
    required this.style,
    this.color = Colors.white,
    this.x = .5,
    this.y = .5,
    this.scale = 1,
    this.rotation = 0,
    Map<String, Object?>? data,
  }) : data = data ?? {};

  final String type;
  String style;
  Color color;
  double x, y, scale, rotation;
  Map<String, Object?> data;

  SmartOverlay copy() => SmartOverlay(
      type: type, style: style, color: color, x: x, y: y, scale: scale, rotation: rotation, data: {...data});

  Map<String, dynamic> toJson() => {
        'type': type,
        'style': style,
        'color': _hex(color),
        'x': double.parse(x.clamp(0, 1).toStringAsFixed(4)),
        'y': double.parse(y.clamp(0, 1).toStringAsFixed(4)),
        'scale': double.parse(scale.clamp(.3, 4).toStringAsFixed(3)),
        'rotation': double.parse(rotation.clamp(-3.2, 3.2).toStringAsFixed(3)),
        'data': data,
      };

  static SmartOverlay? fromJson(Object? j) {
    if (j is! Map || !smartOverlayStyles.containsKey(j['type'])) return null;
    final type = '${j['type']}';
    final styles = smartOverlayStyles[type]!;
    double d(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    return SmartOverlay(
      type: type,
      style: styles.contains(j['style']) ? '${j['style']}' : styles.first,
      color: _color(j['color']),
      x: d('x', .5),
      y: d('y', .5),
      scale: d('scale', 1),
      rotation: d('rotation', 0),
      data: j['data'] is Map ? Map<String, Object?>.from(j['data'] as Map) : {},
    );
  }
}

class FilterSpec {
  FilterSpec({this.look = 'normal', this.effect, this.strength = 1, List<SmartOverlay>? overlays})
      : overlays = overlays ?? [];

  String look;
  String? effect;
  double strength;
  final List<SmartOverlay> overlays;

  bool get isEmpty => overlays.isEmpty && look == 'normal' && (effect == null || effect == 'none');

  FilterSpec copy() =>
      FilterSpec(look: look, effect: effect, strength: strength, overlays: [for (final o in overlays) o.copy()]);

  Map<String, dynamic> toJson() => {
        'look': look,
        if (effect != null && effect != 'none') 'effect': effect,
        'strength': strength,
        'overlays': [for (final o in overlays) o.toJson()],
      };

  static FilterSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    return FilterSpec(
      look: '${j['look'] ?? 'normal'}',
      effect: j['effect'] as String?,
      strength: (j['strength'] as num?)?.toDouble() ?? 1,
      overlays: (j['overlays'] as List? ?? const []).map(SmartOverlay.fromJson).whereType<SmartOverlay>().toList(),
    );
  }
}

// ----------------------------------------------------------------- capture

/// Reads what an overlay shows, at capture time. Throws a message string
/// when it can't (no location permission, offline…).
Future<Map<String, Object?>> captureOverlayData(String type) async {
  final now = DateTime.now().toIso8601String();
  switch (type) {
    case 'time':
    case 'date':
    case 'day':
    case 'greeting':
      return {'at': now};
    case 'battery':
      final battery = Battery();
      final level = await battery.batteryLevel;
      final state = await battery.batteryState;
      return {'level': level, 'charging': state == BatteryState.charging || state == BatteryState.full};
    case 'speed':
      final pos = await currentPosition();
      final kmh = (pos.speed.isFinite && pos.speed > 0 ? pos.speed * 3.6 : 0).round();
      return {'kmh': kmh};
    case 'place':
      final pos = await currentPosition();
      return {'name': await _placeName(pos.latitude, pos.longitude)};
    case 'weather':
      final pos = await currentPosition();
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
      final res = await dio.get<dynamic>('https://api.open-meteo.com/v1/forecast', queryParameters: {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'current': 'temperature_2m,weather_code,is_day',
      });
      final cur = (res.data as Map)['current'] as Map;
      final code = (cur['weather_code'] as num).toInt();
      final day = (cur['is_day'] as num?) != 0;
      return {
        'temp': (cur['temperature_2m'] as num).round(),
        'unit': 'C',
        'icon': weatherIcon(code, day: day),
        'city': await _placeName(pos.latitude, pos.longitude),
      };
  }
  return {};
}

Future<String> _placeName(double lat, double lng) async {
  final google = await googleNearby(lat, lng);
  if (google != null && google.areas.isNotEmpty) return google.areas.first.name;
  final device = await deviceAreas(lat, lng);
  if (device != null && device.isNotEmpty) return device.first.name;
  return (await areaName(lat, lng))?.name ?? 'Somewhere';
}

/// WMO weather code → emoji.
String weatherIcon(int code, {bool day = true}) {
  if (code == 0) return day ? '☀️' : '🌙';
  if (code <= 2) return day ? '🌤️' : '☁️';
  if (code == 3) return '☁️';
  if (code <= 48) return '🌫️';
  if (code <= 67 || (code >= 80 && code <= 82)) return '🌧️';
  if (code <= 77 || code == 85 || code == 86) return '❄️';
  return '⛈️';
}

// ----------------------------------------------------------------- drawing

/// Draws [spec]'s overlays over the area it's given (a 9:16 moment or a
/// square snap). Sizes scale with the width so they look the same on every
/// screen. [editable] widgets get gestures from the editor instead.
class SmartFilterLayer extends StatelessWidget {
  const SmartFilterLayer({required this.spec, super.key});
  final FilterSpec? spec;

  static FilterSpec? parse(Object? json) => FilterSpec.fromJson(json);

  @override
  Widget build(BuildContext context) {
    final s = spec;
    if (s == null || s.overlays.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        return Stack(clipBehavior: Clip.none, children: [
          for (final o in s.overlays) positionedOverlay(o, Size(box.maxWidth, box.maxHeight)),
        ]);
      }),
    );
  }
}

/// [overlay] centred at its (x, y), scaled to the canvas.
Widget positionedOverlay(SmartOverlay overlay, Size canvas, {Widget Function(Widget)? wrap}) {
  final unit = canvas.width / 360;
  final view = Transform.rotate(
    angle: overlay.rotation,
    child: Transform.scale(scale: overlay.scale * unit, child: SmartOverlayView(overlay: overlay)),
  );
  return Positioned(
    left: overlay.x * canvas.width,
    top: overlay.y * canvas.height,
    child: FractionalTranslation(
      translation: const Offset(-.5, -.5),
      child: wrap == null ? view : wrap(view),
    ),
  );
}

const _shadow = [Shadow(color: Color(0x88000000), blurRadius: 10, offset: Offset(0, 2))];

String _two(int n) => n.toString().padLeft(2, '0');
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// One overlay at scale 1 (360-wide design units).
class SmartOverlayView extends StatelessWidget {
  const SmartOverlayView({required this.overlay, super.key});
  final SmartOverlay overlay;

  DateTime get _at => DateTime.tryParse('${overlay.data['at'] ?? ''}') ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final c = overlay.color;
    final ink = c.computeLuminance() > .5 ? const Color(0xFF111318) : Colors.white;
    final d = overlay.data;
    Widget pill(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(30), boxShadow: const [
            BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 3)),
          ]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: ink),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        );
    final t = _at;
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    switch ('${overlay.type}:${overlay.style}') {
      case 'time:bold':
        return Text('$h12:${_two(t.minute)}',
            style: TextStyle(color: c, fontSize: 64, fontWeight: FontWeight.w900, letterSpacing: -2, shadows: _shadow));
      case 'time:lcd':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xCC0B1410),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withValues(alpha: .6), width: 2),
          ),
          child: Text('${_two(t.hour)}:${_two(t.minute)}',
              style: TextStyle(
                  color: c,
                  fontSize: 40,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                  shadows: [Shadow(color: c, blurRadius: 14)])),
        );
      case 'time:pill':
        return pill(Icons.schedule_rounded, '$h12:${_two(t.minute)} $ampm');
      case 'date:stamp':
        // Film-camera date stamp.
        return Text("'${_two(t.year % 100)} ${_two(t.month)} ${_two(t.day)}",
            style: TextStyle(
                color: overlay.color == Colors.white ? const Color(0xFFFF9A3D) : c,
                fontSize: 30,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                shadows: const [Shadow(color: Color(0xFFFF6A00), blurRadius: 8)]));
      case 'date:card':
        return Container(
          width: 92,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: const [
            BoxShadow(color: Color(0x55000000), blurRadius: 12, offset: Offset(0, 4)),
          ]),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              color: c == Colors.white ? const Color(0xFFFF4D67) : c,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(_months[t.month - 1].substring(0, 3).toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ),
            Text('${t.day}', style: const TextStyle(color: Color(0xFF111318), fontSize: 44, fontWeight: FontWeight.w900, height: 1.1)),
            Text(_days[t.weekday - 1].substring(0, 3),
                style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
          ]),
        );
      case 'date:script':
        return Text('${t.day} ${_months[t.month - 1]}',
            style: TextStyle(color: c, fontSize: 36, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, shadows: _shadow));
      case 'weather:big':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${d['icon'] ?? '☀️'}', style: const TextStyle(fontSize: 48)),
          const SizedBox(width: 6),
          Text('${d['temp'] ?? '--'}°', style: TextStyle(color: c, fontSize: 64, fontWeight: FontWeight.w900, shadows: _shadow)),
        ]);
      case 'weather:pill':
        return pill(Icons.thermostat_rounded, '${d['icon'] ?? ''} ${d['temp'] ?? '--'}°${d['unit'] ?? 'C'}');
      case 'weather:retro':
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 16, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF6EFE6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF111318), width: 3),
            boxShadow: const [BoxShadow(color: Color(0xFF111318), offset: Offset(5, 5))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${d['icon'] ?? '☀️'}  ${d['temp'] ?? '--'}°${d['unit'] ?? 'C'}',
                style: const TextStyle(color: Color(0xFF111318), fontSize: 26, fontWeight: FontWeight.w900)),
            Text('${d['city'] ?? ''}'.toUpperCase(),
                style: TextStyle(
                    color: c == Colors.white ? const Color(0xFFFF4D67) : c, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)),
          ]),
        );
      case 'place:banner':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_on_rounded, color: c, size: 30, shadows: _shadow),
          Text('${d['name'] ?? 'Somewhere'}'.toUpperCase(),
              style: TextStyle(color: c, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 1.5, shadows: _shadow)),
        ]);
      case 'place:pill':
        return pill(Icons.location_on_rounded, '${d['name'] ?? 'Somewhere'}');
      case 'place:outline':
        return Stack(children: [
          Text('${d['name'] ?? 'Somewhere'}',
              style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..color = c)),
        ]);
      case 'speed:gauge':
        return SizedBox(
          width: 130,
          height: 92,
          child: CustomPaint(
            painter: _GaugePainter(((d['kmh'] as num?) ?? 0).toDouble(), c),
            child: Align(
              alignment: const Alignment(0, .7),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${d['kmh'] ?? 0}',
                    style: TextStyle(color: c, fontSize: 34, fontWeight: FontWeight.w900, height: 1, shadows: _shadow)),
                Text('KM/H', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2)),
              ]),
            ),
          ),
        );
      case 'speed:pill':
        return pill(Icons.speed_rounded, '${d['kmh'] ?? 0} km/h');
      case 'battery:icon':
        final level = ((d['level'] as num?) ?? 100).toInt().clamp(0, 100);
        return Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 74, height: 36, child: CustomPaint(painter: _BatteryPainter(level / 100, c, d['charging'] == true))),
          const SizedBox(width: 8),
          Text('$level%', style: TextStyle(color: c, fontSize: 30, fontWeight: FontWeight.w900, shadows: _shadow)),
        ]);
      case 'battery:pill':
        return pill(d['charging'] == true ? Icons.battery_charging_full_rounded : Icons.battery_full_rounded,
            '${d['level'] ?? 100}%');
      case 'day:script':
        return Text(_days[t.weekday - 1],
            style: TextStyle(
                color: c, fontSize: 52, fontStyle: FontStyle.italic, fontWeight: FontWeight.w800, letterSpacing: -1, shadows: _shadow));
      case 'day:sticker':
        return Transform.rotate(
          angle: -.08,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Text('happy ${_days[t.weekday - 1].toLowerCase()}!',
                style: TextStyle(color: ink, fontSize: 24, fontWeight: FontWeight.w900)),
          ),
        );
      case 'greeting:gradient':
      case 'greeting:pill':
        final (text, emoji) = switch (t.hour) {
          < 5 => ('Good night', '🌙'),
          < 12 => ('Good morning', '☀️'),
          < 17 => ('Good afternoon', '🌤️'),
          < 21 => ('Good evening', '🌆'),
          _ => ('Good night', '🌙'),
        };
        if (overlay.style == 'pill') return pill(Icons.waving_hand_rounded, '$text $emoji');
        return Row(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
            shaderCallback: (r) => LinearGradient(colors: [c, const Color(0xFFFF8A3D), const Color(0xFFFF4D8D)]).createShader(r),
            child: Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: -1)),
          ),
          Text(' $emoji', style: const TextStyle(fontSize: 38)),
        ]);
    }
    return const SizedBox.shrink();
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.kmh, this.color);
  final double kmh;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 6);
    final r = size.width / 2 - 8;
    const start = math.pi, sweep = math.pi;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: .25);
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), start, sweep, false, track);
    final f = (kmh / 160).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      start,
      sweep * f,
      false,
      track
        ..color = color
        ..shader = const SweepGradient(colors: [Color(0xFF39D98A), Color(0xFFFFD166), Color(0xFFFF4D67)], startAngle: math.pi, endAngle: 2 * math.pi)
            .createShader(Rect.fromCircle(center: center, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.kmh != kmh || old.color != color;
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.level, this.color, this.charging);
  final double level;
  final Color color;
  final bool charging;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromLTRBR(0, 0, size.width - 6, size.height, const Radius.circular(8));
    canvas.drawRRect(body, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = color);
    canvas.drawRRect(RRect.fromLTRBR(size.width - 5, size.height * .3, size.width, size.height * .7, const Radius.circular(2)),
        Paint()..color = color);
    final fill = level < .2 ? const Color(0xFFFF4D67) : (charging ? const Color(0xFF39D98A) : color);
    canvas.drawRRect(
        RRect.fromLTRBR(6, 6, 6 + (size.width - 18) * level, size.height - 6, const Radius.circular(4)), Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_BatteryPainter old) => old.level != level || old.color != color || old.charging != charging;
}
