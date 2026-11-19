// The rotating line under a name on moments and Experiences (Instagram's
// "song · reshared from · …" ticker). Every 3 seconds it slides to the next
// fact about the post: the song, who it was reshared from, who's mentioned,
// collaborators, the place, the story effect, the filter and the effect.
//
//   * [momentMetaLines] / [experienceMetaLines] build the facts from an item.
//   * [RotatingMeta] shows them, one at a time.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/widgets/phlio_card.dart';
import '../media/phlio_look_data.dart';
import '../media/smart_filters.dart';
import '../media/story_fx_catalog.dart';

/// One fact: a leading glyph, the text, and what tapping it does.
class MetaLine {
  const MetaLine({required this.key, required this.lead, required this.text, this.onTap});
  final String key;
  final Widget lead;
  final String text;
  final VoidCallback? onTap;
}

const _metaText = TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500);

Widget _icon(IconData icon) => Icon(icon, size: 14, color: Colors.white);

Widget _faces(List<Map> people) {
  final shown = people.take(2).toList();
  return SizedBox(
    width: 16 + (shown.length - 1) * 10,
    height: 16,
    child: Stack(children: [
      for (var i = 0; i < shown.length; i++)
        Positioned(
          left: i * 10,
          child: PhlioAvatar(
              name: '${shown[i]['display_name'] ?? shown[i]['username'] ?? ''}',
              imageUrl: shown[i]['avatar_url'] as String?,
              size: 16,
              showMomentRing: false),
        ),
    ]),
  );
}

String _people(List<Map> people) {
  final names = people.map((p) => '@${p['username']}').toList();
  if (names.length <= 2) return names.join(', ');
  return '${names.take(2).join(', ')} +${names.length - 2}';
}

/// "@a" handles in a caption (people we can't resolve still read fine).
List<Map> _captionMentions(String? caption) => [
      for (final m in RegExp(r'(?<![A-Za-z0-9_.])@([A-Za-z0-9_](?:[A-Za-z0-9_.]*[A-Za-z0-9_])?)')
          .allMatches(caption ?? ''))
        {'username': m.group(1)}
    ];

List<Map> _mentions(Map item) {
  final seen = <String>{};
  final out = <Map>[];
  void add(Map p) {
    final u = '${p['username'] ?? ''}'.replaceFirst('@', '');
    if (u.isNotEmpty && seen.add(u.toLowerCase())) out.add({...p, 'username': u});
  }

  for (final p in (item['mentions'] as List? ?? const []).whereType<Map>()) {
    add(p);
  }
  // Mention layers kept on videos (text "@name" or sticker data).
  for (final layer in (item['overlays'] as List? ?? const []).whereType<Map>()) {
    if (layer['type'] != 'mention') continue;
    final data = layer['data'] is Map ? layer['data'] as Map : const {};
    final name = '${data['username'] ?? layer['text'] ?? ''}'.trim();
    if (name.isNotEmpty) add({'username': name, 'avatar_url': data['avatar_url']});
  }
  for (final p in _captionMentions(item['caption'] as String?)) {
    add(p);
  }
  return out;
}

/// Filter, effect and story-effect facts shared by moments and Experiences.
List<MetaLine> _lookLines(Map item) {
  final spec = FilterSpec.fromJson(item['filter_spec']);
  final (legacyLook, legacyEffect) = splitMomentFilter(item['filter'] as String?);
  final look = normalizeLook(spec?.appliedLook ?? (spec != null && spec.look != 'normal' ? spec.look : legacyLook));
  final effect = spec?.effect ?? (legacyEffect == 'none' ? null : legacyEffect);
  final fx = storyFxById[spec?.fx];
  final lines = <MetaLine>[];
  if (fx != null) {
    lines.add(MetaLine(key: 'fx', lead: _icon(Icons.auto_awesome_rounded), text: '${fx.name} · Effect'));
  }
  if (effect != null && phlioEffectId(effect) != 0) {
    final label = phlioEffects.firstWhere((e) => e.$1 == effect).$2;
    lines.add(MetaLine(key: 'effect', lead: _icon(Icons.auto_fix_high_rounded), text: '$label · Effect'));
  }
  if (look != 'normal' && phlioLookNames[look] != null) {
    lines.add(MetaLine(key: 'look', lead: _icon(Icons.filter_vintage_outlined), text: '${phlioLookNames[look]} · Filter'));
  }
  if (spec != null && spec.adjust.isNotEmpty) {
    lines.add(MetaLine(key: 'adjust', lead: _icon(Icons.tune_rounded), text: 'Edited · ${spec.adjust.length} adjustment${spec.adjust.length == 1 ? '' : 's'}'));
  }
  return lines;
}

