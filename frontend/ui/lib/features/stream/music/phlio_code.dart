// Phlio Stream · Music — Phlio Codes: Spotify-style scannable sound strips.
//
// A code is the Phlio play mark followed by 23 rounded bars. Bars 0, 11 and
// 22 are always full height (they tell the scanner how tall "full" is, even
// at an angle); the other 20 bars carry 3 bits each = 60 bits:
//
//   kind (2 bits) | payload (46 bits) | CRC-12 (12 bits), whitened with a mask
//
//   kind 0  Audius track id (length + base-62 value)
//   kind 1  Phlio Stream track (46-bit FNV hash of its id)
//   kind 2  a song on this phone (same hash; only resolves on this phone)
//
// The decoder (no ML, no native code) thresholds a grey image, finds bar
// blobs, chains 23 evenly spaced ones and reads their heights relative to
// the three reference bars. Uncertain bars get a second guess, and the CRC
// tells a right guess from a wrong one. Mirrors tool/phlio_code.py, which
// was tested on rendered, rotated, blurred and noisy codes.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'music_models.dart';

const _bars = 23;
const _refs = [0, 11, 22];
final _data = [for (var i = 0; i < _bars; i++) if (!_refs.contains(i)) i];
const _mask = 1024421277861575701; // 0x9E3779B97F4A7C15 & (2^60 - 1)
const _minH = 0.18;
const _alphabet = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
const _p46 = (1 << 46) - 1;

/// A decoded or to-be-drawn Phlio Code: a [kind] and a 46-bit [payload].
class PhlioCode {
  const PhlioCode(this.kind, this.payload);
  final int kind, payload;

  static const audius = 0, phlio = 1, device = 2;

  /// The code for a track, or null when it can't have one.
  static PhlioCode? forTrack(Track t) {
    if (t.source == 'audius' && t.ref != null && t.ref!.length <= 7) {
      final p = _audiusPayload(t.ref!);
      if (p != null) return PhlioCode(audius, p);
    }
    if (t.isDevice) return PhlioCode(device, hashId(t.id));
    return PhlioCode(phlio, hashId(t.id));
  }

  /// The Audius track id for [audius] codes, else null.
  String? get audiusId => kind == audius ? _audiusId(payload) : null;

  /// Bar heights 0–7 for all 23 bars (references are 7).
  List<int> get levels {
    final body = ((kind & 3) << 46) | (payload & _p46);
    final word = ((body << 12) | crc12(body)) ^ _mask;
    final out = List<int>.filled(_bars, 7);
    for (var j = 0; j < _data.length; j++) {
      out[_data[j]] = (word >> (57 - 3 * j)) & 7;
    }
    return out;
  }

  static PhlioCode? fromLevels(List<int> levels) {
    var word = 0;
    for (final i in _data) {
      word = (word << 3) | levels[i];
    }
    word ^= _mask;
    final body = word >> 12, crc = word & 0xFFF;
    if (crc12(body) != crc) return null;
    return PhlioCode(body >> 46, body & _p46);
  }

  @override
  bool operator ==(Object o) => o is PhlioCode && o.kind == kind && o.payload == payload;
  @override
  int get hashCode => Object.hash(kind, payload);

  static int crc12(int value, [int bits = 48]) {
    var crc = 0;
    for (var i = bits - 1; i >= 0; i--) {
      final bit = (value >> i) & 1;
      final top = (crc >> 11) & 1;
      crc = (crc << 1) & 0xFFF;
      if (top ^ bit == 1) crc ^= 0x80F;
    }
    return crc;
  }

  /// 64-bit FNV-1a (wrapping multiply) folded to 46 bits.
  static int hashId(String s) {
    var h = -3750763034362895579; // 0xCBF29CE484222325
    for (final b in utf8.encode(s)) {
      h ^= b;
      h *= 0x100000001B3;
    }
    return h & _p46;
  }

  static int? _audiusPayload(String id) {
    var v = 0;
    for (final ch in id.split('').reversed) {
      final i = _alphabet.indexOf(ch);
      if (i < 0) return null;
      v = v * 62 + i;
    }
    return (id.length << 43) | v;
  }

  static String _audiusId(int payload) {
    final n = payload >> 43;
    var v = payload & ((1 << 43) - 1);
    final s = StringBuffer();
    for (var i = 0; i < n; i++) {
      s.write(_alphabet[v % 62]);
      v ~/= 62;
    }
    return s.toString();
  }
}

