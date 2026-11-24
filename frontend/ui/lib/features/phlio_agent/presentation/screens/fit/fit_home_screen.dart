// Phlio Fit — opened from the Phlio Agent explore tab.
//
// Today at a glance (steps · water · calories rings), Foxy Coach (AI — UI
// preview only, no AI service is called), live steps from the phone's
// sensor with a week chart, a water glass you top up, the food log with
// macros, activity from Phlio Move, and goals.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:phlio/design_system/colors.dart';
import 'package:phlio/design_system/typography.dart';

import '../move/move_home_screen.dart';
import 'fit_api.dart';
import 'fit_coach_screen.dart';
import 'fit_food_sheet.dart';

class FitHomeScreen extends StatefulWidget {
  const FitHomeScreen({super.key});

  @override
  State<FitHomeScreen> createState() => _FitHomeScreenState();
}

class _FitHomeScreenState extends State<FitHomeScreen> {
  DateTime _date = DateTime.now();
  Map<String, dynamic>? _day;
  Map<String, dynamic>? _history;
  String? _error;
  final _tracker = FitStepTracker.instance;

  bool get _isToday => fitYmd(_date) == fitYmd(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
    _tracker.steps.addListener(_onSteps);
    _tracker.start();
  }

  @override
  void dispose() {
    _tracker.steps.removeListener(_onSteps);
    super.dispose();
  }

