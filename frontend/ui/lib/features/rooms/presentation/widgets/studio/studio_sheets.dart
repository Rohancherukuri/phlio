// Phlio Studio panels and sheets added for CapCut parity: speed curves,
// voice effects, blend / mask / chroma key for overlay media, text
// animation (in / out / loop), sound effects, text to audio, auto-caption
// editing, export settings and the cover picker.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../app/config/app_config.dart';
import '../../../../../design_system/colors.dart';
import 'studio_model.dart';
import 'studio_panels.dart';

const _card = Color(0xFF1C2433);
const _sheet = Color(0xFF111722);

// -- small shared pieces ---------------------------------------------------------------

class StudioTabs extends StatelessWidget {
  const StudioTabs({required this.tabs, required this.selected, required this.onPick, super.key});
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onPick;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 34,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < tabs.length; i++)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onPick(i);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(tabs[i],
                      style: TextStyle(
                          color: i == selected ? Colors.white : Colors.white54,
                          fontWeight: i == selected ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 13.5)),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: i == selected ? 18 : 0,
                    height: 3,
                    decoration: BoxDecoration(
                        gradient: PhlioColors.sunsetGradient, borderRadius: BorderRadius.circular(2)),
                  ),
                ]),
              ),
            ),
        ]),
      );
}

class StudioSwitchRow extends StatelessWidget {
  const StudioSwitchRow({required this.label, required this.value, required this.onChanged, super.key});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13.5))),
          Switch.adaptive(
            value: value,
            activeTrackColor: studioViolet,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ]),
      );
}

// -- speed: Normal / Curve -------------------------------------------------------------

class StudioSpeedTabs extends StatefulWidget {
  const StudioSpeedTabs({
    required this.clip,
    required this.onSpeed,
    required this.onCurve,
    required this.onCommit,
    super.key,
  });
  final StudioClip clip;
  final ValueChanged<double> onSpeed;
  final ValueChanged<String?> onCurve;
  final VoidCallback onCommit;
  @override
  State<StudioSpeedTabs> createState() => _StudioSpeedTabsState();
}

class _StudioSpeedTabsState extends State<StudioSpeedTabs> {
  late int tab = widget.clip.hasCurve ? 1 : 0;
  @override
  Widget build(BuildContext context) {
    final c = widget.clip;
    return Column(children: [
      StudioTabs(tabs: const ['Normal', 'Curve'], selected: tab, onPick: (i) => setState(() => tab = i)),
      Expanded(
        child: tab == 0
            ? StudioSpeedPanel(
                speed: c.speed,
                onChanged: (v) {
                  if (c.hasCurve) widget.onCurve(null);
                  widget.onSpeed(v);
                },
                onCommit: widget.onCommit)
            : c.kind != 'video' || c.hold != null
                ? const Center(
                    child: Text('Speed curves work on video clips',
                        style: TextStyle(color: Colors.white54)))
                : ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      _CurveTile(id: null, label: 'None', on: !c.hasCurve, onTap: () => widget.onCurve(null)),
                      for (final (id, label) in studioCurveNames)
                        _CurveTile(
                            id: id, label: label, on: c.curveName == id, onTap: () => widget.onCurve(id)),
                    ],
                  ),
      ),
      if (tab == 1 && c.hasCurve)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Duration ${c.length.toStringAsFixed(1)}s · source ${(c.end - c.start).toStringAsFixed(1)}s',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
    ]);
  }
}

class _CurveTile extends StatelessWidget {
  const _CurveTile({required this.id, required this.label, required this.on, required this.onTap});
  final String? id, label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 64,
              height: 52,
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: on ? Colors.white : Colors.transparent, width: 2),
              ),
              child: id == null
                  ? const Icon(Icons.block_rounded, color: Colors.white54)
                  : CustomPaint(painter: _CurvePainter(studioCurvePoints[id]!)),
            ),
            const SizedBox(height: 5),
            Text(label!, style: TextStyle(color: on ? Colors.white : Colors.white60, fontSize: 11)),
          ]),
        ),
      );
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.points);
  final List<(double, double)> points;
  @override
  void paint(Canvas canvas, Size size) {
    double y(double s) => size.height - 8 - (math.log(s) / math.ln10 + 1) / 2 * (size.height - 16);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final (x, s) = points[i];
      final pt = Offset(8 + x * (size.width - 16), y(s));
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawLine(Offset(6, y(1)), Offset(size.width - 6, y(1)), Paint()..color = Colors.white12);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..shader = PhlioColors.sunsetGradient.createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(_CurvePainter old) => false;
}

