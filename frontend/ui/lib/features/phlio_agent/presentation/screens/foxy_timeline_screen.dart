// Foxy Timeline: a visual day planner — a timeline of your day and a
// calendar — that Foxy fills from your Phlio life (Book bookings, Spaces you
// host, a daily routine) or from a sentence ("gym at 7, study 2 hours"), and
// that you customise: colours, icons, times, repeats, subtasks, energy.
//
//   [FoxyTimelineScreen]   header (month › calendar), week strip, energy +
//                          inbox, Day / Week views, bottom bar + gradient FAB
//   _TaskEditor            add / edit sheet with a coloured header
//   _ColorPicker           palette + hue / brightness sliders + #hex
//   _FoxyPlanSheet         "Let Foxy plan my day"
//   _MonthSheet            month calendar with colour dots per day
//
// Backend: backend/app/api/v1/timeline.py.

import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/foxy_puppet.dart';

final _dio = getIt<ApiClient>().dio;

// -- Model --------------------------------------------------------------------

/// Phlio's palette for tasks (same hues as the platform colours).
const _palette = <Color>[
  Color(0xFFFFB58F), // peach (Agent)
  Color(0xFF8D78FF), // violet (Social)
  Color(0xFFE795D7), // pink (Book)
  Color(0xFF68D7CD), // teal (Rooms)
  Color(0xFF72A7FF), // blue (Pay)
  Color(0xFFF6B93B), // gold
  Color(0xFFF5636B), // red (Stream)
  Color(0xFF7BD88F), // green
  Color(0xFFA78BFA), // lavender
];

const _icons = <String, IconData>{
  'spark': Icons.auto_awesome_rounded,
  'sun': Icons.wb_sunny_rounded,
  'moon': Icons.nightlight_round,
  'alarm': Icons.alarm_rounded,
  'fitness': Icons.fitness_center_rounded,
  'book': Icons.menu_book_rounded,
  'work': Icons.work_rounded,
  'food': Icons.restaurant_rounded,
  'coffee': Icons.local_cafe_rounded,
  'movie': Icons.movie_rounded,
  'music': Icons.music_note_rounded,
  'shop': Icons.shopping_bag_rounded,
  'people': Icons.groups_rounded,
  'heart': Icons.favorite_rounded,
  'home': Icons.home_rounded,
  'ticket': Icons.confirmation_number_rounded,
  'mic': Icons.mic_rounded,
  'travel': Icons.flight_takeoff_rounded,
  'pay': Icons.account_balance_wallet_rounded,
  'code': Icons.code_rounded,
  'game': Icons.sports_esports_rounded,
  'pet': Icons.pets_rounded,
  'call': Icons.call_rounded,
  'meds': Icons.medication_rounded,
};

IconData _icon(String key) => _icons[key] ?? Icons.auto_awesome_rounded;

Color _hex(String? s) {
  if (s == null || s.length != 7 || !s.startsWith('#')) return _palette.first;
  final v = int.tryParse(s.substring(1), radix: 16);
  return v == null ? _palette.first : Color(0xFF000000 | v);
}

