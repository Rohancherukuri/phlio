// Moment stickers — how each sticker looks, in the composer and the viewer.
//
// Every sticker is drawn at its designed size for a 360-wide canvas and
// scaled by [MomentStickerLayer]. Styling follows Phlio: violet → pink →
// peach gradients, rounded cards, Manrope type; Phlio type stickers are
// filled with the moment backdrop shader (holo / mesh) for a printed-foil
// look.
//
// In the viewer, interactive stickers take a [StickerResponse] (totals from
// the server) and report taps through [StickerActions].

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/config/app_config.dart';
import '../../../design_system/colors.dart';
import '../../../design_system/widgets/phlio_fox.dart';
import '../../../features/profile/presentation/controllers/avatar_controller.dart' show MeAvatar;
import '../templates/template_canvas.dart' show BackdropShader, templateFont;
import 'sticker_model.dart';

const _violet = PhlioColors.brandViolet;
const _pink = PhlioColors.brandPink;
const _peach = PhlioColors.brandPeach;
const _ink = Color(0xFF111925);
const _brand = LinearGradient(colors: [_violet, _pink, _peach]);

/// Server totals for one sticker (GET /social/moments/{id}/responses).
class StickerResponse {
  const StickerResponse({this.count = 0, this.counts = const [], this.average, this.mine, this.people = const []});
  final int count;

  /// Poll votes per option.
  final List<int> counts;

  /// Slider average (0–1).
  final double? average;

  /// What the viewer answered (null if they haven't).
  final Object? mine;

  /// Author only: who answered what.
  final List<Map> people;

  static StickerResponse fromJson(Map j) => StickerResponse(
        count: (j['count'] as num? ?? 0).toInt(),
        counts: [for (final c in (j['counts'] as List? ?? const [])) (c as num).toInt()],
        average: (j['average'] as num?)?.toDouble(),
        mine: j['mine'],
        people: [for (final p in (j['people'] as List? ?? const [])) p as Map],
      );
}

/// What the viewer can do with interactive stickers.
class StickerActions {
  const StickerActions({required this.respond, this.ask, this.addYours, this.openLink, this.showResults, this.isAuthor = false});

  /// Sends a response (poll index, slider value, `true` for like/remind).
  final Future<void> Function(MomentSticker sticker, Object value) respond;

  /// Question sticker tapped: ask for an answer.
  final void Function(MomentSticker sticker)? ask;

  /// "Add yours" tapped: start a moment with the same prompt.
  final void Function(MomentSticker sticker)? addYours;
  final void Function(String url)? openLink;

  /// Author tapped a sticker: show who responded.
  final void Function(MomentSticker sticker)? showResults;
  final bool isAuthor;
}

/// Positions stickers on a canvas of [canvasWidth] (Align by x/y, scaled
/// from the 360-wide design size, rotated).
class MomentStickerLayer extends StatelessWidget {
  const MomentStickerLayer({required this.stickers, required this.canvasWidth, required this.builder, super.key});
  final List<MomentSticker> stickers;
  final double canvasWidth;
  final Widget Function(MomentSticker sticker) builder;

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        for (final s in stickers)
          Align(
            alignment: Alignment(s.x * 2 - 1, s.y * 2 - 1),
            child: Transform.rotate(
              angle: s.rotation,
              child: Transform.scale(scale: canvasWidth / 360 * s.scale, child: builder(s)),
            ),
          ),
      ]);
}

/// One sticker. [responses]/[actions] make interactive ones live (viewer);
/// without them they show as in the composer.
class MomentStickerView extends StatelessWidget {
  const MomentStickerView(this.s, {this.response, this.actions, super.key});
  final MomentSticker s;
  final StickerResponse? response;
  final StickerActions? actions;

