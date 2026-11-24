// Foxy Coach — the AI fitness coach, as a UI preview.
//
// No AI service is called. Replies are short, rule-based summaries of the
// numbers already on this phone (today's steps, water, food and goals) and
// are labelled as a preview, so nobody mistakes them for advice from a model.


import 'package:flutter/material.dart';

import 'package:phlio/design_system/colors.dart';
import 'package:phlio/design_system/typography.dart';
import 'package:phlio/design_system/widgets/foxy_puppet.dart';

import 'fit_api.dart';
import 'fit_home_screen.dart' show coachTip;

class FitCoachScreen extends StatefulWidget {
  const FitCoachScreen({required this.day, super.key});
  final Map day;

  @override
  State<FitCoachScreen> createState() => _FitCoachScreenState();
}

class _Msg {
  _Msg(this.text, {this.me = false});
  final String text;
  final bool me;
}

class _FitCoachScreenState extends State<FitCoachScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _typing = false;

  static const _prompts = [
    'How am I doing today?',
    'Plan a meal to hit my protein',
    'How much water should I drink?',
    'Give me a 20-minute workout',
  ];

  @override
  void initState() {
    super.initState();
    _msgs.add(_Msg('Hi! I’m Foxy. ${coachTip(widget.day)}'));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _reply(String q) {
    final d = widget.day;
    final g = (d['goals'] as Map).cast<String, dynamic>();
    final e = (d['eaten'] as Map).cast<String, dynamic>();
    final low = q.toLowerCase();
    if (low.contains('water')) {
      return 'Your goal is ${fitMl(g['water_ml'] as num)} and you’ve had ${fitMl(d['water_ml'] as num)}. '
          'Spread the rest over the day — a glass with every meal and one after any workout.';
    }
    if (low.contains('protein') || low.contains('meal') || low.contains('eat')) {
      final gap = (g['protein_g'] as num) - (e['protein_g'] as num);
      return gap > 0
          ? 'You need about ${gap.round()} g more protein today. Ideas: 2 boiled eggs (12 g), a bowl of dal (10 g), '
              '100 g paneer (18 g) or Greek yogurt (17 g).'
          : 'Protein goal met — nice. Keep the next meal light with vegetables and some whole grains.';
    }
    if (low.contains('workout') || low.contains('exercise') || low.contains('train')) {
      return 'A quick 20-minute circuit: 3 rounds of 10 squats, 10 push-ups (knees are fine), 20 s plank, '
          '15 glute bridges and 30 s of jumping jacks. Rest 1 minute between rounds. Record it in Phlio Move!';
    }
    return 'Today: ${fitNum(d['steps'] as num)} of ${fitNum(g['steps'] as num)} steps, '
        '${fitMl(d['water_ml'] as num)} of ${fitMl(g['water_ml'] as num)} water and '
        '${fitNum(e['kcal'] as num)} of ${fitNum(g['calories'] as num)} kcal. ${coachTip(d)}';
  }

  Future<void> _send(String text) async {
    final q = text.trim();
    if (q.isEmpty || _typing) return;
    _input.clear();
    setState(() {
      _msgs.add(_Msg(q, me: true));
      _typing = true;
    });
    _toEnd();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _typing = false;
      _msgs.add(_Msg(_reply(q)));
    });
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent + 80, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Foxy Coach'),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(8)),
            child: Text('PREVIEW', style: PhlioTypography.caption.copyWith(fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: PhlioColors.surfaceInput, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: PhlioColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text('AI coaching isn’t connected yet. Foxy answers from your Phlio Fit numbers only, and this isn’t medical advice.',
                  style: PhlioTypography.caption),
            ),
          ]),
        ),
        Expanded(
          child: ListView(controller: _scroll, padding: const EdgeInsets.all(16), children: [
            const Center(child: FoxyPuppet(act: FoxyAct.wave, size: 110)),
            const SizedBox(height: 8),
            for (final (i, m) in _msgs.indexed)
              TweenAnimationBuilder<double>(
                key: ValueKey(i),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                builder: (_, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: c)),
                child: Align(
                  alignment: m.me ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: m.me ? PhlioColors.sunsetGradient : null,
                      color: m.me ? null : PhlioColors.surface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(m.text,
                        style: PhlioTypography.body.copyWith(color: m.me ? PhlioColors.textOnBrand : PhlioColors.textPrimary, height: 1.4)),
                  ),
                ),
              ),
            if (_typing)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.circular(18)),
                  child: const _Dots(),
                ),
              ),
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final p in _prompts)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ActionChip(label: Text(p), onPressed: () => _send(p)),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: const InputDecoration(hintText: 'Ask Foxy about your day…'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: () => _send(_input.text), icon: const Icon(Icons.arrow_upward_rounded)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Dots extends StatefulWidget {
  const _Dots();

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .3 + .7 * (((_c.value * 3 - i) % 3) < 1 ? 1 : 0)),
              ),
            ),
        ]),
      );
}