String _toHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _wk = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _clock(int minutes) {
  final h = (minutes ~/ 60) % 24, m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

String _span(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

class TTask {
  TTask({
    this.id,
    required this.title,
    this.date,
    this.start,
    this.duration = 30,
    this.icon = 'spark',
    this.color = const Color(0xFFFFB58F),
    this.notes = '',
    List<Map<String, dynamic>>? subtasks,
    this.energy = 2,
    this.repeat = 'none',
    this.source = 'manual',
    this.done = false,
    this.occurrence,
  }) : subtasks = subtasks ?? [];

  String? id;
  String title;
  String? date; // null → inbox
  int? start; // minutes after midnight; null → anytime
  int duration;
  String icon;
  Color color;
  String notes;
  List<Map<String, dynamic>> subtasks;
  int energy;
  String repeat;
  String source;
  bool done;
  String? occurrence;

  int? get end => start == null ? null : start! + duration;

  TTask copy() => TTask(
        id: id,
        title: title,
        date: date,
        start: start,
        duration: duration,
        icon: icon,
        color: color,
        notes: notes,
        subtasks: [for (final s in subtasks) Map<String, dynamic>.of(s)],
        energy: energy,
        repeat: repeat,
        source: source,
        done: done,
        occurrence: occurrence,
      );

  factory TTask.fromJson(Map j) {
    int? mins(dynamic s) {
      if (s is! String || !s.contains(':')) return null;
      final p = s.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    return TTask(
      id: '${j['id']}',
      title: '${j['title'] ?? ''}',
      date: j['date'] as String?,
      start: mins(j['start']),
      duration: (j['duration_min'] as num?)?.toInt() ?? 30,
      icon: '${j['icon'] ?? 'spark'}',
      color: _hex(j['color'] as String?),
      notes: '${j['notes'] ?? ''}',
      subtasks: [
        for (final s in (j['subtasks'] as List? ?? const []))
          {'title': '${(s as Map)['title']}', 'done': s['done'] == true}
      ],
      energy: (j['energy'] as num?)?.toInt() ?? 2,
      repeat: '${j['repeat'] ?? 'none'}',
      source: '${j['source'] ?? 'manual'}',
      done: j['done'] == true,
      occurrence: j['occurrence'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'date': date,
        'start': start == null
            ? null
            : '${(start! ~/ 60).toString().padLeft(2, '0')}:${(start! % 60).toString().padLeft(2, '0')}',
        'duration_min': duration,
        'icon': icon,
        'color': _toHex(color),
        'notes': notes,
        'subtasks': subtasks,
        'energy': energy,
        'repeat': repeat,
      };
}

String _err(Object e) {
  if (e is DioException) {
    final d = e.response?.data;
    final code = e.response?.statusCode;
    // FastAPI's own 404 ("Not Found") means the server doesn't have the
    // /timeline routes yet — it's running code from before this feature.
    if (code == 404 && (d is! Map || d['detail'] == 'Not Found')) {
      return 'Foxy Timeline needs the latest backend — restart the server, then reopen the timeline.';
    }
    if (d is Map && d['detail'] is String) return d['detail'] as String;
    if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
      return 'Can’t reach Phlio right now. Check your connection.';
    }
  }
  return 'Something went wrong. Try again.';
}

// -- Screen -------------------------------------------------------------------

class FoxyTimelineScreen extends StatefulWidget {
  const FoxyTimelineScreen({super.key});

  @override
  State<FoxyTimelineScreen> createState() => _FoxyTimelineScreenState();
}

class _FoxyTimelineScreenState extends State<FoxyTimelineScreen> {
  DateTime _selected = _day(DateTime.now());
  final Map<String, List<TTask>> _days = {};
  List<TTask> _inbox = [];
  bool _loading = true;
  bool _week = false;
  int _tab = 1; // 0 inbox, 1 timeline
  bool _showGaps = true;

  DateTime get _weekStart => _selected.subtract(Duration(days: _selected.weekday - 1));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final start = _weekStart.subtract(const Duration(days: 7));
      final res = await _dio.get('/timeline', queryParameters: {'start': _ymd(start), 'days': 21});
      final inbox = await _dio.get('/timeline/inbox');
      if (!mounted) return;
      final fresh = <String, List<TTask>>{};
      for (final d in ((res.data as Map)['days'] as List)) {
        fresh['${(d as Map)['date']}'] = [for (final t in d['tasks'] as List) TTask.fromJson(t as Map)];
      }
      setState(() {
        _days
          ..clear()
          ..addAll(fresh);
        _inbox = [for (final t in ((inbox.data as Map)['items'] as List)) TTask.fromJson(t as Map)];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(_err(e));
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  void _pick(DateTime d) {
    final before = _weekStart;
    setState(() => _selected = _day(d));
    if (_weekStart != before) _load();
  }

  Future<void> _toggle(TTask t) async {
    HapticFeedback.selectionClick();
    setState(() => t.done = !t.done);
    try {
      await _dio.post('/timeline/tasks/${t.id}/toggle', data: {'date': t.occurrence ?? t.date});
    } catch (e) {
      if (!mounted) return;
      setState(() => t.done = !t.done);
      _toast(_err(e));
    }
  }

  Future<void> _edit({TTask? task, int? start, bool inbox = false}) async {
    final draft = task ??
        TTask(
          title: '',
          date: inbox ? null : _ymd(_selected),
          start: inbox ? null : (start ?? _nextFreeStart()),
          color: _palette[math.Random().nextInt(_palette.length)],
        );
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaskEditor(task: draft),
    );
    if (changed == true) _load();
  }

  int _nextFreeStart() {
    final now = DateTime.now();
    final tasks = _days[_ymd(_selected)] ?? const <TTask>[];
    var m = _selected == _day(now) ? ((now.hour * 60 + now.minute) ~/ 15 + 1) * 15 : 9 * 60;
    for (final t in tasks) {
      if (t.start != null && t.end! > m && t.start! <= m) m = t.end!;
    }
    return math.min(m, 23 * 60);
  }

  Future<void> _foxy() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FoxyPlanSheet(date: _selected),
    );
    if (added == true) _load();
  }

  Future<void> _month() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MonthSheet(selected: _selected),
    );
    if (picked != null) _pick(picked);
  }

  void _settings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PhlioColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _Grabber(),
              const SizedBox(height: 12),
              Text('Timeline settings', style: PhlioTypography.title),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _showGaps,
                activeColor: PhlioColors.brandOrange,
                title: Text('Show free time between tasks', style: PhlioTypography.bodyStrong),
                subtitle: Text('“Plan or chill for 2h before…” with an Add task button', style: PhlioTypography.caption),
                onChanged: (v) {
                  set(() {});
                  setState(() => _showGaps = v);
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _week,
                activeColor: PhlioColors.brandOrange,
                title: Text('Open in week view', style: PhlioTypography.bodyStrong),
                onChanged: (v) {
                  set(() {});
                  setState(() => _week = v);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.refresh_rounded),
                title: Text('Refresh', style: PhlioTypography.bodyStrong),
                onTap: () {
                  Navigator.pop(ctx);
                  _load();
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final key = _ymd(_selected);
    final tasks = _days[key] ?? const <TTask>[];
    return Scaffold(
      backgroundColor: PhlioColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _Header(
            date: _selected,
            week: _week,
            onBack: () => Navigator.of(context).maybePop(),
            onMonth: _month,
            onToday: () => _pick(DateTime.now()),
            onView: (w) => setState(() => _week = w),
          ),
          _WeekStrip(
            start: _weekStart,
            selected: _selected,
            days: _days,
            onPick: _pick,
            onSwipe: (dir) => _pick(_selected.add(Duration(days: 7 * dir))),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: PhlioColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: PhlioColors.brandOrange))
                      : _tab == 0
                          ? _InboxView(
                              key: const ValueKey('inbox'),
                              items: _inbox,
                              onOpen: (t) => _edit(task: t),
                              onAdd: () => _edit(inbox: true),
                            )
                          : _week
                              ? _WeekView(
                                  key: ValueKey('week${_ymd(_weekStart)}'),
                                  start: _weekStart,
                                  days: _days,
                                  selected: _selected,
                                  onOpen: (t) => _edit(task: t),
                                  onPick: (d) => setState(() {
                                    _selected = d;
                                    _week = false;
                                  }),
                                )
                              : _DayView(
                                  key: ValueKey('day$key'),
                                  date: _selected,
                                  tasks: tasks,
                                  inboxCount: _inbox.length,
                                  showGaps: _showGaps,
                                  onToggle: _toggle,
                                  onOpen: (t) => _edit(task: t),
                                  onAddAt: (m) => _edit(start: m),
                                  onInbox: () => setState(() => _tab = 0),
                                  onFoxy: _foxy,
                                ),
                ),
              ),
            ),
          ),
        ]),
      ),
      floatingActionButton: _GradientFab(onTap: () => _tab == 0 ? _edit(inbox: true) : _edit()),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      bottomNavigationBar: _BottomBar(
        tab: _tab,
        inbox: _inbox.length,
        onTab: (i) {
          if (i == 2) {
            _foxy();
          } else if (i == 3) {
            _settings();
          } else {
            setState(() => _tab = i);
          }
        },
      ),
    );
  }
}