// -- voice effects -------------------------------------------------------------------

class StudioVoicePanel extends StatelessWidget {
  const StudioVoicePanel(
      {required this.voice, required this.denoise, required this.onVoice, required this.onDenoise, super.key});
  final String voice;
  final bool denoise;
  final ValueChanged<String> onVoice;
  final ValueChanged<bool> onDenoise;
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
          child: StudioOptionStrip(
            tile: 52,
            options: studioVoices,
            selected: voice,
            icon: (id, on) => Icon(
              switch (id) {
                'none' => Icons.block_rounded,
                'chipmunk' => Icons.pets_rounded,
                'deep' => Icons.graphic_eq_rounded,
                'robot' => Icons.smart_toy_outlined,
                'echo' || 'hall' => Icons.surround_sound_outlined,
                'radio' => Icons.radio_outlined,
                'megaphone' => Icons.campaign_outlined,
                _ => Icons.waves_rounded,
              },
              color: on ? Colors.white : Colors.white60,
            ),
            onPick: onVoice,
          ),
        ),
        StudioSwitchRow(label: 'Reduce noise', value: denoise, onChanged: onDenoise),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Text('Voice effects and noise reduction are applied when you export.',
              style: TextStyle(color: Colors.white38, fontSize: 11.5)),
        ),
      ]);
}

// -- overlay media: blend, mask, chroma key ---------------------------------------------

class StudioBlendPanel extends StatelessWidget {
  const StudioBlendPanel({required this.pip, required this.onChanged, required this.onCommit, super.key});
  final StudioPip pip;
  final void Function(VoidCallback fn) onChanged;
  final VoidCallback onCommit;
  @override
  Widget build(BuildContext context) => Column(children: [
        StudioSlider(
          label: 'Opacity',
          value: pip.opacity,
          min: 0,
          max: 1,
          onChanged: (v) => onChanged(() => pip.opacity = v),
          onChangeEnd: (_) => onCommit(),
          format: (v) => '${(v * 100).round()}',
        ),
        Expanded(
          child: StudioOptionStrip(
            tile: 50,
            options: studioBlends,
            selected: pip.blend,
            icon: (id, on) => _BlendSwatch(id: id, on: on),
            onPick: (v) => onChanged(() => pip.blend = v),
          ),
        ),
        if (pip.blend != 'normal')
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('Blend modes preview as opacity here; the export blends exactly.',
                style: TextStyle(color: Colors.white38, fontSize: 11.5)),
          ),
      ]);
}

class _BlendSwatch extends StatelessWidget {
  const _BlendSwatch({required this.id, required this.on});
  final String id;
  final bool on;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 30,
        height: 30,
        child: Stack(children: [
          Positioned(
              left: 0,
              top: 0,
              child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(color: PhlioColors.brandViolet, shape: BoxShape.circle))),
          Positioned(
            right: 0,
            bottom: 0,
            child: Opacity(
              opacity: id == 'normal' ? 1 : .7,
              child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(color: PhlioColors.brandPeach, shape: BoxShape.circle)),
            ),
          ),
        ]),
      );
}

class StudioMaskPanel extends StatelessWidget {
  const StudioMaskPanel({required this.pip, required this.onChanged, required this.onCommit, super.key});
  final StudioPip pip;
  final void Function(VoidCallback fn) onChanged;
  final VoidCallback onCommit;
  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
          height: 84,
          child: StudioOptionStrip(
            tile: 48,
            options: studioMasks,
            selected: pip.mask,
            icon: (id, on) => Icon(
              switch (id) {
                'none' => Icons.block_rounded,
                'linear' => Icons.horizontal_rule_rounded,
                'mirror' => Icons.drag_handle_rounded,
                'circle' => Icons.circle_outlined,
                'rect' => Icons.crop_square_rounded,
                'heart' => Icons.favorite_border_rounded,
                _ => Icons.star_border_rounded,
              },
              color: on ? Colors.white : Colors.white60,
            ),
            onPick: (v) => onChanged(() => pip.mask = v),
          ),
        ),
        if (pip.mask != 'none') ...[
          StudioSlider(
            label: pip.mask == 'linear' ? 'Position' : 'Size',
            value: pip.maskSize,
            min: .05,
            max: 1.2,
            onChanged: (v) => onChanged(() => pip.maskSize = v),
            onChangeEnd: (_) => onCommit(),
            format: (v) => '${(v * 100).round()}',
          ),
          StudioSlider(
            label: 'Feather',
            value: pip.maskFeather,
            min: 0,
            max: 1,
            onChanged: (v) => onChanged(() => pip.maskFeather = v),
            onChangeEnd: (_) => onCommit(),
            format: (v) => '${(v * 100).round()}',
          ),
          StudioSlider(
            label: 'Rotate',
            value: pip.maskRotation,
            min: -math.pi,
            max: math.pi,
            onChanged: (v) => onChanged(() => pip.maskRotation = v),
            onChangeEnd: (_) => onCommit(),
            format: (v) => '${(v * 180 / math.pi).round()}°',
          ),
          StudioSwitchRow(
              label: 'Invert', value: pip.maskInvert, onChanged: (v) => onChanged(() => pip.maskInvert = v)),
        ],
      ]);
}

