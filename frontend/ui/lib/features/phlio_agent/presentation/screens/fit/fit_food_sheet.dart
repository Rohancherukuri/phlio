// Phlio Fit — log food: search the built-in list or add your own, choose
// the meal and servings, see calories and macros, then "Add to log".
// "Snap a meal" shows the AI food-scan flow as a UI preview only: no image
// is sent anywhere and nothing is recognised automatically yet.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:phlio/design_system/colors.dart';
import 'package:phlio/design_system/typography.dart';

import 'fit_api.dart';

/// Returns the updated day (from the server) when something was logged.
Future<Map<String, dynamic>?> showFoodLogSheet(BuildContext context, {required DateTime date, String? meal}) =>
    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FoodSheet(date: date, meal: meal),
    );

String _mealFor(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 11) return 'breakfast';
  if (h >= 11 && h < 16) return 'lunch';
  if (h >= 18 && h < 23) return 'dinner';
  return 'snack';
}

class _FoodSheet extends StatefulWidget {
  const _FoodSheet({required this.date, this.meal});
  final DateTime date;
  final String? meal;

  @override
  State<_FoodSheet> createState() => _FoodSheetState();
}

class _FoodSheetState extends State<_FoodSheet> {
  late String _meal = widget.meal ?? _mealFor(DateTime.now());
  List<Map> _results = [];
  Map? _picked;
  double _servings = 1;
  bool _custom = false, _saving = false;
  String? _photo;
  Timer? _debounce;
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _p = TextEditingController();
  final _c = TextEditingController();
  final _f = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_name, _kcal, _p, _c, _f]) {
      c.dispose();
    }
    super.dispose();
  }

  void _query(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _search(q));
  }

  Future<void> _search(String q) async {
    try {
      final r = await fitDio.get('/fitness/foods', queryParameters: {'q': q});
      if (mounted) setState(() => _results = ((r.data as Map)['items'] as List).cast<Map>());
    } catch (_) {}
  }

  Map<String, dynamic>? get _item {
    if (_custom) {
      final kcal = double.tryParse(_kcal.text);
      if (_name.text.trim().isEmpty || kcal == null) return null;
      return {
        'name': _name.text.trim(),
        'kcal': kcal,
        'protein_g': double.tryParse(_p.text) ?? 0,
        'carbs_g': double.tryParse(_c.text) ?? 0,
        'fat_g': double.tryParse(_f.text) ?? 0,
        'serving': '1 serving',
      };
    }
    return _picked == null ? null : Map<String, dynamic>.from(_picked!);
  }

  Future<void> _save() async {
    final item = _item;
    if (item == null) return;
    setState(() => _saving = true);
    try {
      final r = await fitDio.post('/fitness/meals', data: {
        ...item,
        'meal': _meal,
        'servings': _servings,
        'date': fitYmd(widget.date),
      });
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(r.data as Map));
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _snap() async {
    final shot = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1400, imageQuality: 80);
    if (shot == null || !mounted) return;
    setState(() => _photo = shot.path);
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => _ScanPreview(path: shot.path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final k = item == null ? 0.0 : (item['kcal'] as num) * _servings;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .92,
      maxChildSize: .96,
      builder: (_, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: PhlioColors.textMuted.withValues(alpha: .5), borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              Expanded(child: Text('Log food', textAlign: TextAlign.center, style: PhlioTypography.title)),
              IconButton(
                tooltip: _custom ? 'Search foods' : 'Add your own',
                onPressed: () => setState(() => _custom = !_custom),
                icon: Icon(_custom ? Icons.search_rounded : Icons.edit_note_rounded),
              ),
            ]),
          ),
          Expanded(
            child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
              // Photo strip with the snap button (AI preview).
              SizedBox(
                height: 92,
                child: Row(children: [
                  if (_photo != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.file(File(_photo!), width: 92, height: 92, fit: BoxFit.cover),
                      ),
                    ),
                  InkWell(
                    onTap: _snap,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: PhlioColors.border),
                        color: PhlioColors.surfaceInput,
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.photo_camera_rounded, color: fitCalories),
                        const SizedBox(height: 4),
                        Text('Snap a meal', style: PhlioTypography.caption),
                      ]),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'breakfast', label: Text('Breakfast')),
                  ButtonSegment(value: 'lunch', label: Text('Lunch')),
                  ButtonSegment(value: 'dinner', label: Text('Dinner')),
                  ButtonSegment(value: 'snack', label: Text('Snack')),
                ],
                selected: {_meal},
                onSelectionChanged: (v) => setState(() => _meal = v.first),
              ),
              const SizedBox(height: 14),
              if (_custom) ...[
                TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Food name')),
                const SizedBox(height: 10),
                TextField(
                  controller: _kcal,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Calories per serving (kcal)'),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  for (final (c, l) in [(_p, 'Protein g'), (_c, 'Carbs g'), (_f, 'Fat g')]) ...[
                    Expanded(
                      child: TextField(
                        controller: c,
                        onChanged: (_) => setState(() {}),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: l),
                      ),
                    ),
                    if (l != 'Fat g') const SizedBox(width: 8),
                  ],
                ]),
              ] else ...[
                TextField(
                  onChanged: _query,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search idli, dal, eggs, coffee…'),
                ),
                const SizedBox(height: 8),
                for (final f in _results)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: identical(f, _picked) ? fitCalories.withValues(alpha: .12) : PhlioColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: identical(f, _picked) ? fitCalories : Colors.white.withValues(alpha: .06)),
                    ),
                    child: ListTile(
                      onTap: () => setState(() {
                        _picked = f;
                        _servings = 1;
                      }),
                      title: Text('${f['name']}', style: PhlioTypography.bodyStrong),
                      subtitle: Text('${f['serving']} · ${fitNum(f['kcal'] as num)} kcal', style: PhlioTypography.caption),
                      trailing: identical(f, _picked) ? const Icon(Icons.check_circle_rounded, color: fitCalories) : null,
                    ),
                  ),
              ],
            ]),
          ),
          // Totals + servings + add.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: item == null
                ? const SizedBox(width: double.infinity)
                : Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.circular(20)),
                    child: Column(children: [
                      Row(children: [
                        Expanded(child: Text('${item['name']}', style: PhlioTypography.bodyStrong, overflow: TextOverflow.ellipsis)),
                        IconButton(
                          onPressed: _servings > .5 ? () => setState(() => _servings -= .5) : null,
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                        ),
                        Text('${_servings % 1 == 0 ? _servings.round() : _servings} ×', style: PhlioTypography.bodyStrong),
                        IconButton(
                          onPressed: _servings < 20 ? () => setState(() => _servings += .5) : null,
                          icon: const Icon(Icons.add_circle_outline_rounded),
                        ),
                      ]),
                      Row(children: [
                        const Icon(Icons.local_fire_department_rounded, color: fitCalories, size: 18),
                        const SizedBox(width: 4),
                        Text('${fitNum(k)} kcal', style: PhlioTypography.title),
                        const Spacer(),
                        for (final (key, c) in [('protein_g', fitProtein), ('carbs_g', fitCarbs), ('fat_g', fitFat)])
                          Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Text('${((item[key] as num) * _servings).toStringAsFixed(0)} g',
                                style: TextStyle(color: c, fontWeight: FontWeight.w700)),
                          ),
                      ]),
                    ]),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: item == null || _saving ? null : _save,
                child: Text(_saving ? 'Adding…' : 'Add to log'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The food-scan screen as a preview: the photo with a scanning sweep and
/// an honest note that automatic recognition isn't switched on yet.
class _ScanPreview extends StatefulWidget {
  const _ScanPreview({required this.path});
  final String path;

  @override
  State<_ScanPreview> createState() => _ScanPreviewState();
}

class _ScanPreviewState extends State<_ScanPreview> with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: 220,
                height: 220,
                child: Stack(fit: StackFit.expand, children: [
                  Image.file(File(widget.path), fit: BoxFit.cover),
                  // Grid + sweep.
                  CustomPaint(painter: _GridPainter()),
                  AnimatedBuilder(
                    animation: _scan,
                    builder: (_, __) => Align(
                      alignment: Alignment(0, -1 + 2 * _scan.value),
                      child: Container(
                        height: 3,
                        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, fitCalories, Colors.transparent])),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            Text('Food scan is coming soon', style: PhlioTypography.title, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Foxy will recognise what’s on your plate and fill in calories for you. For now your photo stays on this phone — pick the foods from the list.',
              textAlign: TextAlign.center,
              style: PhlioTypography.body.copyWith(color: PhlioColors.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ]),
        ),
      );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: .28)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(s.width * i / 4, 0), Offset(s.width * i / 4, s.height), p);
      canvas.drawLine(Offset(0, s.height * i / 4), Offset(s.width, s.height * i / 4), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