// -- Header & week strip ------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.date, required this.week, required this.onBack, required this.onMonth, required this.onToday, required this.onView});

  final DateTime date;
  final bool week;
  final VoidCallback onBack, onMonth, onToday;
  final ValueChanged<bool> onView;

  @override
  Widget build(BuildContext context) {
    final isToday = date == _day(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 4),
      child: Row(children: [
        IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20)),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onMonth,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${_months[date.month - 1].substring(0, 3)} ${date.day}, ', style: PhlioTypography.headline),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: ShaderMask(
                          shaderCallback: (r) => PhlioColors.sunsetGradient.createShader(r),
                          child: Text('${date.year}', style: PhlioTypography.headline.copyWith(color: Colors.white)),
                        ),
                      ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, color: PhlioColors.textMuted),
              ]),
            ),
          ),
        ),
        if (!isToday)
          TextButton(onPressed: onToday, child: Text('Today', style: PhlioTypography.label.copyWith(color: PhlioColors.brandOrange))),
        _ViewToggle(week: week, onChanged: onView),
      ]),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.week, required this.onChanged});

  final bool week;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool on, bool value) => GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: on ? PhlioColors.sunsetGradient : null,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: PhlioTypography.label.copyWith(color: on ? PhlioColors.textOnBrand : PhlioColors.textSecondary)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: PhlioColors.surfaceElevated, borderRadius: BorderRadius.circular(22)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [seg('Day', !week, false), seg('Week', week, true)]),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.start, required this.selected, required this.days, required this.onPick, required this.onSwipe});

  final DateTime start, selected;
  final Map<String, List<TTask>> days;
  final ValueChanged<DateTime> onPick;
  final ValueChanged<int> onSwipe;

  @override
  Widget build(BuildContext context) {
    final today = _day(DateTime.now());
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() > 200) onSwipe(v < 0 ? 1 : -1);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(child: Builder(builder: (_) {
              final d = start.add(Duration(days: i));
              final on = d == selected;
              final dots = (days[_ymd(d)] ?? const <TTask>[]).take(4).toList();
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(d),
                child: Column(children: [
                  Text(_wk[i], style: PhlioTypography.caption.copyWith(color: d == today ? PhlioColors.brandOrange : PhlioColors.textMuted)),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: on ? PhlioColors.sunsetGradient : null,
                      border: !on && d == today ? Border.all(color: PhlioColors.brandOrange, width: 1.4) : null,
                      boxShadow: on ? [BoxShadow(color: PhlioColors.brandOrange.withValues(alpha: .35), blurRadius: 12)] : null,
                    ),
                    child: Text('${d.day}',
                        style: PhlioTypography.bodyStrong.copyWith(color: on ? PhlioColors.textOnBrand : PhlioColors.textPrimary)),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 6,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (final t in dots)
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(color: t.done ? t.color.withValues(alpha: .35) : t.color, shape: BoxShape.circle),
                        ),
                    ]),
                  ),
                ]),
              );
            })),
        ]),
      ),
    );
  }
}

// -- Day view -----------------------------------------------------------------

class _DayView extends StatelessWidget {
  const _DayView({
    super.key,
    required this.date,
    required this.tasks,
    required this.inboxCount,
    required this.showGaps,
    required this.onToggle,
    required this.onOpen,
    required this.onAddAt,
    required this.onInbox,
    required this.onFoxy,
  });

  final DateTime date;
  final List<TTask> tasks;
  final int inboxCount;
  final bool showGaps;
  final ValueChanged<TTask> onToggle, onOpen;
  final ValueChanged<int> onAddAt;
  final VoidCallback onInbox, onFoxy;

  @override
  Widget build(BuildContext context) {
    final timed = tasks.where((t) => t.start != null).toList()..sort((a, b) => a.start!.compareTo(b.start!));
    final anytime = tasks.where((t) => t.start == null).toList();
    final energy = tasks.where((t) => !t.done).fold<int>(0, (s, t) => s + t.energy);
    final now = DateTime.now();
    final isToday = date == _day(now);
    final nowMin = now.hour * 60 + now.minute;

    final rows = <Widget>[];
    var nowPlaced = !isToday;
    for (var i = 0; i < timed.length; i++) {
      final t = timed[i];
      if (!nowPlaced && nowMin < t.start!) {
        rows.add(_NowRow(minutes: nowMin));
        nowPlaced = true;
      }
      rows.add(_TaskRow(task: t, onToggle: () => onToggle(t), onOpen: () => onOpen(t)));
      final next = i + 1 < timed.length ? timed[i + 1] : null;
      final gapStart = t.end!;
      final gapEnd = next?.start ?? math.max(gapStart, 23 * 60);
      final gap = gapEnd - gapStart;
      final connectorColor = next?.color ?? t.color;
      if (next != null || gap > 0) {
        rows.add(_Connector(
          color: t.color,
          to: connectorColor,
          height: (24 + gap * 0.12).clamp(22, 70).toDouble(),
          gap: showGaps && gap >= 30 && next != null ? gap : null,
          before: next?.title,
          onAdd: () => onAddAt(gapStart),
        ));
      }
    }
    if (!nowPlaced) rows.add(_NowRow(minutes: nowMin));

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 120),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _EnergyRing(value: energy),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_energyLabel(energy), style: PhlioTypography.bodyStrong),
                Text('${tasks.where((t) => t.done).length} of ${tasks.length} done', style: PhlioTypography.caption),
              ]),
            ),
            _Pill(icon: Icons.inbox_rounded, label: 'Inbox · $inboxCount', onTap: onInbox),
          ]),
        ),
        const SizedBox(height: 14),
        if (anytime.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in anytime)
                _Pill(
                  icon: _icon(t.icon),
                  label: t.title,
                  color: t.color,
                  done: t.done,
                  onTap: () => onOpen(t),
                  onLong: () => onToggle(t),
                ),
            ]),
          ),
        if (timed.isEmpty)
          _EmptyDay(onFoxy: onFoxy, onAdd: () => onAddAt(9 * 60))
        else
          ...rows,
      ],
    );
  }

  static String _energyLabel(int e) {
    if (e == 0) return 'Easy day ahead';
    if (e <= 6) return 'Balanced day';
    if (e <= 12) return 'Busy day — pace yourself';
    return 'Packed day — leave room to breathe';
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onToggle, required this.onOpen});

  final TTask task;
  final VoidCallback onToggle, onOpen;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final tall = t.duration >= 30;
    final pillH = tall ? (48 + (t.duration - 30) * 0.55).clamp(56, 150).toDouble() : 48.0;
    final timeText = t.duration == 0 ? _clock(t.start!) : '${_clock(t.start!)} – ${_clock(t.end!)}';
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 56,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_clock(t.start!).split(' ').first, style: PhlioTypography.label.copyWith(color: PhlioColors.textSecondary)),
                Text(_clock(t.start!).split(' ').last, style: PhlioTypography.caption.copyWith(fontSize: 10)),
                if (tall) ...[
                  SizedBox(height: math.max(0.0, pillH - 52)),
                  Text(_clock(t.end!).split(' ').first, style: PhlioTypography.caption),
                ],
              ]),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 52,
              height: pillH,
              decoration: BoxDecoration(
                color: t.done ? t.color.withValues(alpha: .35) : t.color,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [BoxShadow(color: t.color.withValues(alpha: t.done ? 0 : .35), blurRadius: 14, offset: const Offset(0, 4))],
              ),
              alignment: tall ? Alignment.topCenter : Alignment.center,
              padding: EdgeInsets.only(top: tall ? 14 : 0),
              child: Icon(_icon(t.icon), color: const Color(0xFF14101E), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '$timeText${t.duration > 0 ? ' (${_span(t.duration)})' : ''}${t.repeat != 'none' ? '  ↻' : ''}',
                  style: PhlioTypography.caption,
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: PhlioTypography.bodyStrong.copyWith(
                    fontSize: 16,
                    color: t.done ? PhlioColors.textMuted : PhlioColors.textPrimary,
                    decoration: t.done ? TextDecoration.lineThrough : null,
                    decorationColor: PhlioColors.textMuted,
                  ),
                  child: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                if (t.subtasks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('${t.subtasks.where((s) => s['done'] == true).length}/${t.subtasks.length} subtasks',
                        style: PhlioTypography.caption.copyWith(color: t.color)),
                  ),
                if (t.source != 'manual')
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(_sourceLabel(t.source), style: PhlioTypography.caption.copyWith(fontSize: 11, color: PhlioColors.textMuted)),
                  ),
              ]),
            ),
          ),
          _Check(done: t.done, color: t.color, onTap: onToggle),
        ]),
      ),
    );
  }

  static String _sourceLabel(String s) => switch (s) {
        'book' => 'From Phlio Book',
        'social' => 'From Phlio Social',
        'foxy' => 'Planned by Foxy',
        _ => 'From Phlio',
      };
}