class StudioChromaPanel extends StatelessWidget {
  const StudioChromaPanel({required this.pip, required this.onChanged, required this.onCommit, super.key});
  final StudioPip pip;
  final void Function(VoidCallback fn) onChanged;
  final VoidCallback onCommit;
  static const keys = [
    (0xFF00FF00, 'Green'),
    (0xFF00B140, 'Studio green'),
    (0xFF0047BB, 'Blue'),
    (0xFF000000, 'Black'),
    (0xFFFFFFFF, 'White'),
    (0xFFFF00FF, 'Magenta'),
  ];
  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
          height: 78,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _ChromaChip(
                  color: null,
                  label: 'Off',
                  on: pip.chroma == null,
                  onTap: () => onChanged(() => pip.chroma = null)),
              for (final (c, label) in keys)
                _ChromaChip(color: c, label: label, on: pip.chroma == c, onTap: () => onChanged(() => pip.chroma = c)),
            ],
          ),
        ),
        if (pip.chroma != null) ...[
          StudioSlider(
            label: 'Intensity',
            value: pip.chromaStrength,
            min: .01,
            max: 1,
            onChanged: (v) => onChanged(() => pip.chromaStrength = v),
            onChangeEnd: (_) => onCommit(),
            format: (v) => '${(v * 100).round()}',
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 2, 18, 0),
            child: Text('The keyed colour is removed in the export.',
                style: TextStyle(color: Colors.white38, fontSize: 11.5)),
          ),
        ],
      ]);
}

class _ChromaChip extends StatelessWidget {
  const _ChromaChip({required this.color, required this.label, required this.on, required this.onTap});
  final int? color;
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color == null ? _card : Color(color!),
                shape: BoxShape.circle,
                border: Border.all(color: on ? Colors.white : Colors.white24, width: on ? 3 : 1),
              ),
              child: color == null ? const Icon(Icons.block_rounded, color: Colors.white54, size: 18) : null,
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: on ? Colors.white : Colors.white54, fontSize: 10.5)),
          ]),
        ),
      );
}

// -- text animation: In / Out / Loop ---------------------------------------------------

class StudioTextAnimPanel extends StatefulWidget {
  const StudioTextAnimPanel({required this.overlay, required this.onChanged, super.key});
  final StudioOverlay overlay;
  final void Function(VoidCallback fn) onChanged;
  @override
  State<StudioTextAnimPanel> createState() => _StudioTextAnimPanelState();
}

class _StudioTextAnimPanelState extends State<StudioTextAnimPanel> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final o = widget.overlay;
    final (options, selected, apply) = switch (tab) {
      0 => (
          const [
            ('none', 'None'),
            ('fade', 'Fade in'),
            ('slide_up', 'Rise'),
            ('slide_left', 'Slide'),
            ('pop', 'Pop'),
            ('drop', 'Drop'),
          ],
          o.animIn,
          (String v) => o.animIn = v,
        ),
      1 => (
          const [('none', 'None'), ('fade', 'Fade out'), ('slide_down', 'Sink'), ('shrink', 'Shrink')],
          o.animOut,
          (String v) => o.animOut = v,
        ),
      _ => (studioLoops, o.loop, (String v) => o.loop = v),
    };
    return Column(children: [
      StudioTabs(tabs: const ['In', 'Out', 'Loop'], selected: tab, onPick: (i) => setState(() => tab = i)),
      Expanded(
        child: StudioOptionStrip(
          tile: 52,
          options: options,
          selected: selected,
          icon: (id, on) => Icon(
            switch (id) {
              'none' => Icons.block_rounded,
              'fade' => Icons.gradient_rounded,
              'slide_up' => Icons.north_rounded,
              'slide_left' => Icons.west_rounded,
              'slide_down' => Icons.south_rounded,
              'pop' || 'pulse' => Icons.bubble_chart_outlined,
              'drop' => Icons.vertical_align_bottom_rounded,
              'shrink' => Icons.close_fullscreen_rounded,
              'bounce' => Icons.sports_basketball_outlined,
              'wiggle' => Icons.waving_hand_outlined,
              'float' => Icons.air_rounded,
              _ => Icons.flash_on_rounded,
            },
            color: on ? Colors.white : Colors.white60,
          ),
          onPick: (v) => widget.onChanged(() => apply(v)),
        ),
      ),
    ]);
  }
}