  @override
  Widget build(BuildContext context) {
    final d = s.data;
    final style = (d['style'] as num? ?? 0).toInt();
    return switch (s.type) {
      StickerType.location => _Pill(icon: Icons.place_rounded, text: '${d['text'] ?? 'Location'}'.toUpperCase(), style: style),
      StickerType.mention => _Pill(icon: Icons.alternate_email_rounded, text: '${d['text'] ?? 'username'}'.replaceFirst('@', '').toUpperCase(), style: style),
      StickerType.hashtag => _Pill(text: '#${'${d['text'] ?? 'hashtag'}'.replaceFirst('#', '').toUpperCase()}', style: style),
      StickerType.link => GestureDetector(
          onTap: actions?.openLink == null ? null : () => actions!.openLink!('${d['url']}'),
          child: _Pill(icon: Icons.link_rounded, text: '${d['label'] ?? _host('${d['url']}')}'.toUpperCase(), style: style),
        ),
      StickerType.music => _MusicCard(d, style: style),
      StickerType.photo || StickerType.frame || StickerType.cutout => _PhotoSticker(s),
      StickerType.gif => _GifSticker('${d['url']}', framed: d['kind'] == 'gif'),
      StickerType.avatar => _AvatarSticker(name: '${d['name'] ?? 'You'}'),
      StickerType.poll => _PollCard(s, response: response, actions: actions),
      StickerType.question => _QuestionCard(s, actions: actions, response: response),
      StickerType.slider => _SliderCard(s, response: response, actions: actions),
      StickerType.countdown => _CountdownCard(s, response: response, actions: actions),
      StickerType.addyours => _AddYoursCard(s, response: response, actions: actions),
      StickerType.like => _LikeBubble(s, response: response, actions: actions),
      StickerType.clock => _FlipClock('${d['time'] ?? '9:41'}', '${d['period'] ?? ''}'),
      StickerType.weather => _Weather(d),
      StickerType.word => WordSticker('${d['word']}', '${d['style'] ?? 'bubble'}'),
      StickerType.foxy => PhlioStickerView(stickerId: '${d['sticker']}', size: 110, interactive: false),
    };
  }

  static String _host(String url) => Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? url;
}

// -- pills (location, mention, hashtag, link) ---------------------------------------------

/// Tap a pill in the composer to cycle its [style]: 0 white with brand
/// gradient text, 1 brand gradient with white text, 2 dark glass.
class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.icon, this.style = 0});
  final String text;
  final IconData? icon;
  final int style;

  @override
  Widget build(BuildContext context) {
    final s = style % 3;
    final textStyle = const TextStyle(fontFamily: 'Manrope', fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: .4);
    Widget label(Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 20, color: c), const SizedBox(width: 4)],
          Text(text, style: textStyle.copyWith(color: c)),
        ]);
    final content = s == 0
        ? ShaderMask(blendMode: BlendMode.srcIn, shaderCallback: _brand.createShader, child: label(Colors.white))
        : label(Colors.white);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: s == 0 ? Colors.white : (s == 2 ? const Color(0xB3111925) : null),
        gradient: s == 1 ? _brand : null,
        borderRadius: BorderRadius.circular(12),
        border: s == 2 ? Border.all(color: Colors.white24) : null,
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: content,
    );
  }
}

// -- music ------------------------------------------------------------------------------

class _MusicCard extends StatelessWidget {
  const _MusicCard(this.d, {this.style = 0});
  final Map<String, dynamic> d;
  final int style;

  @override
  Widget build(BuildContext context) {
    final cover = d['cover_url'] as String?;
    final dark = style % 2 == 1;
    final fg = dark ? Colors.white : _ink;
    return Container(
      width: 250,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: dark ? const Color(0xE6111925) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 52,
            height: 52,
            child: cover == null
                ? const DecoratedBox(decoration: BoxDecoration(gradient: _brand), child: Icon(Icons.music_note_rounded, color: Colors.white))
                : CachedNetworkImage(imageUrl: AppConfig.mediaUrl(cover), fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${d['title'] ?? 'Song'}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
            Text('${d['artist'] ?? ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withValues(alpha: .65), fontSize: 13)),
          ]),
        ),
        const _Equalizer(),
      ]),
    );
  }
}

class _Equalizer extends StatefulWidget {
  const _Equalizer();
  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 4,
              height: 6 + 14 * (.5 + .5 * math.sin(_c.value * 2 * math.pi + i * 1.3)),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(gradient: _brand, borderRadius: BorderRadius.circular(2)),
            ),
        ]),
      );
}

// -- photos, frames, cutouts, GIFs, avatar ----------------------------------------------

/// Cutout shapes for photo cutouts.
const cutoutShapes = ['heart', 'star', 'circle', 'blob', 'arch'];