  void _onSteps() {
    final s = _tracker.steps.value;
    if (s != null && _isToday && _day != null && mounted) setState(() => _day!['steps'] = s);
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        fitDio.get('/fitness/day', queryParameters: {'date': fitYmd(_date)}),
        fitDio.get('/fitness/history', queryParameters: {'days': 7, 'end': fitYmd(_date)}),
      ]);
      if (!mounted) return;
      setState(() {
        _day = Map<String, dynamic>.from(r[0].data as Map);
        _history = Map<String, dynamic>.from(r[1].data as Map);
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Phlio Fit isn’t available yet — restart the backend.');
    }
  }

  void _apply(dynamic data) {
    if (!mounted) return;
    setState(() => _day = Map<String, dynamic>.from(data as Map));
    _refreshHistory();
  }

  Future<void> _refreshHistory() async {
    try {
      final r = await fitDio.get('/fitness/history', queryParameters: {'days': 7, 'end': fitYmd(_date)});
      if (mounted) setState(() => _history = Map<String, dynamic>.from(r.data as Map));
    } catch (_) {}
  }

  Future<void> _water(int ml) async {
    HapticFeedback.lightImpact();
    try {
      _apply((await fitDio.post('/fitness/water', data: {'ml': ml, 'date': fitYmd(_date)})).data);
    } catch (_) {}
  }

  Future<void> _addSteps() async {
    final c = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add steps'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'e.g. 1500'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: const Text('Add')),
        ],
      ),
    );
    if (n == null || n == 0) return;
    try {
      _apply((await fitDio.post('/fitness/steps', data: {'add': n, 'date': fitYmd(_date)})).data);
    } catch (_) {}
  }

  Future<void> _logFood({String? meal}) async {
    final added = await showFoodLogSheet(context, date: _date, meal: meal);
    if (added != null) _apply(added);
  }

  Future<void> _removeMeal(Map m) async {
    try {
      _apply((await fitDio.delete('/fitness/meals/${m['id']}', queryParameters: {'date': fitYmd(_date)})).data);
    } catch (_) {}
  }

  Future<void> _goals() async {
    final saved = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GoalsSheet(goals: Map<String, dynamic>.from(_day!['goals'] as Map)),
    );
    if (saved != null) _load();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (d == null) return;
    setState(() {
      _date = d;
      _day = null;
    });
    _load();
  }

  String get _dateTitle {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final prefix = _isToday
        ? 'Today, '
        : fitYmd(_date) == fitYmd(DateTime.now().subtract(const Duration(days: 1)))
            ? 'Yesterday, '
            : '';
    return '$prefix${months[_date.month - 1]} ${_date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final d = _day;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phlio Fit'),
        actions: [
          if (d != null) IconButton(tooltip: 'Goals', onPressed: _goals, icon: const Icon(Icons.flag_rounded)),
        ],
      ),
      floatingActionButton: d == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: fitCalories,
              foregroundColor: PhlioColors.textOnBrand,
              onPressed: () => _logFood(),
              icon: const Icon(Icons.restaurant_rounded),
              label: const Text('Log food'),
            ),
      body: d == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 110), children: [
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Text(_dateTitle, style: PhlioTypography.headline),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: PhlioColors.textMuted),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                _rings(d),
                const SizedBox(height: 12),
                _coachCard(d),
                const SizedBox(height: 12),
                _stepsCard(d),
                const SizedBox(height: 12),
                _waterCard(d),
                const SizedBox(height: 12),
                _foodCard(d),
                const SizedBox(height: 12),
                _activityCard(d),
              ]),
            ),
    );
  }

  // -- Sections -------------------------------------------------------------------

  Widget _rings(Map d) {
    final p = (d['progress'] as Map).cast<String, dynamic>();
    final g = (d['goals'] as Map).cast<String, dynamic>();
    Widget ring(String label, double v, Color c, String value) => Expanded(
          child: Column(children: [
            FitRing(
              value: v,
              color: c,
              size: 92,
              child: Text('${(v * 100).round()}%', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            const SizedBox(height: 8),
            Text(label, style: PhlioTypography.bodyStrong),
            Text(value, style: PhlioTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        );
    return FitCard(
      child: Row(children: [
        ring('Steps', (p['steps'] as num).toDouble(), fitSteps, '${fitNum(d['steps'] as num)} / ${fitNum(g['steps'] as num)}'),
        ring('Water', (p['water'] as num).toDouble(), fitWater, '${fitMl(d['water_ml'] as num)} / ${fitMl(g['water_ml'] as num)}'),
        ring('Calories', (p['calories'] as num).toDouble(), fitCalories,
            '${fitNum((d['eaten'] as Map)['kcal'] as num)} / ${fitNum(g['calories'] as num)}'),
      ]),
    );
  }

  Widget _coachCard(Map d) {
    final tip = coachTip(d);
    return FitCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FitCoachScreen(day: d))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(gradient: PhlioColors.sunsetGradient, borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.auto_awesome_rounded, color: PhlioColors.textOnBrand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Foxy Coach', style: PhlioTypography.bodyStrong),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(8)),
                child: Text('PREVIEW', style: PhlioTypography.caption.copyWith(fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(tip, style: PhlioTypography.body.copyWith(color: PhlioColors.textSecondary, height: 1.4)),
            const SizedBox(height: 8),
            Row(children: [
              Text('Ask Foxy', style: PhlioTypography.label.copyWith(color: PhlioColors.brandPeach)),
              const Icon(Icons.arrow_forward_rounded, size: 16, color: PhlioColors.brandPeach),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _stepsCard(Map d) {
    final days = ((_history?['days'] as List?) ?? const []).cast<Map>();
    final goal = ((d['goals'] as Map)['steps'] as num).toDouble();
    return FitCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.directions_walk_rounded, color: fitSteps),
          const SizedBox(width: 8),
          Text('Steps', style: PhlioTypography.title),
          const Spacer(),
          ValueListenableBuilder<String>(
            valueListenable: _tracker.status,
            builder: (_, s, __) => switch (s) {
              'live' => _Chip(icon: Icons.sensors_rounded, text: 'Live', color: fitSteps),
              'denied' => TextButton(onPressed: _tracker.start, child: const Text('Allow step tracking')),
              'unavailable' => _Chip(icon: Icons.sensors_off_rounded, text: 'No sensor', color: PhlioColors.textMuted),
              _ => const SizedBox.shrink(),
            },
          ),
          IconButton(tooltip: 'Add steps', onPressed: _addSteps, icon: const Icon(Icons.add_circle_outline_rounded)),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (d['steps'] as num).toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text(fitNum(v), style: PhlioTypography.displayMedium),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('of ${fitNum(goal)}', style: PhlioTypography.caption),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${((d['steps'] as num) * 0.0007).toStringAsFixed(1)} km · ${fitNum((d['steps'] as num) * 0.04)} kcal',
                style: PhlioTypography.caption),
          ),
        ]),
        const SizedBox(height: 14),
        if (days.isNotEmpty)
          FitBarChart(
            key: ValueKey('steps-${fitYmd(_date)}-${days.last['steps']}'),
            values: [for (final x in days) (x['steps'] as num).toDouble()],
            labels: [for (final x in days) weekdayLabel('${x['date']}')],
            color: fitSteps,
            goal: goal,
            format: (i) => '${fitNum(days[i]['steps'] as num)} steps',
          ),
      ]),
    );
  }

  Widget _waterCard(Map d) {
    final ml = (d['water_ml'] as num).toDouble();
    final goal = ((d['goals'] as Map)['water_ml'] as num).toDouble();
    return FitCard(
      child: Row(children: [
        _WaterGlass(fill: (ml / goal).clamp(0.0, 1.0)),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.water_drop_rounded, color: fitWater, size: 20),
              const SizedBox(width: 6),
              Text('Water', style: PhlioTypography.title),
            ]),
            const SizedBox(height: 6),
            Text('${fitMl(ml)} of ${fitMl(goal)}', style: PhlioTypography.bodyStrong),
            Text(ml >= goal ? 'Goal reached — nice!' : '${fitMl(goal - ml)} to go · ${((goal - ml) / 250).ceil()} glasses',
                style: PhlioTypography.caption),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _PillButton(text: '+ 250 ml', color: fitWater, onTap: () => _water(250)),
              _PillButton(text: '+ 500 ml', color: fitWater, onTap: () => _water(500)),
              if (ml > 0) _PillButton(text: 'Undo', color: PhlioColors.textMuted, onTap: () => _water(-250)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _foodCard(Map d) {
    final eaten = (d['eaten'] as Map).cast<String, dynamic>();
    final goals = (d['goals'] as Map).cast<String, dynamic>();
    final meals = ((d['meals'] as List?) ?? const []).cast<Map>();
    final kcal = (eaten['kcal'] as num).toDouble();
    final goal = (goals['calories'] as num).toDouble();
    final burned = (d['burned_kcal'] as num).toDouble();
    final left = goal + burned - kcal;
    final macroTotal = math.max(1.0, (eaten['protein_g'] as num) * 4 + (eaten['carbs_g'] as num) * 4 + (eaten['fat_g'] as num) * 9);
    return FitCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.restaurant_rounded, color: fitCalories, size: 20),
          const SizedBox(width: 8),
          Text('Nutrition', style: PhlioTypography.title),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _logFood(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Log food'),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: _Big(value: fitNum(kcal), label: 'Eaten')),
          Expanded(child: _Big(value: fitNum(burned), label: 'Burned')),
          Expanded(child: _Big(value: fitNum(left.abs()), label: left >= 0 ? 'Left' : 'Over', color: left >= 0 ? fitSteps : PhlioColors.danger)),
        ]),
        const SizedBox(height: 14),
        // Macro split bar.
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 10,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (_, t, __) => Row(children: [
                for (final (g, factor, c) in [
                  (eaten['protein_g'] as num, 4, fitProtein),
                  (eaten['carbs_g'] as num, 4, fitCarbs),
                  (eaten['fat_g'] as num, 9, fitFat),
                ])
                  Expanded(flex: math.max(1, (g * factor / macroTotal * 1000 * t).round()), child: ColoredBox(color: kcal == 0 ? Colors.white10 : c)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          _Macro(label: 'Protein', grams: eaten['protein_g'] as num, color: fitProtein, goal: goals['protein_g'] as num?),
          _Macro(label: 'Carbs', grams: eaten['carbs_g'] as num, color: fitCarbs),
          _Macro(label: 'Fat', grams: eaten['fat_g'] as num, color: fitFat),
        ]),
        const SizedBox(height: 12),
        for (final meal in const ['breakfast', 'lunch', 'dinner', 'snack']) ...[
          Builder(builder: (_) {
            final items = meals.where((m) => m['meal'] == meal).toList();
            final total = items.fold<num>(0, (a, m) => a + (m['kcal'] as num));
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text(meal[0].toUpperCase() + meal.substring(1), style: PhlioTypography.bodyStrong),
                const SizedBox(width: 8),
                if (items.isNotEmpty) Text('${fitNum(total)} kcal', style: PhlioTypography.caption),
                const Spacer(),
                IconButton(
                  tooltip: 'Add to $meal',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _logFood(meal: meal),
                  icon: const Icon(Icons.add_rounded, size: 20),
                ),
              ]),
              for (final m in items)
                Dismissible(
                  key: ValueKey(m['id']),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _removeMeal(m),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    color: PhlioColors.danger.withValues(alpha: .2),
                    child: const Icon(Icons.delete_outline_rounded, color: PhlioColors.danger),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 8),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${m['name']}', style: PhlioTypography.body),
                          Text(
                            '${(m['servings'] as num) == 1 ? '' : '${m['servings']} × '}${m['serving'] ?? ''} · P ${m['protein_g']}g · C ${m['carbs_g']}g · F ${m['fat_g']}g',
                            style: PhlioTypography.caption,
                          ),
                        ]),
                      ),
                      Text('${fitNum(m['kcal'] as num)} kcal', style: PhlioTypography.label),
                    ]),
                  ),
                ),
            ]);
          }),
        ],
        if (meals.isNotEmpty)
          Text('Swipe a food left to remove it.', style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
      ]),
    );
  }

  Widget _activityCard(Map d) {
    final goal = ((d['goals'] as Map)['active_min'] as num).toDouble();
    final active = (d['active_min'] as num).toDouble();
    final move = (d['move'] as Map).cast<String, dynamic>();
    return FitCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MoveHomeScreen())),
      child: Row(children: [
        FitRing(
          value: active / goal,
          color: fitActive,
          size: 70,
          stroke: 8,
          child: const Icon(Icons.bolt_rounded, color: fitActive),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Active minutes', style: PhlioTypography.title),
            Text('${active.round()} of ${goal.round()} min', style: PhlioTypography.bodyStrong),
            Text(
              (move['count'] as num) > 0
                  ? '${move['count']} Phlio Move activit${move['count'] == 1 ? 'y' : 'ies'} · ${fitNum(move['kcal'] as num)} kcal'
                  : 'Record a run or workout in Phlio Move',
              style: PhlioTypography.caption,
            ),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: PhlioColors.textMuted),
      ]),
    );
  }
}

