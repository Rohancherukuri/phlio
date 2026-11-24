// Phlio Move — record an activity: live map with your route, time / pace /
// distance, a sport picker, pause / resume / finish, a "Nice work!" moment,
// then the save screen (title, description with @mentions, tag people,
// privacy, share to Phlio Social).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phlio/features/social/presentation/controllers/feed_controller.dart';

import 'package:phlio/design_system/colors.dart';
import 'package:phlio/design_system/typography.dart';
import 'package:phlio/shared/content/mentions.dart';
import 'package:phlio/shared/location/location_share_screen.dart' show phlioMapStyle;

import 'move_activity_screen.dart';
import 'move_api.dart';

// -- Sport picker ---------------------------------------------------------------

Future<Sport?> pickSport(BuildContext context, {required String current, List<String> top = const []}) =>
    showModalBottomSheet<Sport>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SportSheet(current: current, top: top),
    );

class _SportSheet extends StatefulWidget {
  const _SportSheet({required this.current, required this.top});
  final String current;
  final List<String> top;

  @override
  State<_SportSheet> createState() => _SportSheetState();
}

class _SportSheetState extends State<_SportSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final match = sports.where((s) => s.label.toLowerCase().contains(_q.toLowerCase())).toList();
    final groups = <String, List<Sport>>{};
    for (final s in match) {
      groups.putIfAbsent(s.group, () => []).add(s);
    }
    final top = [for (final id in (widget.top.isEmpty ? const ['run', 'walk', 'hike'] : widget.top)) sportOf(id)];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      maxChildSize: .95,
      builder: (_, scroll) => Column(children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: PhlioColors.textMuted.withValues(alpha: .5), borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
          child: Row(children: [
            Expanded(child: Text('Choose a sport', style: PhlioTypography.title)),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search'),
          ),
        ),
        Expanded(
          child: ListView(controller: scroll, padding: const EdgeInsets.only(bottom: 24), children: [
            if (_q.isEmpty) ...[
              Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: Text('Your top sports', style: PhlioTypography.bodyStrong)),
              SizedBox(
                height: 104,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                  for (final s in top) _TopSport(sport: s, selected: s.id == widget.current, onTap: () => Navigator.pop(context, s)),
                ]),
              ),
              const Divider(height: 24),
            ],
            for (final e in groups.entries) ...[
              Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 4), child: Text('${e.key} sports', style: PhlioTypography.bodyStrong)),
              for (final s in e.value)
                ListTile(
                  leading: Icon(s.icon, color: s.id == widget.current ? moveAccent : PhlioColors.textSecondary),
                  title: Text(s.label,
                      style: PhlioTypography.body.copyWith(color: s.id == widget.current ? moveAccent : PhlioColors.textPrimary)),
                  trailing: s.id == widget.current ? const Icon(Icons.check_rounded, color: moveAccent) : null,
                  onTap: () => Navigator.pop(context, s),
                ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _TopSport extends StatelessWidget {
  const _TopSport({required this.sport, required this.selected, required this.onTap});
  final Sport sport;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? moveAccent.withValues(alpha: .18) : PhlioColors.surfaceInput,
                ),
                child: Icon(sport.icon, size: 30, color: selected ? moveAccent : PhlioColors.textPrimary),
              ),
              if (selected)
                const Positioned(
                  right: -2,
                  top: -2,
                  child: CircleAvatar(radius: 11, backgroundColor: moveAccent, child: Icon(Icons.check_rounded, size: 14, color: Colors.white)),
                ),
            ]),
            const SizedBox(height: 6),
            Text(sport.label, style: PhlioTypography.caption.copyWith(color: selected ? moveAccent : PhlioColors.textPrimary)),
          ]),
        ),
      );
}

// -- Recorder -------------------------------------------------------------------

enum _Phase { ready, recording, paused }

