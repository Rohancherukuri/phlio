// Build your Phlio avatar (like Bitmoji): a live, shader-lit preview on top
// and a tab per part underneath — Skin, Face, Hair, Eyes, Brows, Mouth,
// Beard, Glasses, Outfit, Extras, Background. Save stores it on your
// account; it then shows up as the Avatar sticker in Moments and snaps.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'avatar_figure.dart';

Future<AvatarConfig?> openAvatarBuilder(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push<AvatarConfig>(MaterialPageRoute(builder: (_) => const AvatarBuilderScreen(), fullscreenDialog: true));

class AvatarBuilderScreen extends ConsumerStatefulWidget {
  const AvatarBuilderScreen({super.key});

  @override
  ConsumerState<AvatarBuilderScreen> createState() => _AvatarBuilderScreenState();
}

class _Tab {
  const _Tab(this.label, this.icon, {this.option, this.color, this.palette});
  final String label;
  final IconData icon;
  final String? option; // key in avatarOptions
  final String? color; // colour key
  final List<Color>? palette;
}

const _tabs = [
  _Tab('Skin', Icons.face_rounded, color: 'skin', palette: avatarSkinTones),
  _Tab('Face', Icons.face_6_rounded, option: 'face'),
  _Tab('Hair', Icons.content_cut_rounded, option: 'hair', color: 'hair_color', palette: avatarHairColors),
  _Tab('Eyes', Icons.visibility_rounded, option: 'eyes', color: 'eye_color', palette: avatarEyeColors),
  _Tab('Brows', Icons.remove_rounded, option: 'brows'),
  _Tab('Mouth', Icons.sentiment_satisfied_rounded, option: 'mouth'),
  _Tab('Beard', Icons.face_retouching_natural_rounded, option: 'beard'),
  _Tab('Glasses', Icons.visibility_outlined, option: 'glasses'),
  _Tab('Outfit', Icons.checkroom_rounded, option: 'top', color: 'top_color', palette: avatarClothColors),
  _Tab('Extras', Icons.auto_awesome_rounded, option: 'accessory'),
  _Tab('Background', Icons.wallpaper_rounded, option: 'background'),
];

String _label(String v) => v == 'none'
    ? 'None'
    : v.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');

class _AvatarBuilderScreenState extends ConsumerState<AvatarBuilderScreen> {
  AvatarConfig? cfg;
  int tab = 0;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    ref.read(myAvatarProvider.future).then((value) {
      if (mounted) setState(() => cfg = value ?? AvatarConfig(null));
    }, onError: (_) {
      if (mounted) setState(() => cfg = AvatarConfig(null));
    });
  }

  void _set(String key, Object value) {
    HapticFeedback.selectionClick();
    setState(() => cfg = cfg!.copyWith(key, value));
  }

  void _shuffle() {
    final r = math.Random();
    var next = cfg!;
    T pick<T>(List<T> l) => l[r.nextInt(l.length)];
    for (final e in avatarOptions.entries) {
      if (e.key == 'background') continue;
      next = next.copyWith(e.key, pick(e.value));
    }
    next = next
        .copyWith('skin', hexOf(pick(avatarSkinTones)))
        .copyWith('hair_color', hexOf(pick(avatarHairColors.take(7).toList())))
        .copyWith('top_color', hexOf(pick(avatarClothColors)));
    HapticFeedback.mediumImpact();
    setState(() => cfg = next);
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await saveMyAvatar(cfg!);
      ref.invalidate(myAvatarProvider);
      if (mounted) Navigator.pop(context, cfg);
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save your avatar. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = cfg;
    return Scaffold(
      backgroundColor: const Color(0xFF0E1118),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1118),
        title: const Text('Your avatar'),
        actions: [
          IconButton(tooltip: 'Surprise me', icon: const Icon(Icons.casino_outlined), onPressed: c == null ? null : _shuffle),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              onPressed: c == null || saving ? null : _save,
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(
                flex: 5,
                child: Center(child: AvatarFigure(config: c, size: 230)),
              ),
              SizedBox(
                height: 64,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: _tabs.length,
                  itemBuilder: (_, i) {
                    final t = _tabs[i];
                    final on = i == tab;
                    return GestureDetector(
                      onTap: () => setState(() => tab = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 68,
                        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                        decoration: BoxDecoration(
                          color: on ? const Color(0xFF8D78FF) : const Color(0xFF1C212B),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(t.icon, color: Colors.white, size: 20),
                          const SizedBox(height: 2),
                          Text(t.label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              Expanded(flex: 4, child: _panel(c, _tabs[tab])),
            ]),
    );
  }

  Widget _panel(AvatarConfig c, _Tab t) {
    return ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 20), children: [
      if (t.palette != null) ...[
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final color in t.palette!)
            GestureDetector(
              onTap: () => _set(t.color!, hexOf(color)),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: c.s(t.color!).toUpperCase() == hexOf(color) ? Colors.white : Colors.white24,
                      width: c.s(t.color!).toUpperCase() == hexOf(color) ? 3 : 1),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 14),
      ],
      if (t.label == 'Skin') ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: c.blush,
          onChanged: (v) => _set('blush', v),
          title: const Text('Blush', style: TextStyle(color: Colors.white)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: c.freckles,
          onChanged: (v) => _set('freckles', v),
          title: const Text('Freckles', style: TextStyle(color: Colors.white)),
        ),
      ],
      if (t.option != null)
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .78,
          children: [
            for (final value in avatarOptions[t.option]!)
              GestureDetector(
                onTap: () => _set(t.option!, value),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C212B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: c.s(t.option!) == value ? const Color(0xFF8D78FF) : Colors.transparent, width: 2.5),
                  ),
                  child: Column(children: [
                    // A small, still preview with this choice.
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: FittedBox(
                          child: AvatarFigure(
                              config: c.copyWith(t.option!, value), size: 90, animate: false, background: t.option == 'background'),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(_label(value), style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                    ),
                  ]),
                ),
              ),
          ],
        ),
    ]);
  }
}