class _PhotoSticker extends StatelessWidget {
  const _PhotoSticker(this.s);
  final MomentSticker s;

  @override
  Widget build(BuildContext context) {
    final path = s.data['path'] as String?;
    final url = s.data['url'] as String?;
    Widget img = path != null
        ? Image.file(File(path), fit: BoxFit.cover, cacheWidth: 900)
        : url != null
            ? CachedNetworkImage(imageUrl: AppConfig.mediaUrl(url), fit: BoxFit.cover)
            : const DecoratedBox(decoration: BoxDecoration(gradient: _brand));
    if (s.type == StickerType.frame) {
      // Instant-photo frame with a handwritten caption.
      return Container(
        width: 200,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: const BoxDecoration(
          color: Color(0xFFFDFBF7),
          boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 180, height: 200, child: img),
          const SizedBox(height: 6),
          Text('${s.data['caption'] ?? ''}',
              style: templateFont('Caveat', const TextStyle(color: _ink, fontSize: 22, fontWeight: FontWeight.w600))),
        ]),
      );
    }
    if (s.type == StickerType.cutout) {
      final shape = '${s.data['shape'] ?? 'heart'}';
      return CustomPaint(
        foregroundPainter: _CutoutOutline(shape),
        child: ClipPath(clipper: _CutoutClipper(shape), child: SizedBox(width: 190, height: 190, child: img)),
      );
    }
    return Container(
      width: 180,
      height: 230,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: img),
    );
  }
}

/// Path for a cutout shape in a box of [size].
Path cutoutPath(String shape, Size size) {
  final w = size.width, h = size.height;
  switch (shape) {
    case 'circle':
      return Path()..addOval(Offset.zero & size);
    case 'arch':
      return Path()
        ..moveTo(0, h)
        ..lineTo(0, w / 2)
        ..arcToPoint(Offset(w, w / 2), radius: Radius.circular(w / 2))
        ..lineTo(w, h)
        ..close();
    case 'star':
      final p = Path();
      for (var i = 0; i < 10; i++) {
        final r = (i.isEven ? .5 : .23) * w;
        final a = -math.pi / 2 + i * math.pi / 5;
        final pt = Offset(w / 2 + r * math.cos(a), h / 2 + r * math.sin(a));
        i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
      }
      return p..close();
    case 'blob':
      final p = Path();
      for (var i = 0; i <= 64; i++) {
        final a = i / 64 * 2 * math.pi;
        final r = .5 * w * (.86 + .08 * math.sin(3 * a) + .06 * math.cos(5 * a + 1));
        final pt = Offset(w / 2 + r * math.cos(a), h / 2 + r * math.sin(a));
        i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
      }
      return p..close();
    default: // heart
      return Path()
        ..moveTo(w / 2, h * .95)
        ..cubicTo(-w * .1, h * .55, w * .12, -h * .05, w / 2, h * .25)
        ..cubicTo(w * .88, -h * .05, w * 1.1, h * .55, w / 2, h * .95)
        ..close();
  }
}

class _CutoutClipper extends CustomClipper<Path> {
  _CutoutClipper(this.shape);
  final String shape;
  @override
  Path getClip(Size size) => cutoutPath(shape, size);
  @override
  bool shouldReclip(_CutoutClipper old) => old.shape != shape;
}

/// White sticker outline + soft shadow around a cutout.
class _CutoutOutline extends CustomPainter {
  _CutoutOutline(this.shape);
  final String shape;
  @override
  void paint(Canvas canvas, Size size) {
    final path = cutoutPath(shape, size);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_CutoutOutline old) => old.shape != shape;
}

/// A GIPHY sticker (transparent) or GIF ([framed]: rounded, with a shadow).
class _GifSticker extends StatelessWidget {
  const _GifSticker(this.url, {this.framed = false});
  final String url;
  final bool framed;
  @override
  Widget build(BuildContext context) {
    final img = Image.network(url,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const Icon(Icons.gif_box_rounded, color: Colors.white, size: 60));
    if (!framed) return SizedBox(width: 170, child: img);
    return Container(
      width: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: img),
    );
  }
}

class _AvatarSticker extends StatelessWidget {
  const _AvatarSticker({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _brand,
              boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 5))]),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: MeAvatar(name: name, size: 110),
          ),
        ),
      ]);
}