// -- sound effects --------------------------------------------------------------------

typedef StudioSound = ({String id, String name, String category, double duration, String url});

Future<StudioSound?> showStudioSounds(BuildContext context, Dio dio) =>
    showModalBottomSheet<StudioSound>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(heightFactor: .62, child: _SoundsSheet(dio: dio)),
    );

class _SoundsSheet extends StatefulWidget {
  const _SoundsSheet({required this.dio});
  final Dio dio;
  @override
  State<_SoundsSheet> createState() => _SoundsSheetState();
}

class _SoundsSheetState extends State<_SoundsSheet> {
  List<StudioSound>? items;
  String? error, playing, category;
  final player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    widget.dio.get('/messaging/studio/sounds').then((r) {
      final list = ((r.data as Map)['items'] as List).cast<Map>();
      if (mounted) {
        setState(() => items = [
              for (final m in list)
                (
                  id: '${m['id']}',
                  name: '${m['name']}',
                  category: '${m['category']}',
                  duration: (m['duration'] as num).toDouble(),
                  url: '${m['url']}',
                )
            ]);
      }
    }).catchError((Object _) {
      if (mounted) setState(() => error = 'Sound effects are unavailable right now.');
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> _preview(StudioSound s) async {
    HapticFeedback.selectionClick();
    if (playing == s.id) {
      await player.stop();
      setState(() => playing = null);
      return;
    }
    setState(() => playing = s.id);
    await player.stop();
    await player.play(UrlSource(AppConfig.mediaUrl(s.url)));
    player.onPlayerComplete.first.then((_) {
      if (mounted && playing == s.id) setState(() => playing = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = items;
    final cats = {for (final s in all ?? const <StudioSound>[]) s.category}.toList();
    final shown = [for (final s in all ?? const <StudioSound>[]) if (category == null || s.category == category) s];
    return Column(children: [
      const Text('Sound effects', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final c in [null, ...cats])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(c ?? 'All'),
                  selected: category == c,
                  onSelected: (_) => setState(() => category = c),
                  backgroundColor: _card,
                  selectedColor: Colors.white,
                  labelStyle: TextStyle(
                      color: category == c ? const Color(0xFF0B0F17) : Colors.white70,
                      fontWeight: FontWeight.w700),
                  side: BorderSide.none,
                  showCheckmark: false,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: error != null
            ? Center(child: Text(error!, style: const TextStyle(color: Colors.white54)))
            : all == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final s = shown[i];
                      final on = playing == s.id;
                      return ListTile(
                        leading: GestureDetector(
                          onTap: () => _preview(s),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: on ? PhlioColors.sunsetGradient : null,
                              color: on ? null : _card,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(on ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                color: on ? PhlioColors.textOnBrand : Colors.white),
                          ),
                        ),
                        title: Text(s.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        subtitle: Text('${s.category} · ${s.duration.toStringAsFixed(1)}s',
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        trailing: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: studioViolet,
                              minimumSize: const Size(64, 34),
                              shape: const StadiumBorder()),
                          onPressed: () => Navigator.pop(context, s),
                          child: const Text('Use', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        onTap: () => _preview(s),
                      );
                    },
                  ),
      ),
    ]);
  }
}

// -- text to audio --------------------------------------------------------------------

typedef StudioSpeechRequest = ({String text, String voice, double speed});

Future<StudioSpeechRequest?> showStudioTextToSpeech(BuildContext context, Dio dio, {String initial = ''}) =>
    showModalBottomSheet<StudioSpeechRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _SpeechSheet(dio: dio, initial: initial),
      ),
    );

class _SpeechSheet extends StatefulWidget {
  const _SpeechSheet({required this.dio, required this.initial});
  final Dio dio;
  final String initial;
  @override
  State<_SpeechSheet> createState() => _SpeechSheetState();
}

class _SpeechSheetState extends State<_SpeechSheet> {
  late final text = TextEditingController(text: widget.initial);
  List<({String id, String name, String tone})> voices = const [
    (id: 'nova', name: 'Nova', tone: 'Bright'),
    (id: 'adam', name: 'Adam', tone: 'Narrator'),
  ];
  String voice = 'nova';
  double speed = 1;

