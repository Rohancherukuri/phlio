import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../../design_system/colors.dart';
import '../controllers/video_playback_controller.dart';

/// Twitch's player chrome, drawn inside the picture: tap to show or hide,
/// auto-hides while playing.
///   top-left  ⌄ minimise          top-right  cast · share · settings
///   centre    ❚❚ / ▶ (large, no circle)
///   bottom    ● time [👤 viewers]    🔊 · rotate/fullscreen
/// Twitch's Clip and Cast buttons are left out; the red dot and the viewer
/// pill only appear on live videos. Recorded videos keep a scrubber on the
/// bottom edge.
class VideoOverlayControls extends StatefulWidget {
  const VideoOverlayControls({
    required this.controller,
    required this.picture,
    required this.fullscreen,
    required this.onSettings,
    this.title,
    this.live = false,
    this.viewers,
    this.onClose,
    this.onShare,
    super.key,
  });

  final VideoPlaybackController controller;
  final Widget picture;
  final bool fullscreen, live;
  final String? title;
  final num? viewers;
  final VoidCallback onSettings;
  final VoidCallback? onClose;
  final VoidCallback? onShare;

  @override
  State<VideoOverlayControls> createState() => _VideoOverlayControlsState();
}

const _iconSize = 26.0; // every control icon (play/pause excepted)

class _VideoOverlayControlsState extends State<VideoOverlayControls> {
  bool _visible = true;
  bool _scrubbing = false;
  double? _scrubValue;
  Timer? _hide;
  VideoPlayerController? _player;

  @override
  void initState() {
    super.initState();
    _attach();
    _schedule();
  }

  @override
  void didUpdateWidget(VideoOverlayControls old) {
    super.didUpdateWidget(old);
    if (widget.controller.player != _player) _attach();
  }

  void _attach() {
    _player?.removeListener(_tick);
    _player = widget.controller.player;
    _player?.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hide?.cancel();
    _player?.removeListener(_tick);
    super.dispose();
  }

  bool get _playing => _player?.value.isPlaying == true;

