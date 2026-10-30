// CapCut-style timeline: fixed centre playhead, scrolling ruler, a main clip
// track with film strips + transition buttons (Mute / Cover on its left),
// then layer lanes: effects, filters & adjustments, overlay media, text /
// stickers / captions and audio. Items pack into as many lanes as they need;
// the selected item shows trim handles and its keyframes (◆). Pinch to zoom,
// long-press a clip to reorder.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../../design_system/colors.dart';
import 'studio_model.dart';

enum StudioSelectKind { none, clip, audio, overlay, pip, segment }

class StudioSelection {
  const StudioSelection(this.kind, [this.id]);
  const StudioSelection.none() : this(StudioSelectKind.none);
  final StudioSelectKind kind;
  final String? id;
  bool get isNone => kind == StudioSelectKind.none;
  bool matches(StudioSelectKind k, String i) => kind == k && id == i;
}

class StudioTimeline extends StatefulWidget {
  const StudioTimeline({
    required this.project,
    required this.t,
    required this.pps,
    required this.selection,
    required this.strips,
    required this.onScrubStart,
    required this.onScrub,
    required this.onZoom,
    required this.onSelect,
    required this.onTrimClip,
    required this.onTrimItem,
    required this.onMoveItem,
    required this.onEditEnd,
    required this.onTransition,
    required this.onAddClip,
    required this.onAddAudio,
    required this.onAddText,
    required this.onToggleMute,
    required this.onCover,
    required this.onReorder,
    this.cover,
    super.key,
  });

  final StudioProject project;
  final double t, pps;
  final StudioSelection selection;
  final Map<String, ui.Image> strips; // clip fileId -> film strip
  final VoidCallback onScrubStart, onAddClip, onAddAudio, onAddText, onToggleMute, onEditEnd;
  final VoidCallback onCover, onReorder;
  final Widget? cover; // cover thumbnail
  final ValueChanged<double> onScrub, onZoom;
  final ValueChanged<StudioSelection> onSelect;
  final void Function(int index, bool head, double seconds) onTrimClip;
  final void Function(StudioSelection item, bool head, double seconds) onTrimItem;
  final void Function(StudioSelection item, double seconds) onMoveItem;
  final ValueChanged<int> onTransition;

  @override
  State<StudioTimeline> createState() => _StudioTimelineState();
}

const _ruler = 24.0, _main = 58.0, _lane = 34.0, _gap = 8.0;
const _violet = PhlioColors.brandViolet;
const _peach = PhlioColors.brandPeach;
const _pink = PhlioColors.brandPink;
const _teal = Color(0xFF68D7CD);
const _blue = Color(0xFF72A7FF);
const _yellow = Color(0xFFF6B93B);
const _pinkSoft = Color(0xFFF08BC0);

class _StudioTimelineState extends State<StudioTimeline> {
  final _scroll = ScrollController();
  bool _user = false;
  final Map<int, Offset> _pointers = {};
  double? _pinchStart, _ppsStart;