// -- cards (poll, question, slider, countdown, add yours) -------------------------------

/// Shared card shell: white card, brand gradient header strip.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.width = 280});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F6FB),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 20, offset: Offset(0, 8))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(type: MaterialType.transparency, child: child),
      );
}

/// Poll (like the Instagram channel poll, in Phlio colours): question,
/// options; after voting, gradient bars with counts and your pick ticked.
class _PollCard extends StatelessWidget {
  const _PollCard(this.s, {this.response, this.actions});
  final MomentSticker s;
  final StickerResponse? response;
  final StickerActions? actions;

  @override
  Widget build(BuildContext context) {
    final options = [for (final o in (s.data['options'] as List? ?? const [])) '$o'];
    final r = response;
    final voted = r?.mine is int || (actions?.isAuthor ?? false);
    final total = r == null ? 0 : r.counts.fold<int>(0, (a, b) => a + b);
    return _Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('${s.data['question'] ?? 'Ask a question'}',
              textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontSize: 20, fontWeight: FontWeight.w800, height: 1.2)),
          const SizedBox(height: 14),
          for (final (i, o) in options.indexed) ...[
            if (!voted)
              GestureDetector(
                onTap: actions == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        actions!.respond(s, i);
                      },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0x1A111925))),
                  child: Text(o, textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              )
            else
              _PollResult(label: o, count: r?.counts.elementAtOrNull(i) ?? 0, total: total, mine: r?.mine == i),
          ],
          if (voted)
            GestureDetector(
              onTap: actions?.isAuthor == true ? () => actions!.showResults?.call(s) : null,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(actions?.isAuthor == true ? '$total votes · See who voted' : '$total votes',
                    textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF858D9E), fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _PollResult extends StatelessWidget {
  const _PollResult({required this.label, required this.count, required this.total, required this.mine});
  final String label;
  final int count, total;
  final bool mine;
  @override
  Widget build(BuildContext context) {
    final f = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (mine) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.check_circle_rounded, color: _violet, size: 18)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(gradient: _brand, borderRadius: BorderRadius.circular(20)),
            child: Text('${(f * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(children: [
            Container(height: 9, color: const Color(0xFFE6E4EF)),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: f),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => FractionallySizedBox(
                widthFactor: v.clamp(0.0, 1.0),
                child: Container(height: 9, decoration: const BoxDecoration(gradient: _brand)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Question box: viewers tap to answer (the answer goes to the author's DMs).
class _QuestionCard extends StatelessWidget {
  const _QuestionCard(this.s, {this.actions, this.response});
  final MomentSticker s;
  final StickerActions? actions;
  final StickerResponse? response;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: actions == null
            ? null
            : () => actions!.isAuthor ? actions!.showResults?.call(s) : actions!.ask?.call(s),
        child: _Card(
          width: 270,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: const BoxDecoration(gradient: _brand),
              child: Text('${s.data['prompt'] ?? 'Ask me a question'}',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFEDEBF4), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  actions?.isAuthor == true
                      ? '${response?.count ?? 0} answers · See all'
                      : (response?.mine != null ? 'Answered · tap to send another' : 'Type something…'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF858D9E), fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ]),
        ),
      );
}

/// Emoji slider: drag the emoji, let go to send; then shows the average.
class _SliderCard extends StatefulWidget {
  const _SliderCard(this.s, {this.response, this.actions});
  final MomentSticker s;
  final StickerResponse? response;
  final StickerActions? actions;
  @override
  State<_SliderCard> createState() => _SliderCardState();
}

class _SliderCardState extends State<_SliderCard> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final emoji = '${widget.s.data['emoji'] ?? '😍'}';
    final r = widget.response;
    final mine = r?.mine is num ? (r!.mine as num).toDouble() : null;
    final value = _drag ?? mine ?? (widget.actions == null ? .55 : .0);
    final done = mine != null || (widget.actions?.isAuthor ?? false);
    return _Card(
      width: 270,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${widget.s.data['prompt'] ?? 'How much do you love this?'}',
              textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (_, box) {
            final w = box.maxWidth;
            return GestureDetector(
              onHorizontalDragUpdate: widget.actions == null || done
                  ? null
                  : (d) => setState(() => _drag = (d.localPosition.dx / w).clamp(0.0, 1.0)),
              onHorizontalDragEnd: widget.actions == null || done || _drag == null
                  ? null
                  : (_) {
                      HapticFeedback.mediumImpact();
                      widget.actions!.respond(widget.s, _drag!);
                    },
              child: SizedBox(
                height: 40,
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
                  Container(height: 10, decoration: BoxDecoration(color: const Color(0xFFE6E4EF), borderRadius: BorderRadius.circular(6))),
                  FractionallySizedBox(
                    widthFactor: value,
                    child: Container(height: 10, decoration: BoxDecoration(gradient: _brand, borderRadius: BorderRadius.circular(6))),
                  ),
                  if (done && r?.average != null)
                    Positioned(
                      left: w * r!.average! - 12,
                      top: -2,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: _ink),
                        alignment: Alignment.center,
                        child: const Text('avg', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  Positioned(
                    left: w * value - 18,
                    child: Text(emoji, style: TextStyle(fontSize: _drag != null ? 40 : 32)),
                  ),
                ]),
              ),
            );
          }),
          if (done && widget.actions != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  widget.actions!.isAuthor
                      ? '${r?.count ?? 0} responses · average ${((r?.average ?? 0) * 100).round()}%'
                      : 'Average ${((r?.average ?? 0) * 100).round()}%',
                  style: const TextStyle(color: Color(0xFF858D9E), fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }
}

/// Countdown to [data.ends] (ISO date); viewers can tap "Remind me".
class _CountdownCard extends StatefulWidget {
  const _CountdownCard(this.s, {this.response, this.actions});
  final MomentSticker s;
  final StickerResponse? response;
  final StickerActions? actions;
  @override
  State<_CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<_CountdownCard> {
  Timer? _tick;
  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ends = DateTime.tryParse('${widget.s.data['ends']}') ?? DateTime.now().add(const Duration(days: 1));
    final left = ends.difference(DateTime.now());
    final over = left.isNegative;
    String two(int n) => n.toString().padLeft(2, '0');
    final parts = over
        ? const [('00', 'days'), ('00', 'hours'), ('00', 'min')]
        : [(two(left.inDays), 'days'), (two(left.inHours % 24), 'hours'), (two(left.inMinutes % 60), 'min')];
    final reminded = widget.response?.mine == true;
    return Container(
      width: 280,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2A1F5C), _violet, _pink]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${widget.s.data['title'] ?? 'Countdown'}'.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final (n, label) in parts)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(children: [
                Container(
                  width: 58,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(12)),
                  child: Text(n,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800,
                          fontFeatures: [ui.FontFeature.tabularFigures()])),
                ),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
        if (widget.actions != null) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: widget.actions!.isAuthor
                ? () => widget.actions!.showResults?.call(widget.s)
                : reminded || over
                    ? null
                    : () => widget.actions!.respond(widget.s, true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Text(
                widget.actions!.isAuthor
                    ? '${widget.response?.count ?? 0} reminders'
                    : over
                        ? 'It\'s here!'
                        : reminded
                            ? '✓ Reminder set'
                            : 'Remind me',
                style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// "Add yours": a prompt others answer with their own moment.
class _AddYoursCard extends StatelessWidget {
  const _AddYoursCard(this.s, {this.response, this.actions});
  final MomentSticker s;
  final StickerResponse? response;
  final StickerActions? actions;
  @override
  Widget build(BuildContext context) => _Card(
        width: 260,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: _brand.createShader,
              child: const Text('ADD YOURS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 12)),
            ),
            const SizedBox(height: 6),
            Text('${s.data['prompt'] ?? 'Show your view right now'}',
                textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: actions == null
                  ? null
                  : () => actions!.isAuthor ? actions!.showResults?.call(s) : actions!.addYours?.call(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(gradient: _brand, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add_a_photo_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(response == null || response!.count == 0 ? 'Add yours' : 'Add yours · ${response!.count}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
              ),
            ),
          ]),
        ),
      );
}

/// Heart bubble with a live count; viewers tap to like.
class _LikeBubble extends StatelessWidget {
  const _LikeBubble(this.s, {this.response, this.actions});
  final MomentSticker s;
  final StickerResponse? response;
  final StickerActions? actions;
  @override
  Widget build(BuildContext context) {
    final liked = response?.mine == true;
    final count = response?.count ?? 1;
    return GestureDetector(
      onTap: actions == null || liked || actions!.isAuthor
          ? null
          : () {
              HapticFeedback.lightImpact();
              actions!.respond(s, true);
            },
      child: CustomPaint(
        painter: _BubbleTail(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFF5636B), _pink]),
            borderRadius: BorderRadius.circular(40),
            boxShadow: const [BoxShadow(color: Color(0x4DF5636B), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: Colors.white, size: 34),
            const SizedBox(width: 8),
            Text('$count', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}

class _BubbleTail extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(size.width * .42, size.height - 2)
      ..lineTo(size.width * .5, size.height + 14)
      ..lineTo(size.width * .58, size.height - 2)
      ..close();
    canvas.drawPath(p, Paint()..color = const Color(0xFFEB7BB0));
  }

  @override
  bool shouldRepaint(_BubbleTail old) => false;
}

// -- clock and weather --------------------------------------------------------------------

class _FlipClock extends StatelessWidget {
  const _FlipClock(this.time, this.period);
  final String time, period;
  @override
  Widget build(BuildContext context) {
    final digits = time.replaceAll(':', '');
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      if (period.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 4),
          child: Text(period, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
      for (final (i, ch) in digits.split('').indexed) ...[
        if (i == digits.length - 2) const SizedBox(width: 6),
        Container(
          width: 42,
          height: 62,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2B3346), Color(0xFF151A26)]),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 4))],
          ),
          child: Stack(alignment: Alignment.center, children: [
            Text(ch, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w600)),
            Container(height: 1.5, color: const Color(0xFF0A0D14)), // the flap line
          ]),
        ),
      ],
    ]);
  }
}

