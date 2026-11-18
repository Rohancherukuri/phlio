// The Notes speech bubble, drawn like Instagram's: a rounded card with the
// two-dot "thought" tail at the bottom-left, a song line (waveform + title,
// artist underneath), the text, and the optional bubble colour and animated
// effect from the Bubble Editor (assets/shaders/note_effects.frag).

import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../design_system/colors.dart';

/// The bubble's default (uncoloured) fill.
const kNoteBubbleColor = Color(0xFF262A33);

/// Bubble Editor colours: five pages of six, like Instagram's picker.
const kNoteColorPages = <List<Color>>[
  [Color(0xFFB69CFF), Color(0xFF7B3FF2), Color(0xFF4A0DB8), Color(0xFFF58BF0), Color(0xFFD600C6), Color(0xFF8E0A8E)],
  [Color(0xFF9CC8FF), Color(0xFF3D8BFF), Color(0xFF0B4FD6), Color(0xFF7FE7F2), Color(0xFF00B8D9), Color(0xFF006C8A)],
  [Color(0xFFA6F0B5), Color(0xFF2FCB6A), Color(0xFF0E7A3A), Color(0xFFE6F59A), Color(0xFFB5D300), Color(0xFF6B7F00)],
  [Color(0xFFFFD27A), Color(0xFFFF9F1C), Color(0xFFE85D04), Color(0xFFFFB3A7), Color(0xFFFF5A5F), Color(0xFFC1121F)],
  [Color(0xFFFFFFFF), Color(0xFFBFC5D2), Color(0xFF6B7280), Color(0xFF3A3F4B), Color(0xFF1F2937), Color(0xFF000000)],
];

/// Effects the shader can draw, in the order the picker shows them.
const kNoteEffects = <(String, String, IconData)>[
  ('confetti', 'Congrats', Icons.celebration_rounded),
  ('sparkles', 'Sparkles', Icons.auto_awesome_rounded),
  ('hearts', 'Hearts', Icons.favorite_rounded),
  ('fireworks', 'Fireworks', Icons.flare_rounded),
  ('glow', 'Glow', Icons.blur_on_rounded),
  ('snow', 'Snow', Icons.ac_unit_rounded),
  ('fizz', 'Fizz', Icons.bubble_chart_rounded),
];

int _effectIndex(String? effect) => kNoteEffects.indexWhere((e) => e.$1 == effect);

Color? parseNoteColor(Object? hex) {
  if (hex is! String || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

String noteColorHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Readable text on a bubble colour.
Color noteInk(Color fill) => fill.computeLuminance() > 0.5 ? const Color(0xFF111318) : Colors.white;

/// Draws the bubble background and its two-dot tail.
class _BubblePainter extends CustomPainter {
  _BubblePainter(this.fill, this.radius, this.tailScale);
  final Color fill;
  final double radius, tailScale;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = fill;
    final body = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(radius)), paint);
    // The tail: a dot just under the bubble and a smaller one below-left.
    final x = (size.width * 0.32).clamp(14.0, 40.0);
    canvas.drawCircle(Offset(x, size.height + 1.5 * tailScale), 5.5 * tailScale, paint);
    canvas.drawCircle(Offset(x - 6 * tailScale, size.height + 9 * tailScale), 2.6 * tailScale, paint);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.fill != fill || old.radius != radius || old.tailScale != tailScale;
}

/// A note bubble.
///
/// [note] is the server shape (`text`, `music`, `gif`, `color`, `effect`).
/// Pass [child] to put something else inside (the composer's text field).
class NoteBubble extends StatelessWidget {
  const NoteBubble({
    super.key,
    this.note,
    this.placeholder,
    this.child,
    this.large = false,
    this.maxWidth,
    this.playEffect = true,
    this.loopEffect = false,
  });

  final Map? note;
  final String? placeholder;
  final Widget? child;

  /// Composer / editor size (bigger type) vs. inbox size.
  final bool large;
  final double? maxWidth;

  /// Run the bubble's effect: once (inbox) or on a loop (editor, composer).
  final bool playEffect, loopEffect;