  @override
  void didUpdateWidget(StudioTimeline old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted || _user || !_scroll.hasClients) return;
    final target = widget.t * widget.pps;
    if ((_scroll.offset - target).abs() > .5) {
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Every layer item, grouped by lane family (top to bottom).
  List<List<_Item>> _families() {
    final p = widget.project;
    final effects = <_Item>[], colors = <_Item>[], pips = <_Item>[], texts = <_Item>[], audios = <_Item>[];
    for (final s in p.segments) {
      final item = _Item(
        StudioSelection(StudioSelectKind.segment, s.id),
        s.start,
        s.end,
        s.kind == 'effect' ? _yellow : s.kind == 'filter' ? _teal : _blue,
        s.kind == 'effect'
            ? Icons.auto_awesome_rounded
            : s.kind == 'filter'
                ? Icons.filter_vintage_outlined
                : Icons.tune_rounded,
        s.label,
      );
      (s.kind == 'effect' ? effects : colors).add(item);
    }
    for (final x in p.pips) {
      pips.add(_Item(StudioSelection(StudioSelectKind.pip, x.id), x.at, x.at + x.length, _pink,
          x.isPhoto ? Icons.image_outlined : Icons.video_library_outlined, x.name,
          keys: [for (final k in x.keys) x.at + k[0]], pip: x));
    }
    for (final o in p.overlays) {
      texts.add(_Item(
        StudioSelection(StudioSelectKind.overlay, o.id),
        o.start,
        o.end,
        o.isCaption ? _blue : o.kind == 'text' ? _peach : _pinkSoft,
        o.isCaption
            ? Icons.closed_caption_outlined
            : o.kind == 'text'
                ? Icons.text_fields_rounded
                : Icons.emoji_emotions_outlined,
        o.label,
        keys: [for (final k in o.keys) o.start + k[0]],
      ));
    }
    for (final a in p.audios) {
      audios.add(_Item(
        StudioSelection(StudioSelectKind.audio, a.id),
        a.at,
        a.at + a.length,
        switch (a.kind) {
          'voice' => _peach,
          'extract' => _teal,
          'sfx' => _yellow,
          'tts' => _blue,
          _ => _violet,
        },
        switch (a.kind) {
          'voice' => Icons.mic_rounded,
          'sfx' => Icons.graphic_eq_rounded,
          'tts' => Icons.record_voice_over_outlined,
          'extract' => Icons.video_file_outlined,
          _ => Icons.music_note_rounded,
        },
        a.title,
        peaks: a.peaks,
        peakOffset: a.sourceDuration > 0 ? a.start / a.sourceDuration : 0,
        peakSpan: a.sourceDuration > 0 ? a.length / a.sourceDuration : 1,
      ));
    }
    return [effects, colors, pips, texts, audios];
  }

  /// Greedy lane packing within one family.
  List<List<_Item>> _pack(List<_Item> items) {
    final lanes = <List<_Item>>[];
    final sorted = [...items]..sort((a, b) => a.start.compareTo(b.start));
    for (final it in sorted) {
      final lane = lanes.where((l) => l.last.end <= it.start + 1e-3).firstOrNull;
      if (lane != null) {
        lane.add(it);
      } else {
        lanes.add([it]);
      }
    }
    return lanes;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final half = box.maxWidth / 2;
      final p = widget.project;
      final pps = widget.pps;
      final total = p.total;
      final families = _families();
      // Lanes: packed families; text and audio always keep an "Add" row.
      final rows = <List<_Item>?>[];
      for (var f = 0; f < families.length; f++) {
        final packed = _pack(families[f]);
        if (packed.isEmpty && (f == 3 || f == 4)) {
          rows.add(null); // placeholder "Add" lane
        } else {
          rows.addAll(packed);
        }
      }
      final laneTop = _ruler + _main + _gap;
      final height = laneTop + rows.length * (_lane + 4) + 16;
      final width = total * pps + box.maxWidth;
      final lanes = <Widget>[];
      var addTextShown = false;
      for (var r = 0; r < rows.length; r++) {
        final y = laneTop + r * (_lane + 4);
        final row = rows[r];
        if (row == null) {
          final text = !addTextShown && families[3].isEmpty;
          addTextShown = addTextShown || text;
          lanes.add(Positioned(
            left: half,
            top: y,
            height: _lane,
            child: text
                ? _AddLane(icon: Icons.text_fields_rounded, label: 'Add text', onTap: widget.onAddText)
                : _AddLane(icon: Icons.music_note_rounded, label: 'Add audio', onTap: widget.onAddAudio),
          ));
          continue;
        }
        for (final it in row) {
          lanes.addAll(_itemWidgets(it, half, y));
        }
      }
      return Listener(
        onPointerDown: (e) {
          _pointers[e.pointer] = e.position;
          if (_pointers.length == 2) {
            final v = _pointers.values.toList();
            _pinchStart = (v[0] - v[1]).distance;
            _ppsStart = widget.pps;
          }
        },
        onPointerMove: (e) {
          if (!_pointers.containsKey(e.pointer)) return;
          _pointers[e.pointer] = e.position;
          if (_pointers.length == 2 && _pinchStart != null && _pinchStart! > 10) {
            final v = _pointers.values.toList();
            final next = (_ppsStart! * (v[0] - v[1]).distance / _pinchStart!).clamp(16.0, 260.0);
            widget.onZoom(next);
          }
        },
        onPointerUp: (e) {
          _pointers.remove(e.pointer);
          if (_pointers.length < 2) _pinchStart = null;
        },
        onPointerCancel: (e) => _pointers.remove(e.pointer),
        child: Stack(children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) {
                _user = true;
                widget.onScrubStart();
              } else if (n is ScrollUpdateNotification && _user) {
                widget.onScrub((n.metrics.pixels / pps).clamp(0.0, total));
              } else if (n is ScrollEndNotification) {
                _user = false;
              }
              return false;
            },
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => widget.onSelect(const StudioSelection.none()),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned(
                      left: half,
                      top: 0,
                      width: total * pps,
                      height: _ruler,
                      child: CustomPaint(painter: _RulerPainter(pps, total)),
                    ),
                    // Leading controls, CapCut-style: mute clip audio + cover.
                    Positioned(
                      left: half - 118,
                      top: _ruler,
                      width: 52,
                      height: _main,
                      child: _MuteToggle(muted: p.muteOriginal, onTap: widget.onToggleMute),
                    ),
                    Positioned(
                      left: half - 62,
                      top: _ruler + 2,
                      width: 52,
                      height: _main - 4,
                      child: _CoverButton(onTap: widget.onCover, child: widget.cover),
                    ),
                    ..._clips(half),
                    Positioned(
                      left: half + total * pps + 10,
                      top: _ruler + (_main - 40) / 2,
                      child: _AddButton(onTap: widget.onAddClip),
                    ),
                    ...lanes,
                  ]),
                ),
              ),
            ),
          ),
          // Centre playhead.
          Positioned(
            left: half - 1,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: .4), blurRadius: 4)
                  ],
                ),
              ),
            ),
          ),
        ]),
      );
    });
  }

  List<Widget> _clips(double half) {
    final p = widget.project;
    final pps = widget.pps;
    final starts = p.starts;
    final out = <Widget>[];
    for (var i = 0; i < p.clips.length; i++) {
      final c = p.clips[i];
      final selected = widget.selection.matches(StudioSelectKind.clip, c.id);
      final visible = (c.length - p.overlapAfter(i)) * pps;
      final left = half + starts[i] * pps;
      out.add(Positioned(
        left: left,
        top: _ruler,
        width: math.max(6, visible - 2),
        height: _main,
        child: GestureDetector(
          onTap: () => widget.onSelect(StudioSelection(StudioSelectKind.clip, c.id)),
          onLongPress: widget.onReorder,
          child: _ClipBox(
            clip: c,
            strip: c.fileId == null ? null : widget.strips[c.fileId],
            selected: selected,
            pps: pps,
          ),
        ),
      ));
      if (selected) {
        for (final k in c.keys) {
          out.add(_diamond(left + k[0] * pps, _ruler + _main - 9));
        }
        out.add(_handle(left - 14, _ruler, _main, (dx) => widget.onTrimClip(i, true, dx / pps)));
        out.add(_handle(left + visible - 2, _ruler, _main, (dx) => widget.onTrimClip(i, false, dx / pps)));
      }
      if (i < p.clips.length - 1) {
        final x = half + starts[i + 1] * pps;
        out.add(Positioned(
          left: x - 13,
          top: _ruler + _main / 2 - 13,
          child: GestureDetector(
            onTap: () => widget.onTransition(i),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: c.transition == 'none' ? Colors.white : _violet,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .4), blurRadius: 6)],
              ),
              child: Icon(
                c.transition == 'none' ? Icons.horizontal_rule_rounded : Icons.auto_awesome_motion_rounded,
                size: 15,
                color: c.transition == 'none' ? const Color(0xFF0B0F17) : Colors.white,
              ),
            ),
          ),
        ));
      }
    }
    return out;
  }

  Widget _diamond(double x, double y) => Positioned(
        left: x - 6,
        top: y - 6,
        child: IgnorePointer(
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: _violet, width: 2),
              ),
            ),
          ),
        ),
      );

  Widget _handle(double left, double top, double height, ValueChanged<double> onDrag) => Positioned(
        left: left,
        top: top,
        width: 16,
        height: height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
          onHorizontalDragEnd: (_) => widget.onEditEnd(),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Container(
                width: 2.5,
                height: height * .36,
                decoration: BoxDecoration(
                    color: const Color(0xFF0B0F17), borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
        ),
      );

  List<Widget> _itemWidgets(_Item it, double half, double y) {
    final pps = widget.pps;
    final sel = it.sel;
    final selected = widget.selection.matches(sel.kind, sel.id!);
    final left = half + it.start * pps;
    final w = math.max(8.0, (it.end - it.start) * pps);
    final out = <Widget>[
      Positioned(
        left: left,
        top: y,
        width: w,
        height: _lane,
        child: GestureDetector(
          onTap: () => widget.onSelect(sel),
          onHorizontalDragUpdate: selected ? (d) => widget.onMoveItem(sel, d.delta.dx / pps) : null,
          onHorizontalDragEnd: selected ? (_) => widget.onEditEnd() : null,
          child: _Pill(
            color: it.color,
            selected: selected,
            icon: it.icon,
            label: it.label,
            peaks: it.peaks,
            peakOffset: it.peakOffset,
            peakSpan: it.peakSpan,
            thumb: it.pip == null
                ? null
                : it.pip!.isPhoto
                    ? FileImage(File(it.pip!.path))
                    : null,
          ),
        ),
      ),
    ];
    if (selected) {
      for (final k in it.keys) {
        out.add(_diamond(half + k * pps, y + _lane - 7));
      }
      out.add(_handle(left - 14, y, _lane, (dx) => widget.onTrimItem(sel, true, dx / pps)));
      out.add(_handle(left + w - 2, y, _lane, (dx) => widget.onTrimItem(sel, false, dx / pps)));
    }
    return out;
  }
}

