// Phlio Fit in the profile dashboard (Foxy tab): pick a measure — steps,
// water, calories (eaten vs burned) or active minutes — and read the
// animated, tappable chart; averages, goal days and best day underneath.

import 'package:flutter/material.dart';

import '../../../design_system/colors.dart';
import '../../../features/phlio_agent/presentation/screens/fit/fit_api.dart';
import '../../../features/phlio_agent/presentation/screens/fit/fit_home_screen.dart';

class FitDashboardBlock extends StatefulWidget {
  const FitDashboardBlock({required this.fitness, super.key});
  final Map<String, dynamic> fitness;

  @override
  State<FitDashboardBlock> createState() => _FitDashboardBlockState();
}

class _FitDashboardBlockState extends State<FitDashboardBlock> {
  String _metric = 'steps';

  @override
  Widget build(BuildContext context) {
    final f = widget.fitness;
    final days = ((f['days'] as List?) ?? const []).cast<Map>();
    final goals = ((f['goals'] as Map?) ?? const {}).cast<String, dynamic>();
    final avg = ((f['averages'] as Map?) ?? const {}).cast<String, dynamic>();
    final labels = [for (final d in days) weekdayLabel('${d['date']}')];
    List<double> series(String k) => [for (final d in days) ((d[k] as num?) ?? 0).toDouble()];
    final chart = switch (_metric) {
      'water' => FitBarChart(
          key: const ValueKey('water'),
          values: series('water_ml'),
          labels: labels,
          color: fitWater,
          goal: (goals['water_ml'] as num?)?.toDouble(),
          format: (i) => fitMl(days[i]['water_ml'] as num),
        ),
      'calories' => FitBarChart(
          key: const ValueKey('calories'),
          values: series('eaten_kcal'),
          secondary: series('burned_kcal'),
          secondaryColor: fitActive,
          labels: labels,
          color: fitCalories,
          goal: (goals['calories'] as num?)?.toDouble(),
          format: (i) => '${fitNum(days[i]['eaten_kcal'] as num)} eaten · ${fitNum(days[i]['burned_kcal'] as num)} burned',
        ),
      'active' => FitBarChart(
          key: const ValueKey('active'),
          values: series('active_min'),
          labels: labels,
          color: fitActive,
          goal: (goals['active_min'] as num?)?.toDouble(),
          format: (i) => '${days[i]['active_min']} active min',
        ),
      _ => FitBarChart(
          key: const ValueKey('steps'),
          values: series('steps'),
          labels: labels,
          color: fitSteps,
          goal: (goals['steps'] as num?)?.toDouble(),
          format: (i) => '${fitNum(days[i]['steps'] as num)} steps',
        ),
    };
    Widget tile(String value, String label, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18))),
              Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PhlioColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: fitSteps.withValues(alpha: .16), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.favorite_rounded, color: fitSteps),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('Phlio Fit', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true)
                .push(MaterialPageRoute<void>(builder: (_) => const FitHomeScreen())),
            child: const Text('Open'),
          ),
        ]),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (id, label, color) in const [
              ('steps', 'Steps', fitSteps),
              ('water', 'Water', fitWater),
              ('calories', 'Calories', fitCalories),
              ('active', 'Active', fitActive),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  showCheckmark: false,
                  selected: _metric == id,
                  selectedColor: color.withValues(alpha: .22),
                  side: BorderSide(color: _metric == id ? color : PhlioColors.border),
                  label: Text(label, style: TextStyle(color: _metric == id ? color : Colors.white70, fontWeight: FontWeight.w700)),
                  onSelected: (_) => setState(() => _metric = id),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(position: Tween(begin: const Offset(.04, 0), end: Offset.zero).animate(a), child: c),
          ),
          child: chart,
        ),
        if (_metric == 'calories')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(children: [
              _Legend(color: fitCalories, text: 'Eaten'),
              SizedBox(width: 14),
              _Legend(color: fitActive, text: 'Burned'),
            ]),
          ),
        const SizedBox(height: 14),
        Row(children: [
          tile(fitNum((avg['steps'] as num?) ?? 0), 'Avg steps', fitSteps),
          const SizedBox(width: 8),
          tile('${f['step_goal_days'] ?? 0}/${days.length}', 'Step goal days', fitActive),
          const SizedBox(width: 8),
          tile(fitMl((avg['water_ml'] as num?) ?? 0), 'Avg water', fitWater),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          tile(fitNum((f['best_steps'] as num?) ?? 0), 'Best day (steps)', fitSteps),
          const SizedBox(width: 8),
          tile(fitNum((avg['eaten_kcal'] as num?) ?? 0), 'Avg kcal eaten', fitCalories),
          const SizedBox(width: 8),
          tile(fitNum((avg['burned_kcal'] as num?) ?? 0), 'Avg kcal burned', fitActive),
        ]),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]);
}