class _Check extends StatelessWidget {
  const _Check({required this.done, required this.color, required this.onTap});

  final bool done;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? color : Colors.transparent,
            border: Border.all(color: done ? color : PhlioColors.textMuted, width: 2),
          ),
          child: done ? const Icon(Icons.check_rounded, size: 18, color: Color(0xFF14101E)) : null,
        ),
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.color, required this.to, required this.height, this.gap, this.before, required this.onAdd});

  final Color color, to;
  final double height;
  final int? gap;
  final String? before;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final g = gap;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        const SizedBox(width: 66),
        SizedBox(
          width: 52,
          height: g == null ? height : math.max(height, 64.0),
          child: CustomPaint(painter: _DashPainter(color, to)),
        ),
        const SizedBox(width: 14),
        if (g != null)
          Expanded(
            child: Row(children: [
              Icon(Icons.schedule_rounded, size: 16, color: PhlioColors.textMuted.withValues(alpha: .8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Plan or chill for ${_span(g)}${before != null ? ' before $before' : ''}',
                  style: PhlioTypography.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              _Pill(icon: Icons.add_rounded, label: 'Add task', onTap: onAdd, small: true),
            ]),
          ),
      ]),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.from, this.to);

  final Color from, to;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final paint = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [from, to])
          .createShader(Offset.zero & size);
    const dash = 5.0, space = 5.0;
    var y = 3.0;
    while (y < size.height - 3) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + dash, size.height - 3)), paint);
      y += dash + space;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.from != from || old.to != to;
}

class _NowRow extends StatelessWidget {
  const _NowRow({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        SizedBox(
          width: 56,
          child: Text(_clock(minutes).split(' ').first,
              textAlign: TextAlign.right, style: PhlioTypography.label.copyWith(color: PhlioColors.brandOrange)),
        ),
        const SizedBox(width: 10),
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: PhlioColors.sunsetGradient),
        ),
        Expanded(
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [PhlioColors.brandOrange, PhlioColors.brandOrange.withValues(alpha: 0)]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.onFoxy, required this.onAdd});

  final VoidCallback onFoxy, onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Column(children: [
        const FoxyPuppet(act: FoxyAct.wave, size: 150),
        const SizedBox(height: 8),
        Text('Nothing planned yet', style: PhlioTypography.title),
        const SizedBox(height: 4),
        Text(
          'Let Foxy build your day from your bookings, Spaces and a quick note — or add tasks yourself.',
          textAlign: TextAlign.center,
          style: PhlioTypography.caption,
        ),
        const SizedBox(height: 16),
        _GradientButton(label: 'Let Foxy plan my day', icon: Icons.auto_awesome_rounded, onTap: onFoxy),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, color: PhlioColors.textSecondary),
          label: Text('Add a task', style: PhlioTypography.label.copyWith(color: PhlioColors.textSecondary)),
        ),
      ]),
    );
  }
}