class _Item {
  _Item(this.sel, this.start, this.end, this.color, this.icon, this.label,
      {this.peaks = const [], this.peakOffset = 0, this.peakSpan = 1, this.keys = const [], this.pip});
  final StudioSelection sel;
  final double start, end;
  final Color color;
  final IconData icon;
  final String label;
  final List<double> peaks;
  final double peakOffset, peakSpan;
  final List<double> keys; // absolute keyframe times
  final StudioPip? pip;
}

class _ClipBox extends StatelessWidget {
  const _ClipBox({required this.clip, required this.strip, required this.selected, required this.pps});
  final StudioClip clip;
  final ui.Image? strip;
  final bool selected;
  final double pps;

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (clip.kind == 'image') {
      body = DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: ResizeImage(FileImage(File(clip.path)), height: 140),
            fit: BoxFit.fitHeight,
            repeat: ImageRepeat.repeatX,
            alignment: Alignment.centerLeft,
          ),
        ),
      );
    } else if (strip != null) {
      body = CustomPaint(painter: _StripPainter(strip!, clip));
    } else {
      body = DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF2A2350), Color(0xFF3B3470)]),
        ),
        child: const Center(
          child: SizedBox(
              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6)),
        ),
      );
    }
    final badges = <Widget>[
      if (clip.hasCurve) const _Badge('〰')
      else if (clip.speed != 1) _Badge('${_fmt(clip.speed)}x'),
      if (clip.voice != 'none') const _Badge('🎙'),
      if (clip.reverse) const _Badge('↺'),
      if (clip.hold != null) const _Badge('❄'),
      if (clip.volume == 0) const _Badge('🔇'),
      if (clip.filter != 'none') const _Badge('◐'),
      if (clip.effect != 'none') const _Badge('✦'),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(fit: StackFit.expand, children: [
        ColorFiltered(
          colorFilter: ColorFilter.matrix(flutterColorMatrix(clip.colorMatrix)),
          child: body,
        ),
        Positioned(
          left: 4,
          top: 4,
          child: Row(mainAxisSize: MainAxisSize.min, children: badges),
        ),
        Positioned(
          right: 4,
          bottom: 3,
          child: Text(_fmt(clip.length) + 's',
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 3)])),
        ),
        if (selected)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2.2),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
      ]),
    );
  }
}