  @override
  void initState() {
    super.initState();
    widget.dio.get('/messaging/studio/voices').then((r) {
      final list = ((r.data as Map)['items'] as List).cast<Map>();
      if (mounted && list.isNotEmpty) {
        setState(() => voices = [
              for (final m in list) (id: '${m['id']}', name: '${m['name']}', tone: '${m['tone']}')
            ]);
      }
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Text to audio',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: text,
              autofocus: widget.initial.isEmpty,
              maxLength: 600,
              minLines: 3,
              maxLines: 6,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type what the voice should say',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: _card,
                counterStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final v in voices)
                    GestureDetector(
                      onTap: () => setState(() => voice = v.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 84,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: voice == v.id ? Colors.white : Colors.transparent, width: 2),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.record_voice_over_outlined,
                              size: 20, color: voice == v.id ? PhlioColors.brandPeach : Colors.white60),
                          const SizedBox(height: 3),
                          Text(v.name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                          Text(v.tone, style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
            StudioSlider(
              label: 'Speed',
              value: speed,
              min: .5,
              max: 2,
              divisions: 15,
              onChanged: (v) => setState(() => speed = v),
              format: (v) => '${v.toStringAsFixed(1)}x',
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: PhlioColors.sunsetGradient, borderRadius: BorderRadius.circular(25)),
                child: TextButton(
                  onPressed: () {
                    final value = text.text.trim();
                    if (value.isEmpty) return;
                    Navigator.pop(context, (text: value, voice: voice, speed: speed));
                  },
                  child: const Text('Add to timeline',
                      style: TextStyle(color: PhlioColors.textOnBrand, fontWeight: FontWeight.w900, fontSize: 15)),
                ),
              ),
            ),
          ]),
        ),
      );
}

// -- captions -------------------------------------------------------------------------

/// Edit every caption line in one list (CapCut "Edit captions").
class StudioCaptionsEditor extends StatefulWidget {
  const StudioCaptionsEditor({required this.captions, super.key});
  final List<StudioOverlay> captions;
  @override
  State<StudioCaptionsEditor> createState() => _StudioCaptionsEditorState();
}

class _StudioCaptionsEditorState extends State<StudioCaptionsEditor> {
  late final controllers = [for (final c in widget.captions) TextEditingController(text: c.text)];
  final removed = <String>{};

  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  String _clock(double s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toStringAsFixed(1).padLeft(4, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _sheet,
        appBar: AppBar(
          backgroundColor: _sheet,
          foregroundColor: Colors.white,
          title: const Text('Edit captions', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, {
                for (var i = 0; i < widget.captions.length; i++)
                  widget.captions[i].id: removed.contains(widget.captions[i].id) ? '' : controllers[i].text.trim(),
              }),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w800, color: PhlioColors.brandPeach)),
            ),
          ],
        ),
        body: ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: widget.captions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final c = widget.captions[i];
            if (removed.contains(c.id)) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_clock(c.start),
                      style: const TextStyle(color: Colors.white54, fontSize: 12, fontFeatures: [ui.FontFeature.tabularFigures()])),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controllers[i],
                    maxLines: null,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete line',
                  onPressed: () => setState(() => removed.add(c.id)),
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54),
                ),
              ]),
            );
          },
        ),
      );
}

// -- export settings ------------------------------------------------------------------

class StudioExportSettings extends StatelessWidget {
  const StudioExportSettings({required this.project, required this.onChanged, super.key});
  final StudioProject project;
  final void Function(VoidCallback fn) onChanged;