class _EnergyRing extends StatelessWidget {
  const _EnergyRing({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final frac = (value / 15).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: frac),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => SizedBox(
        width: 46,
        height: 46,
        child: CustomPaint(
          painter: _RingPainter(v),
          child: Center(child: Icon(Icons.bolt_rounded, size: 22, color: Color.lerp(PhlioColors.success, PhlioColors.danger, v))),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v);

  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    canvas.drawArc(rect, 0, math.pi * 2, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = PhlioColors.surfaceElevated);
    if (v <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          colors: [Color(0xFF68D7CD), Color(0xFFFFB58F), Color(0xFFF5636B), Color(0xFF68D7CD)],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v;
}

// -- Week view ----------------------------------------------------------------

class _WeekView extends StatelessWidget {
  const _WeekView({super.key, required this.start, required this.days, required this.selected, required this.onOpen, required this.onPick});

  final DateTime start, selected;
  final Map<String, List<TTask>> days;
  final ValueChanged<TTask> onOpen;
  final ValueChanged<DateTime> onPick;

  static const _from = 6 * 60, _to = 24 * 60;
  static const _hourH = 44.0;

  @override
  Widget build(BuildContext context) {
    const height = (_to - _from) / 60 * _hourH;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 12, 8, 120),
      child: SizedBox(
        height: height + 24,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 40,
            child: Stack(children: [
              for (var h = _from ~/ 60; h < _to ~/ 60; h += 2)
                Positioned(
                  top: 24 + (h * 60 - _from) / 60 * _hourH - 6,
                  right: 4,
                  child: Text(h == 12 ? '12p' : h > 12 ? '${h - 12}p' : '${h}a',
                      style: PhlioTypography.caption.copyWith(fontSize: 10)),
                ),
            ]),
          ),
          for (var i = 0; i < 7; i++)
            Expanded(child: Builder(builder: (_) {
              final d = start.add(Duration(days: i));
              final tasks = (days[_ymd(d)] ?? const <TTask>[]).where((t) => t.start != null).toList();
              final on = d == selected;
              return GestureDetector(
                onTap: () => onPick(d),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: on ? PhlioColors.brandOrange.withValues(alpha: .06) : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Text(_wk[i].substring(0, 1),
                          textAlign: TextAlign.center,
                          style: PhlioTypography.label.copyWith(color: on ? PhlioColors.brandOrange : PhlioColors.textMuted)),
                    ),
                    for (var h = _from ~/ 60; h < _to ~/ 60; h += 2)
                      Positioned(
                        top: 24 + (h * 60 - _from) / 60 * _hourH,
                        left: 0,
                        right: 0,
                        child: Container(height: 1, color: PhlioColors.borderSubtle.withValues(alpha: .4)),
                      ),
                    for (final t in tasks)
                      Positioned(
                        top: 24 + (math.max(t.start!, _from) - _from) / 60 * _hourH,
                        left: 2,
                        right: 2,
                        height: math.max(22.0, t.duration / 60 * _hourH),
                        child: GestureDetector(
                          onTap: () => onOpen(t),
                          child: Container(
                            decoration: BoxDecoration(
                              color: t.color.withValues(alpha: t.done ? .3 : .9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.topCenter,
                            padding: const EdgeInsets.only(top: 3),
                            child: Icon(_icon(t.icon), size: 14, color: const Color(0xFF14101E)),
                          ),
                        ),
                      ),
                  ]),
                ),
              );
            })),
        ]),
      ),
    );
  }
}

// -- Inbox --------------------------------------------------------------------

class _InboxView extends StatelessWidget {
  const _InboxView({super.key, required this.items, required this.onOpen, required this.onAdd});

  final List<TTask> items;
  final ValueChanged<TTask> onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
      children: [
        Text('Inbox', style: PhlioTypography.title),
        Text('Ideas without a time yet. Open one and give it a day to put it on your timeline.',
            style: PhlioTypography.caption),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 30),
            child: Column(children: [
              const FoxyPuppet(act: FoxyAct.happy, size: 120),
              const SizedBox(height: 8),
              Text('Inbox zero!', style: PhlioTypography.bodyStrong),
              TextButton(onPressed: onAdd, child: Text('Add something for later', style: PhlioTypography.label.copyWith(color: PhlioColors.brandOrange))),
            ]),
          ),
        for (final t in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: PhlioColors.surfaceElevated,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onOpen(t),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: t.color, shape: BoxShape.circle),
                      child: Icon(_icon(t.icon), color: const Color(0xFF14101E), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title, style: PhlioTypography.bodyStrong),
                        Text(t.duration > 0 ? _span(t.duration) : 'Anytime', style: PhlioTypography.caption),
                      ]),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: PhlioColors.textMuted),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// -- Bottom bar ---------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.tab, required this.inbox, required this.onTab});

  final int tab, inbox;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icon, String label, {int badge = 0}) {
      final on = tab == i;
      return Expanded(
        child: InkWell(
          onTap: () => onTab(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                backgroundColor: PhlioColors.brandOrange,
                textColor: PhlioColors.textOnBrand,
                child: on
                    ? ShaderMask(
                        shaderCallback: (r) => PhlioColors.sunsetGradient.createShader(r),
                        child: Icon(icon, color: Colors.white),
                      )
                    : Icon(icon, color: PhlioColors.textMuted),
              ),
              const SizedBox(height: 2),
              Text(label, style: PhlioTypography.caption.copyWith(fontSize: 11, color: on ? PhlioColors.textPrimary : PhlioColors.textMuted)),
            ]),
          ),
        ),
      );
    }

    return BottomAppBar(
      color: PhlioColors.surfaceElevated,
      shape: const CircularNotchedRectangle(),
      notchMargin: 6,
      padding: EdgeInsets.zero,
      height: 64,
      child: Row(children: [
        item(0, Icons.inbox_rounded, 'Inbox', badge: inbox),
        item(1, Icons.view_timeline_rounded, 'Timeline'),
        item(2, Icons.auto_awesome_rounded, 'Foxy'),
        item(3, Icons.tune_rounded, 'Settings'),
        const SizedBox(width: 76),
      ]),
    );
  }
}

class _GradientFab extends StatelessWidget {
  const _GradientFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: PhlioColors.sunsetGradient,
          boxShadow: [BoxShadow(color: PhlioColors.brandViolet.withValues(alpha: .45), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: const Icon(Icons.add_rounded, size: 32, color: PhlioColors.textOnBrand),
      ),
    );
  }
}

// -- Small pieces -------------------------------------------------------------

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap, this.color, this.done = false, this.onLong, this.small = false});

  final IconData icon;
  final String label;
  final Color? color;
  final bool done, small;
  final VoidCallback onTap;
  final VoidCallback? onLong;

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Material(
      color: c == null ? PhlioColors.surfaceElevated : c.withValues(alpha: done ? .12 : .2),
      shape: StadiumBorder(side: BorderSide(color: c ?? PhlioColors.borderSubtle)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        onLongPress: onLong,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: small ? 10 : 12, vertical: small ? 5 : 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: small ? 14 : 16, color: c ?? PhlioColors.textSecondary),
            const SizedBox(width: 5),
            Text(label,
                style: PhlioTypography.label.copyWith(
                  fontSize: small ? 12 : null,
                  color: PhlioColors.textPrimary,
                  decoration: done ? TextDecoration.lineThrough : null,
                )),
          ]),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.icon, required this.onTap, this.busy = false});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? .5 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(gradient: PhlioColors.sunsetGradient, borderRadius: BorderRadius.circular(28)),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: busy ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (busy)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: PhlioColors.textOnBrand))
                else
                  Icon(icon, size: 18, color: PhlioColors.textOnBrand),
                const SizedBox(width: 8),
                Text(label, style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textOnBrand)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: PhlioColors.textMuted.withValues(alpha: .5), borderRadius: BorderRadius.circular(2)),
        ),
      );
}