// -- Small pieces -----------------------------------------------------------------

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.text, required this.color, required this.onTap});
  final String text;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: .14),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ),
        ),
      );
}

class _Big extends StatelessWidget {
  const _Big({required this.value, required this.label, this.color});
  final String value, label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: PhlioTypography.title.copyWith(color: color ?? PhlioColors.textPrimary, fontSize: 22)),
        Text('$label kcal', style: PhlioTypography.caption),
      ]);
}

class _Macro extends StatelessWidget {
  const _Macro({required this.label, required this.grams, required this.color, this.goal});
  final String label;
  final num grams;
  final num? goal;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(
            child: Text('$label ${grams.round()}${goal != null ? '/${goal!.round()}' : ''} g',
                style: PhlioTypography.caption.copyWith(color: PhlioColors.textPrimary), overflow: TextOverflow.ellipsis),
          ),
        ]),
      );
}

/// A glass that fills with a gently moving wave.
class _WaterGlass extends StatefulWidget {
  const _WaterGlass({required this.fill});
  final double fill;

  @override
  State<_WaterGlass> createState() => _WaterGlassState();
}

class _WaterGlassState extends State<_WaterGlass> with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: widget.fill),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, level, __) => AnimatedBuilder(
          animation: _wave,
          builder: (_, __) => CustomPaint(size: const Size(70, 96), painter: _GlassPainter(level, _wave.value)),
        ),
      );
}

