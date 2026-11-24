// Moment text — the full-screen text editor and the styled text it makes.
//
//   [openMomentTextEditor]  type over a dimmed canvas: Done top-right, a size
//                           slider on the left, font chips (Classic, Bubble,
//                           Deco, Squeeze, Typewriter…), a tool row (font,
//                           colour, animation, outline, alignment, background,
//                           effects) and Mention / Location / Rewrite above
//                           the keyboard.
//   [RichMomentText]        draws the result anywhere (composer, viewer,
//                           snaps) from its sticker data.
//
// The text is stored as a `word` sticker with style `rich`, so moments,
// videos (as live overlays) and snaps all render it the same way.


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../content/mentions.dart';
import '../templates/template_canvas.dart' show templateFont;

/// Font chips: label → Google font (or a bundled family).
const richFonts = <(String, String, FontWeight)>[
  ('Classic', 'Manrope', FontWeight.w800),
  ('Bubble', 'Fredoka', FontWeight.w700),
  ('Deco', 'Poiret One', FontWeight.w400),
  ('Squeeze', 'Bebas Neue', FontWeight.w400),
  ('Typewriter', 'Courier Prime', FontWeight.w700),
  ('Strong', 'Archivo Black', FontWeight.w400),
  ('Elegant', 'Playfair Display', FontWeight.w700),
  ('Script', 'Pacifico', FontWeight.w400),
  ('Hand', 'Caveat', FontWeight.w700),
];

const richColors = <Color>[
  Colors.white, Colors.black, Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFFFB58F),
  Color(0xFF68D7CD), Color(0xFF72A7FF), Color(0xFFF6B93B), Color(0xFFF5636B), Color(0xFF7BD88F),
  Color(0xFFFF8C2B), Color(0xFFC8A2FF),
];

const _animations = ['none', 'pop', 'type', 'wave'];
const _effects = ['none', 'shadow', 'glow', 'sunset'];

Color richHex(dynamic v, [Color fallback = Colors.white]) {
  if (v is! String || v.length != 7) return fallback;
  final n = int.tryParse(v.substring(1), radix: 16);
  return n == null ? fallback : Color(0xFF000000 | n);
}

String richToHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

TextStyle richStyle(Map d, {double? size}) {
  final font = richFonts.firstWhere((f) => f.$1 == d['font'], orElse: () => richFonts.first);
  final color = richHex(d['color']);
  final effect = '${d['effect'] ?? 'none'}';
  final s = size ?? (d['size'] as num? ?? 34).toDouble();
  return templateFont(
    font.$2,
    TextStyle(
      color: color,
      fontSize: s,
      fontWeight: font.$3,
      height: 1.12,
      shadows: switch (effect) {
        'shadow' => const [Shadow(color: Color(0xAA000000), blurRadius: 10, offset: Offset(0, 3))],
        'glow' => [Shadow(color: color, blurRadius: 18), Shadow(color: color.withValues(alpha: .6), blurRadius: 36)],
        _ => null,
      },
    ),
  );
}

/// The styled text from sticker data.
class RichMomentText extends StatefulWidget {
  const RichMomentText(this.data, {this.animate = true, super.key});
  final Map data;
  final bool animate;

  @override
  State<RichMomentText> createState() => _RichMomentTextState();
}

class _RichMomentTextState extends State<RichMomentText> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  String get _anim => '${widget.data['anim'] ?? 'none'}';

  @override
  void initState() {
    super.initState();
    if (widget.animate && _anim != 'none') {
      _anim == 'wave' ? _c.repeat() : _c.forward();
    }
  }

  @override
  void didUpdateWidget(RichMomentText old) {
    super.didUpdateWidget(old);
    if (old.data['anim'] != widget.data['anim'] && widget.animate) {
      _c
        ..reset()
        ..forward();
      if (_anim == 'wave') _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final text = '${d['word'] ?? ''}';
    final style = richStyle(d);
    final align = switch ('${d['align'] ?? 'center'}') {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };
    final color = richHex(d['color']);
    final bg = (d['bg'] as num? ?? 0).toInt();
    final outline = d['outline'] == true;
    final effect = '${d['effect'] ?? 'none'}';

    Widget paint(String t) {
      Widget body = Text(t, textAlign: align, style: style);
      if (outline) {
        body = Stack(children: [
          Text(t,
              textAlign: align,
              style: style.copyWith(
                  shadows: const [],
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = (style.fontSize ?? 34) * .12
                    ..strokeJoin = StrokeJoin.round
                    ..color = color.computeLuminance() > .5 ? Colors.black : Colors.white)),
          Text(t, textAlign: align, style: style),
        ]);
      }
      if (effect == 'sunset') {
        body = ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: const LinearGradient(colors: [Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFFFB58F)]).createShader,
          child: body,
        );
      }
      if (bg == 0) return body;
      final fill = bg == 1 ? (color.computeLuminance() > .5 ? Colors.black : Colors.white) : Colors.black.withValues(alpha: .45);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: bg == 1 ? color : fill, borderRadius: BorderRadius.circular(12)),
        child: bg == 1
            ? DefaultTextStyle.merge(
                style: TextStyle(color: color.computeLuminance() > .5 ? Colors.black : Colors.white),
                child: Text(t, textAlign: align, style: style.copyWith(color: color.computeLuminance() > .5 ? Colors.black : Colors.white)),
              )
            : body,
      );
    }

    if (!widget.animate || _anim == 'none') return paint(text);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        switch (_anim) {
          case 'type':
            final n = (text.length * Curves.easeOut.transform((t * 1.2).clamp(0.0, 1.0))).ceil();
            return Opacity(opacity: 1, child: Stack(children: [Opacity(opacity: 0, child: paint(text)), paint(text.substring(0, n))]));
          case 'wave':
            return Transform.translate(offset: Offset(0, 4 * (t < .5 ? t * 2 - .5 : 1.5 - t * 2)), child: paint(text));
          default: // pop
            final s = Curves.elasticOut.transform(t.clamp(0.0, 1.0));
            return Transform.scale(scale: .4 + .6 * s, child: Opacity(opacity: t.clamp(0.0, 1.0), child: paint(text)));
        }
      },
    );
  }
}