  @override
  Widget build(BuildContext context) {
    final n = note;
    final fill = parseNoteColor(n?['color']) ?? kNoteBubbleColor;
    final ink = noteInk(fill);
    final muted = ink.withValues(alpha: 0.62);
    final music = n?['music'] as Map?;
    final gif = n?['gif'] as Map?;
    final text = '${n?['text'] ?? ''}'.trim();
    final fs = large ? 18.0 : 12.5;

    final lines = <Widget>[
      if (music != null) ...[
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.graphic_eq_rounded, size: fs, color: ink),
          const SizedBox(width: 3),
          Flexible(
            child: Text('${music['title']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: ink, fontSize: fs - 0.5, fontWeight: FontWeight.w800, height: 1.15)),
          ),
        ]),
        if ('${music['artist'] ?? ''}'.isNotEmpty)
          Text('${music['artist']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: fs - 1.5, height: 1.15)),
      ],
      if (gif != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(imageUrl: '${gif['url']}', height: large ? 72 : 36, fit: BoxFit.cover),
          ),
        ),
      if (child != null)
        child!
      else if (text.isNotEmpty)
        Text(text,
            maxLines: music != null || gif != null ? 1 : 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: ink, fontSize: fs, height: 1.2))
      else if (music == null && gif == null)
        Text(placeholder ?? 'Note...',
            textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: fs, height: 1.2)),
    ];

    final bubble = CustomPaint(
      painter: _BubblePainter(fill, large ? 24 : 16, large ? 1.4 : 1),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? (large ? 260 : 96), minWidth: large ? 120 : 44),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: large ? 18 : 10, vertical: large ? 12 : 7),
          child: Column(mainAxisSize: MainAxisSize.min, children: lines),
        ),
      ),
    );

    final effect = n?['effect'] as String?;
    if (!playEffect || _effectIndex(effect) < 0) return bubble;
    return NoteEffectLayer(effect: effect!, color: fill, loop: loopEffect, pad: large ? 46 : 22, child: bubble);
  }
}

/// Paints [effect] around [child] with the note_effects shader. Plays one
/// round (about 3 s) unless [loop]. Draws nothing if shaders aren't
/// available (e.g. the shader failed to compile on an old GPU).
class NoteEffectLayer extends StatefulWidget {
  const NoteEffectLayer({
    required this.effect,
    required this.child,
    super.key,
    this.color = kNoteBubbleColor,
    this.loop = true,
    this.pad = 30,
  });

  final String effect;
  final Widget child;
  final Color color;
  final bool loop;
  final double pad;

  @override
  State<NoteEffectLayer> createState() => _NoteEffectLayerState();
}

class _NoteEffectLayerState extends State<NoteEffectLayer> with SingleTickerProviderStateMixin {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;
  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  double _t = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _t = elapsed.inMicroseconds / 1e6;
      if (!widget.loop && _t > 3.2) {
        _ticker.stop();
        _done = true;
      }
      if (mounted) setState(() {});
    });
    if (_program != null) {
      _shader = _program!.fragmentShader();
    } else {
      _loading ??= () async {
        try {
          _program = await ui.FragmentProgram.fromAsset('assets/shaders/note_effects.frag');
        } catch (_) {}
      }();
      _loading!.then((_) {
        if (mounted && _program != null) setState(() => _shader = _program!.fragmentShader());
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (mounted && !reduce) _ticker.start();
    });
  }

  @override
  void didUpdateWidget(NoteEffectLayer old) {
    super.didUpdateWidget(old);
    if (old.effect != widget.effect) {
      // Restart so a newly picked effect plays from the beginning.
      _ticker.stop();
      _done = false;
      _t = 0;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    return Stack(clipBehavior: Clip.none, children: [
      if (widget.effect == 'glow' && shader != null && !_done) _overlay(shader),
      widget.child,
      if (widget.effect != 'glow' && shader != null && !_done) _overlay(shader),
    ]);
  }

  Widget _overlay(ui.FragmentShader shader) => Positioned(
        left: -widget.pad,
        top: -widget.pad,
        right: -widget.pad,
        bottom: -widget.pad,
        child: IgnorePointer(
          child: CustomPaint(
            painter: _EffectPainter(shader, _t, _effectIndex(widget.effect).toDouble(), widget.color, widget.pad),
          ),
        ),
      );
}

class _EffectPainter extends CustomPainter {
  _EffectPainter(this.shader, this.t, this.mode, this.color, this.pad);
  final ui.FragmentShader shader;
  final double t, mode, pad;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, t)
      ..setFloat(3, mode)
      ..setFloat(4, color.r)
      ..setFloat(5, color.g)
      ..setFloat(6, color.b)
      ..setFloat(7, pad);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_EffectPainter old) => old.t != t || old.mode != mode || old.color != color;
}

/// The tile Instagram shows at the top of the inbox: bubble resting on the
/// avatar, name, and (for your own note) where it's visible.
class NoteTile extends StatelessWidget {
  const NoteTile({
    required this.avatar,
    required this.caption,
    required this.onTap,
    super.key,
    this.note,
    this.placeholder,
    this.subcaption,
    this.playEffect = true,
  });

  final Widget avatar;
  final String caption;
  final Widget? subcaption;
  final Map? note;
  final String? placeholder;
  final VoidCallback onTap;
  final bool playEffect;

  static const avatarSize = 78.0;
  static const _avatarTop = 52.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(children: [
          SizedBox(
            height: _avatarTop + avatarSize,
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
              const SizedBox(width: 100),
              Positioned(top: _avatarTop, child: avatar),
              // The bubble's bottom overlaps the top of the avatar.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: _avatarTop + 12,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: NoteBubble(note: note, placeholder: placeholder, playEffect: playEffect),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Text(caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: PhlioColors.textPrimary)),
          if (subcaption != null) subcaption!,
        ]),
      ),
    );
  }
}