String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 3),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(4)),
        child: Text(text,
            style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w800)),
      );
}

class _StripPainter extends CustomPainter {
  _StripPainter(this.strip, this.clip);
  final ui.Image strip;
  final StudioClip clip;
  @override
  void paint(Canvas canvas, Size size) {
    const frames = 12;
    final tileW = strip.width / frames, tileH = strip.height.toDouble();
    final dstW = size.height * tileW / tileH;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final dur = math.max(.1, clip.sourceDuration);
    for (var x = 0.0; x < size.width; x += dstW) {
      final local = (x + dstW / 2) / size.width * clip.length;
      final src = clip.sourceAt(local);
      final i = (src / dur * frames).floor().clamp(0, frames - 1);
      canvas.drawImageRect(strip, Rect.fromLTWH(i * tileW, 0, tileW, tileH),
          Rect.fromLTWH(x, 0, dstW, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) => true;
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.color,
    required this.selected,
    required this.icon,
    required this.label,
    this.peaks = const [],
    this.peakOffset = 0,
    this.peakSpan = 1,
    this.thumb,
  });
  final ImageProvider? thumb;
  final Color color;
  final bool selected;
  final IconData icon;
  final String label;
  final List<double> peaks;
  final double peakOffset, peakSpan;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withValues(alpha: .28), const Color(0xFF151C29)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? Colors.white : color.withValues(alpha: .7), width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (thumb != null)
            Opacity(
              opacity: .45,
              child: Image(
                  image: ResizeImage(thumb!, height: 80),
                  fit: BoxFit.fitHeight,
                  repeat: ImageRepeat.repeatX,
                  alignment: Alignment.centerLeft),
            ),
          if (peaks.isNotEmpty)
            CustomPaint(painter: _PeaksPainter(peaks, color, peakOffset, peakSpan)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [
              Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 4),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ]),
          ),
        ]),
      );
}