  void _schedule() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing && !_scrubbing) setState(() => _visible = false);
    });
  }

  void _show() {
    setState(() => _visible = true);
    _schedule();
  }

  void _toggleVisible() {
    setState(() => _visible = !_visible);
    if (_visible) _schedule();
  }

  void _act(VoidCallback action) {
    HapticFeedback.selectionClick();
    action();
    _show();
  }

  void _cast() {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Casting to a TV — coming soon.')));
  }

  String _time(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  String _count(num n) => n >= 1e6
      ? '${(n / 1e6).toStringAsFixed(1)}M'
      : n >= 1e3
          ? '${(n / 1e3).toStringAsFixed(1)}K'
          : '${n.toInt()}';

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final p = _player;
    final ready = p?.value.isInitialized == true && c.error == null;
    final duration = ready ? p!.value.duration : Duration.zero;
    final position = ready ? p!.value.position : Duration.zero;
    final live = widget.live || (ready && duration == Duration.zero);
    final buffering = ready && p!.value.isBuffering;
    final showChrome = _visible || !ready || !_playing;
    final total = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final progress = (_scrubValue ?? position.inMilliseconds.toDouble()).clamp(0.0, total);
    Widget icon(IconData icon, String tip, VoidCallback onTap) => IconButton(
          tooltip: tip,
          onPressed: () => _act(onTap),
          icon: Icon(icon, color: Colors.white, size: _iconSize),
          visualDensity: VisualDensity.compact,
        );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleVisible,
      child: Stack(fit: StackFit.expand, children: [
        widget.picture,
        if (buffering)
          const Center(
            child: SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
          ),
        IgnorePointer(
          ignoring: !showChrome,
          child: AnimatedOpacity(
            opacity: showChrome ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Stack(fit: StackFit.expand, children: [
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, .3, .65, 1],
                      colors: [Color(0x66000000), Color(0x22000000), Color(0x22000000), Color(0x80000000)],
                    ),
                  ),
                ),
              ),
              // Top bar (Twitch: ⌄ on the left; share, settings on the right).
              Positioned(
                left: 2,
                right: 4,
                top: 0,
                child: Row(children: [
                  icon(Icons.keyboard_arrow_down_rounded, widget.fullscreen ? 'Exit fullscreen' : 'Minimize player',
                      () => c.setMode(widget.fullscreen ? SocialPlayerMode.expanded : SocialPlayerMode.floating)),
                  Expanded(
                    child: widget.fullscreen && widget.title != null
                        ? Text(widget.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))
                        : const SizedBox(),
                  ),
                  icon(Icons.cast_rounded, 'Cast', _cast),
                  if (widget.onShare != null) icon(Icons.share_outlined, 'Share', widget.onShare!),
                  icon(Icons.settings_outlined, 'Settings', widget.onSettings),
                ]),
              ),
              // Centre: one large play / pause glyph.
              if (ready)
                Center(
                  child: GestureDetector(
                    onTap: () => _act(c.toggle),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: widget.fullscreen ? 76 : 62,
                          shadows: const [Shadow(blurRadius: 10, color: Colors.black38)]),
                    ),
                  ),
                ),
              // Bottom bar: ● time + (live) viewer pill … volume, rotate.
              Positioned(
                left: 10,
                right: 4,
                bottom: live ? 4 : 10,
                child: Row(children: [
                  if (live)
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(right: 7),
                      decoration: const BoxDecoration(color: Color(0xFFEB0400), shape: BoxShape.circle),
                    ),
                  if (ready)
                    Text(_time(live ? position : Duration(milliseconds: progress.round())),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
                            fontFeatures: [FontFeature.tabularFigures()])),
                  if (live && widget.viewers != null) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .35), borderRadius: BorderRadius.circular(6)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.person_outline_rounded, color: Colors.white, size: 17),
                        const SizedBox(width: 4),
                        Text(_count(widget.viewers!),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14)),
                      ]),
                    ),
                  ],
                  const Spacer(),
                  icon(c.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, 'Mute or unmute',
                      () => c.setVolume(c.volume == 0 ? 1 : 0)),
                  icon(widget.fullscreen ? Icons.fullscreen_exit_rounded : Icons.screen_rotation_rounded,
                      widget.fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                      () => c.setMode(widget.fullscreen ? SocialPlayerMode.expanded : SocialPlayerMode.fullscreen)),
                ]),
              ),
            ]),
          ),
        ),
        // Progress bar on the bottom edge: thin when hidden, scrubbable when shown.
        if (ready && !live)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: showChrome ? 24 : 3,
            child: showChrome
                ? SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: PhlioColors.brandViolet,
                      inactiveTrackColor: Colors.white24,
                      secondaryActiveTrackColor: Colors.white54,
                      thumbColor: PhlioColors.brandViolet,
                      overlayShape: SliderComponentShape.noOverlay,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: _scrubbing ? 8 : 6),
                      trackShape: const _EdgeTrackShape(),
                    ),
                    child: Slider(
                      min: 0,
                      max: total,
                      value: progress,
                      secondaryTrackValue: _buffered(p!).clamp(0.0, total),
                      onChangeStart: (v) => setState(() {
                        _scrubbing = true;
                        _scrubValue = v;
                        _hide?.cancel();
                      }),
                      onChanged: (v) => setState(() => _scrubValue = v),
                      onChangeEnd: (v) {
                        c.seek(Duration(milliseconds: v.round()));
                        setState(() {
                          _scrubbing = false;
                          _scrubValue = null;
                        });
                        _schedule();
                      },
                    ),
                  )
                : IgnorePointer(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress / total,
                        child: const ColoredBox(color: PhlioColors.brandViolet, child: SizedBox(height: 3)),
                      ),
                    ),
                  ),
          ),
      ]),
    );
  }

  double _buffered(VideoPlayerController p) {
    var end = 0;
    for (final r in p.value.buffered) {
      if (r.end.inMilliseconds > end) end = r.end.inMilliseconds;
    }
    return end.toDouble();
  }
}

/// Track that runs edge to edge (no side padding), like Twitch's scrubber.
class _EdgeTrackShape extends RoundedRectSliderTrackShape {
  const _EdgeTrackShape();
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final height = sliderTheme.trackHeight ?? 3;
    return Rect.fromLTWH(offset.dx, offset.dy + parentBox.size.height - height - 4, parentBox.size.width, height);
  }
}