// -- drawing -----------------------------------------------------------------------------------

/// The strip: the Phlio play mark + 23 bars. [height] is the bar area.
class PhlioCodeView extends StatelessWidget {
  const PhlioCodeView(
      {required this.code, this.height = 64, this.color = Colors.white, this.background = const Color(0xFF7C5CFF), super.key});
  final PhlioCode code;
  final double height;
  final Color color;
  final Color background;

  /// Width for a given bar-area height (unit = height / 8).
  static double widthFor(double height) {
    final u = height / 8;
    return height + 1.5 * u + (2 * _bars - 1) * u;
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(widthFor(height), height),
        painter: _CodePainter(code.levels, color, background),
      );
}

/// Draws the play mark and the bars at the given heights.
class _CodePainter extends CustomPainter {
  _CodePainter(this.levels, this.color, this.background);
  final List<int> levels;
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final hmax = size.height;
    final u = hmax / 8;
    final cy = size.height / 2;
    final p = Paint()..color = color;
    // The play mark: a disc with a play triangle cut out of it.
    canvas.drawCircle(Offset(hmax / 2, cy), hmax / 2, p);
    final tri = Path()
      ..moveTo(hmax * .38, cy - hmax * .22)
      ..lineTo(hmax * .38, cy + hmax * .22)
      ..lineTo(hmax * .72, cy)
      ..close();
    canvas.drawPath(tri, Paint()..color = background);
    var x = hmax + 1.5 * u;
    for (final lv in levels) {
      final h = math.max(u, hmax * (_minH + (1 - _minH) * lv / 7));
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, cy - h / 2, u, h), Radius.circular(u / 2)), p);
      x += 2 * u;
    }
  }

  @override
  bool shouldRepaint(_CodePainter old) => old.color != color || old.background != background || old.levels.join() != levels.join();
}

// -- decoding ----------------------------------------------------------------------------------

/// A connected blob of foreground pixels: bounding box, area and centre.
class _Blob {
  _Blob(this.x, this.y, this.w, this.h, this.area, this.cx, this.cy);
  final int x, y, w, h, area;
  final double cx, cy;
}

/// Finds and reads a Phlio Code in a grey image (row-major, one byte per
/// pixel). Returns null when there is none. Upside-down codes read too (their bars come out reversed).
PhlioCode? decodePhlioCode(Uint8List gray, int w, int h) {
  if (w < 40 || h < 10) return null;
  final th = _otsu(gray);
  for (final dark in const [true, false]) {
    final blobs = _components(gray, w, h, th, dark);
    final found = _find(blobs, w);
    if (found != null) return found;
  }
  return null;
}

int _otsu(Uint8List g) {
  final hist = List<int>.filled(256, 0);
  for (final v in g) {
    hist[v]++;
  }
  final total = g.length;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sb = 0.0, wb = 0, best = -1.0, th = 128;
  for (var t = 0; t < 256; t++) {
    wb += hist[t];
    if (wb == 0) continue;
    final wf = total - wb;
    if (wf == 0) break;
    sb += t * hist[t];
    final mb = sb / wb, mf = (sum - sb) / wf;
    final v = wb * wf * (mb - mf) * (mb - mf);
    if (v > best) {
      best = v;
      th = t;
    }
  }
  return th;
}

List<_Blob> _components(Uint8List g, int w, int h, int th, bool dark) {
  final n = w * h;
  final label = Uint8List(n); // visited flags
  final stack = Int32List(n);
  final maxW = w ~/ 12;
  final out = <_Blob>[];
  /// Whether pixel [i] is foreground for this polarity.
  bool fg(int i) => dark ? g[i] <= th : g[i] > th;
  for (var start = 0; start < n; start++) {
    if (label[start] != 0 || !fg(start)) continue;
    label[start] = 1;
    var sp = 0;
    stack[sp++] = start;
    var x0 = start % w, x1 = x0, y0 = start ~/ w, y1 = y0, area = 0, sx = 0, sy = 0;
    while (sp > 0) {
      final p = stack[--sp];
      final x = p % w, y = p ~/ w;
      area++;
      sx += x;
      sy += y;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
      if (x > 0 && label[p - 1] == 0 && fg(p - 1)) {
        label[p - 1] = 1;
        stack[sp++] = p - 1;
      }
      if (x < w - 1 && label[p + 1] == 0 && fg(p + 1)) {
        label[p + 1] = 1;
        stack[sp++] = p + 1;
      }
      if (y > 0 && label[p - w] == 0 && fg(p - w)) {
        label[p - w] = 1;
        stack[sp++] = p - w;
      }
      if (y < h - 1 && label[p + w] == 0 && fg(p + w)) {
        label[p + w] = 1;
        stack[sp++] = p + w;
      }
    }
    final bw = x1 - x0 + 1;
    if (area >= 4 && bw <= maxW) {
      out.add(_Blob(x0, y0, bw, y1 - y0 + 1, area, sx / area, sy / area));
    }
  }
  out.sort((a, b) => a.cx.compareTo(b.cx));
  return out;
}

