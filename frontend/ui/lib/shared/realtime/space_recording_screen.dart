// Play a recorded Space.
//
// The speakers sit on a stage; whoever was talking at the playhead (from
// the recording's speaker timeline) grows and gets a live ring, and their
// name shows under "Now speaking". Below: a scrubbable waveform built from
// the recording's peaks, ±15 s skips, play/pause and playback speed.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../features/profile/presentation/controllers/avatar_controller.dart';
import 'spaces.dart';
import 'spaces_hub_screen.dart' show formatSpaceDuration;

const _violet = PhlioColors.brandViolet;

class SpaceRecordingScreen extends StatefulWidget {
  const SpaceRecordingScreen({required this.item, super.key});
  final Map item;
  @override
  State<SpaceRecordingScreen> createState() => _SpaceRecordingScreenState();
}

class _SpaceRecordingScreenState extends State<SpaceRecordingScreen>
    with TickerProviderStateMixin {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription>[];
  late Map _item = widget.item;
  Duration _pos = Duration.zero, _dur = Duration.zero;
  bool _playing = false, _loading = true, _counted = false;
  String? _error;
  double _speed = 1;
  double? _drag;
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  List<Map> get _speakers =>
      ((_item['speakers'] as List?) ?? const []).whereType<Map>().toList();
  List<double> get _peaks => ((_item['peaks'] as List?) ?? const [])
      .map((e) => (e as num).toDouble())
      .toList();

  @override
  void initState() {
    super.initState();
    final seconds = (widget.item['duration'] as num?)?.toDouble() ?? 0;
    _dur = Duration(milliseconds: (seconds * 1000).round());
    _subs
      ..add(_player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _pos = p);
      }))
      ..add(_player.onDurationChanged.listen((d) {
        if (mounted && d > Duration.zero) setState(() => _dur = d);
      }))
      ..add(_player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playing = s == PlayerState.playing);
      }))
      ..add(_player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _pos = _dur);
      }));
    _load();
  }

  Future<void> _load() async {
    final id = _item['id'].toString();
    try {
      final full = (await getIt<ApiClient>()
              .dio
              .get('/realtime/spaces/recordings/${Uri.encodeComponent(id)}'))
          .data as Map;
      if (mounted) setState(() => _item = full);
    } catch (_) {/* the list row is enough to play */}
    try {
      await _player.setSourceUrl(
          AppConfig.mediaUrl(_item['media_url'] as String));
      if (mounted) setState(() => _loading = false);
      await _toggle();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load this recording.';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    HapticFeedback.selectionClick();
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_dur > Duration.zero && _pos >= _dur - const Duration(milliseconds: 300)) {
      await _player.seek(Duration.zero);
    }
    await _player.resume();
    if (!_counted) {
      _counted = true;
      unawaited(getIt<ApiClient>()
          .dio
          .post(
              '/realtime/spaces/recordings/${Uri.encodeComponent(_item['id'].toString())}/play')
          .then((_) {}, onError: (_) {}));
    }
  }

  Future<void> _skip(int seconds) async {
    final target = _pos + Duration(seconds: seconds);
    await _player.seek(target < Duration.zero
        ? Duration.zero
        : target > _dur
            ? _dur
            : target);
  }

  Future<void> _cycleSpeed() async {
    const speeds = [1.0, 1.25, 1.5, 2.0, 0.75];
    final next = speeds[(speeds.indexOf(_speed) + 1) % speeds.length];
    setState(() => _speed = next);
    await _player.setPlaybackRate(next);
  }

  /// Who is talking at [t] seconds, from the recording's timeline.
  String? _speakingAt(double t) {
    for (final seg in ((_item['timeline'] as List?) ?? const [])) {
      if (seg is List && seg.length >= 3) {
        final a = (seg[0] as num).toDouble(), b = (seg[1] as num).toDouble();
        if (t >= a && t <= b + .15) return seg[2].toString();
      }
    }
    return null;
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final speakers = _speakers;
    final t = _pos.inMilliseconds / 1000;
    final talking = _playing || _pos > Duration.zero ? _speakingAt(t) : null;
    final current = speakers.where((s) => s['id'] == talking).firstOrNull;
    final progress = _dur.inMilliseconds == 0
        ? 0.0
        : (_drag ?? _pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0);
    final ended = DateTime.tryParse(_item['ended_at'] as String? ?? '');
    final topics = ((_item['topics'] as List?) ?? const []).cast<String>();

    return Scaffold(
      backgroundColor: PhlioColors.backgroundDeep,
      body: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(_violet.withValues(alpha: .28),
                      PhlioColors.backgroundDeep),
                  PhlioColors.backgroundDeep,
                ],
                stops: const [0, .6],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32)),
              const Spacer(),
              IconButton(
                  tooltip: 'Share',
                  onPressed: () => SharePlus.instance.share(ShareParams(
                      text:
                          'Listen to "${_item['title']}" — a recorded Space on Phlio Social.')),
                  icon: const Icon(Icons.ios_share_rounded)),
            ]),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: _violet.withValues(alpha: .22),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('RECORDED',
                          style: PhlioTypography.caption.copyWith(
                              color: PhlioColors.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: .6)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                        [
                          formatSpaceDuration(
                              (_item['duration'] as num?) ?? 0),
                          if (ended != null) timeago.format(ended),
                        ].join(' · '),
                        style: PhlioTypography.caption
                            .copyWith(color: PhlioColors.textMuted)),
                  ]),
                  const SizedBox(height: 12),
                  Text(_item['title'] as String? ?? 'Space',
                      style: PhlioTypography.displayMedium
                          .copyWith(fontSize: 26, height: 1.18)),
                  if (topics.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final topic in topics)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: _violet.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(999)),
                          child: Text(topic,
                              style: PhlioTypography.caption.copyWith(
                                  color: PhlioColors.textPrimary)),
                        ),
                    ]),
                  ],
                  const SizedBox(height: 26),
                  _Stage(
                    speakers: speakers,
                    talking: talking,
                    hostId: _item['host_id']?.toString(),
                    pulse: _pulse,
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Row(
                      key: ValueKey(current?['id']),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (current != null) ...[
                          const SpaceEqualiser(height: 14),
                          const SizedBox(width: 8),
                          Text(
                              '${current['display_name'] ?? ''} is speaking',
                              style: PhlioTypography.bodyStrong
                                  .copyWith(color: PhlioColors.textSecondary)),
                        ] else
                          Text(_playing ? ' ' : 'Tap play to listen',
                              style: PhlioTypography.body),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Player.
            Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
              child: Column(children: [
                LayoutBuilder(builder: (context, c) {
                  void seekTo(double dx) =>
                      setState(() => _drag = (dx / c.maxWidth).clamp(0.0, 1.0));
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (d) => seekTo(d.localPosition.dx),
                    onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
                    onHorizontalDragEnd: (_) async {
                      final v = _drag;
                      if (v != null) {
                        await _player.seek(Duration(
                            milliseconds: (_dur.inMilliseconds * v).round()));
                      }
                      if (mounted) setState(() => _drag = null);
                    },
                    onTapUp: (d) async {
                      final v = (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0);
                      HapticFeedback.selectionClick();
                      await _player.seek(Duration(
                          milliseconds: (_dur.inMilliseconds * v).round()));
                    },
                    child: SizedBox(
                      height: 56,
                      width: double.infinity,
                      child: CustomPaint(
                          painter: _WavePainter(_peaks, progress,
                              dragging: _drag != null)),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                Row(children: [
                  Text(
                      _fmt(_drag != null
                          ? Duration(
                              milliseconds:
                                  (_dur.inMilliseconds * _drag!).round())
                          : _pos),
                      style: PhlioTypography.caption.copyWith(
                          color: PhlioColors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  const Spacer(),
                  Text('-${_fmt(_dur - _pos < Duration.zero ? Duration.zero : _dur - _pos)}',
                      style: PhlioTypography.caption.copyWith(
                          color: PhlioColors.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
                const SizedBox(height: 10),
                if (_error != null)
                  TextButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _loading = true;
                        });
                        _load();
                      },
                      child: Text('$_error Try again'))
                else
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(
                      width: 56,
                      child: TextButton(
                        onPressed: _cycleSpeed,
                        child: Text(
                            '${_speed == _speed.roundToDouble() ? _speed.toInt() : _speed}×',
                            style: PhlioTypography.bodyStrong
                                .copyWith(fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                        iconSize: 30,
                        tooltip: 'Back 15 seconds',
                        onPressed: _loading ? null : () => _skip(-15),
                        icon: const Icon(Icons.replay_rounded)),
                    const SizedBox(width: 14),
                    GestureDetector(
                      onTap: _loading ? null : _toggle,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: PhlioColors.sunsetGradient,
                          boxShadow: [
                            BoxShadow(
                                color: _violet
                                    .withValues(alpha: _playing ? .45 : .2),
                                blurRadius: _playing ? 26 : 12,
                                offset: const Offset(0, 6)),
                          ],
                        ),
                        child: _loading
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: PhlioColors.textOnBrand))
                            : AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                transitionBuilder: (c, a) =>
                                    ScaleTransition(scale: a, child: c),
                                child: Icon(
                                  _playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  key: ValueKey(_playing),
                                  size: 40,
                                  color: PhlioColors.textOnBrand,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    IconButton(
                        iconSize: 30,
                        tooltip: 'Forward 15 seconds',
                        onPressed: _loading ? null : () => _skip(15),
                        icon: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.rotationY(math.pi),
                            child: const Icon(Icons.replay_rounded))),
                    const SizedBox(width: 66),
                  ]),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage(
      {required this.speakers,
      required this.talking,
      required this.hostId,
      required this.pulse});
  final List<Map> speakers;
  final String? talking, hostId;
  final Animation<double> pulse;
  @override
  Widget build(BuildContext context) {
    if (speakers.isEmpty) return const SizedBox(height: 40);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 16,
      children: [
        for (final s in speakers)
          _StageSeat(
              person: s,
              talking: s['id'] == talking,
              host: s['id'] == hostId,
              pulse: pulse),
      ],
    );
  }
}

class _StageSeat extends StatelessWidget {
  const _StageSeat(
      {required this.person,
      required this.talking,
      required this.host,
      required this.pulse});
  final Map person;
  final bool talking, host;
  final Animation<double> pulse;
  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: talking ? 1.08 : .94,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: talking ? 1 : .7,
        duration: const Duration(milliseconds: 260),
        child: SizedBox(
          width: 86,
          child: Column(children: [
            SizedBox(
              width: 86,
              height: 86,
              child: Stack(alignment: Alignment.center, children: [
                if (talking)
                  AnimatedBuilder(
                    animation: pulse,
                    builder: (_, __) => CustomPaint(
                      size: const Size(86, 86),
                      painter: _PulsePainter(pulse.value),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: talking || host
                        ? PhlioColors.sunsetGradient
                        : null,
                    color: talking || host ? null : PhlioColors.border,
                  ),
                  child: IgnorePointer(
                    child: ContentAuthorAvatar(
                        author: person['id'].toString(),
                        name: person['display_name'] as String? ?? '',
                        imageUrl: person['avatar_url'] as String?,
                        size: 66),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Text(person['display_name'] as String? ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhlioTypography.bodyStrong.copyWith(fontSize: 13)),
            Text(host ? 'Host' : 'Speaker',
                style: PhlioTypography.caption.copyWith(
                    color: host
                        ? PhlioColors.brandPeach
                        : PhlioColors.textMuted)),
          ]),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final p = (t + i * .5) % 1.0;
      canvas.drawCircle(
          c,
          36 + p * 12,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = _violet.withValues(alpha: (1 - p) * .5));
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t;
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.peaks, this.progress, {required this.dragging});
  final List<double> peaks;
  final double progress;
  final bool dragging;
  @override
  void paint(Canvas canvas, Size size) {
    final n = peaks.isEmpty ? 64 : peaks.length;
    final gap = 2.0;
    final w = (size.width - gap * (n - 1)) / n;
    final played = Paint()
      ..shader = PhlioColors.sunsetGradient
          .createShader(Offset.zero & size);
    final rest = Paint()..color = PhlioColors.textMuted.withValues(alpha: .35);
    for (var i = 0; i < n; i++) {
      final v = peaks.isEmpty ? .3 : math.max(.06, peaks[i]);
      final h = size.height * (.12 + .88 * v);
      final x = i * (w + gap);
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, w, h),
          Radius.circular(w / 2));
      canvas.drawRRect(r, (x + w / 2) / size.width <= progress ? played : rest);
    }
    // Playhead.
    final x = size.width * progress;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(x, size.height / 2),
                width: dragging ? 4 : 3,
                height: size.height + (dragging ? 10 : 4)),
            const Radius.circular(2)),
        Paint()..color = PhlioColors.textPrimary);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.peaks != peaks || old.dragging != dragging;
}
