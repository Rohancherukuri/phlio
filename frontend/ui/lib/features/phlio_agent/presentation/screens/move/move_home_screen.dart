// Phlio Move — the hub opened from the Agent explore tab: this week at a
// glance, your streak, Record / Add manual, and your activities. First open
// shows the privacy intro.

import 'package:flutter/material.dart';

import 'package:phlio/app/config/app_config.dart';
import 'package:phlio/core/network/media_cache.dart';
import 'package:phlio/design_system/colors.dart';
import 'package:phlio/design_system/typography.dart';

import 'move_activity_screen.dart';
import 'move_api.dart';
import 'move_record_screen.dart';

class MoveHomeScreen extends StatefulWidget {
  const MoveHomeScreen({super.key});

  @override
  State<MoveHomeScreen> createState() => _MoveHomeScreenState();
}

class _MoveHomeScreenState extends State<MoveHomeScreen> {
  Map<String, dynamic>? _summary;
  List<Map> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([moveDio.get('/activities/summary'), moveDio.get('/activities')]);
      if (!mounted) return;
      setState(() {
        _summary = Map<String, dynamic>.from(results[0].data as Map);
        _items = ((results[1].data as Map)['items'] as List).cast<Map>();
        _loading = false;
        _error = null;
      });
      if (_summary!['intro_seen'] != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _intro());
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Phlio Move isn’t available yet — restart the backend.';
        });
      }
    }
  }

  Future<void> _intro() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const _PrivacyIntro()));
    try {
      await moveDio.post('/activities/intro-seen');
    } catch (_) {}
  }

  List<String> get _top => ((_summary?['top_sports'] as List?) ?? const []).cast<String>();

  Future<void> _record() async {
    final sport = _top.isEmpty ? 'run' : _top.first;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MoveRecordScreen(sport: sport, topSports: _top)));
    _load();
  }

  Future<void> _manual() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => MoveSaveScreen(
        draft: MoveDraft(sport: sportOf(_top.isEmpty ? 'run' : _top.first), startedAt: DateTime.now(), elapsed: 0, manual: true),
      ),
    ));
    if (id != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MoveActivityScreen(id: id)));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final week = (_summary?['week'] as Map?) ?? const {};
    final days = ((week['days'] as List?) ?? List.filled(7, false)).cast<bool>();
    return Scaffold(
      appBar: AppBar(title: const Text('Phlio Move')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: moveAccent,
        foregroundColor: Colors.white,
        onPressed: _record,
        icon: const Icon(Icons.radio_button_checked_rounded),
        label: const Text('Record'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
                    // This week.
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: PhlioColors.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white.withValues(alpha: .06)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text('This week', style: PhlioTypography.title),
                          const Spacer(),
                          const Icon(Icons.local_fire_department_rounded, size: 18, color: moveAccent),
                          const SizedBox(width: 4),
                          Text('${_summary?['streak_days'] ?? 0} day streak', style: PhlioTypography.label.copyWith(color: moveAccent)),
                        ]),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(child: MoveStat(value: '${fmtKm((week['distance_m'] as num?) ?? 0)} km', label: 'Distance')),
                          Expanded(child: MoveStat(value: fmtShortDuration((week['moving_s'] as num?) ?? 0), label: 'Time')),
                          Expanded(child: MoveStat(value: '${week['count'] ?? 0}', label: 'Activities')),
                        ]),
                        const SizedBox(height: 16),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          for (var i = 0; i < 7; i++)
                            Column(children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i < days.length && days[i] ? moveAccent : PhlioColors.surfaceInput,
                                ),
                                child: i < days.length && days[i] ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                              ),
                              const SizedBox(height: 4),
                              Text(const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i], style: PhlioTypography.caption),
                            ]),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: _ActionTile(icon: Icons.radio_button_checked_rounded, title: 'Record', subtitle: 'GPS route, time, pace', onTap: _record),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionTile(icon: Icons.edit_note_rounded, title: 'Add manually', subtitle: 'Gym, yoga, sports', onTap: _manual),
                      ),
                    ]),
                    const SizedBox(height: 22),
                    Text('Your activities', style: PhlioTypography.title),
                    const SizedBox(height: 10),
                    if (_items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(children: [
                          const Icon(Icons.directions_run_rounded, size: 48, color: PhlioColors.textMuted),
                          const SizedBox(height: 8),
                          Text('No activities yet', style: PhlioTypography.bodyStrong),
                          Text('Record your first run, ride or workout.', style: PhlioTypography.caption),
                        ]),
                      ),
                    for (final a in _items)
                      ActivityTile(
                        a: a,
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MoveActivityScreen(id: '${a['id']}')));
                          _load();
                        },
                      ),
                  ]),
                ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: PhlioColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: moveAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: PhlioTypography.bodyStrong),
                  Text(subtitle, style: PhlioTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
        ),
      );
}