PhlioCode? _find(List<_Blob> comps, int imageW) {
  final refs = comps.where((c) => c.h >= 3.2 * c.w && c.h >= 12);
  for (final a in refs) {
    final bw = a.w.toDouble(), bh = a.h.toDouble();
    final cand = [
      for (final c in comps)
        if (c.w >= .55 * bw &&
            c.w <= 1.7 * bw &&
            c.h <= bh * 1.3 &&
            c.cx > a.cx &&
            (c.cy - a.cy).abs() <= bh * .5 + (c.cx - a.cx) * .12)
          c
    ];
    if (cand.length < _bars - 1) continue;
    var pitch = cand.first.cx - a.cx; // cand is sorted by x
    if (pitch < bw * .9 || pitch > bw * 3.5) continue;
    final bars = <_Blob>[a];
    var slope = 0.0;
    var prev = a;
    for (var k = 0; k < _bars - 1; k++) {
      final ex = prev.cx + pitch, ey = prev.cy + slope * pitch;
      _Blob? best;
      for (final c in cand) {
        final dx = (c.cx - ex).abs();
        if (dx <= pitch * .35 && (c.cy - ey).abs() <= bh * .2 && (best == null || dx < (best.cx - ex).abs())) {
          best = c;
        }
      }
      if (best == null) break;
      pitch = .7 * pitch + .3 * (best.cx - prev.cx);
      bars.add(best);
      prev = best;
      if (bars.length >= 3) slope = (bars.last.cy - bars.first.cy) / (bars.last.cx - bars.first.cx);
    }
    if (bars.length < _bars) continue;
    final r = [for (final i in _refs) bars[i].h.toDouble()];
    if (r.reduce(math.min) < .8 * r.reduce(math.max)) continue;
    // Blur grows every bar by the same few pixels: estimate the growth from
    // the bar width (true width = full height / 8) and take half of it off.
    final ws = [for (final b in bars) b.w]..sort();
    final wm = ws[ws.length ~/ 2].toDouble();
    final raw = <double>[];
    for (var i = 0; i < _bars; i++) {
      final ref = i <= 11 ? r[0] + (r[1] - r[0]) * i / 11 : r[1] + (r[2] - r[1]) * (i - 11) / 11;
      final u = math.max(1.0, (ref - wm) / 7);
      final e = .5 * math.max(0.0, math.min(wm - u, ref * .25));
      final f = (bars[i].h - e) / math.max(1.0, ref - e);
      raw.add(((f - _minH) / (1 - _minH) * 7).clamp(-.49, 7.49));
    }
    final out = _soft(raw) ?? _soft(raw.reversed.toList());
    if (out != null) return out;
  }
  return null;
}

/// Nearest levels first; then the least certain bars at their second-nearest
/// level (the CRC tells a right guess from a wrong one).
PhlioCode? _soft(List<double> raw) {
  final levels = [for (final v in raw) v.round().clamp(0, 7)];
  final first = PhlioCode.fromLevels(levels);
  if (first != null) return first;
  final idx = [..._data]..sort((a, b) => (raw[b] - raw[b].round()).abs().compareTo((raw[a] - raw[a].round()).abs()));
  final doubt = idx.take(5).toList();
  for (var m = 1; m < 1 << doubt.length; m++) {
    final trial = [...levels];
    var valid = true;
    for (var k = 0; k < doubt.length; k++) {
      if ((m >> k) & 1 == 0) continue;
      final i = doubt[k];
      final alt = levels[i] + (raw[i] > levels[i] ? 1 : -1);
      if (alt < 0 || alt > 7) {
        valid = false;
        break;
      }
      trial[i] = alt;
    }
    if (!valid) continue;
    final out = PhlioCode.fromLevels(trial);
    if (out != null) return out;
  }
  return null;
}