/// Facts about a moment, in Instagram's order: song, reshare, mentions,
/// then effect / filter.
List<MetaLine> momentMetaLines(
  Map item, {
  required bool playing,
  ValueChanged<String>? onProfile,
  VoidCallback? onSong,
}) {
  final lines = <MetaLine>[];
  final song = item['music'] is Map ? item['music'] as Map : null;
  if (song != null) {
    lines.add(MetaLine(
      key: 'song',
      lead: EqualizerBars(playing: playing),
      text: '${song['artist'] ?? ''} · ${song['title'] ?? ''}',
      onTap: onSong,
    ));
  }
  final reshare = item['reshared_from'] is Map ? item['reshared_from'] as Map : null;
  if (reshare != null) {
    lines.add(MetaLine(
      key: 'reshare',
      lead: Row(mainAxisSize: MainAxisSize.min, children: [
        _icon(Icons.repeat_rounded),
        const SizedBox(width: 5),
        _faces([reshare]),
      ]),
      text: '${reshare['username'] ?? ''}',
      onTap: onProfile == null || reshare['username'] == null ? null : () => onProfile('${reshare['username']}'),
    ));
  }
  final mentioned = _mentions(item);
  if (mentioned.isNotEmpty) {
    lines.add(MetaLine(
      key: 'mentions',
      lead: mentioned.any((p) => p['avatar_url'] != null) ? _faces(mentioned) : _icon(Icons.alternate_email_rounded),
      text: _people(mentioned),
      onTap: onProfile == null ? null : () => onProfile('${mentioned.first['username']}'),
    ));
  }
  lines.addAll(_lookLines(item));
  return lines;
}

/// Facts about an Experience card: place, collaborators, mentions, then
/// effect / filter / edits.
List<MetaLine> experienceMetaLines(Map item, {List<Map> collaborators = const [], ValueChanged<String>? onProfile, VoidCallback? onPlace}) {
  final lines = <MetaLine>[];
  final place = item['location'] is Map ? item['location'] as Map : null;
  if (place != null) {
    lines.add(MetaLine(key: 'place', lead: _icon(Icons.location_on_rounded), text: '${place['name']}', onTap: onPlace));
  }
  if (collaborators.isNotEmpty) {
    lines.add(MetaLine(
      key: 'team',
      lead: _faces(collaborators),
      text: 'With ${_people(collaborators)}',
      onTap: onProfile == null ? null : () => onProfile('${collaborators.first['username']}'),
    ));
  }
  final mentioned = _mentions(item);
  if (mentioned.isNotEmpty) {
    lines.add(MetaLine(
      key: 'mentions',
      lead: _icon(Icons.alternate_email_rounded),
      text: _people(mentioned),
      onTap: onProfile == null ? null : () => onProfile('${mentioned.first['username']}'),
    ));
  }
  lines.addAll(_lookLines(item));
  return lines;
}

/// Shows [lines] one at a time, sliding up to the next every [interval].
class RotatingMeta extends StatefulWidget {
  const RotatingMeta({required this.lines, this.interval = const Duration(seconds: 3), this.paused = false, this.style, super.key});
  final List<MetaLine> lines;
  final Duration interval;

  /// Holds on the current line (while the story is paused).
  final bool paused;
  final TextStyle? style;

  @override
  State<RotatingMeta> createState() => _RotatingMetaState();
}

class _RotatingMetaState extends State<RotatingMeta> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(RotatingMeta old) {
    super.didUpdateWidget(old);
    final keys = widget.lines.map((l) => l.key).join('|');
    if (keys != old.lines.map((l) => l.key).join('|')) {
      _index = 0;
      _restart();
    } else if (old.paused != widget.paused) {
      _restart();
    }
  }

  void _restart() {
    _timer?.cancel();
    if (widget.lines.length < 2 || widget.paused) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _index = (_index + 1) % widget.lines.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) return const SizedBox.shrink();
    final line = widget.lines[math.min(_index, widget.lines.length - 1)];
    return SizedBox(
      height: 20,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final incoming = child.key == ValueKey(line.key);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(begin: Offset(0, incoming ? 1 : -1), end: Offset.zero).animate(animation),
                child: child,
              ),
            );
          },
          layoutBuilder: (current, previous) =>
              Stack(alignment: Alignment.centerLeft, children: [...previous, if (current != null) current]),
          child: GestureDetector(
            key: ValueKey(line.key),
            behavior: HitTestBehavior.opaque,
            onTap: line.onTap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              line.lead,
              const SizedBox(width: 6),
              Flexible(
                child: Text(line.text,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: widget.style ?? _metaText),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Three little bars that bounce while the song plays.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({required this.playing, super.key});
  final bool playing;
  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _beat.repeat();
  }

  @override
  void didUpdateWidget(covariant EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_beat.isAnimating) _beat.repeat();
    if (!widget.playing && _beat.isAnimating) _beat.stop();
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _beat,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 3,
                height: 5 + 7 * (0.5 + 0.5 * math.sin(_beat.value * 2 * math.pi + i * 1.7)),
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
              ),
          ],
        ),
      );
}