class MoveRecordScreen extends StatefulWidget {
  const MoveRecordScreen({this.sport = 'run', this.topSports = const [], super.key});
  final String sport;
  final List<String> topSports;

  @override
  State<MoveRecordScreen> createState() => _MoveRecordScreenState();
}

class _MoveRecordScreenState extends State<MoveRecordScreen> {
  late Sport _sport = sportOf(widget.sport);
  _Phase _phase = _Phase.ready;
  StreamSubscription<Position>? _gps;
  Position? _pos;
  String? _gpsProblem;
  GoogleMapController? _map;
  final List<List<double>> _points = []; // [lat, lng, seconds]
  double _distance = 0, _climb = 0;
  double? _lastAlt;
  DateTime? _startedAt, _resumedAt;
  Duration _banked = Duration.zero;
  Timer? _tick;
  bool _hideEndpoints = true;
  bool _follow = true;

  bool get _gpsReady => _pos != null && _pos!.accuracy <= 30;
  Duration get _elapsed => _banked + (_resumedAt == null ? Duration.zero : DateTime.now().difference(_resumedAt!));

  @override
  void initState() {
    super.initState();
    _startGps();
  }

  @override
  void dispose() {
    _gps?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _gpsProblem = 'Turn on location to map your route.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _gpsProblem = 'Location is off for Phlio. You can still record time.');
        return;
      }
      _gps = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 4),
      ).listen(_onPosition, onError: (_) {
        if (mounted) setState(() => _gpsProblem = 'Lost GPS. Recording time only.');
      });
    } catch (_) {
      if (mounted) setState(() => _gpsProblem = 'GPS isn’t available on this device.');
    }
  }

  void _onPosition(Position p) {
    if (!mounted) return;
    setState(() {
      _pos = p;
      _gpsProblem = null;
    });
    if (_follow) _map?.animateCamera(CameraUpdate.newLatLng(LatLng(p.latitude, p.longitude)));
    if (_phase != _Phase.recording || p.accuracy > 30) return;
    final t = _elapsed.inMilliseconds / 1000;
    if (_points.isNotEmpty) {
      final last = _points.last;
      final step = haversine(last[0], last[1], p.latitude, p.longitude);
      // Ignore GPS jitter and impossible jumps (> 60 m/s).
      if (step < 3 || step / math.max(t - last[2], 1) > 60) return;
      _distance += step;
    }
    if (_lastAlt != null && p.altitude - _lastAlt! > 2) _climb += p.altitude - _lastAlt!;
    if (_lastAlt == null || (p.altitude - _lastAlt!).abs() > 2) _lastAlt = p.altitude;
    _points.add([p.latitude, p.longitude, t]);
  }

  void _start() {
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _Phase.recording;
      _startedAt ??= DateTime.now();
      _resumedAt = DateTime.now();
    });
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    final p = _pos;
    if (p != null && _points.isEmpty && p.accuracy <= 30) _points.add([p.latitude, p.longitude, 0]);
  }

  void _pause() {
    HapticFeedback.selectionClick();
    setState(() {
      _banked = _elapsed;
      _resumedAt = null;
      _phase = _Phase.paused;
    });
  }

  Future<void> _finish() async {
    _pause();
    final elapsed = _elapsed.inSeconds;
    if (elapsed < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record a little longer to save this.')));
      return;
    }
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => NiceWorkScreen(icon: _sport.icon),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
    if (!mounted) return;
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => MoveSaveScreen(
        draft: MoveDraft(
          sport: _sport,
          startedAt: _startedAt ?? DateTime.now(),
          elapsed: elapsed,
          distance: _distance,
          climb: _climb,
          route: List.of(_points),
          hideEndpoints: _hideEndpoints,
        ),
      ),
    ));
    if (id != null && mounted) {
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => MoveActivityScreen(id: id)));
    }
  }

  Future<bool> _confirmDiscard() async {
    if (_phase == _Phase.ready) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this activity?'),
        content: const Text('Your time and route so far won’t be saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep recording')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return ok == true;
  }

  String get _status => switch (_phase) {
        _Phase.recording => _sport.distance && !_gpsReady ? 'Recording · weak GPS' : 'Recording',
        _Phase.paused => 'Paused',
        _Phase.ready => _gpsProblem != null
            ? 'No GPS'
            : _gpsReady
                ? 'GPS ready'
                : 'Acquiring GPS',
      };

  @override
  Widget build(BuildContext context) {
    final here = _pos == null ? const LatLng(12.9716, 77.5946) : LatLng(_pos!.latitude, _pos!.longitude);
    final paceSecs = _distance >= 50 ? _elapsed.inSeconds / (_distance / 1000) : null;
    final ready = _gpsReady || !_sport.distance || _gpsProblem != null;
    return PopScope(
      canPop: _phase == _Phase.ready,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: PhlioColors.background,
        body: Stack(children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: here, zoom: 16),
              style: phlioMapStyle,
              myLocationEnabled: _pos != null,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              padding: const EdgeInsets.only(bottom: 300),
              onMapCreated: (c) => _map = c,
              polylines: {
                if (_points.length > 1)
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: [for (final p in _points) LatLng(p[0], p[1])],
                    color: moveAccent,
                    width: 6,
                    jointType: JointType.round,
                    startCap: Cap.roundCap,
                    endCap: Cap.roundCap,
                  ),
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                _RoundButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  onTap: () async {
                    if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
                  },
                ),
                const Spacer(),
                _RoundButton(
                  icon: _follow ? Icons.my_location_rounded : Icons.location_searching_rounded,
                  onTap: () {
                    setState(() => _follow = true);
                    if (_pos != null) _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(_pos!.latitude, _pos!.longitude), 16.5));
                  },
                ),
              ]),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Stats panel.
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: PhlioColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withValues(alpha: .07)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: switch (_phase) {
                      _Phase.recording => moveAccent.withValues(alpha: .18),
                      _Phase.paused => PhlioColors.warning.withValues(alpha: .16),
                      _Phase.ready => _gpsReady ? PhlioColors.success.withValues(alpha: .14) : PhlioColors.brandBlue.withValues(alpha: .14),
                    },
                    child: Text(_status, textAlign: TextAlign.center, style: PhlioTypography.bodyStrong),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: Row(children: [
                      Expanded(child: MoveStat(value: fmtDuration(_elapsed.inSeconds), label: 'Time', align: CrossAxisAlignment.center, big: true)),
                      if (_sport.distance) ...[
                        Expanded(
                          child: MoveStat(
                              value: _sport.pace
                                  ? fmtPace(paceSecs)
                                  : (_elapsed.inSeconds > 0 ? (_distance / 1000 / (_elapsed.inSeconds / 3600)).toStringAsFixed(1) : '0.0'),
                              label: _sport.pace ? 'Avg pace (/km)' : 'Avg speed (km/h)',
                              align: CrossAxisAlignment.center),
                        ),
                        Expanded(child: MoveStat(value: fmtKm(_distance), label: 'Distance (km)', align: CrossAxisAlignment.center)),
                      ],
                    ]),
                  ),
                  if (_gpsProblem != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(_gpsProblem!, style: PhlioTypography.caption, textAlign: TextAlign.center),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              // Controls.
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + MediaQuery.paddingOf(context).bottom),
                decoration: const BoxDecoration(
                  color: PhlioColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: switch (_phase) {
                  _Phase.ready => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      _SideButton(
                        icon: _sport.icon,
                        label: _sport.label,
                        accent: true,
                        onTap: () async {
                          final s = await pickSport(context, current: _sport.id, top: widget.topSports);
                          if (s != null) setState(() => _sport = s);
                        },
                      ),
                      _BigButton(icon: Icons.play_arrow_rounded, label: 'Start', onTap: ready ? _start : null),
                      _SideButton(
                        icon: _hideEndpoints ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        label: _hideEndpoints ? 'Start & end hidden' : 'Full route',
                        onTap: () => setState(() => _hideEndpoints = !_hideEndpoints),
                      ),
                    ]),
                  _Phase.recording => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _BigButton(icon: Icons.pause_rounded, label: 'Pause', onTap: _pause, dark: true),
                    ]),
                  _Phase.paused => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      _BigButton(icon: Icons.play_arrow_rounded, label: 'Resume', onTap: _start, dark: true),
                      _BigButton(icon: Icons.flag_rounded, label: 'Finish', onTap: _finish),
                    ]),
                },
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: PhlioColors.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(12), child: Icon(icon, size: 26, color: PhlioColors.textPrimary)),
        ),
      );
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.icon, required this.label, required this.onTap, this.dark = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? .45 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? PhlioColors.surfaceElevated : moveAccent,
              ),
              child: Icon(icon, size: 40, color: dark ? PhlioColors.textPrimary : Colors.white),
            ),
            const SizedBox(height: 6),
            Text(label, style: PhlioTypography.bodyStrong.copyWith(color: dark ? PhlioColors.textPrimary : moveAccent)),
          ]),
        ),
      );
}