// -- Month calendar -----------------------------------------------------------

class _MonthSheet extends StatefulWidget {
  const _MonthSheet({required this.selected});

  final DateTime selected;

  @override
  State<_MonthSheet> createState() => _MonthSheetState();
}

class _MonthSheetState extends State<_MonthSheet> {
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);
  Map<String, List<Color>> _dots = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    try {
      final res = await _dio.get('/timeline', queryParameters: {'start': _ymd(_month), 'days': days});
      if (!mounted) return;
      setState(() => _dots = {
            for (final d in ((res.data as Map)['days'] as List))
              '${(d as Map)['date']}': [for (final c in d['dots'] as List) _hex('$c')]
          });
    } catch (_) {}
  }

  void _shift(int n) {
    setState(() {
      _month = DateTime(_month.year, _month.month + n);
      _dots = {};
    });
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final first = _month;
    final lead = first.weekday - 1;
    final count = DateTime(first.year, first.month + 1, 0).day;
    final today = _day(DateTime.now());
    return Container(
      decoration: const BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _Grabber(),
          const SizedBox(height: 10),
          Row(children: [
            IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${_months[first.month - 1]} ', style: PhlioTypography.title),
                  TextSpan(text: '${first.year}', style: PhlioTypography.title.copyWith(color: PhlioColors.brandOrange)),
                ]),
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            for (final w in _wk)
              Expanded(child: Text(w.substring(0, 1), textAlign: TextAlign.center, style: PhlioTypography.caption)),
          ]),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: lead + count,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: .82),
            itemBuilder: (_, i) {
              if (i < lead) return const SizedBox.shrink();
              final d = DateTime(first.year, first.month, i - lead + 1);
              final on = d == widget.selected;
              final dots = _dots[_ymd(d)] ?? const <Color>[];
              return GestureDetector(
                onTap: () => Navigator.pop(context, d),
                child: Column(children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: on ? PhlioColors.sunsetGradient : null,
                      border: !on && d == today ? Border.all(color: PhlioColors.brandOrange) : null,
                    ),
                    child: Text('${d.day}',
                        style: PhlioTypography.label.copyWith(color: on ? PhlioColors.textOnBrand : PhlioColors.textPrimary)),
                  ),
                  const SizedBox(height: 3),
                  Wrap(spacing: 2, runSpacing: 2, alignment: WrapAlignment.center, children: [
                    for (final c in dots.take(4))
                      Container(width: 5, height: 5, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                  ]),
                ]),
              );
            },
          ),
        ]),
      ),
    );
  }
}

// -- Task editor --------------------------------------------------------------

class _TaskEditor extends StatefulWidget {
  const _TaskEditor({required this.task});

  final TTask task;

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late final TTask t = widget.task.copy();
  late final _title = TextEditingController(text: t.title);
  late final _notes = TextEditingController(text: t.notes);
  final _sub = TextEditingController();
  bool _saving = false;