/// Opens the editor. Returns the sticker data (`style: rich`), an empty map
/// when the text was cleared (delete the layer), or null when cancelled.
Future<Map<String, dynamic>?> openMomentTextEditor(BuildContext context, {Map<String, dynamic>? initial, String? startWith}) =>
    Navigator.of(context, rootNavigator: true).push<Map<String, dynamic>>(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: .72),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => _TextEditor(initial: initial, startWith: startWith),
      transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
    ));

class _TextEditor extends StatefulWidget {
  const _TextEditor({this.initial, this.startWith});
  final Map<String, dynamic>? initial;
  final String? startWith;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final Map<String, dynamic> d = {
    'style': 'rich',
    'word': '',
    'font': 'Classic',
    'color': '#ffffff',
    'align': 'center',
    'bg': 0,
    'size': 34,
    'outline': false,
    'effect': 'none',
    'anim': 'none',
    ...?widget.initial,
  };
  late final _text = MentionTextEditingController(text: widget.initial?['word'] as String? ?? widget.startWith ?? '');
  final _focus = FocusNode();
  String _panel = 'fonts'; // fonts | colors
  List _people = [];
  int _req = 0;
  bool _rewriting = false;

  @override
  void initState() {
    super.initState();
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(String k, dynamic v) {
    HapticFeedback.selectionClick();
    setState(() => d[k] = v);
  }

  T _cycle<T>(List<T> list, T current) => list[(list.indexOf(current) + 1) % list.length];

  void _done() {
    final t = _text.text.trim();
    Navigator.pop(context, t.isEmpty ? <String, dynamic>{} : {...d, 'word': t});
  }

  Future<void> _mentions() async {
    final token = ++_req;
    final q = mentionQuery(_text);
    if (q == null) {
      if (_people.isNotEmpty) setState(() => _people = []);
      return;
    }
    final found = await searchMentionPeople(q);
    if (mounted && token == _req) setState(() => _people = found);
  }

  void _insert(String s) {
    final sel = _text.selection;
    final at = sel.isValid ? sel.start : _text.text.length;
    final v = _text.text.replaceRange(at, sel.isValid ? sel.end : at, s);
    _text.value = TextEditingValue(text: v, selection: TextSelection.collapsed(offset: at + s.length));
    setState(() {});
  }

  Future<void> _location() async {
    final c = TextEditingController();
    final place = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a location'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Place name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (place != null && place.isNotEmpty) _insert('📍 $place');
  }

  /// Rewrite: quick local variations (no AI service) — tap again to cycle.
  int _rewriteStep = 0;
  Future<void> _rewrite() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    setState(() => _rewriting = true);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final words = t.split(RegExp(r'\s+'));
    final options = [
      words.map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' '),
      t.toUpperCase(),
      '$t ✨',
      t.toLowerCase(),
    ];
    final next = options[_rewriteStep++ % options.length];
    _text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
    if (mounted) setState(() => _rewriting = false);
  }

  @override
  Widget build(BuildContext context) {
    final style = richStyle(d);
    final color = richHex(d['color']);
    final align = '${d['align']}';
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(children: [
          // The text, live.
          Positioned.fill(
            bottom: bottom + 150,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(56, 60, 24, 0),
                child: IntrinsicWidth(
                  child: Container(
                    padding: (d['bg'] as num) == 0 ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: switch ((d['bg'] as num).toInt()) {
                        1 => color,
                        2 => Colors.black.withValues(alpha: .45),
                        _ => Colors.transparent,
                      },
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      autofocus: true,
                      maxLines: null,
                      onChanged: (_) {
                        setState(() {});
                        _mentions();
                      },
                      textAlign: switch (align) {
                        'left' => TextAlign.left,
                        'right' => TextAlign.right,
                        _ => TextAlign.center,
                      },
                      cursorColor: const Color(0xFF72A7FF),
                      style: (d['bg'] as num) == 1
                          ? style.copyWith(color: color.computeLuminance() > .5 ? Colors.black : Colors.white)
                          : style,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        filled: false,
                        isCollapsed: true,
                        hintText: 'Type something',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 30, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Done.
          Positioned(
            top: 6,
            right: 8,
            child: TextButton(
              onPressed: _done,
              child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
          // Size slider (left edge).
          Positioned(
            left: 6,
            top: 90,
            bottom: bottom + 190,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: Colors.white,
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  min: 16,
                  max: 72,
                  value: (d['size'] as num).toDouble().clamp(16.0, 72.0),
                  onChanged: (v) => setState(() => d['size'] = v.roundToDouble()),
                ),
              ),
            ),
          ),
          // Bottom controls above the keyboard.
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              MentionSuggestions(
                people: _people,
                onPick: (p) {
                  applyMention(_text, '${p['username']}');
                  _req++;
                  setState(() => _people = []);
                },
              ),
              SizedBox(
                height: 48,
                child: _panel == 'colors'
                    ? ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                        for (final c in richColors)
                          GestureDetector(
                            onTap: () => _set('color', richToHex(c)),
                            child: Container(
                              width: 34,
                              height: 34,
                              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: richToHex(c) == d['color'] ? 3 : 1.5),
                              ),
                            ),
                          ),
                      ])
                    : ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                        for (final f in richFonts)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: GestureDetector(
                              onTap: () => _set('font', f.$1),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: d['font'] == f.$1 ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Text(f.$1,
                                    style: templateFont(
                                        f.$2,
                                        TextStyle(
                                            fontSize: 17,
                                            fontWeight: f.$3,
                                            color: d['font'] == f.$1 ? Colors.black : Colors.white))),
                              ),
                            ),
                          ),
                      ]),
              ),
              const SizedBox(height: 8),
              // Tool row.
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF1C1F26), borderRadius: BorderRadius.circular(16)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _Tool(
                    tooltip: 'Fonts',
                    on: _panel == 'fonts',
                    onTap: () => setState(() => _panel = 'fonts'),
                    child: const Text('Aa', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  _Tool(
                    tooltip: 'Colour',
                    on: _panel == 'colors',
                    onTap: () => setState(() => _panel = _panel == 'colors' ? 'fonts' : 'colors'),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(colors: [
                          Color(0xFFF5636B), Color(0xFFF6B93B), Color(0xFF7BD88F), Color(0xFF72A7FF), Color(0xFF8D78FF), Color(0xFFF5636B),
                        ]),
                      ),
                    ),
                  ),
                  _Tool(
                    tooltip: 'Animation: ${d['anim']}',
                    on: d['anim'] != 'none',
                    onTap: () => _set('anim', _cycle(_animations, '${d['anim']}')),
                    child: const Text('//A', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic)),
                  ),
                  _Tool(
                    tooltip: 'Outline',
                    on: d['outline'] == true,
                    onTap: () => _set('outline', d['outline'] != true),
                    child: const Icon(Icons.text_format_rounded, color: Colors.white),
                  ),
                  _Tool(
                    tooltip: 'Align',
                    onTap: () => _set('align', _cycle(const ['center', 'left', 'right'], align)),
                    child: Icon(
                      switch (align) {
                        'left' => Icons.format_align_left_rounded,
                        'right' => Icons.format_align_right_rounded,
                        _ => Icons.format_align_center_rounded,
                      },
                      color: Colors.white,
                    ),
                  ),
                  _Tool(
                    tooltip: 'Background',
                    on: (d['bg'] as num) != 0,
                    onTap: () => _set('bg', ((d['bg'] as num).toInt() + 1) % 3),
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (d['bg'] as num) == 0 ? Colors.transparent : Colors.white,
                        border: Border.all(color: Colors.white, width: 1.5),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text('A',
                          style: TextStyle(
                              color: (d['bg'] as num) == 0 ? Colors.white : Colors.black, fontWeight: FontWeight.w900, fontSize: 14)),
                    ),
                  ),
                  _Tool(
                    tooltip: 'Effect: ${d['effect']}',
                    on: d['effect'] != 'none',
                    onTap: () => _set('effect', _cycle(_effects, '${d['effect']}')),
                    child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                  ),
                ]),
              ),
              const SizedBox(height: 6),
              // Mention · Location · Rewrite.
              Container(
                color: const Color(0xFF1C1F26),
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        _insert('@');
                        _mentions();
                      },
                      icon: const Icon(Icons.alternate_email_rounded, color: Colors.white, size: 20),
                      label: const Text('Mention', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  Container(width: 1, height: 22, color: Colors.white24),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _location,
                      icon: const Icon(Icons.place_outlined, color: Colors.white, size: 20),
                      label: const Text('Location', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  Container(width: 1, height: 22, color: Colors.white24),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _rewriting ? null : _rewrite,
                      icon: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 20),
                      label: const Text('Rewrite', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.tooltip, required this.onTap, required this.child, this.on = false});
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final bool on;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? Colors.white24 : Colors.transparent, borderRadius: BorderRadius.circular(12)),
            child: child,
          ),
        ),
      );
}