class _GlassPainter extends CustomPainter {
  _GlassPainter(this.level, this.phase);
  final double level, phase;

  @override
  void paint(Canvas canvas, Size s) {
    final glass = Path()
      ..moveTo(4, 2)
      ..lineTo(s.width - 4, 2)
      ..lineTo(s.width - 12, s.height - 4)
      ..quadraticBezierTo(s.width / 2, s.height + 2, 12, s.height - 4)
      ..close();
    canvas.save();
    canvas.clipPath(glass);
    canvas.drawRect(Offset.zero & s, Paint()..color = fitWater.withValues(alpha: .08));
    final top = s.height * (1 - level) + 2;
    final wave = Path()..moveTo(0, top);
    for (double x = 0; x <= s.width; x += 2) {
      wave.lineTo(x, top + math.sin((x / s.width * 2 * math.pi) + phase * 2 * math.pi) * (level > 0 && level < 1 ? 3 : 0));
    }
    wave
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(
        wave,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF9CC2FF), fitWater],
          ).createShader(Offset.zero & s));
    canvas.restore();
    canvas.drawPath(glass, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white.withValues(alpha: .35));
  }

  @override
  bool shouldRepaint(_GlassPainter old) => old.level != level || old.phase != phase;
}

class _GoalsSheet extends StatefulWidget {
  const _GoalsSheet({required this.goals});
  final Map<String, dynamic> goals;