  bool get _isNew => t.id == null;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _sub.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    t
      ..title = _title.text.trim()
      ..notes = _notes.text.trim();
    setState(() => _saving = true);
    try {
      final body = t.toJson();
      if (_isNew) {
        await _dio.post('/timeline/tasks', data: body);
      } else {
        body['clear_date'] = t.date == null;
        body['clear_start'] = t.start == null;
        await _dio.patch('/timeline/tasks/${t.id}', data: body);
      }
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_err(e))));
    }
  }

  Future<void> _delete() async {
    try {
      await _dio.delete('/timeline/tasks/${t.id}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_err(e))));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: t.date != null ? DateTime.parse(t.date!) : now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
    );
    if (d != null) setState(() => t.date = _ymd(d));
  }

  Future<void> _pickTime() async {
    final s = t.start ?? 9 * 60;
    final tod = await showTimePicker(context: context, initialTime: TimeOfDay(hour: s ~/ 60, minute: s % 60));
    if (tod != null) setState(() => t.start = tod.hour * 60 + tod.minute);
  }

  Future<void> _pickColor() async {
    final c = await showModalBottomSheet<Color>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ColorPicker(initial: t.color),
    );
    if (c != null) setState(() => t.color = c);
  }

  @override
  Widget build(BuildContext context) {
    final ink = ThemeData.estimateBrightnessForColor(t.color) == Brightness.dark ? Colors.white : const Color(0xFF14101E);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .9,
        maxChildSize: .95,
        minChildSize: .5,
        builder: (_, scroll) => Container(
          decoration: const BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          clipBehavior: Clip.antiAlias,
          child: ListView(controller: scroll, padding: EdgeInsets.zero, children: [
            // Coloured header.
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              color: t.color,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: Column(children: [
                Center(
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: ink.withValues(alpha: .35), borderRadius: BorderRadius.circular(2))),
                ),
                Row(children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: ink)),
                  const Spacer(),
                  if (!_isNew) IconButton(onPressed: _delete, icon: Icon(Icons.delete_outline_rounded, color: ink)),
                ]),
                Row(children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(color: ink.withValues(alpha: .14), shape: BoxShape.circle),
                    child: Icon(_icon(t.icon), color: ink, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _title,
                      autofocus: _isNew,
                      textCapitalization: TextCapitalization.sentences,
                      style: PhlioTypography.headline.copyWith(color: ink),
                      cursorColor: ink,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'What’s the plan?',
                        hintStyle: PhlioTypography.headline.copyWith(color: ink.withValues(alpha: .5)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _section('When'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _Pill(
                    icon: Icons.calendar_today_rounded,
                    label: t.date == null ? 'Inbox (no day)' : _prettyDate(t.date!),
                    color: t.color,
                    onTap: _pickDate,
                  ),
                  if (t.date != null)
                    _Pill(
                      icon: Icons.schedule_rounded,
                      label: t.start == null ? 'Anytime' : _clock(t.start!),
                      color: t.color,
                      onTap: _pickTime,
                    ),
                  if (t.start != null) _Pill(icon: Icons.all_inclusive_rounded, label: 'Anytime', onTap: () => setState(() => t.start = null)),
                  if (t.date != null) _Pill(icon: Icons.inbox_rounded, label: 'Move to inbox', onTap: () => setState(() {
                        t.date = null;
                        t.start = null;
                      })),
                ]),
                const SizedBox(height: 18),
                _section('Duration'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in const [0, 15, 30, 45, 60, 90, 120, 180])
                    ChoiceChip(
                      label: Text(m == 0 ? 'Moment' : _span(m)),
                      selected: t.duration == m,
                      selectedColor: t.color.withValues(alpha: .35),
                      side: BorderSide(color: t.duration == m ? t.color : PhlioColors.borderSubtle),
                      showCheckmark: false,
                      onSelected: (_) => setState(() => t.duration = m),
                    ),
                ]),
                const SizedBox(height: 18),
                _section('Colour'),
                SizedBox(
                  height: 44,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final c in _palette)
                      GestureDetector(
                        onTap: () => setState(() => t.color = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.only(right: 10, top: 4, bottom: 4),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(color: t.color.toARGB32() == c.toARGB32() ? Colors.white : Colors.transparent, width: 3),
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: _pickColor,
                      child: Container(
                        width: 36,
                        height: 36,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(colors: [
                            Color(0xFFF5636B), Color(0xFFF6B93B), Color(0xFF7BD88F), Color(0xFF68D7CD),
                            Color(0xFF72A7FF), Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFF5636B),
                          ]),
                        ),
                        child: const Icon(Icons.colorize_rounded, size: 16, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                _section('Icon'),
                GridView.count(
                  crossAxisCount: 8,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final e in _icons.entries)
                      GestureDetector(
                        onTap: () => setState(() => t.icon = e.key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          decoration: BoxDecoration(
                            color: t.icon == e.key ? t.color : PhlioColors.surfaceElevated,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(e.value, size: 18, color: t.icon == e.key ? const Color(0xFF14101E) : PhlioColors.textSecondary),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _section('Repeat'),
                Wrap(spacing: 8, children: [
                  for (final r in const ['none', 'daily', 'weekdays', 'weekly'])
                    ChoiceChip(
                      label: Text(r == 'none' ? 'Once' : r[0].toUpperCase() + r.substring(1)),
                      selected: t.repeat == r,
                      selectedColor: t.color.withValues(alpha: .35),
                      showCheckmark: false,
                      onSelected: t.date == null ? null : (_) => setState(() => t.repeat = r),
                    ),
                ]),
                const SizedBox(height: 18),
                _section('Energy'),
                Row(children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: () => setState(() => t.energy = i),
                      icon: Icon(Icons.bolt_rounded, color: i <= t.energy ? t.color : PhlioColors.textMuted.withValues(alpha: .4)),
                    ),
                  const SizedBox(width: 6),
                  Text(const ['', 'Light', 'Easy', 'Medium', 'Demanding', 'Intense'][t.energy], style: PhlioTypography.caption),
                ]),
                const SizedBox(height: 12),
                _section('Subtasks'),
                for (var i = 0; i < t.subtasks.length; i++)
                  Row(children: [
                    Checkbox(
                      value: t.subtasks[i]['done'] == true,
                      activeColor: t.color,
                      checkColor: const Color(0xFF14101E),
                      shape: const CircleBorder(),
                      onChanged: (v) => setState(() => t.subtasks[i]['done'] = v == true),
                    ),
                    Expanded(
                      child: Text('${t.subtasks[i]['title']}',
                          style: PhlioTypography.body.copyWith(
                              decoration: t.subtasks[i]['done'] == true ? TextDecoration.lineThrough : null)),
                    ),
                    IconButton(
                      onPressed: () => setState(() => t.subtasks.removeAt(i)),
                      icon: const Icon(Icons.close_rounded, size: 18, color: PhlioColors.textMuted),
                    ),
                  ]),
                TextField(
                  controller: _sub,
                  style: PhlioTypography.body,
                  decoration: InputDecoration(
                    hintText: 'Add a subtask',
                    prefixIcon: Icon(Icons.add_rounded, color: t.color),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isEmpty) return;
                    setState(() => t.subtasks.add({'title': v.trim(), 'done': false}));
                    _sub.clear();
                  },
                ),
                const SizedBox(height: 8),
                _section('Notes'),
                TextField(
                  controller: _notes,
                  maxLines: 4,
                  minLines: 2,
                  style: PhlioTypography.body,
                  decoration: InputDecoration(
                    hintText: 'Links, address, anything…',
                    filled: true,
                    fillColor: PhlioColors.surfaceElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: _GradientButton(
                    label: _isNew ? 'Create task' : 'Save changes',
                    icon: Icons.check_rounded,
                    busy: _saving,
                    onTap: _title.text.trim().isEmpty ? null : _save,
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _section(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s.toUpperCase(), style: PhlioTypography.caption.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w700)),
      );

  static String _prettyDate(String ymd) {
    final d = DateTime.parse(ymd);
    return '${_wk[d.weekday - 1]}, ${_months[d.month - 1].substring(0, 3)} ${d.day}';
  }
}

// -- Colour picker ------------------------------------------------------------

class _ColorPicker extends StatefulWidget {
  const _ColorPicker({required this.initial});

  final Color initial;

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final _hexCtl = TextEditingController(text: _toHex(widget.initial));

  Color get _color => _hsv.toColor();

  void _set(HSVColor v) {
    setState(() => _hsv = v);
    _hexCtl.text = _toHex(_color);
  }

  @override
  void dispose() {
    _hexCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hues = [for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h.toDouble() % 360, 1, 1).toColor()];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _Grabber(),
            const SizedBox(height: 12),
            Row(children: [
              Text('Choose a colour', style: PhlioTypography.title),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: _color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _color.withValues(alpha: .5), blurRadius: 12)]),
              ),
            ]),
            const SizedBox(height: 18),
            Text('Hue', style: PhlioTypography.caption),
            _GradientSlider(
              colors: hues,
              value: _hsv.hue / 360,
              thumb: _color,
              onChanged: (v) => _set(_hsv.withHue((v * 360).clamp(0.0, 359.9))),
            ),
            const SizedBox(height: 12),
            Text('Brightness', style: PhlioTypography.caption),
            _GradientSlider(
              colors: [
                HSVColor.fromAHSV(1, _hsv.hue, 1, .25).toColor(),
                HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
                HSVColor.fromAHSV(1, _hsv.hue, .2, 1).toColor(),
              ],
              value: _brightness,
              thumb: _color,
              onChanged: (v) => _set(v <= .5
                  ? _hsv.withSaturation(1).withValue(.25 + v * 1.5)
                  : _hsv.withValue(1).withSaturation(1 - (v - .5) * 1.6)),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _hexCtl,
                  style: PhlioTypography.bodyStrong,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')), LengthLimitingTextInputFormatter(7)],
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                    filled: true,
                    fillColor: PhlioColors.surfaceElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) {
                    final s = v.startsWith('#') ? v : '#$v';
                    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s)) setState(() => _hsv = HSVColor.fromColor(_hex(s.toUpperCase())));
                  },
                ),
              ),
              const SizedBox(width: 12),
              _GradientButton(label: 'Use', icon: Icons.check_rounded, onTap: () => Navigator.pop(context, _color)),
            ]),
          ]),
        ),
      ),
    );
  }

  double get _brightness =>
      _hsv.saturation >= .99 ? ((_hsv.value - .25) / 1.5).clamp(0.0, .5) : (.5 + (1 - _hsv.saturation) / 1.6).clamp(.5, 1.0);
}