class _Weather extends StatelessWidget {
  const _Weather(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${d['temp'] ?? '--'}°${d['unit'] ?? 'C'}',
            style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w300, height: 1,
                shadows: [Shadow(color: Color(0x66000000), blurRadius: 12)])),
        if (d['city'] != null)
          Text('${d['icon'] ?? ''} ${d['city']}'.trim(),
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Color(0x66000000), blurRadius: 8)])),
      ]);
}

// -- Phlio type stickers ------------------------------------------------------------------

const _weekdays = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];

/// A word in one of the Phlio sticker styles: bubble, chrome, burst, tv,
/// holo, neon, tag. Bubble and holo are filled with the backdrop shader.
class WordSticker extends StatelessWidget {
  const WordSticker(this.word, this.style, {super.key});
  final String word, style;

  @override
  Widget build(BuildContext context) {
    final text = word == 'TODAY' ? _weekdays[DateTime.now().weekday - 1] : word;
    final long = text.length > 6;
    switch (style) {
      case 'bubble':
        return Transform.rotate(
          angle: -.08,
          child: _Outlined(
            text: text,
            style: templateFont('Righteous', TextStyle(fontSize: long ? 40 : 54, height: 1)),
            stroke: Colors.white,
            strokeWidth: 9,
            shadow: _violet,
            fill: const _ShaderFill(style: 0, colors: [_violet, _pink, _peach, Color(0xFF72A7FF)]),
          ),
        );
      case 'holo':
        return _Outlined(
          text: text,
          style: templateFont('Archivo Black', TextStyle(fontSize: long ? 40 : 56, height: 1)),
          stroke: Colors.white,
          strokeWidth: 8,
          shadow: const Color(0xFF111925),
          fill: const _ShaderFill(style: 6, colors: [_violet, _pink, _peach, Color(0xFF111925)]),
        );
      case 'chrome':
        return _Outlined(
          text: text,
          style: templateFont('Anton', TextStyle(fontSize: long ? 42 : 58, height: 1, letterSpacing: 1)),
          stroke: _pink,
          strokeWidth: 5,
          shadow: const Color(0xFF2A1F5C),
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Color(0xFFD7D2F5), _violet, Colors.white],
              stops: [0, .45, .55, 1]),
        );
      case 'burst':
        return SizedBox(
          width: 150,
          height: 150,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(size: const Size(150, 150), painter: _BurstPainter()),
            _Outlined(
              text: text,
              style: templateFont('Archivo Black', TextStyle(fontSize: long ? 26 : 64, height: 1)),
              stroke: _violet,
              strokeWidth: 6,
              shadow: const Color(0xFF2A1F5C),
              gradient: const LinearGradient(colors: [Colors.white, Color(0xFFFFE3F6)]),
            ),
          ]),
        );
      case 'tv':
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_violet, Color(0xFF5B45D6)]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 12, offset: Offset(0, 6))],
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A1F5C), Color(0xFF8D4FD8)]),
            ),
            child: Text(text,
                style: templateFont('Archivo Black', const TextStyle(color: Colors.white, fontSize: 46, fontStyle: FontStyle.italic, height: 1,
                    shadows: [Shadow(color: _pink, offset: Offset(3, 3))]))),
          ),
        );
      case 'neon':
        return Text(text,
            style: templateFont('Monoton', TextStyle(color: const Color(0xFFFFE3F6), fontSize: long ? 34 : 50, height: 1, shadows: const [
              Shadow(color: _pink, blurRadius: 8),
              Shadow(color: _pink, blurRadius: 22),
              Shadow(color: _violet, blurRadius: 40),
            ])));
      default: // tag
        return Transform.rotate(
          angle: .06,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 4))]),
            child: Text(text,
                style: templateFont('Space Grotesk', const TextStyle(color: _peach, fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: 2))),
          ),
        );
    }
  }
}