class _PeaksPainter extends CustomPainter {
  _PeaksPainter(this.peaks, this.color, this.offset, this.span);
  final List<double> peaks;
  final Color color;
  final double offset, span;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: .7);
    const bar = 3.0;
    for (var x = 0.0; x < size.width; x += bar + 1) {
      final f = offset + (x / size.width) * span;
      final i = (f * peaks.length).floor().clamp(0, peaks.length - 1);
      final h = math.max(2.0, peaks[i] * size.height * .8);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - h - 2, bar, h), const Radius.circular(1)),
          paint);
    }
  }

  @override
  bool shouldRepaint(_PeaksPainter old) => true;
}

class _RulerPainter extends CustomPainter {
  _RulerPainter(this.pps, this.total);
  final double pps, total;
  @override
  void paint(Canvas canvas, Size size) {
    final step = pps >= 90 ? .5 : pps >= 40 ? 1.0 : pps >= 20 ? 2.0 : 5.0;
    final label = step <= 1 ? 2.0 : step * 2;
    final dot = Paint()..color = Colors.white.withValues(alpha: .35);
    for (var s = 0.0; s <= total + 1e-6; s += step) {
      final x = s * pps;
      if ((s / label - (s / label).round()).abs() < 1e-6) {
        final tp = TextPainter(
          text: TextSpan(
              text: _clock(s),
              style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: .55))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 4));
      } else {
        canvas.drawCircle(Offset(x, 10), 1.4, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.pps != pps || old.total != total;
}

String _clock(double s) {
  final m = s ~/ 60, r = (s % 60).floor();
  return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}

class _MuteToggle extends StatelessWidget {
  const _MuteToggle({required this.muted, required this.onTap});
  final bool muted;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              size: 20, color: muted ? PhlioColors.danger : Colors.white),
          const SizedBox(height: 3),
          Text(muted ? 'Unmute\nclip audio' : 'Mute clip\naudio',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, height: 1.15, color: Colors.white70)),
        ]),
      );
}

class _CoverButton extends StatelessWidget {
  const _CoverButton({required this.onTap, this.child});
  final VoidCallback onTap;
  final Widget? child;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C2433),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(fit: StackFit.expand, children: [
            if (child != null) Opacity(opacity: .55, child: child!),
            const Center(
              child: Text('Cover',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 3)])),
            ),
          ]),
        ),
      );
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.add_rounded, color: Color(0xFF0B0F17), size: 26),
        ),
      );
}

class _AddLane extends StatelessWidget {
  const _AddLane({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 170,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(children: [
            const Icon(Icons.add_rounded, size: 16, color: Colors.white70),
            const SizedBox(width: 4),
            Icon(icon, size: 14, color: Colors.white54),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
        ),
      );
}