/// One activity in a list: route thumbnail, title, sport and headline stats.
class ActivityTile extends StatelessWidget {
  const ActivityTile({required this.a, required this.onTap, super.key});
  final Map a;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sport = sportOf(a['sport'] as String?);
    final route = [
      for (final p in (a['route'] as List? ?? const [])) [((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()]
    ];
    final image = a['image_url'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: PhlioColors.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(children: [
            Container(
              width: 104,
              height: 104,
              color: const Color(0xFF0C131E),
              child: route.length > 1
                  ? CustomPaint(painter: RoutePainter(route, stroke: 3))
                  : image != null
                      ? phlioNetworkImage(AppConfig.mediaUrl(image),
                          fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(sport.icon, color: moveAccent, size: 34))
                      : Icon(sport.icon, color: moveAccent, size: 34),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${a['title']}', style: PhlioTypography.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (a['visibility'] == 'only_me') const Icon(Icons.lock_rounded, size: 14, color: PhlioColors.textMuted),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(sport.icon, size: 14, color: PhlioColors.textMuted),
                    const SizedBox(width: 4),
                    Flexible(child: Text(fmtWhen('${a['started_at']}'), style: PhlioTypography.caption, overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 8),
                  Text(headlineStats(a).map((s) => s.$1).join('  ·  '),
                      style: PhlioTypography.label.copyWith(color: PhlioColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PrivacyIntro extends StatelessWidget {
  const _PrivacyIntro();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
            child: Column(children: [
              const Spacer(),
              const Icon(Icons.lock_outline_rounded, size: 44, color: PhlioColors.textPrimary),
              const SizedBox(height: 18),
              Text('Privacy you control', textAlign: TextAlign.center, style: PhlioTypography.displayMedium),
              const SizedBox(height: 12),
              Text(
                'Phlio hides the start and end of your routes by default, so nobody can work out where you live or work.',
                textAlign: TextAlign.center,
                style: PhlioTypography.body.copyWith(color: PhlioColors.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 28),
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Container(
                  decoration: BoxDecoration(color: const Color(0xFF0C131E), borderRadius: BorderRadius.circular(22)),
                  clipBehavior: Clip.antiAlias,
                  child: const CustomPaint(painter: _IntroPainter()),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Make any activity private, choose who you tag, and change it later from the activity’s menu.',
                textAlign: TextAlign.center,
                style: PhlioTypography.caption,
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: moveAccent, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(54)),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Continue'),
              ),
            ]),
          ),
        ),
      );
}

/// A route whose last stretch (near "home") is greyed out and hidden.
class _IntroPainter extends CustomPainter {
  const _IntroPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .05)
      ..strokeWidth = 1;
    for (double x = 0; x < s.width; x += 26) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), grid);
    }
    for (double y = 0; y < s.height; y += 26) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    Paint line(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final shown = Path()
      ..moveTo(0, s.height * .25)
      ..lineTo(s.width * .3, s.height * .25)
      ..lineTo(s.width * .32, s.height * .45)
      ..lineTo(s.width * .4, s.height * .62)
      ..lineTo(s.width * .58, s.height * .62);
    canvas.drawPath(shown, line(moveAccent));
    canvas.drawLine(Offset(s.width * .58, s.height * .62), Offset(s.width * .82, s.height * .62), line(Colors.white24));
    canvas.drawCircle(Offset(s.width * .58, s.height * .62), 7, Paint()..color = moveAccent);
    canvas.drawCircle(Offset(s.width * .82, s.height * .62), 6, Paint()..color = Colors.white38);
    final icon = TextPainter(
      text: TextSpan(text: String.fromCharCode(Icons.home_rounded.codePoint), style: TextStyle(fontFamily: Icons.home_rounded.fontFamily, package: Icons.home_rounded.fontPackage, fontSize: 22, color: PhlioColors.brandBlue)),
      textDirection: TextDirection.ltr,
    )..layout();
    icon.paint(canvas, Offset(s.width * .82 - 11, s.height * .7));
    final eye = TextPainter(
      text: TextSpan(text: String.fromCharCode(Icons.visibility_off_rounded.codePoint), style: TextStyle(fontFamily: Icons.visibility_off_rounded.fontFamily, package: Icons.visibility_off_rounded.fontPackage, fontSize: 22, color: Colors.white70)),
      textDirection: TextDirection.ltr,
    )..layout();
    eye.paint(canvas, Offset(s.width * .7 - 11, s.height * .45));
  }

  @override
  bool shouldRepaint(_IntroPainter old) => false;
}