/// Text with a thick outline, a hard drop shadow and a fill (shader or gradient).
class _Outlined extends StatelessWidget {
  const _Outlined({required this.text, required this.style, required this.stroke, required this.strokeWidth, required this.shadow, this.fill, this.gradient});
  final String text;
  final TextStyle style;
  final Color stroke, shadow;
  final double strokeWidth;
  final _ShaderFill? fill;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    Text t(TextStyle s) => Text(text, textAlign: TextAlign.center, style: style.merge(s));
    final body = t(const TextStyle(color: Colors.white));
    return Stack(alignment: Alignment.center, children: [
      Transform.translate(
        offset: const Offset(4, 5),
        child: t(TextStyle(foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..color = shadow)),
      ),
      t(TextStyle(foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = stroke)),
      if (fill != null)
        fill!.wrap(body)
      else
        ShaderMask(blendMode: BlendMode.srcIn, shaderCallback: (r) => gradient!.createShader(r), child: body),
    ]);
  }
}

/// Fills a child with the backdrop shader (mesh = 0, holo = 6…), falling
/// back to the brand gradient until the shader has loaded.
class _ShaderFill {
  const _ShaderFill({required this.style, required this.colors});
  final int style;
  final List<Color> colors;

  Widget wrap(Widget child) => _ShaderFillView(fill: this, child: child);
}