class _SideButton extends StatelessWidget {
  const _SideButton({required this.icon, required this.label, required this.onTap, this.accent = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 92,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent ? moveAccent.withValues(alpha: .16) : PhlioColors.surfaceInput,
              ),
              child: Icon(icon, color: accent ? moveAccent : PhlioColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(label, maxLines: 2, textAlign: TextAlign.center, style: PhlioTypography.caption.copyWith(color: PhlioColors.textPrimary)),
          ]),
        ),
      );
}

// -- "Nice work!" ---------------------------------------------------------------

class NiceWorkScreen extends StatefulWidget {
  const NiceWorkScreen({required this.icon, super.key});
  final IconData icon;

  @override
  State<NiceWorkScreen> createState() => _NiceWorkScreenState();
}

class _NiceWorkScreenState extends State<NiceWorkScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final t = Curves.easeOutCubic.transform(_c.value);
              return Stack(children: [
                Positioned.fill(child: CustomPaint(painter: _RibbonPainter(t))),
                Center(
                  child: Opacity(
                    opacity: Curves.easeOut.transform(((_c.value - .3) / .7).clamp(0.0, 1.0)),
                    child: Transform.scale(
                      scale: .9 + .1 * t,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(widget.icon, size: 64, color: Colors.white),
                        const SizedBox(height: 14),
                        Text('Nice work!', style: PhlioTypography.displayLarge.copyWith(color: Colors.white)),
                      ]),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      );
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size s) {
    Paint band(Color a, Color b) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * .17
      ..strokeCap = StrokeCap.butt
      ..shader = LinearGradient(colors: [a, b]).createShader(Offset.zero & s);
    final top = Path()
      ..moveTo(-s.width * .1, s.height * .36)
      ..cubicTo(s.width * .35, s.height * .12, s.width * .7, s.height * .22, s.width * 1.05, -s.height * .02);
    final bottom = Path()
      ..moveTo(-s.width * .1, s.height * .7)
      ..cubicTo(s.width * .3, s.height * .9, s.width * .75, s.height * .86, s.width * 1.1, s.height * .66);
    for (final (path, paint) in [
      (top, band(const Color(0xFFFF6A2B), const Color(0xFFFFB58F))),
      (bottom, band(const Color(0xFFFF8C2B), const Color(0xFFE795D7))),
    ]) {
      for (final m in path.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * t), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.t != t;
}

// -- Save -----------------------------------------------------------------------

class MoveDraft {
  MoveDraft({
    required this.sport,
    required this.startedAt,
    required this.elapsed,
    this.distance = 0,
    this.climb = 0,
    this.route = const [],
    this.hideEndpoints = true,
    this.manual = false,
  });

  Sport sport;
  DateTime startedAt;
  int elapsed;
  double distance, climb;
  final List<List<double>> route;
  bool hideEndpoints;
  final bool manual;
}

class MoveSaveScreen extends StatefulWidget {
  const MoveSaveScreen({required this.draft, super.key});
  final MoveDraft draft;

  @override
  State<MoveSaveScreen> createState() => _MoveSaveScreenState();
}

class _MoveSaveScreenState extends State<MoveSaveScreen> {
  late final MoveDraft d = widget.draft;
  final _title = TextEditingController();
  final _desc = MentionTextEditingController();
  final _minutes = TextEditingController();
  final _km = TextEditingController();
  final _tagSearch = TextEditingController();
  List _people = [];
  List _tagResults = [];
  final List<Map> _tagged = [];
  bool _everyone = true, _post = true, _saving = false;
  int _mentionReq = 0, _tagReq = 0;

  @override
  void initState() {
    super.initState();
    _title.text = _defaultTitle();
    if (d.manual) {
      _minutes.text = '30';
    }
  }

  String _defaultTitle() {
    final h = d.startedAt.hour;
    final part = h >= 5 && h < 12
        ? 'Morning'
        : h < 17
            ? 'Afternoon'
            : h < 21
                ? 'Evening'
                : 'Night';
    return '$part ${d.sport.label}';
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _minutes.dispose();
    _km.dispose();
    _tagSearch.dispose();
    super.dispose();
  }

  Future<void> _mentions() async {
    final token = ++_mentionReq;
    final q = mentionQuery(_desc);
    if (q == null) {
      if (_people.isNotEmpty) setState(() => _people = []);
      return;
    }
    final found = await searchMentionPeople(q);
    if (mounted && token == _mentionReq) setState(() => _people = found);
  }

  Future<void> _searchTag(String q) async {
    final token = ++_tagReq;
    if (q.trim().isEmpty) {
      setState(() => _tagResults = []);
      return;
    }
    final found = await searchMentionPeople(q.trim());
    if (mounted && token == _tagReq) setState(() => _tagResults = found);
  }

  Future<void> _save() async {
    if (d.manual) {
      d.elapsed = ((double.tryParse(_minutes.text) ?? 0) * 60).round();
      d.distance = (double.tryParse(_km.text.replaceAll(',', '.')) ?? 0) * 1000;
      if (d.elapsed <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add how long it took.')));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final res = await moveDio.post('/activities', data: {
        'sport': d.sport.id,
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'started_at': d.startedAt.toUtc().toIso8601String(),
        'elapsed_s': d.elapsed,
        'moving_s': d.elapsed,
        if (d.manual || d.route.length < 2) 'distance_m': d.distance,
        'elevation_m': d.climb,
        'route': d.route,
        'visibility': _everyone ? 'everyone' : 'only_me',
        'hide_endpoints': d.hideEndpoints,
        'tagged': [for (final p in _tagged) p['username']],
        'post': _everyone && _post,
      });
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (_everyone && _post) {
        // The new post shows at the top of the Social Posts tab right away.
        try {
          unawaited(ProviderScope.containerOf(context, listen: false).read(feedControllerProvider.notifier).refresh());
        } catch (_) {}
      }
      Navigator.of(context).pop('${(res.data as Map)['id']}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t save your activity. Try again.')));
    }
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(text, style: PhlioTypography.bodyStrong),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        leadingWidth: 88,
        title: Text(d.manual ? 'Add activity' : 'Save activity'),
        centerTitle: true,
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (!d.manual)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: .06))),
            child: Row(children: [
              if (d.route.length > 1)
                Container(
                  width: 84,
                  height: 84,
                  margin: const EdgeInsets.only(right: 14),
                  decoration: BoxDecoration(color: PhlioColors.background, borderRadius: BorderRadius.circular(14)),
                  child: CustomPaint(painter: RoutePainter([for (final p in d.route) [p[0], p[1]]], stroke: 3)),
                ),
              Expanded(
                child: Wrap(spacing: 18, runSpacing: 10, children: [
                  MoveStat(value: fmtDuration(d.elapsed), label: 'Time'),
                  if (d.sport.distance) MoveStat(value: '${fmtKm(d.distance)} km', label: 'Distance'),
                  if (d.climb > 0) MoveStat(value: '${d.climb.round()} m', label: 'Elevation'),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        TextField(controller: _title, maxLength: 120, decoration: const InputDecoration(hintText: 'Title', counterText: '')),
        const SizedBox(height: 10),
        TextField(
          controller: _desc,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          onChanged: (_) => _mentions(),
          decoration: const InputDecoration(hintText: 'How did it go? @ to mention someone', counterText: ''),
        ),
        MentionSuggestions(
          people: _people,
          onPick: (p) {
            applyMention(_desc, '${p['username']}');
            _mentionReq++;
            setState(() => _people = []);
          },
        ),
        _section('Sport'),
        ListTile(
          tileColor: PhlioColors.surfaceInput,
          leading: Icon(d.sport.icon, color: moveAccent),
          title: Text(d.sport.label),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            final s = await pickSport(context, current: d.sport.id);
            if (s != null) {
              final wasDefault = _title.text == _defaultTitle();
              setState(() => d.sport = s);
              if (wasDefault) _title.text = _defaultTitle();
            }
          },
        ),
        if (d.manual) ...[
          _section('Details'),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _minutes,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Minutes'),
              ),
            ),
            if (d.sport.distance) ...[
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _km,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Distance (km)'),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_rounded),
            label: Text(fmtWhen(d.startedAt.toIso8601String())),
            onPressed: () async {
              final day = await showDatePicker(context: context, initialDate: d.startedAt, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (day == null || !context.mounted) return;
              final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(d.startedAt));
              setState(() => d.startedAt = DateTime(day.year, day.month, day.day, time?.hour ?? 8, time?.minute ?? 0));
            },
          ),
        ],
        _section('Tag people who joined you'),
        if (_tagged.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in _tagged)
              InputChip(
                label: Text('@${p['username']}'),
                onDeleted: () => setState(() => _tagged.remove(p)),
              ),
          ]),
        const SizedBox(height: 8),
        TextField(
          controller: _tagSearch,
          onChanged: _searchTag,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.person_add_alt_1_rounded), hintText: 'Search people'),
        ),
        for (final p in _tagResults.take(5))
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: Text('${p['display_name'] ?? p['username']}'),
            subtitle: Text('@${p['username']}'),
            onTap: () => setState(() {
              if (!_tagged.any((t) => t['username'] == p['username'])) _tagged.add(p as Map);
              _tagResults = [];
              _tagSearch.clear();
            }),
          ),
        _section('Privacy'),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, icon: Icon(Icons.public_rounded), label: Text('Everyone')),
            ButtonSegment(value: false, icon: Icon(Icons.lock_rounded), label: Text('Only you')),
          ],
          selected: {_everyone},
          onSelectionChanged: (v) => setState(() => _everyone = v.first),
        ),
        if (d.route.length > 1)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: d.hideEndpoints,
            onChanged: (v) => setState(() => d.hideEndpoints = v),
            title: const Text('Hide start and end'),
            subtitle: const Text('Others don’t see the first and last 200 m of your route.'),
          ),
        if (_everyone)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _post,
            onChanged: (v) => setState(() => _post = v),
            title: const Text('Share to Phlio Social'),
            subtitle: const Text('Followers see it in their feed and can react and comment.'),
          ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: moveAccent, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(54)),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_everyone && _post ? 'Save & share' : 'Save activity'),
        ),
      ]),
    );
  }
}