  @override
  State<_GoalsSheet> createState() => _GoalsSheetState();
}

class _GoalsSheetState extends State<_GoalsSheet> {
  late final g = Map<String, dynamic>.from(widget.goals);
  bool _saving = false;

  Widget _slider(String key, String label, double min, double max, int divisions, String Function(num) fmt, Color color) {
    final v = ((g[key] as num?) ?? min).toDouble().clamp(min, max);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: PhlioTypography.bodyStrong),
        const Spacer(),
        Text(fmt(v), style: PhlioTypography.bodyStrong.copyWith(color: color)),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(activeTrackColor: color, thumbColor: color),
        child: Slider(value: v, min: min, max: max, divisions: divisions, onChanged: (x) => setState(() => g[key] = x.round())),
      ),
    ]);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final res = await fitDio.put('/fitness/goals', data: {
        for (final k in ['steps', 'water_ml', 'calories', 'active_min', 'protein_g']) k: g[k],
        if (g['weight_kg'] != null) 'weight_kg': g['weight_kg'],
        if (g['target_kg'] != null) 'target_kg': g['target_kg'],
      });
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(res.data as Map));
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: PhlioColors.textMuted.withValues(alpha: .5), borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 14),
            Text('Your goals', style: PhlioTypography.title),
            const SizedBox(height: 14),
            _slider('steps', 'Daily steps', 2000, 30000, 56, fitNum, fitSteps),
            _slider('water_ml', 'Water', 1000, 5000, 16, fitMl, fitWater),
            _slider('calories', 'Calories', 1200, 4500, 33, (v) => '${fitNum(v)} kcal', fitCalories),
            _slider('active_min', 'Active minutes', 10, 180, 34, (v) => '${v.round()} min', fitActive),
            _slider('protein_g', 'Protein', 30, 250, 44, (v) => '${v.round()} g', fitProtein),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  initialValue: g['weight_kg']?.toString() ?? '',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Weight (kg)'),
                  onChanged: (v) => g['weight_kg'] = double.tryParse(v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: g['target_kg']?.toString() ?? '',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Target (kg)'),
                  onChanged: (v) => g['target_kg'] = double.tryParse(v),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _saving ? null : _save,
              child: const Text('Save goals'),
            ),
          ]),
        ),
      );
}

/// A short, rule-based tip from today's numbers (no AI service involved).
String coachTip(Map d) {
  final g = (d['goals'] as Map).cast<String, dynamic>();
  final steps = (d['steps'] as num).toInt();
  final water = (d['water_ml'] as num).toInt();
  final kcal = ((d['eaten'] as Map)['kcal'] as num).toInt();
  final protein = ((d['eaten'] as Map)['protein_g'] as num).toInt();
  final stepGap = (g['steps'] as num).toInt() - steps;
  final waterGap = (g['water_ml'] as num).toInt() - water;
  if (waterGap > 1000) return 'You’re ${fitMl(waterGap)} short on water — two glasses now gets you well on the way.';
  if (stepGap > 2000) return '${fitNum(stepGap)} steps to your goal. A brisk ${((stepGap / 110).round())}-minute walk would close it.';
  if (kcal > 0 && protein < (g['protein_g'] as num) * .5) return 'Protein is at ${protein}g. Add eggs, paneer, dal or yogurt to your next meal.';
  if (kcal == 0) return 'Log your first meal so I can keep an eye on calories and macros.';
  if (stepGap <= 0) return 'Step goal done! Stretch for five minutes to help recovery.';
  return 'You’re on track today. Keep sipping water and stay moving.';
}