class _GradientSlider extends StatelessWidget {
  const _GradientSlider({required this.colors, required this.value, required this.thumb, required this.onChanged});

  final List<Color> colors;
  final double value;
  final Color thumb;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, box) {
      void at(Offset p) => onChanged((p.dx / box.maxWidth).clamp(0.0, 1.0));
      return GestureDetector(
        onPanDown: (d) => at(d.localPosition),
        onPanUpdate: (d) => at(d.localPosition),
        child: SizedBox(
          height: 36,
          child: Stack(alignment: Alignment.centerLeft, children: [
            Container(
              height: 22,
              decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(11)),
            ),
            Positioned(
              left: (value.clamp(0.0, 1.0) * (box.maxWidth - 30)),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: thumb,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

// -- Foxy plans the day -------------------------------------------------------

class _FoxyPlanSheet extends StatefulWidget {
  const _FoxyPlanSheet({required this.date});

  final DateTime date;

  @override
  State<_FoxyPlanSheet> createState() => _FoxyPlanSheetState();
}

class _FoxyPlanSheetState extends State<_FoxyPlanSheet> {
  final _prompt = TextEditingController();
  final _sources = {'book', 'social', 'routine'};
  bool _busy = false;
  String? _message;
  List<TTask> _added = [];
  int _hop = 0;

  static const _ideas = ['Gym at 7am', 'Study 2 hours', 'Lunch with friends at 1pm', 'Watch a movie at 9pm', 'Groceries', 'Guitar practice 30 min'];

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _plan() async {
    setState(() => _busy = true);
    try {
      final res = await _dio.post('/timeline/foxy', data: {
        'date': _ymd(widget.date),
        'prompt': _prompt.text.trim(),
        'sources': _sources.toList(),
      });
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _busy = false;
        _message = '${(res.data as Map)['message']}';
        _added = [for (final t in (res.data as Map)['added'] as List) TTask.fromJson(t as Map)];
        _hop++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = _err(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _message != null && _added.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const _Grabber(),
              const SizedBox(height: 4),
              FoxyPuppet(
                act: _busy ? FoxyAct.talk : done ? FoxyAct.hooray : FoxyAct.wave,
                talking: _busy,
                size: 130,
                hopSignal: _hop,
              ),
              Text(done ? 'Your day is ready!' : 'Let Foxy plan your day', style: PhlioTypography.title),
              const SizedBox(height: 4),
              Text(
                _message ?? 'Tell me what you want to fit in. I’ll add your Phlio plans and find free time for the rest.',
                textAlign: TextAlign.center,
                style: PhlioTypography.caption,
              ),
              const SizedBox(height: 14),
              if (done) ...[
                for (final t in _added)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 300 + 80 * _added.indexOf(t)),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child)),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(color: t.color, shape: BoxShape.circle),
                          child: Icon(_icon(t.icon), size: 18, color: const Color(0xFF14101E)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(t.title, style: PhlioTypography.bodyStrong)),
                        Text(t.start == null ? 'Anytime' : _clock(t.start!), style: PhlioTypography.caption),
                      ]),
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: _GradientButton(label: 'See my timeline', icon: Icons.view_timeline_rounded, onTap: () => Navigator.pop(context, true)),
                ),
              ] else ...[
                TextField(
                  controller: _prompt,
                  minLines: 2,
                  maxLines: 4,
                  style: PhlioTypography.body,
                  decoration: InputDecoration(
                    hintText: 'e.g. gym at 7am, study 2 hours, dinner with Neha at 8pm',
                    filled: true,
                    fillColor: PhlioColors.surfaceElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final idea in _ideas)
                    ActionChip(
                      label: Text(idea, style: PhlioTypography.caption.copyWith(color: PhlioColors.textPrimary)),
                      onPressed: () {
                        final cur = _prompt.text.trim();
                        _prompt.text = cur.isEmpty ? idea : '$cur, ${idea.toLowerCase()}';
                      },
                    ),
                ]),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('PULL FROM', style: PhlioTypography.caption.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in const [
                    ('book', 'Phlio Book', Icons.confirmation_number_rounded, Color(0xFFE795D7)),
                    ('social', 'Spaces you host', Icons.mic_rounded, Color(0xFF8D78FF)),
                    ('routine', 'Morning & wind-down', Icons.wb_sunny_rounded, Color(0xFFF6B93B)),
                  ])
                    FilterChip(
                      avatar: Icon(s.$3, size: 16, color: s.$4),
                      label: Text(s.$2),
                      selected: _sources.contains(s.$1),
                      selectedColor: s.$4.withValues(alpha: .25),
                      showCheckmark: false,
                      side: BorderSide(color: _sources.contains(s.$1) ? s.$4 : PhlioColors.borderSubtle),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _sources.add(s.$1);
                        } else {
                          _sources.remove(s.$1);
                        }
                      }),
                    ),
                ]),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: _GradientButton(label: 'Plan my day', icon: Icons.auto_awesome_rounded, busy: _busy, onTap: _plan),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