  @override
  Widget build(BuildContext context) {
    final p = project;
    const resolutions = [480, 720, 1080];
    const rates = [24, 25, 30, 50, 60];
    const qualities = ['low', 'recommended', 'high'];
    // Rough size estimate (H.264 at the chosen CRF).
    final mbps = {480: 1.2, 720: 2.6, 1080: 5.5}[p.resolution]! *
        {'low': .6, 'recommended': 1.0, 'high': 1.7}[p.quality]! *
        (p.fps / 30);
    final mb = (mbps * p.total / 8) + p.total * .02;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(children: [
        _StepSlider(
          label: 'Resolution',
          values: [for (final r in resolutions) '${r}p'],
          index: resolutions.indexOf(p.resolution),
          onPick: (i) => onChanged(() => p.resolution = resolutions[i]),
        ),
        _StepSlider(
          label: 'Frame rate',
          values: [for (final r in rates) '$r'],
          index: rates.indexOf(p.fps).clamp(0, rates.length - 1),
          onPick: (i) => onChanged(() => p.fps = rates[i]),
        ),
        _StepSlider(
          label: 'Quality',
          values: const ['Lower', 'Recommended', 'Higher'],
          index: qualities.indexOf(p.quality),
          onPick: (i) => onChanged(() => p.quality = qualities[i]),
        ),
        Text('Estimated file size: ${mb < 1 ? '<1' : mb.toStringAsFixed(0)} MB',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }
}

class _StepSlider extends StatelessWidget {
  const _StepSlider({required this.label, required this.values, required this.index, required this.onPick});
  final String label;
  final List<String> values;
  final int index;
  final ValueChanged<int> onPick;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
            const Spacer(),
            Text(values[index], style: const TextStyle(color: PhlioColors.brandPeach, fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2.5),
              activeTickMarkColor: Colors.white,
              inactiveTickMarkColor: Colors.white38,
            ),
            child: Slider(
              value: index.toDouble(),
              min: 0,
              max: (values.length - 1).toDouble(),
              divisions: values.length - 1,
              onChanged: (v) {
                if (v.round() != index) HapticFeedback.selectionClick();
                onPick(v.round());
              },
            ),
          ),
        ]),
      );
}

// -- cover ----------------------------------------------------------------------------

/// Choose the cover: scrub to a frame or pick a photo, then add a title.
class StudioCoverScreen extends StatefulWidget {
  const StudioCoverScreen({
    required this.total,
    required this.initialTime,
    required this.initialPath,
    required this.initialText,
    required this.frameAt,
    required this.aspect,
    required this.pickPhoto,
    super.key,
  });
  final double total, aspect;
  final double? initialTime;
  final String? initialPath;
  final String initialText;
  final Widget Function(double t) frameAt;
  final Future<String?> Function() pickPhoto;
  @override
  State<StudioCoverScreen> createState() => _StudioCoverScreenState();
}

class _StudioCoverScreenState extends State<StudioCoverScreen> {
  late double t = widget.initialTime ?? 0;
  late String? path = widget.initialPath;
  late final text = TextEditingController(text: widget.initialText);
  int tab = 0;

  @override
  void initState() {
    super.initState();
    if (path != null) tab = 1;
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF07090E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF07090E),
          foregroundColor: Colors.white,
          title: const Text('Cover', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context,
                  (time: tab == 0 ? t : null, path: tab == 1 ? path : null, text: text.text.trim())),
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800, color: PhlioColors.brandPeach)),
            ),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.aspect,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(fit: StackFit.expand, children: [
                    if (tab == 1 && path != null)
                      Image.file(File(path!), fit: BoxFit.cover)
                    else
                      widget.frameAt(t),
                    ValueListenableBuilder(
                      valueListenable: text,
                      builder: (_, v, __) => v.text.trim().isEmpty
                          ? const SizedBox()
                          : Align(
                              alignment: const Alignment(0, .55),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(v.text,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 30,
                                        fontWeight: FontWeight.w900,
                                        shadows: [Shadow(blurRadius: 12, color: Colors.black54)])),
                              ),
                            ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          StudioTabs(tabs: const ['Video frame', 'Add from album'], selected: tab, onPick: (i) async {
            if (i == 1) {
              final picked = await widget.pickPhoto();
              if (picked == null) return;
              path = picked;
            }
            setState(() => tab = i);
          }),
          if (tab == 0)
            StudioSlider(
              value: t,
              min: 0,
              max: math.max(.1, widget.total),
              onChanged: (v) => setState(() => t = v),
              format: (v) => '${v.toStringAsFixed(1)}s',
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: TextField(
              controller: text,
              maxLength: 60,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Add cover text (optional)',
                hintStyle: const TextStyle(color: Colors.white38),
                counterStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: _card,
                prefixIcon: const Icon(Icons.title_rounded, color: Colors.white54),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
        ]),
      );
}

typedef StudioCoverResult = ({double? time, String? path, String text});