class _ShaderFillView extends StatefulWidget {
  const _ShaderFillView({required this.fill, required this.child});
  final _ShaderFill fill;
  final Widget child;
  @override
  State<_ShaderFillView> createState() => _ShaderFillViewState();
}

class _ShaderFillViewState extends State<_ShaderFillView> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    BackdropShader.load().then((p) {
      if (p != null && mounted) setState(() => _shader = p.fragmentShader());
    });
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) {
          final s = _shader;
          if (s == null) return _brand.createShader(rect);
          var i = 0;
          void set(double v) => s.setFloat(i++, v);
          set(rect.width);
          set(rect.height);
          set(3.0); // a fixed, pleasing moment of the animation
          set(widget.fill.style.toDouble());
          for (final c in widget.fill.colors) {
            set(c.r);
            set(c.g);
            set(c.b);
          }
          set(0.0);
          return s;
        },
        child: widget.child,
      );
}

class _BurstPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Path();
    for (var i = 0; i < 24; i++) {
      final r = (i.isEven ? .5 : .36) * size.width;
      final a = i * math.pi / 12;
      final pt = c + Offset(r * math.cos(a), r * math.sin(a));
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    p.close();
    canvas.drawPath(p.shift(const Offset(4, 5)), Paint()..color = const Color(0xFF2A1F5C));
    canvas.drawPath(p, Paint()..shader = const RadialGradient(colors: [_peach, _pink, Color(0xFFF5636B)]).createShader(Offset.zero & size));
    canvas.drawPath(p, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_BurstPainter old) => false;
}
