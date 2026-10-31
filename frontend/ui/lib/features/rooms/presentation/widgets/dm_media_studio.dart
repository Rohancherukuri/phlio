// Phlio Studio — the CapCut-style photo & video editor for DMs.
//
//  ┌ ✕          1080P ▾   [Export] ┐   top bar (export settings sheet)
//  │          preview canvas        │   clips, overlay media, text: drag / pinch
//  │ ⤢   00:03 / 00:25  ▶  ◇ ↶ ↷   │   transport (◇ = keyframe at playhead)
//  │ ruler · clips · layer lanes    │   timeline (centre playhead, pinch zoom)
//  └ Edit Audio Text Effects Overlay Captions Filters Adjust Stickers Ratio Background
//
// Same toolset and layout as CapCut's editor, in Phlio's palette: per-clip
// menus (split, speed + curves, volume, animations, effects, voice effects,
// extract audio, filters, adjust, crop, transform, reverse, freeze…),
// timeline effect / filter / adjustment layers, overlay media with blend
// modes, masks and chroma key, keyframes, text / stickers / auto captions
// with in / out / loop animations, music, sound effects, text to audio and
// voiceovers, cover and export settings.
//
// Everything is edited on the device (live preview with the same colour
// matrices and overlay painter the export uses); Export uploads the sources,
// renders on the server with progress, then opens the publish screen: send
// here, send to other chats, share as a moment or experience, or save to the
// gallery. The project model lives in studio/studio_model.dart.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../shared/music/song_picker.dart';
import '../../data/datasources/messaging_api.dart';
import 'chat_composer.dart';
import 'studio/studio_model.dart';
import '../../../../shared/media/phlio_look_view.dart';
import 'studio/studio_layers.dart';
import 'studio/studio_overlay.dart';
import 'studio/studio_panels.dart';
import 'studio/studio_publish.dart';
import 'studio/studio_sheets.dart';
import 'studio/studio_timeline.dart';

const _bg = Color(0xFF07090E);
const _violet = PhlioColors.brandViolet;

enum _Panel {
  none,
  speed,
  volume,
  filters,
  adjust,
  effects,
  animation,
  transition,
  ratio,
  background,
  stickers,
  audioMenu,
  voiceover,
  textStyle,
  overlayAnim,
  export,
  voice,
  blend,
  mask,
  chroma,
  textMenu,
  segEffects,
}

class DmMediaStudio extends StatefulWidget {
  const DmMediaStudio(
      {required this.peer, required this.initial, required this.onSend, super.key});
  final String peer;
  final StagedAttachment initial;
  final Future<void> Function(StagedAttachment) onSend;
  @override
  State<DmMediaStudio> createState() => _StudioState();
}

class _StudioState extends State<DmMediaStudio> with TickerProviderStateMixin {
  final _dio = getIt<ApiClient>().dio;
  late final _messaging = MessagingApi(_dio);
  final p = StudioProject();
  final _undo = <String>[], _redo = <String>[];

  // Playback.
  double t = 0;
  bool playing = false;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  int _active = -1;
  double _driftCheck = 0;
  double _rate = 1;
  final Map<String, VideoPlayerController> _players = {};
  final Map<String, VideoPlayerController> _pipPlayers = {};
  bool _reorder = false;
  bool _captioning = false;
  final Map<String, AudioPlayer> _audio = {};
  final Set<String> _audioOn = {};

  // Timeline.
  double pps = 56;
  StudioSelection sel = const StudioSelection.none();
  final Map<String, ui.Image> _strips = {};

  // Uploads (path → future file map).
  final Map<String, Future<Map<String, dynamic>>> _uploads = {};

  _Panel panel = _Panel.none;
  bool _clipTools = false;
  String? _toast;
  Timer? _toastTimer;
  bool _busy = false;
  bool _fullscreen = false;

  // Voiceover.
  final _recorder = AudioRecorder();
  bool _recording = false;
  double _recordFrom = 0;
  DateTime? _recordStarted;

  // Overlay gestures.
  double _gestureSize = 0, _gestureRotation = 0;
  Offset _gesturePan = Offset.zero;
  double _pipStartW = .5;

  StudioClip? get _clip => sel.kind == StudioSelectKind.clip
      ? p.clips.where((c) => c.id == sel.id).firstOrNull
      : null;
  StudioAudio? get _audioSel => sel.kind == StudioSelectKind.audio
      ? p.audios.where((a) => a.id == sel.id).firstOrNull
      : null;
  StudioOverlay? get _overlay => sel.kind == StudioSelectKind.overlay
      ? p.overlays.where((o) => o.id == sel.id).firstOrNull
      : null;
  StudioPip? get _pip => sel.kind == StudioSelectKind.pip
      ? p.pips.where((x) => x.id == sel.id).firstOrNull
      : null;
  StudioSegment? get _segment => sel.kind == StudioSelectKind.segment
      ? p.segments.where((x) => x.id == sel.id).firstOrNull
      : null;

  /// The clip under the playhead (tools apply to it when nothing is selected).
  StudioClip? get _target {
    if (_clip != null) return _clip;
    if (p.clips.isEmpty) return null;
    return p.clips[p.clipAt(t).$1];
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    final initial = widget.initial;
    _addMedia(initial.path!, initial.name, initial.kind == 'video' ? 'video' : 'image', first: true);
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final c in _players.values) {
      c.dispose();
    }
    for (final c in _pipPlayers.values) {
      c.dispose();
    }
    for (final a in _audio.values) {
      a.dispose();
    }
    _recorder.dispose();
    _toastTimer?.cancel();
    super.dispose();
  }

  // -- history -------------------------------------------------------------------

  void remember() {
    _undo.add(p.snapshot());
    if (_undo.length > 40) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoAction() {
    if (_undo.isEmpty) return;
    _redo.add(p.snapshot());
    p.restore(_undo.removeLast());
    _afterRestore();
  }

  void _redoAction() {
    if (_redo.isEmpty) return;
    _undo.add(p.snapshot());
    p.restore(_redo.removeLast());
    _afterRestore();
  }

  void _afterRestore() {
    HapticFeedback.selectionClick();
    sel = const StudioSelection.none();
    t = t.clamp(0.0, p.total);
    _active = -1;
    for (final c in p.clips) {
      _ensurePlayer(c);
    }
    for (final x in p.pips) {
      _ensurePipPlayer(x);
    }
    _seekPreview();
    setState(() {});
  }

  void toast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // -- media ------------------------------------------------------------------------

  Future<void> _addMedia(String path, String name, String kind, {bool first = false, int? at}) async {
    double duration = 3;
    if (kind == 'video') {
      final c = VideoPlayerController.file(File(path));
      try {
        await c.initialize();
        duration = c.value.duration.inMilliseconds / 1000;
        if (first) {
          final size = c.value.size;
          if (size.width > 0) p.setOriginalAspect(size.width / size.height);
        }
      } catch (_) {
        await c.dispose();
        toast('Could not open $name');
        return;
      }
      if (duration < .3) {
        await c.dispose();
        toast('Choose a clip longer than a third of a second');
        return;
      }
      final clip = StudioClip(path: path, name: name, kind: 'video', sourceDuration: duration,
          end: math.min(duration, 300));
      _players[clip.id] = c;
      c.addListener(_onVideo);
      if (!first) remember();
      p.clips.insert(at ?? p.clips.length, clip);
    } else {
      if (first) {
        try {
          final bytes = await File(path).readAsBytes();
          final img = await decodeImageFromList(bytes);
          p.setOriginalAspect(img.width / img.height);
        } catch (_) {}
      }
      if (!first) remember();
      p.clips.insert(at ?? p.clips.length,
          StudioClip(path: path, name: name, kind: 'image', sourceDuration: 3, end: 3));
    }
    if (first) p.ratio = 'original';
    if (!mounted) return;
    setState(() {});
    _seekPreview();
    final clip = p.clips.firstWhere((c) => c.path == path);
    unawaited(_upload(path, name).then((file) async {
      final id = file['url'].toString().split('/').last;
      for (final c in p.clips.where((c) => c.path == path)) {
        c.fileId = id;
      }
      if (clip.kind == 'video') await _loadStrip(id);
    }).catchError((Object e) {
      if (mounted) toast(_error(e));
    }));
  }

  /// Controllers may still be on screen this frame: dispose after it.
  void _disposeLater(VideoPlayerController? c) {
    if (c == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
  }

  void _ensurePlayer(StudioClip c) {
    if (c.kind != 'video' || _players.containsKey(c.id)) return;
    // Duplicates/splits share the file: open another controller.
    final ctrl = VideoPlayerController.file(File(c.path));
    _players[c.id] = ctrl;
    ctrl.initialize().then((_) {
      ctrl.addListener(_onVideo);
      if (mounted) {
        _active = -1;
        _seekPreview();
        setState(() {});
      }
    });
  }

  void _onVideo() {
    if (!playing && mounted) setState(() {});
  }

  void _ensurePipPlayer(StudioPip x) {
    if (x.kind != 'video' || _pipPlayers.containsKey(x.id)) return;
    final ctrl = VideoPlayerController.file(File(x.path));
    _pipPlayers[x.id] = ctrl;
    ctrl.initialize().then((_) {
      ctrl.addListener(_onVideo);
      if (mounted) {
        _syncPips(seek: true);
        setState(() {});
      }
    });
  }

  /// Keep overlay-media players in step with the playhead.
  void _syncPips({bool seek = false}) {
    for (final x in p.pips) {
      final ctrl = _pipPlayers[x.id];
      if (ctrl == null || !ctrl.value.isInitialized) continue;
      final inside = t >= x.at && t < x.at + x.length;
      final want = x.sourceAt(t - x.at);
      if (playing && inside) {
        final have = ctrl.value.position.inMilliseconds / 1000;
        if (!ctrl.value.isPlaying) {
          ctrl.setVolume(p.muteOriginal || _recording ? 0 : x.volume.clamp(0.0, 1.0));
          ctrl.setPlaybackSpeed(x.speed.clamp(.25, 4.0));
          ctrl.seekTo(_ms(want));
          ctrl.play();
        } else if ((want - have).abs() > .35) {
          ctrl.seekTo(_ms(want));
        }
      } else {
        if (ctrl.value.isPlaying) ctrl.pause();
        if (seek || !playing) ctrl.seekTo(_ms(want));
      }
    }
  }

  Future<Map<String, dynamic>> _upload(String path, String name) =>
      _uploads[path] ??= () async {
        final data = (await _dio.post('${_messaging.peerPath(widget.peer)}/files',
                data: FormData.fromMap({
                  'files': [await MultipartFile.fromFile(path, filename: name)],
                  'purpose': 'studio',
                }),
                options: Options(
                    sendTimeout: const Duration(minutes: 8),
                    receiveTimeout: const Duration(minutes: 8))))
            .data as List;
        return Map<String, dynamic>.from(data.single as Map);
      }()
        ..catchError((Object _) {
          _uploads.remove(path);
          return <String, dynamic>{};
        });

  Future<void> _loadStrip(String fileId) async {
    try {
      final bytes = (await _dio.get<List<int>>(
              '${_messaging.peerPath(widget.peer)}/studio/filmstrip/$fileId',
              options: Options(responseType: ResponseType.bytes)))
          .data!;
      final img = await decodeImageFromList(Uint8List.fromList(bytes));
      if (mounted) setState(() => _strips[fileId] = img);
    } catch (_) {}
  }

  String _error(Object e) {
    if (e is DioException && e.response?.data is Map) {
      final d = e.response!.data as Map;
      if (d['detail'] is String) return d['detail'] as String;
    }
    if (e is FormatException) return e.message;
    return 'Something went wrong. Try again.';
  }

  Future<void> _pickClips({int? at, bool replace = false}) async {
    _pause();
    final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'mp4', 'mov', 'webm', 'm4v'],
        allowMultiple: !replace);
    if (result == null || !mounted) return;
    if (!replace && result.files.length + p.clips.length > 20) {
      toast('Use up to 20 clips');
      return;
    }
    if (replace) {
      final old = _target;
      final file = result.files.single;
      if (old == null || file.path == null) return;
      final before = p.snapshot();
      final i = p.clips.indexOf(old);
      p.clips.removeAt(i);
      _disposeLater(_players.remove(old.id));
      await _addMedia(file.path!, file.name, _isVideo(file.extension) ? 'video' : 'image', at: i);
      // One undo step for the whole replace.
      if (_undo.isNotEmpty) _undo[_undo.length - 1] = before;
      return;
    }
    var index = at ?? p.clips.length;
    for (final file in result.files) {
      if (file.path == null) continue;
      await _addMedia(file.path!, file.name, _isVideo(file.extension) ? 'video' : 'image', at: index++);
    }
  }

  bool _isVideo(String? ext) => const {'mp4', 'mov', 'webm', 'm4v'}.contains(ext?.toLowerCase());

  // -- playback --------------------------------------------------------------------

  void _togglePlay() {
    HapticFeedback.selectionClick();
    playing ? _pause() : _play();
  }

  void _play() {
    if (p.clips.isEmpty) return;
    if (t >= p.total - .05) t = 0;
    setState(() => playing = true);
    _active = -1;
    _last = Duration.zero;
    _ticker.start();
    _syncAudio(force: true);
  }

  void _pause() {
    if (!playing) return;
    _ticker.stop();
    for (final c in [..._players.values, ..._pipPlayers.values]) {
      if (c.value.isInitialized && c.value.isPlaying) c.pause();
    }
    for (final a in _audio.values) {
      a.pause();
    }
    _audioOn.clear();
    setState(() => playing = false);
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero ? 0.0 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    t += dt;
    if (t >= p.total) {
      t = p.total;
      _pause();
      return;
    }
    final (i, local) = p.clipAt(t);
    final clip = p.clips[i];
    final ctrl = _players[clip.id];
    if (i != _active) {
      if (_active >= 0 && _active < p.clips.length) {
        final prev = _players[p.clips[_active].id];
        if (prev != null && prev.value.isPlaying) prev.pause();
      }
      _active = i;
      if (ctrl != null && ctrl.value.isInitialized) {
        ctrl.setVolume(p.muteOriginal || _recording ? 0 : clip.volume.clamp(0.0, 1.0));
        _rate = clip.speedAt(local).clamp(.25, 4.0);
        ctrl.setPlaybackSpeed(_rate);
        ctrl.seekTo(_ms(clip.sourceAt(local)));
        if (!clip.reverse && clip.hold == null) ctrl.play();
      }
      _driftCheck = 0;
    } else if (ctrl != null && ctrl.value.isInitialized) {
      _driftCheck += dt;
      if (clip.hasCurve) {
        // Speed curves: follow the ramp and re-sync often.
        final rate = clip.speedAt(local).clamp(.25, 4.0);
        if ((rate - _rate).abs() > .05) {
          _rate = rate;
          ctrl.setPlaybackSpeed(rate);
        }
        if (_driftCheck > .25) {
          _driftCheck = 0;
          final want = clip.sourceAt(local);
          if ((want - ctrl.value.position.inMilliseconds / 1000).abs() > .2) ctrl.seekTo(_ms(want));
        }
      }
      if (clip.reverse && _driftCheck > .12) {
        _driftCheck = 0;
        ctrl.seekTo(_ms(clip.sourceAt(local)));
      } else if (!clip.reverse && clip.hold == null && _driftCheck > .6) {
        _driftCheck = 0;
        final want = clip.sourceAt(local);
        final have = ctrl.value.position.inMilliseconds / 1000;
        if ((want - have).abs() > .3) ctrl.seekTo(_ms(want));
        if (!ctrl.value.isPlaying) ctrl.play();
      }
    }
    _syncAudio();
    _syncPips();
    setState(() {});
  }

  Duration _ms(double s) => Duration(milliseconds: (s * 1000).round());

  /// Seek the preview to [t] while paused / scrubbing.
  void _seekPreview() {
    if (p.clips.isEmpty) return;
    final (i, local) = p.clipAt(t);
    final clip = p.clips[i];
    final ctrl = _players[clip.id];
    if (ctrl != null && ctrl.value.isInitialized) ctrl.seekTo(_ms(clip.sourceAt(local)));
    // Show the next clip's first frame for transition previews.
    if (i + 1 < p.clips.length) {
      final next = p.clips[i + 1];
      final n = _players[next.id];
      if (n != null && n.value.isInitialized && !n.value.isPlaying) {
        n.seekTo(_ms(next.sourceAt(0)));
      }
    }
    _syncPips(seek: true);
  }

  Future<AudioPlayer> _audioPlayer(StudioAudio a) async {
    final hit = _audio[a.id];
    if (hit != null) return hit;
    final player = AudioPlayer();
    _audio[a.id] = player;
    if (a.libraryUrl != null) {
      await player.setSourceUrl(AppConfig.mediaUrl(a.libraryUrl!));
    } else {
      await player.setSourceDeviceFile(a.path!);
    }
    return player;
  }

  void _syncAudio({bool force = false}) {
    if (!playing) return;
    for (final a in p.audios) {
      final inside = t >= a.at && t < a.at + a.length;
      final on = _audioOn.contains(a.id);
      if (inside && (!on || force)) {
        _audioOn.add(a.id);
        _audioPlayer(a).then((player) async {
          await player.setVolume(_recording ? 0 : a.volume.clamp(0.0, 1.0));
          await player.seek(_ms(a.start + (t - a.at)));
          if (playing && _audioOn.contains(a.id)) await player.resume();
        });
      } else if (!inside && on) {
        _audioOn.remove(a.id);
        _audio[a.id]?.pause();
      }
    }
  }

  // -- editing actions -----------------------------------------------------------

  void _select(StudioSelection s) {
    _pause();
    setState(() {
      sel = s;
      _clipTools = s.kind == StudioSelectKind.clip;
      if (panel != _Panel.export) panel = _Panel.none;
    });
  }

  void _commit() => setState(() {});

  void _split() {
    final clip = _target;
    if (clip == null) return;
    final i = p.clips.indexOf(clip);
    final local = t - p.starts[i];
    if (local < .2 || clip.length - local < .2) {
      toast('Move the playhead inside the clip to split');
      return;
    }
    remember();
    final second = clip.duplicate();
    if (clip.hold != null) {
      second.hold = clip.hold! - local;
      clip.hold = local;
    } else if (clip.reverse) {
      final cut = clip.sourceAt(local);
      second.end = cut;
      clip.start = cut;
    } else {
      final cut = clip.sourceAt(local);
      clip.end = cut;
      second.start = cut;
    }
    second.transition = clip.transition;
    clip.transition = 'none';
    p.clips.insert(i + 1, second);
    _ensurePlayer(second);
    HapticFeedback.mediumImpact();
    setState(() => sel = StudioSelection(StudioSelectKind.clip, second.id));
  }

  void _deleteClip() {
    final clip = _target;
    if (clip == null) return;
    if (p.clips.length == 1) {
      toast('A project needs at least one clip');
      return;
    }
    remember();
    p.clips.remove(clip);
    _disposeLater(_players.remove(clip.id));
    t = t.clamp(0.0, p.total);
    _active = -1;
    _select(const StudioSelection.none());
    _seekPreview();
  }

  void _duplicateClip() {
    final clip = _target;
    if (clip == null) return;
    remember();
    final copy = clip.duplicate();
    p.clips.insert(p.clips.indexOf(clip) + 1, copy);
    _ensurePlayer(copy);
    setState(() {});
  }

  void _freeze() {
    final clip = _target;
    if (clip == null || clip.kind != 'video') {
      toast('Freeze works on video clips');
      return;
    }
    final i = p.clips.indexOf(clip);
    final local = t - p.starts[i];
    remember();
    final frame = clip.duplicate()
      ..start = clip.sourceAt(local)
      ..end = clip.sourceAt(local) + .5
      ..hold = 3
      ..transition = 'none';
    // Split around the frozen frame when the playhead is inside the clip.
    if (local > .2 && clip.length - local > .2 && !clip.reverse) {
      final tail = clip.duplicate()..start = clip.sourceAt(local);
      clip.end = clip.sourceAt(local);
      tail.transition = clip.transition;
      clip.transition = 'none';
      p.clips.insertAll(i + 1, [frame, tail]);
      _ensurePlayer(tail);
    } else {
      p.clips.insert(i + 1, frame);
    }
    _ensurePlayer(frame);
    toast('Freeze frame added · 3s');
    setState(() => sel = StudioSelection(StudioSelectKind.clip, frame.id));
  }

  void _rotate() {
    final c = _target;
    if (c == null) return;
    remember();
    setState(() {
      c.turns = (c.turns + 1) % 4;
      c.crop = null;
    });
  }

  void _mirror() {
    final c = _target;
    if (c == null) return;
    remember();
    setState(() => c.flip = !c.flip);
  }

  void _flipV() {
    final c = _target;
    if (c == null) return;
    remember();
    setState(() => c.flipV = !c.flipV);
  }

  void _reverse() {
    final c = _target;
    if (c == null || c.kind != 'video' || c.hold != null) {
      toast('Reverse works on video clips');
      return;
    }
    if (c.end - c.start > 30) {
      toast('Trim the clip to 30s or less to reverse it');
      return;
    }
    remember();
    setState(() {
      c.reverse = !c.reverse;
      if (c.reverse) c.setCurve(null);
    });
    toast(c.reverse ? 'Reversed' : 'Playing forwards');
  }

  void _trimClip(int i, bool head, double dt) {
    final c = p.clips[i];
    if (c.kind == 'image' || c.hold != null) {
      // Stills: either handle changes the duration.
      final len = (c.hold ?? (c.end - c.start)) + (head ? -dt : dt);
      final v = len.clamp(.5, 30.0);
      if (c.hold != null) {
        c.hold = v;
      } else {
        c.end = c.start + v;
      }
    } else {
      final ds = dt * c.speed;
      if (head == !c.reverse) {
        c.start = (c.start + ds).clamp(0.0, c.end - .3 * c.speed);
      } else {
        c.end = (c.end + ds).clamp(c.start + .3 * c.speed, c.sourceDuration);
      }
    }
    if (head) t = p.starts[i];
    _seekPreview();
    setState(() {});
  }

  void _trimItem(StudioSelection s, bool head, double dt) {
    if (s.kind == StudioSelectKind.audio) {
      final a = p.audios.firstWhere((a) => a.id == s.id);
      if (head) {
        final ds = dt.clamp(-a.start, a.length - .3);
        a.start += ds;
        a.at = (a.at + ds).clamp(0.0, p.total);
      } else {
        a.end = (a.end + dt).clamp(a.start + .3, a.sourceDuration);
      }
    } else if (s.kind == StudioSelectKind.overlay) {
      final o = p.overlays.firstWhere((o) => o.id == s.id);
      if (head) {
        final before = o.start;
        o.start = (o.start + dt).clamp(0.0, o.end - .3);
        // Keyframes stay where they are on the timeline.
        for (final k in o.keys) {
          k[0] -= o.start - before;
        }
      } else {
        o.end = (o.end + dt).clamp(o.start + .3, p.total);
      }
    } else if (s.kind == StudioSelectKind.pip) {
      final x = p.pips.firstWhere((x) => x.id == s.id);
      if (x.isPhoto) {
        if (head) {
          final len = (x.end - x.start) - dt;
          final v = len.clamp(.3, 60.0);
          x.at = (x.at + (x.end - x.start) - v).clamp(0.0, p.total);
          x.end = x.start + v;
        } else {
          x.end = (x.end + dt).clamp(x.start + .3, x.start + 60);
        }
      } else if (head) {
        final ds = (dt * x.speed).clamp(-x.start, x.end - x.start - .3);
        x.start += ds;
        x.at = (x.at + ds / x.speed).clamp(0.0, p.total);
      } else {
        x.end = (x.end + dt * x.speed).clamp(x.start + .3, x.sourceDuration);
      }
    } else if (s.kind == StudioSelectKind.segment) {
      final x = p.segments.firstWhere((x) => x.id == s.id);
      if (head) {
        x.start = (x.start + dt).clamp(0.0, x.end - .2);
      } else {
        x.end = (x.end + dt).clamp(x.start + .2, p.total);
      }
    }
    setState(() {});
  }

  void _moveItem(StudioSelection s, double dt) {
    if (s.kind == StudioSelectKind.audio) {
      final a = p.audios.firstWhere((a) => a.id == s.id);
      a.at = (a.at + dt).clamp(0.0, math.max(0.0, p.total - .3));
    } else if (s.kind == StudioSelectKind.overlay) {
      final o = p.overlays.firstWhere((o) => o.id == s.id);
      final len = o.end - o.start;
      o.start = (o.start + dt).clamp(0.0, math.max(0.0, p.total - len));
      o.end = o.start + len;
    } else if (s.kind == StudioSelectKind.pip) {
      final x = p.pips.firstWhere((x) => x.id == s.id);
      x.at = (x.at + dt).clamp(0.0, math.max(0.0, p.total - .2));
    } else if (s.kind == StudioSelectKind.segment) {
      final x = p.segments.firstWhere((x) => x.id == s.id);
      final len = x.end - x.start;
      x.start = (x.start + dt).clamp(0.0, math.max(0.0, p.total - len));
      x.end = x.start + len;
    }
    setState(() {});
  }

  bool _dragHistory = false;
  void _editStart() {
    if (!_dragHistory) {
      remember();
      _dragHistory = true;
    }
  }

  void _editEnd() {
    _dragHistory = false;
    setState(() {});
  }

  // -- text & stickers ---------------------------------------------------------------

  Future<void> _addText({StudioOverlay? edit}) async {
    _pause();
    final o = edit ??
        StudioOverlay(kind: 'text', start: t, end: math.min(p.total, t + 3).clamp(t + .5, t + 3));
    final result = await Navigator.of(context).push<StudioOverlay>(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black54,
      pageBuilder: (_, __, ___) => _TextEditor(overlay: StudioOverlay.fromJson(o.toJson())),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
    if (result == null || !mounted) return;
    if (result.text.trim().isEmpty) {
      if (edit != null) {
        remember();
        p.overlays.removeWhere((x) => x.id == edit.id);
        setState(() => sel = const StudioSelection.none());
      }
      return;
    }
    remember();
    final i = p.overlays.indexWhere((x) => x.id == result.id);
    if (i >= 0) {
      p.overlays[i] = result;
    } else {
      p.overlays.add(result);
    }
    setState(() {
      sel = StudioSelection(StudioSelectKind.overlay, result.id);
      panel = _Panel.none;
    });
  }

  Future<void> _addSticker({String? emoji, String? asset}) async {
    if (asset != null) await StickerImages.load(asset);
    remember();
    final o = StudioOverlay(
      kind: 'sticker',
      sticker: emoji,
      asset: asset,
      size: .28,
      start: t,
      end: math.min(p.total, t + 3).clamp(t + .5, t + 3),
    )..animIn = 'fade';
    p.overlays.add(o);
    HapticFeedback.selectionClick();
    setState(() => sel = StudioSelection(StudioSelectKind.overlay, o.id));
  }

  // -- audio -------------------------------------------------------------------------

  Future<void> _addMusic() async {
    _pause();
    final song = await showSongPicker(context);
    if (song == null || !mounted) return;
    final url = song['url'] as String?;
    if (url == null || !url.startsWith('/media/')) {
      toast('That track can only be played in its own app. Pick a Phlio Stream track.');
      return;
    }
    final player = AudioPlayer();
    double duration = 30;
    try {
      await player.setSourceUrl(AppConfig.mediaUrl(url));
      final d = await player.getDuration();
      if (d != null) duration = d.inMilliseconds / 1000;
    } catch (_) {}
    await player.dispose();
    remember();
    final a = StudioAudio(
      kind: 'music',
      title: '${song['title'] ?? 'Music'}',
      sourceDuration: duration,
      libraryUrl: url,
      at: t,
      end: math.min(duration, math.max(1, p.total - t)),
    )..volume = .8;
    p.audios.add(a);
    setState(() {
      sel = StudioSelection(StudioSelectKind.audio, a.id);
      panel = _Panel.none;
    });
    try {
      final data = (await _dio.get('/messaging/studio/library-waveform',
              queryParameters: {'url': url}))
          .data as Map;
      a.peaks = [for (final v in data['peaks'] as List) (v as num).toDouble()];
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _addAudioFile({bool extract = false}) async {
    _pause();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extract
          ? ['mp4', 'mov', 'webm', 'm4v']
          : ['mp3', 'm4a', 'wav', 'ogg', 'aac', 'flac'],
    );
    final file = result?.files.single;
    if (file?.path == null || !mounted) return;
    await _addAudioPath(file!.path!, file.name, extract ? 'extract' : 'file',
        title: extract ? 'Extracted · ${file.name}' : file.name);
  }

  Future<void> _addAudioPath(String path, String name, String kind,
      {required String title, double? at}) async {
    final player = AudioPlayer();
    double duration = 10;
    try {
      await player.setSourceDeviceFile(path);
      final d = await player.getDuration();
      if (d != null) duration = d.inMilliseconds / 1000;
    } catch (_) {}
    await player.dispose();
    remember();
    final a = StudioAudio(
      kind: kind,
      title: title,
      sourceDuration: duration,
      path: path,
      at: at ?? t,
      end: kind == 'voice' ? duration : math.min(duration, math.max(1, p.total - (at ?? t))),
    );
    p.audios.add(a);
    setState(() {
      sel = StudioSelection(StudioSelectKind.audio, a.id);
      panel = _Panel.none;
    });
    try {
      final file = await _upload(path, name);
      a.fileId = file['url'].toString().split('/').last;
      final wave = (await _dio.get('${_messaging.peerPath(widget.peer)}/studio/waveform/${a.fileId}'))
          .data as Map;
      a.peaks = [for (final v in wave['peaks'] as List) (v as num).toDouble()];
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) toast(_error(e));
    }
  }

  Future<void> _toggleVoiceover() async {
    if (_recording) {
      final path = await _recorder.stop();
      final started = _recordStarted;
      _pause();
      setState(() => _recording = false);
      if (path != null && started != null &&
          DateTime.now().difference(started).inMilliseconds > 400) {
        final n = p.audios.where((a) => a.kind == 'voice').length + 1;
        await _addAudioPath(path, 'voiceover_$n.m4a', 'voice', title: 'Voiceover $n', at: _recordFrom);
      }
      return;
    }
    if (!await _recorder.hasPermission()) {
      toast('Allow microphone access to record a voiceover');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('phlio_vo_');
    final path = '${dir.path}/voiceover_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _recordFrom = t;
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1), path: path);
    _recordStarted = DateTime.now();
    HapticFeedback.heavyImpact();
    setState(() => _recording = true);
    // Play the edit silently underneath so you can talk over it.
    _play();
  }

  // -- keyframes ----------------------------------------------------------------------

  /// Keyframe list + local time of the selected item at the playhead.
  (List<List<double>>, double)? _keyTarget() {
    final c = _clip;
    if (c != null) {
      final i = p.clips.indexOf(c);
      final local = t - p.starts[i];
      if (local < -1e-3 || local > c.length + 1e-3) return null;
      return (c.keys, local.clamp(0.0, c.length));
    }
    final o = _overlay;
    if (o != null) {
      if (t < o.start - 1e-3 || t > o.end + 1e-3) return null;
      return (o.keys, (t - o.start).clamp(0.0, o.end - o.start));
    }
    final x = _pip;
    if (x != null) {
      if (t < x.at - 1e-3 || t > x.at + x.length + 1e-3) return null;
      return (x.keys, (t - x.at).clamp(0.0, x.length));
    }
    return null;
  }

  bool get _onKey {
    final k = _keyTarget();
    return k != null && keyIndexAt(k.$1, k.$2) >= 0;
  }

  void _toggleKeyframe() {
    final target = _keyTarget();
    if (target == null) {
      toast(sel.isNone
          ? 'Select a clip, overlay or text to add keyframes'
          : 'Move the playhead over the selected item');
      return;
    }
    _pause();
    remember();
    final (keys, local) = target;
    final i = keyIndexAt(keys, local);
    if (i >= 0) {
      keys.removeAt(i);
      toast('Keyframe removed');
    } else {
      _writeKey(local);
      toast('Keyframe added · move or resize to animate');
    }
    HapticFeedback.mediumImpact();
    setState(() {});
  }

  /// Store the selected item's current state as a keyframe at [local].
  void _writeKey(double local, {double? zoom, double? panX, double? panY}) {
    final c = _clip;
    if (c != null) {
      final (z, px, py) = c.transformAt(local);
      setKey(c.keys, [local, zoom ?? z, panX ?? px, panY ?? py]);
      return;
    }
    final o = _overlay;
    if (o != null) {
      final a = o.at(o.start + local);
      setKey(o.keys, [local, a.x, a.y, a.size, a.rotation, a.opacity]);
      return;
    }
    final x = _pip;
    if (x != null) {
      final a = x.placeAt(x.at + local);
      setKey(x.keys, [local, a.x, a.y, a.scale, a.rotation, a.opacity]);
    }
  }

  // -- overlay media (PiP) ------------------------------------------------------------

  Future<void> _addPip() async {
    _pause();
    final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'mp4', 'mov', 'webm', 'm4v']);
    final file = result?.files.single;
    if (file?.path == null || !mounted) return;
    if (p.pips.length >= 6) {
      toast('Use up to 6 overlays');
      return;
    }
    final path = file!.path!;
    final video = _isVideo(file.extension);
    double duration = 3, aspect = 1;
    VideoPlayerController? ctrl;
    try {
      if (video) {
        ctrl = VideoPlayerController.file(File(path));
        await ctrl.initialize();
        duration = ctrl.value.duration.inMilliseconds / 1000;
        if (ctrl.value.size.height > 0) aspect = ctrl.value.size.width / ctrl.value.size.height;
      } else {
        final img = await decodeImageFromList(await File(path).readAsBytes());
        aspect = img.width / img.height;
      }
    } catch (_) {
      await ctrl?.dispose();
      toast('Could not open ${file.name}');
      return;
    }
    remember();
    final x = StudioPip(
      path: path,
      name: file.name,
      kind: video ? 'video' : 'image',
      sourceDuration: video ? duration : 600,
      at: t,
      end: video ? math.min(duration, math.max(.5, p.total - t)) : math.min(3.0, math.max(.5, p.total - t)),
      aspect: aspect,
    );
    p.pips.add(x);
    if (ctrl != null) {
      _pipPlayers[x.id] = ctrl;
      ctrl.addListener(_onVideo);
    }
    setState(() => sel = StudioSelection(StudioSelectKind.pip, x.id));
    _syncPips(seek: true);
    unawaited(_upload(path, file.name).then((f) {
      x.fileId = f['url']?.toString().split('/').last;
    }).catchError((Object e) {
      if (mounted) toast(_error(e));
    }));
  }

  // -- timeline effect / filter / adjustment layers ---------------------------------------

  StudioSegment _newSegment(String kind, {String? effect}) {
    final end = math.min(p.total, t + 3);
    final start = end - t < .5 ? math.max(0.0, end - 3) : t;
    return StudioSegment(kind: kind, start: start, end: end, effect: effect);
  }

  void _addColorLayer(String kind) {
    remember();
    final s = _newSegment(kind);
    p.segments.add(s);
    setState(() {
      sel = StudioSelection(StudioSelectKind.segment, s.id);
      panel = kind == 'filter' ? _Panel.filters : _Panel.adjust;
    });
  }

  void _pickSegmentEffect(String effect) {
    remember();
    final current = _segment;
    if (current != null && current.kind == 'effect') {
      setState(() => current.effect = effect);
    } else {
      final s = _newSegment('effect', effect: effect);
      p.segments.add(s);
      setState(() => sel = StudioSelection(StudioSelectKind.segment, s.id));
    }
    final s = _segment!;
    t = s.start;
    _play();
  }

  // -- sound effects, text to audio, extract audio ---------------------------------------

  Future<void> _addSoundEffect() async {
    _pause();
    final sound = await showStudioSounds(context, _dio);
    if (sound == null || !mounted) return;
    remember();
    final a = StudioAudio(
      kind: 'sfx',
      title: sound.name,
      sourceDuration: sound.duration,
      libraryUrl: sound.url,
      at: t,
    );
    p.audios.add(a);
    setState(() {
      sel = StudioSelection(StudioSelectKind.audio, a.id);
      panel = _Panel.none;
    });
    try {
      final data = (await _dio.get('/messaging/studio/library-waveform', queryParameters: {'url': sound.url}))
          .data as Map;
      a.peaks = [for (final v in data['peaks'] as List) (v as num).toDouble()];
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _textToAudio({String initial = '', double? at}) async {
    _pause();
    final req = await showStudioTextToSpeech(context, _dio, initial: initial);
    if (req == null || !mounted) return;
    setState(() => _busy = true);
    toast('Creating voice…');
    try {
      final data = (await _dio.post('${_messaging.peerPath(widget.peer)}/studio/tts',
              data: {'text': req.text, 'voice': req.voice, 'speed': req.speed},
              options: Options(receiveTimeout: const Duration(minutes: 4))))
          .data as Map;
      final cached = await _messaging.localFile(data['url'] as String);
      final dir = await Directory.systemTemp.createTemp('phlio_tts_');
      final path = (await File(cached).copy('${dir.path}/speech_${data['id']}.m4a')).path;
      // Already on the server: reuse that file at export.
      _uploads[path] = Future.value(Map<String, dynamic>.from(data));
      if (!mounted) return;
      final title = req.text.length > 28 ? '${req.text.substring(0, 28)}…' : req.text;
      await _addAudioPath(path, 'speech.m4a', 'tts', title: title, at: at ?? t);
    } catch (e) {
      if (mounted) toast(_error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// CapCut "Extract audio": the clip's sound moves to its own audio track.
  Future<void> _extractClipAudio() async {
    final c = _target;
    if (c == null || c.kind != 'video' || c.hold != null) {
      toast('Extract audio works on video clips');
      return;
    }
    if (c.reverse || c.hasCurve || c.speed != 1) {
      toast('Set the clip to normal speed to extract its audio');
      return;
    }
    final i = p.clips.indexOf(c);
    await _addAudioPath(c.path, c.name, 'extract', title: 'Extracted · ${c.name}', at: p.starts[i]);
    final a = p.audios.last;
    a
      ..start = c.start
      ..end = c.end
      ..volume = c.volume;
    // One undo step: _addAudioPath remembered the state before.
    c.volume = 0;
    toast('Audio extracted · clip muted');
    setState(() {});
  }

  // -- auto captions ---------------------------------------------------------------------

  Future<void> _autoCaptions() async {
    _pause();
    if (_captioning) return;
    final starts = p.starts;
    setState(() {
      _captioning = true;
      panel = _Panel.none;
    });
    toast('Recognising speech…');
    try {
      final sources = <Map<String, dynamic>>[];
      for (var i = 0; i < p.clips.length; i++) {
        final c = p.clips[i];
        if (c.kind != 'video' || c.hold != null || c.reverse || c.volume == 0 || p.muteOriginal) continue;
        final file = await _upload(c.path, c.name);
        if (file.isEmpty) continue;
        sources.add({
          'file_id': file['url'].toString().split('/').last,
          'at': starts[i],
          'start': c.start,
          'end': c.end,
          'speed': c.hasCurve ? 1 : c.speed,
        });
      }
      for (final a in p.audios.where((a) => a.kind == 'voice' || a.kind == 'extract' || a.kind == 'tts')) {
        final file = await _upload(a.path!, a.path!.split(Platform.pathSeparator).last);
        if (file.isEmpty) continue;
        sources.add({
          'file_id': file['url'].toString().split('/').last,
          'at': a.at,
          'start': a.start,
          'end': a.end,
          'speed': 1,
        });
      }
      if (sources.isEmpty) {
        toast('No speech to caption: add a video with sound or a voiceover');
        return;
      }
      final data = (await _dio.post('${_messaging.peerPath(widget.peer)}/studio/captions',
              data: {'sources': sources},
              options: Options(receiveTimeout: const Duration(minutes: 10))))
          .data as Map;
      final lines = (data['lines'] as List).cast<Map>();
      if (!mounted) return;
      if (lines.isEmpty) {
        toast('No speech found');
        return;
      }
      remember();
      final style = p.overlays.where((o) => o.isCaption).firstOrNull;
      p.overlays.removeWhere((o) => o.isCaption);
      for (final l in lines) {
        final start = (l['start'] as num).toDouble().clamp(0.0, p.total);
        if (start >= p.total - .1) continue;
        final end = math.max(start + .3, (l['end'] as num).toDouble());
        p.overlays.add(StudioOverlay(
          kind: 'caption',
          text: '${l['text']}',
          x: style?.x ?? .5,
          y: style?.y ?? .8,
          size: style?.size ?? .055,
          start: start,
          end: math.min(end, p.total),
        )
          ..style = style?.style ?? 'outline'
          ..color = style?.color ?? 0xFFFFFFFF
          ..accent = style?.accent ?? 0xFF0B0F17
          ..font = style?.font ?? 'Manrope'
          ..animIn = 'none'
          ..animOut = 'none');
      }
      toast('${lines.length} captions added');
      setState(() {});
    } catch (e) {
      if (mounted) toast(_error(e));
    } finally {
      if (mounted) setState(() => _captioning = false);
    }
  }

  Future<void> _editCaptions() async {
    _pause();
    final captions = [...p.overlays.where((o) => o.isCaption)]..sort((a, b) => a.start.compareTo(b.start));
    if (captions.isEmpty) return;
    final result = await Navigator.of(context).push<Map<String, String>>(
        MaterialPageRoute(builder: (_) => StudioCaptionsEditor(captions: captions)));
    if (result == null || !mounted) return;
    remember();
    setState(() {
      for (final e in result.entries) {
        final o = p.overlays.where((o) => o.id == e.key).firstOrNull;
        if (o == null) continue;
        if (e.value.isEmpty) {
          p.overlays.remove(o);
        } else {
          o.text = e.value;
        }
      }
      if (_overlay == null) sel = const StudioSelection.none();
    });
  }

  // -- cover ---------------------------------------------------------------------------

  Widget _coverThumb(double at) {
    if (p.clips.isEmpty) return const ColoredBox(color: Colors.black);
    final (i, local) = p.clipAt(at.clamp(0.0, p.total));
    final c = p.clips[i];
    if (c.kind == 'image') return Image.file(File(c.path), fit: BoxFit.cover, cacheWidth: 400);
    final strip = c.fileId == null ? null : _strips[c.fileId];
    if (strip == null) return const ColoredBox(color: Color(0xFF2A2350));
    final frame = (c.sourceAt(local) / math.max(.1, c.sourceDuration) * 12).floor().clamp(0, 11);
    return CustomPaint(painter: _StripFrame(strip, frame));
  }

  Widget? _coverPreview() {
    if (p.coverPath != null) return Image.file(File(p.coverPath!), fit: BoxFit.cover, cacheWidth: 120);
    if (p.clips.isEmpty) return null;
    return _coverThumb(p.coverTime ?? 0);
  }

  Future<void> _editCover() async {
    _pause();
    final result = await Navigator.of(context).push<StudioCoverResult>(MaterialPageRoute(
      builder: (_) => StudioCoverScreen(
        total: p.total,
        initialTime: p.coverTime,
        initialPath: p.coverPath,
        initialText: p.coverText,
        aspect: _canvasAspect(),
        frameAt: _coverThumb,
        pickPhoto: () async {
          final r = await FilePicker.pickFiles(type: FileType.image);
          return r?.files.single.path;
        },
      ),
    ));
    if (result == null || !mounted) return;
    remember();
    setState(() {
      p.coverTime = result.time;
      p.coverPath = result.path;
      p.coverText = result.text;
    });
    toast('Cover set');
  }

  /// Full-canvas PNG with the cover title (same look as the cover screen).
  Future<File> _rasterizeCoverText(int w, int h, Directory dir) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final scale = w / 360;
    final tp = TextPainter(
      text: TextSpan(
        text: p.coverText,
        style: TextStyle(
          color: Colors.white,
          fontSize: 30 * scale,
          fontWeight: FontWeight.w900,
          fontFamily: 'Manrope',
          shadows: [Shadow(blurRadius: 12 * scale, color: Colors.black54)],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - 32 * scale);
    final y = h * .775 - tp.height / 2;
    tp.paint(canvas, Offset((w - tp.width) / 2, y));
    final img = await recorder.endRecording().toImage(w, h);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File('${dir.path}/cover_text.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file;
  }

  // -- export ------------------------------------------------------------------------

  (int, int) _exportSize() {
    final ratio = p.ratio == 'original' ? _originalRatio() : p.aspect;
    final short = p.resolution.toDouble();
    var w = ratio <= 1 ? short : short * ratio;
    var h = ratio <= 1 ? short / ratio : short;
    final scale = math.min(1.0, 1920 / math.max(w, h));
    w *= scale;
    h *= scale;
    return ((w ~/ 4) * 4, (h ~/ 4) * 4);
  }

  double _originalRatio() {
    final c = p.clips.first;
    var a = p.aspect;
    final ctrl = _players[c.id];
    if (ctrl != null && ctrl.value.isInitialized && ctrl.value.size.width > 0) {
      a = ctrl.value.size.width / ctrl.value.size.height;
    }
    if (c.turns.isOdd) a = 1 / a;
    if (c.crop != null) a = a * c.crop![2] / c.crop![3];
    return a;
  }

  Future<void> _export() async {
    _pause();
    if (p.total > 300) {
      toast('Keep projects within five minutes');
      return;
    }
    final result = await Navigator.of(context).push<StagedAttachment>(PageRouteBuilder(
      opaque: false,
      pageBuilder: (_, __, ___) => StudioExportScreen(
        peer: widget.peer,
        prepare: _prepareExport,
        dio: _dio,
      ),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
    if (result == null || !mounted) return;
    final finished = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => StudioPublishScreen(
              peer: widget.peer,
              attachment: result,
              onSend: widget.onSend,
            )));
    if (finished == true && mounted) Navigator.of(context).pop();
  }

  /// Upload everything and build the server plan.
  Future<Map<String, dynamic>> _prepareExport(void Function(double, String) report) async {
    // Upload names carry the extension the server uses to type the file.
    final paths = {
      for (final c in p.clips) c.path: c.name,
      for (final x in p.pips) x.path: x.name,
      for (final a in p.audios.where((a) => a.libraryUrl == null))
        a.path!: a.path!.split(Platform.pathSeparator).last,
      if (p.coverPath != null) p.coverPath!: p.coverPath!.split(Platform.pathSeparator).last,
    };
    final ids = <String, String>{};
    var done = 0;
    for (final entry in paths.entries) {
      report(done / (paths.length + 1) * .25, 'Uploading media ${done + 1} of ${paths.length}');
      final file = await _upload(entry.key, entry.value);
      if (file.isEmpty) throw const FormatException('Upload failed. Check your connection.');
      final id = file['url'].toString().split('/').last;
      ids[entry.key] = id;
      for (final c in p.clips.where((c) => c.path == entry.key)) {
        c.fileId = id;
      }
      for (final x in p.pips.where((x) => x.path == entry.key)) {
        x.fileId = id;
      }
      for (final a in p.audios.where((a) => a.path == entry.key)) {
        a.fileId = id;
      }
      done++;
    }
    final (w, h) = _exportSize();
    final dir = await Directory.systemTemp.createTemp('phlio_layers_');
    Future<String> png(File f) async {
      final file = await _upload(f.path, f.path.split(Platform.pathSeparator).last);
      if (file.isEmpty) throw const FormatException('Upload failed. Check your connection.');
      return file['url'].toString().split('/').last;
    }

    final overlays = <Map<String, dynamic>>[];
    if (p.overlays.isNotEmpty) {
      report(.25, 'Preparing text and stickers');
      for (final o in p.overlays) {
        final moving = o.isDynamic;
        final raster = await rasterizeOverlay(o, w.toDouble(), h.toDouble(), dir, upright: moving);
        final id = await png(raster.file);
        double r(double v) => double.parse(v.toStringAsFixed(4));
        overlays.add({
          'file_id': id,
          'x': raster.x,
          'y': raster.y,
          'w': raster.w,
          'start': o.start,
          'end': o.end,
          'anim_in': o.animIn,
          'anim_out': o.animOut,
          'loop': o.loop,
          if (moving) ...{
            'cx': r(o.x),
            'cy': r(o.y),
            'rotation': r(o.rotation),
            if (o.keys.isNotEmpty)
              'keys': [
                for (final k in o.keys)
                  [r(o.start + k[0]), r(k[1]), r(k[2]), r(k[3] / o.size), r(k[4]), r(k[5])]
              ],
          },
        });
      }
    }
    final pips = <Map<String, dynamic>>[];
    for (final x in p.pips) {
      String? maskId;
      if (x.mask != 'none') maskId = await png(await rasterizeMask(x, dir));
      pips.add(x.plan(maskId));
    }
    Map<String, dynamic>? cover;
    if (p.coverPath != null || p.coverTime != null || p.coverText.isNotEmpty) {
      report(.28, 'Preparing the cover');
      cover = {
        if (p.coverPath != null) 'file_id': ids[p.coverPath!] else 'time': p.coverTime ?? 0,
        if (p.coverText.isNotEmpty) 'overlay_id': await png(await _rasterizeCoverText(w, h, dir)),
      };
    }
    report(.3, 'Sending your edit');
    return {
      'clips': [for (final c in p.clips) c.plan()],
      'pips': pips,
      'segments': [
        for (final s in p.segments)
          if (s.kind != 'effect' || s.effect != null) s.plan()
      ],
      'overlays': overlays,
      'audios': [for (final a in p.audios) a.plan()],
      if (cover != null && !p.isSinglePhoto) 'cover': cover,
      'mute_original': p.muteOriginal,
      'ratio': p.ratio,
      'resolution': p.resolution,
      'fps': p.fps,
      'quality': p.quality,
      'background': p.background,
      'blur': p.blur,
      'image_format': 'jpg',
    };
  }

  Future<bool> _confirmClose() async {
    if (_undo.isEmpty) return true;
    final leave = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: PhlioColors.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Discard this edit?',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 6),
            const Text('Your changes will be lost.', style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: PhlioColors.danger, shape: const StadiumBorder()),
                onPressed: () => Navigator.pop(sheet, true),
                child: const Text('Discard', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            TextButton(onPressed: () => Navigator.pop(sheet, false), child: const Text('Keep editing')),
          ]),
        ),
      ),
    );
    return leave == true;
  }

  // -- build ------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (panel != _Panel.none) {
          setState(() => panel = _Panel.none);
          return;
        }
        if (await _confirmClose() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Stack(children: [
            Column(children: [
              if (!_fullscreen) _topBar(),
              Expanded(flex: 11, child: _preview()),
              _transport(),
              if (!_fullscreen) ...[
                Expanded(
                  flex: 8,
                  child: p.clips.isEmpty
                      ? const SizedBox()
                      : _reorder
                          ? _reorderStrip()
                          : SingleChildScrollView(
                          child: StudioTimeline(
                            project: p,
                            t: t,
                            pps: pps,
                            selection: sel,
                            strips: _strips,
                            onScrubStart: () {
                              _pause();
                            },
                            onScrub: (v) {
                              t = v;
                              _seekPreview();
                              setState(() {});
                            },
                            onZoom: (v) => setState(() => pps = v),
                            onSelect: _select,
                            onTrimClip: (i, head, dt) {
                              _editStart();
                              _trimClip(i, head, dt);
                            },
                            onTrimItem: (s, head, dt) {
                              _editStart();
                              _trimItem(s, head, dt);
                            },
                            onMoveItem: (s, dt) {
                              _editStart();
                              _moveItem(s, dt);
                            },
                            onEditEnd: _editEnd,
                            onTransition: (i) => setState(() {
                              _pause();
                              sel = StudioSelection(StudioSelectKind.clip, p.clips[i].id);
                              panel = _Panel.transition;
                            }),
                            onAddClip: () => _pickClips(),
                            onAddAudio: () => setState(() => panel = _Panel.audioMenu),
                            onAddText: () => _addText(),
                            onToggleMute: () {
                              remember();
                              setState(() => p.muteOriginal = !p.muteOriginal);
                              toast(p.muteOriginal ? 'Clip audio muted' : 'Clip audio on');
                            },
                            onCover: _editCover,
                            cover: _coverPreview(),
                            onReorder: () {
                              if (p.clips.length < 2) return;
                              _pause();
                              HapticFeedback.mediumImpact();
                              setState(() => _reorder = true);
                            },
                          ),
                        ),
                ),
                _bottom(),
              ],
            ]),
            if (_captioning)
              Positioned(
                left: 0,
                right: 0,
                top: 120,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                        color: const Color(0xFF111722).withValues(alpha: .95),
                        borderRadius: BorderRadius.circular(16)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: PhlioColors.brandPeach)),
                      SizedBox(width: 12),
                      Text('Generating captions…',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            if (_toast != null)
              Positioned(
                left: 0,
                right: 0,
                top: 70,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .78),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(_toast!,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _topBar() => SizedBox(
        height: 54,
        child: Row(children: [
          IconButton(
            tooltip: 'Close',
            onPressed: () async {
              if (await _confirmClose() && mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => panel = panel == _Panel.export ? _Panel.none : _Panel.export),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                  color: const Color(0xFF1C2433), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${p.resolution}P',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                const Icon(Icons.arrow_drop_down_rounded, color: Colors.white, size: 20),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          DecoratedBox(
            decoration: BoxDecoration(
                gradient: PhlioColors.sunsetGradient, borderRadius: BorderRadius.circular(8)),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _busy || p.clips.isEmpty ? null : _export,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Export',
                      style: TextStyle(
                          color: PhlioColors.textOnBrand, fontWeight: FontWeight.w900, fontSize: 14.5)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ]),
      );

  Widget _transport() {
    String clock(double s) {
      final m = s ~/ 60, r = (s % 60).floor();
      return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
    }

    return SizedBox(
      height: 46,
      child: Row(children: [
        IconButton(
          tooltip: _fullscreen ? 'Exit full screen' : 'Full screen',
          onPressed: () => setState(() => _fullscreen = !_fullscreen),
          icon: Icon(_fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              color: Colors.white70),
        ),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: clock(t), style: const TextStyle(color: Colors.white)),
            TextSpan(text: ' / ${clock(p.total)}', style: const TextStyle(color: Colors.white38)),
          ]),
          style: const TextStyle(fontSize: 12.5, fontFeatures: [ui.FontFeature.tabularFigures()]),
        ),
        const Spacer(),
        IconButton(
          tooltip: playing ? 'Pause' : 'Play',
          onPressed: _togglePlay,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(playing), color: Colors.white, size: 32),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: _onKey ? 'Remove keyframe' : 'Add keyframe',
          onPressed: _toggleKeyframe,
          icon: Icon(_onKey ? Icons.diamond_rounded : Icons.diamond_outlined,
              color: _keyTarget() == null ? Colors.white24 : (_onKey ? PhlioColors.brandPeach : Colors.white),
              size: 21),
        ),
        IconButton(
          tooltip: 'Undo',
          onPressed: _undo.isEmpty ? null : _undoAction,
          icon: Icon(Icons.undo_rounded, color: _undo.isEmpty ? Colors.white24 : Colors.white),
        ),
        IconButton(
          tooltip: 'Redo',
          onPressed: _redo.isEmpty ? null : _redoAction,
          icon: Icon(Icons.redo_rounded, color: _redo.isEmpty ? Colors.white24 : Colors.white),
        ),
      ]),
    );
  }

  // -- preview canvas ---------------------------------------------------------------------

  double _canvasAspect() => p.ratio == 'original' ? _originalRatio() : p.aspect;

  Widget _preview() {
    return LayoutBuilder(builder: (context, box) {
      final aspect = _canvasAspect();
      var w = box.maxWidth - 24, h = w / aspect;
      if (h > box.maxHeight - 8) {
        h = box.maxHeight - 8;
        w = h * aspect;
      }
      final size = Size(w, h);
      return Center(
        child: GestureDetector(
          onTap: () {
            if (sel.kind == StudioSelectKind.overlay) _select(const StudioSelection.none());
          },
          // Pinch / drag the selected clip inside the frame (CapCut-style).
          onScaleStart: (_) {
            final c = _clip;
            if (c == null) return;
            _pause();
            remember();
            final local = t - p.starts[p.clips.indexOf(c)];
            final (z, px, py) = c.transformAt(local);
            _gestureSize = z;
            _gesturePan = Offset(px, py);
          },
          onScaleUpdate: (d) {
            final c = _clip;
            if (c == null) return;
            _gesturePan += Offset(d.focalPointDelta.dx / (w / 2), d.focalPointDelta.dy / (h / 2));
            final z = (_gestureSize * d.scale).clamp(c.fit == 'fill' ? 1.0 : .5, 4.0);
            final px = _gesturePan.dx.clamp(-1.0, 1.0), py = _gesturePan.dy.clamp(-1.0, 1.0);
            setState(() {
              if (c.keys.isNotEmpty) {
                // Animating: the gesture edits the keyframe at the playhead.
                final local = (t - p.starts[p.clips.indexOf(c)]).clamp(0.0, c.length);
                setKey(c.keys, [local, z, px, py]);
              } else {
                c.zoom = z;
                c.panX = px;
                c.panY = py;
              }
            });
          },
          child: SizedBox(
            width: w,
            height: h,
            child: ClipRect(
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: _segmentsView(_withPips(_frame(size), size), size)),
                for (final o in p.overlays)
                  if ((t >= o.start && t <= o.end) || sel.matches(StudioSelectKind.overlay, o.id))
                    OverlayView(
                      key: ValueKey(o.id),
                      overlay: o,
                      canvas: size,
                      t: t,
                      animate: playing,
                      selected: sel.matches(StudioSelectKind.overlay, o.id),
                      onTap: () => _select(StudioSelection(StudioSelectKind.overlay, o.id)),
                      onDoubleTap: o.kind == 'text' ? () => _addText(edit: o) : null,
                      onScaleStart: (_) {
                        _select(StudioSelection(StudioSelectKind.overlay, o.id));
                        remember();
                        final a = o.at(t);
                        _gestureSize = a.size;
                        _gestureRotation = a.rotation;
                        _gesturePan = Offset(a.x, a.y);
                      },
                      onScaleUpdate: (d) => setState(() {
                        _gesturePan += Offset(d.focalPointDelta.dx / w, d.focalPointDelta.dy / h);
                        final x = _gesturePan.dx.clamp(-.2, 1.2), y = _gesturePan.dy.clamp(-.2, 1.2);
                        final size = d.pointerCount > 1
                            ? (_gestureSize * d.scale).clamp(.02, 1.5)
                            : _gestureSize;
                        final rot = d.pointerCount > 1 ? _gestureRotation + d.rotation : _gestureRotation;
                        if (o.keys.isNotEmpty) {
                          final local = (t - o.start).clamp(0.0, o.end - o.start);
                          setKey(o.keys, [local, x, y, size, rot, o.at(t).opacity]);
                        } else {
                          o
                            ..x = x
                            ..y = y
                            ..size = size
                            ..rotation = rot;
                        }
                      }),
                      onDelete: () {
                        remember();
                        setState(() {
                          p.overlays.remove(o);
                          sel = const StudioSelection.none();
                        });
                      },
                      onDuplicate: () {
                        remember();
                        final copy = o.duplicate();
                        setState(() {
                          p.overlays.add(copy);
                          sel = StudioSelection(StudioSelectKind.overlay, copy.id);
                        });
                      },
                      onHandle: (d, centre) => setState(() {
                        final v = d.globalPosition - centre;
                        final v0 = v - d.delta;
                        if (v0.distance > 4) {
                          final a = o.at(t);
                          final size = (a.size * v.distance / v0.distance).clamp(.02, 1.5);
                          final rot = a.rotation + v.direction - v0.direction;
                          if (o.keys.isNotEmpty) {
                            setKey(o.keys, [(t - o.start).clamp(0.0, o.end - o.start), a.x, a.y, size, rot, a.opacity]);
                          } else {
                            o
                              ..size = size
                              ..rotation = rot;
                          }
                        }
                      }),
                    ),
                if (_recording)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: PhlioColors.danger, borderRadius: BorderRadius.circular(20)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.fiber_manual_record, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text('Recording',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
    });
  }

  /// The clip under the playhead (plus the incoming clip during a transition).
  Widget _frame(Size size) {
    if (p.clips.isEmpty) return const ColoredBox(color: Colors.black);
    final (i, local) = p.clipAt(t);
    final clip = p.clips[i];
    final ov = p.overlapAfter(i);
    final layers = <Widget>[Positioned.fill(child: _clipView(clip, local, size))];
    if (ov > 0 && local > clip.length - ov && i + 1 < p.clips.length) {
      final f = ((local - (clip.length - ov)) / ov).clamp(0.0, 1.0);
      layers.add(Positioned.fill(
          child: Opacity(opacity: f, child: _clipView(p.clips[i + 1], 0, size))));
    }
    return Stack(children: layers);
  }

  Widget _media(StudioClip c, {bool background = false}) {
    Widget child;
    final ctrl = _players[c.id];
    if (c.kind == 'video' && ctrl != null && ctrl.value.isInitialized) {
      child = SizedBox(
        width: ctrl.value.size.width,
        height: ctrl.value.size.height,
        child: VideoPlayer(ctrl),
      );
    } else if (c.kind == 'image') {
      child = Image.file(File(c.path),
          cacheWidth: background ? 240 : null, gaplessPlayback: true, fit: BoxFit.contain);
    } else {
      return const ColoredBox(color: Colors.black);
    }
    if (c.turns != 0) child = RotatedBox(quarterTurns: c.turns, child: child);
    if (c.flip || c.flipV) {
      child = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(c.flip ? -1 : 1, c.flipV ? -1 : 1, 1),
        child: child,
      );
    }
    final crop = c.crop;
    if (crop != null) {
      final ax = crop[2] >= .999 ? 0.0 : crop[0] / (1 - crop[2]) * 2 - 1;
      final ay = crop[3] >= .999 ? 0.0 : crop[1] / (1 - crop[3]) * 2 - 1;
      child = ClipRect(
        child: Align(
          alignment: Alignment(ax, ay),
          widthFactor: crop[2],
          heightFactor: crop[3],
          child: child,
        ),
      );
    }
    return child;
  }

  Widget _clipView(StudioClip c, double local, Size size) {
    Widget fg = FittedBox(fit: c.fit == 'fill' ? BoxFit.cover : BoxFit.contain, clipBehavior: Clip.hardEdge, child: _media(c));
    final (zoom, panX, panY) = c.transformAt(local);
    fg = Transform.translate(
      offset: Offset(panX * size.width / 2, panY * size.height / 2),
      child: Transform.scale(scale: c.fit == 'fill' ? math.max(1.0, zoom) : zoom, child: fg),
    );
    // Ken Burns motion (keyframes take over when present).
    if (c.motion != 'none' && c.keys.isEmpty) {
      final pr = (local / c.length).clamp(0.0, 1.0);
      final z = switch (c.motion) {
        'zoom_in' => 1 + .18 * pr,
        'zoom_out' => 1.18 - .18 * pr,
        _ => 1.15,
      };
      final dx = switch (c.motion) {
        'pan_left' => (1 - pr) - .5,
        'pan_right' => pr - .5,
        _ => 0.0,
      };
      fg = Transform.translate(
        offset: Offset(-dx * size.width * (z - 1), 0),
        child: Transform.scale(scale: z, child: fg),
      );
    }
    final layers = <Widget>[];
    if (c.fit == 'fit') {
      layers.add(Positioned.fill(
        child: p.background == 'blur'
            ? ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                    sigmaX: 6 + p.blur * 24, sigmaY: 6 + p.blur * 24, tileMode: TileMode.clamp),
                child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: _media(c, background: true)),
              )
            : ColoredBox(color: Color(int.parse('FF${p.background.substring(1)}', radix: 16))),
      ));
    }
    layers.add(Positioned.fill(child: fg));
    Widget out = Stack(fit: StackFit.expand, children: layers);
    // GPU shader: filter/look grade (tone curve, vignette, grain) plus the
    // effect when the shader can draw it — same maths as the export.
    final shaderFx = _shaderEffect(c.effect);
    out = PhlioLook(grade: c.grade, effect: shaderFx ?? 'none', child: out);
    if (shaderFx == null) out = _effectPreview(c.effect, out, size);
    final shaded = PhlioLookShader.supported;
    final vignette = c.effect == 'vignette' ? .7 : (shaded ? 0.0 : (c.adjust['vignette'] ?? 0));
    final extras = <Widget>[Positioned.fill(child: out)];
    if (vignette > 0) {
      extras.add(Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: .95,
                colors: [Colors.transparent, Colors.black.withValues(alpha: .25 + .55 * vignette)],
                stops: [.55 - .25 * vignette, 1],
              ),
            ),
          ),
        ),
      ));
    }
    // Fade in/out animations.
    const d = .5;
    double? fade;
    bool white = false;
    if (c.animIn != 'none' && local < d) {
      fade = 1 - local / d;
      white = c.animIn == 'fade_white';
    } else if (c.animOut != 'none' && c.length - local < d) {
      fade = 1 - (c.length - local) / d;
      white = c.animOut == 'fade_white';
    }
    if (fade != null && fade > 0) {
      extras.add(Positioned.fill(
          child: IgnorePointer(
              child: ColoredBox(
                  color: (white ? Colors.white : Colors.black).withValues(alpha: fade.clamp(0.0, 1.0))))));
    }
    if (c.effect == 'flash') {
      final f = math.pow(math.max(0, math.sin(t * 5)), 8).toDouble() * .45;
      extras.add(Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: Colors.white.withValues(alpha: f)))));
    }
    return ClipRect(child: Stack(children: extras));
  }

  /// Overlay media layers on top of the main track.
  Widget _withPips(Widget base, Size size) {
    final live = [
      for (final x in p.pips)
        if ((t >= x.at && t < x.at + x.length) || sel.matches(StudioSelectKind.pip, x.id)) x
    ];
    if (live.isEmpty) return base;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(child: base),
      for (final x in live)
        PipView(
          key: ValueKey(x.id),
          pip: x,
          canvas: size,
          t: (t >= x.at && t < x.at + x.length) ? t : x.at,
          media: _pipMedia(x),
          selected: sel.matches(StudioSelectKind.pip, x.id),
          onTap: () => _select(StudioSelection(StudioSelectKind.pip, x.id)),
          onScaleStart: (_) {
            _select(StudioSelection(StudioSelectKind.pip, x.id));
            remember();
            final a = x.placeAt(t);
            _gestureSize = a.scale;
            _gestureRotation = a.rotation;
            _gesturePan = Offset(a.x, a.y);
            _pipStartW = x.w;
          },
          onScaleUpdate: (d) => setState(() {
            _gesturePan += Offset(d.focalPointDelta.dx / size.width, d.focalPointDelta.dy / size.height);
            final px = _gesturePan.dx.clamp(-.5, 1.5), py = _gesturePan.dy.clamp(-.5, 1.5);
            final scale = d.pointerCount > 1 ? (_gestureSize * d.scale).clamp(.05, 6.0) : _gestureSize;
            final rot = d.pointerCount > 1 ? _gestureRotation + d.rotation : _gestureRotation;
            if (x.keys.isNotEmpty) {
              setKey(x.keys, [(t - x.at).clamp(0.0, x.length), px, py, scale, rot, x.placeAt(t).opacity]);
            } else {
              x
                ..x = px
                ..y = py
                ..w = d.pointerCount > 1 ? (_pipStartW * d.scale).clamp(.05, 4.0) : x.w
                ..rotation = rot;
            }
          }),
        ),
    ]);
  }

  Widget _pipMedia(StudioPip x) {
    final ctrl = _pipPlayers[x.id];
    if (x.kind == 'video' && ctrl != null && ctrl.value.isInitialized) {
      return SizedBox(width: ctrl.value.size.width, height: ctrl.value.size.height, child: VideoPlayer(ctrl));
    }
    if (x.kind == 'image') {
      return Image.file(File(x.path), gaplessPlayback: true, cacheWidth: 900);
    }
    return const SizedBox(width: 16, height: 16, child: ColoredBox(color: Colors.black26));
  }

  /// Timeline effect / filter / adjustment layers active at the playhead.
  Widget _segmentsView(Widget child, Size size) {
    var out = child;
    for (final s in p.segments) {
      if (t < s.start || t >= s.end) continue;
      if (s.kind == 'effect') {
        final e = s.effect ?? 'none';
        final shaderFx = _shaderEffect(e);
        out = shaderFx != null
            ? PhlioLook(effect: shaderFx, child: out)
            : _effectPreview(switch (e) { 'dream' => 'soft', 'neon' => 'vivid', 'sepia_flicker' => 'vhs', _ => e }, out, size);
        if (e == 'vignette' || (e == 'film' && shaderFx == null)) out = _vignette(out, .7);
        if (e == 'flash') {
          final f = math.pow(math.max(0, math.sin(t * 5)), 8).toDouble() * .45;
          out = Stack(fit: StackFit.expand, children: [
            out,
            IgnorePointer(child: ColoredBox(color: Colors.white.withValues(alpha: f))),
          ]);
        }
      } else {
        out = PhlioLook(grade: s.grade, child: out);
        final v = s.adjust['vignette'] ?? 0;
        if (v > 0 && !PhlioLookShader.supported) out = _vignette(out, v);
      }
    }
    return out;
  }

  Widget _vignette(Widget child, double v) => Stack(fit: StackFit.expand, children: [
        child,
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: .95,
                colors: [Colors.transparent, Colors.black.withValues(alpha: .25 + .55 * v)],
                stops: [.55 - .25 * v, 1],
              ),
            ),
          ),
        ),
      ]);

  /// Studio effects the GPU shader previews (the server renders them on export).
  String? _shaderEffect(String effect) {
    if (!PhlioLookShader.supported) return null;
    return switch (effect) {
      'glitch' => 'glitch',
      'rgb_split' => 'chromatic',
      'vhs' => 'vhs',
      'film' || 'sepia_flicker' => 'film',
      'dream' || 'soft' => 'dreamy',
      'blur' => 'blur',
      'grain' => 'grain',
      _ => null,
    };
  }

  Widget _effectPreview(String effect, Widget child, Size size) {
    switch (effect) {
      case 'blur':
        return ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5), child: child);
      case 'soft':
        return Stack(fit: StackFit.expand, children: [
          child,
          Opacity(
              opacity: .35,
              child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: child)),
        ]);
      case 'film':
        return ColorFiltered(
          colorFilter: ColorFilter.matrix(flutterColorMatrix(studioColorMatrix('noir', 1, const {}))),
          child: child,
        );
      case 'vivid':
        return ColorFiltered(
          colorFilter: ColorFilter.matrix(flutterColorMatrix(studioColorMatrix('vivid', 1, const {}))),
          child: child,
        );
      case 'vhs':
        return ColorFiltered(
          colorFilter: ColorFilter.matrix(flutterColorMatrix(studioColorMatrix('vintage', .6, const {}))),
          child: child,
        );
      case 'mirror':
        final half = ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: .5,
            child: SizedBox(width: size.width, height: size.height, child: child),
          ),
        );
        return Row(children: [
          half,
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(-1, 1, 1),
            child: half,
          ),
        ]);
      case 'shake':
        return Transform.translate(
          offset: Offset(math.sin(t * 37) * size.width * .02, math.cos(t * 29) * size.height * .02),
          child: Transform.scale(scale: 1.1, child: child),
        );
      case 'glitch':
      case 'rgb_split':
        return Stack(fit: StackFit.expand, children: [
          child,
          Transform.translate(
            offset: Offset(effect == 'glitch' ? 5 : 3, 0),
            child: Opacity(
              opacity: .35,
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(
                    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]),
                child: child,
              ),
            ),
          ),
        ]);
      default:
        return child;
    }
  }

  // -- toolbar + panels ------------------------------------------------------------------

  Widget _bottom() {
    final child = switch (panel) {
      _Panel.none => _toolbar(),
      _ => _panelView(),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (c, a) => SizeTransition(sizeFactor: a, axisAlignment: -1, child: c),
      child: KeyedSubtree(key: ValueKey('${panel.name}-${sel.kind.name}'), child: child),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap, {bool on = false}) => InkResponse(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        radius: 34,
        child: SizedBox(
          width: 66,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: on ? _violet : Colors.white, size: 23),
            const SizedBox(height: 5),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: on ? _violet : Colors.white, fontSize: 11.2)),
          ]),
        ),
      );

  Widget _toolbar() {
    final List<Widget> tools;
    final clip = _clip;
    final audio = _audioSel;
    final overlay = _overlay;
    final pip = _pip;
    final segment = _segment;
    if (clip != null || _clipTools) {
      final c = clip ?? _target!;
      // CapCut's clip menu order.
      tools = [
        _tool(Icons.content_cut_rounded, 'Split', _split),
        _tool(Icons.speed_rounded, 'Speed', () => _open(_Panel.speed), on: c.speed != 1 || c.hasCurve),
        _tool(Icons.volume_up_outlined, 'Volume', () => _open(_Panel.volume), on: c.volume != 1),
        _tool(Icons.animation_rounded, 'Animations', () => _open(_Panel.animation),
            on: c.animIn != 'none' || c.animOut != 'none' || c.motion != 'none'),
        _tool(Icons.auto_fix_high_outlined, 'Effects', () => _open(_Panel.effects), on: c.effect != 'none'),
        _tool(Icons.delete_outline_rounded, 'Delete', _deleteClip),
        _tool(Icons.record_voice_over_outlined, 'Voice effects', () => _open(_Panel.voice),
            on: c.voice != 'none' || c.denoise),
        _tool(Icons.music_video_outlined, 'Extract audio', _extractClipAudio),
        _tool(Icons.filter_vintage_outlined, 'Filters', () => _open(_Panel.filters), on: c.filter != 'none'),
        _tool(Icons.tune_rounded, 'Adjust', () => _open(_Panel.adjust), on: c.adjust.values.any((v) => v != 0)),
        _tool(Icons.crop_rounded, 'Crop', _crop, on: c.crop != null),
        _tool(Icons.rotate_90_degrees_cw_outlined, 'Rotate', _rotate),
        _tool(Icons.flip_rounded, 'Mirror', _mirror, on: c.flip),
        _tool(Icons.swap_vert_rounded, 'Flip', _flipV, on: c.flipV),
        _tool(Icons.fit_screen_rounded, c.fit == 'fill' ? 'Fit' : 'Fill', () {
          remember();
          setState(() => c.fit = c.fit == 'fill' ? 'fit' : 'fill');
        }),
        _tool(Icons.zoom_in_map_rounded, 'Reset', () {
          remember();
          setState(() {
            c.zoom = 1;
            c.panX = 0;
            c.panY = 0;
            c.keys.clear();
          });
        }),
        _tool(Icons.history_rounded, 'Reverse', _reverse, on: c.reverse),
        _tool(Icons.ac_unit_rounded, 'Freeze', _freeze),
        _tool(Icons.copy_all_rounded, 'Duplicate', _duplicateClip),
        _tool(Icons.find_replace_rounded, 'Replace', () => _pickClips(replace: true)),
        _tool(Icons.swap_horiz_rounded, 'Reorder', () {
          if (p.clips.length < 2) return;
          setState(() => _reorder = true);
        }),
      ];
    } else if (audio != null) {
      tools = [
        _tool(Icons.volume_up_outlined, 'Volume', () => _open(_Panel.volume)),
        _tool(Icons.content_cut_rounded, 'Split', () {
          final local = t - audio.at;
          if (local < .2 || audio.length - local < .2) {
            toast('Move the playhead inside the audio to split');
            return;
          }
          remember();
          final second = audio.duplicate()
            ..start = audio.start + local
            ..at = t;
          audio.end = audio.start + local;
          setState(() => p.audios.add(second));
        }),
        _tool(Icons.record_voice_over_outlined, 'Voice effects', () => _open(_Panel.voice),
            on: audio.voice != 'none' || audio.denoise),
        _tool(Icons.copy_all_rounded, 'Duplicate', () {
          remember();
          setState(() => p.audios.add(audio.duplicate()..at = audio.at + audio.length));
        }),
        _tool(Icons.delete_outline_rounded, 'Delete', () {
          remember();
          _audio.remove(audio.id)?.dispose();
          setState(() {
            p.audios.remove(audio);
            sel = const StudioSelection.none();
          });
        }),
      ];
    } else if (overlay != null) {
      tools = [
        if (overlay.isCaption) ...[
          _tool(Icons.edit_note_rounded, 'Edit captions', _editCaptions),
          _tool(Icons.text_format_rounded, 'Style', () => _open(_Panel.textStyle)),
        ] else if (overlay.kind == 'text') ...[
          _tool(Icons.edit_outlined, 'Edit', () => _addText(edit: overlay)),
          _tool(Icons.text_format_rounded, 'Style', () => _open(_Panel.textStyle)),
        ],
        _tool(Icons.animation_rounded, 'Animation', () => _open(_Panel.overlayAnim),
            on: overlay.loop != 'none' || overlay.animIn != 'none'),
        if (overlay.isText)
          _tool(Icons.record_voice_over_outlined, 'Text to audio',
              () => _textToAudio(initial: overlay.text, at: overlay.start)),
        _tool(Icons.content_cut_rounded, 'Split', () {
          if (t - overlay.start < .3 || overlay.end - t < .3) {
            toast('Move the playhead inside the item to split');
            return;
          }
          remember();
          final second = overlay.duplicate()
            ..x = overlay.x
            ..y = overlay.y
            ..start = t
            ..end = overlay.end
            ..keys = [for (final k in overlay.keys) [k[0] - (t - overlay.start), ...k.skip(1)]];
          overlay.end = t;
          setState(() => p.overlays.add(second));
        }),
        _tool(Icons.align_horizontal_center_rounded, 'Center', () {
          remember();
          setState(() => overlay.x = .5);
        }),
        _tool(Icons.timer_outlined, 'Full length', () {
          remember();
          setState(() {
            overlay.start = 0;
            overlay.end = p.total;
          });
        }),
        _tool(Icons.copy_all_rounded, 'Duplicate', () {
          remember();
          final copy = overlay.duplicate();
          setState(() {
            p.overlays.add(copy);
            sel = StudioSelection(StudioSelectKind.overlay, copy.id);
          });
        }),
        if (overlay.isCaption)
          _tool(Icons.layers_clear_outlined, 'Delete all', () {
            remember();
            setState(() {
              p.overlays.removeWhere((o) => o.isCaption);
              sel = const StudioSelection.none();
            });
          }),
        _tool(Icons.delete_outline_rounded, 'Delete', () {
          remember();
          setState(() {
            p.overlays.remove(overlay);
            sel = const StudioSelection.none();
          });
        }),
      ];
    } else if (pip != null) {
      tools = [
        _tool(Icons.content_cut_rounded, 'Split', () {
          final local = t - pip.at;
          if (local < .2 || pip.length - local < .2) {
            toast('Move the playhead inside the overlay to split');
            return;
          }
          remember();
          final second = pip.duplicate()
            ..start = pip.sourceAt(local)
            ..at = t
            ..keys = [for (final k in pip.keys) [k[0] - local, ...k.skip(1)]];
          pip.end = pip.sourceAt(local);
          p.pips.add(second);
          _ensurePipPlayer(second);
          setState(() {});
        }),
        _tool(Icons.layers_outlined, 'Blend', () => _open(_Panel.blend),
            on: pip.blend != 'normal' || pip.opacity < 1),
        _tool(Icons.blur_circular_rounded, 'Mask', () => _open(_Panel.mask), on: pip.mask != 'none'),
        _tool(Icons.colorize_rounded, 'Chroma key', () => _open(_Panel.chroma), on: pip.chroma != null),
        if (!pip.isPhoto) ...[
          _tool(Icons.volume_up_outlined, 'Volume', () => _open(_Panel.volume), on: pip.volume != 1),
          _tool(Icons.speed_rounded, 'Speed', () => _open(_Panel.speed), on: pip.speed != 1),
        ],
        _tool(Icons.animation_rounded, 'Animations', () => _open(_Panel.animation),
            on: pip.animIn != 'none' || pip.animOut != 'none'),
        _tool(Icons.filter_vintage_outlined, 'Filters', () => _open(_Panel.filters), on: pip.filter != 'none'),
        _tool(Icons.tune_rounded, 'Adjust', () => _open(_Panel.adjust),
            on: pip.adjust.values.any((v) => v != 0)),
        _tool(Icons.flip_rounded, 'Mirror', () {
          remember();
          setState(() => pip.flip = !pip.flip);
        }, on: pip.flip),
        _tool(Icons.copy_all_rounded, 'Duplicate', () {
          remember();
          final copy = pip.duplicate()..at = pip.at + pip.length;
          p.pips.add(copy);
          _ensurePipPlayer(copy);
          setState(() => sel = StudioSelection(StudioSelectKind.pip, copy.id));
        }),
        _tool(Icons.delete_outline_rounded, 'Delete', () {
          remember();
          _disposeLater(_pipPlayers.remove(pip.id));
          setState(() {
            p.pips.remove(pip);
            sel = const StudioSelection.none();
          });
        }),
      ];
    } else if (segment != null) {
      tools = [
        if (segment.kind == 'effect')
          _tool(Icons.find_replace_rounded, 'Replace', () => _open(_Panel.segEffects))
        else if (segment.kind == 'filter')
          _tool(Icons.filter_vintage_outlined, 'Filters', () => _open(_Panel.filters))
        else
          _tool(Icons.tune_rounded, 'Adjust', () => _open(_Panel.adjust)),
        _tool(Icons.timer_outlined, 'Full length', () {
          remember();
          setState(() {
            segment.start = 0;
            segment.end = p.total;
          });
        }),
        _tool(Icons.copy_all_rounded, 'Duplicate', () {
          remember();
          final len = segment.end - segment.start;
          final copy = segment.duplicate()
            ..start = math.min(segment.end, math.max(0.0, p.total - len))
            ..end = math.min(p.total, segment.end + len);
          setState(() {
            p.segments.add(copy);
            sel = StudioSelection(StudioSelectKind.segment, copy.id);
          });
        }),
        _tool(Icons.delete_outline_rounded, 'Delete', () {
          remember();
          setState(() {
            p.segments.remove(segment);
            sel = const StudioSelection.none();
          });
        }),
      ];
    } else {
      // CapCut's main toolbar.
      tools = [
        _tool(Icons.content_cut_rounded, 'Edit', () {
          final c = _target;
          if (c != null) _select(StudioSelection(StudioSelectKind.clip, c.id));
        }),
        _tool(Icons.music_note_outlined, 'Audio', () => _open(_Panel.audioMenu)),
        _tool(Icons.title_rounded, 'Text', () => _open(_Panel.textMenu)),
        _tool(Icons.auto_awesome_outlined, 'Effects', () => _open(_Panel.segEffects)),
        _tool(Icons.picture_in_picture_alt_outlined, 'Overlay', _addPip),
        _tool(Icons.closed_caption_outlined, 'Captions', _autoCaptions, on: _captioning),
        _tool(Icons.filter_vintage_outlined, 'Filters', () => _addColorLayer('filter')),
        _tool(Icons.tune_rounded, 'Adjust', () => _addColorLayer('adjust')),
        _tool(Icons.emoji_emotions_outlined, 'Stickers', () => _open(_Panel.stickers)),
        _tool(Icons.aspect_ratio_rounded, 'Aspect ratio', () => _open(_Panel.ratio)),
        _tool(Icons.wallpaper_rounded, 'Background', () => _open(_Panel.background)),
      ];
    }
    final nested = clip != null || audio != null || overlay != null || pip != null || segment != null || _clipTools;
    return Container(
      height: 74,
      color: const Color(0xFF0B0F17),
      child: Row(children: [
        if (nested)
          InkResponse(
            onTap: () => _select(const StudioSelection.none()),
            child: Container(
              width: 38,
              height: 58,
              margin: const EdgeInsets.only(left: 6, right: 2),
              decoration: BoxDecoration(
                  color: const Color(0xFF1C2433), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.keyboard_double_arrow_left_rounded, color: Colors.white70),
            ),
          ),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: tools,
          ),
        ),
      ]),
    );
  }

  void _open(_Panel next) {
    _pause();
    setState(() => panel = next);
  }

  void _applyAll(void Function(StudioClip c) copy) {
    remember();
    setState(() {
      for (final c in p.clips) {
        copy(c);
      }
    });
    toast('Applied to all clips');
  }

  Widget _panelView() {
    final c = _target;
    void done() => setState(() => panel = _Panel.none);
    switch (panel) {
      case _Panel.speed:
        final pipSpeed = _pip;
        if (pipSpeed != null) {
          return StudioPanel(
            title: 'Speed',
            onDone: done,
            child: StudioSpeedPanel(
              speed: pipSpeed.speed,
              onChanged: (v) {
                _editStart();
                setState(() => pipSpeed.speed = v.clamp(.25, 4.0));
              },
              onCommit: _editEnd,
            ),
          );
        }
        if (c == null) return _toolbar();
        return StudioPanel(
          title: 'Speed',
          height: 236,
          onDone: done,
          onApplyAll: () => _applyAll((x) {
            x.speed = c.speed;
            if (x.kind == 'video' && x.hold == null) x.setCurve(c.curveName);
          }),
          child: StudioSpeedTabs(
            clip: c,
            onSpeed: (v) {
              _editStart();
              setState(() => c.speed = v);
            },
            onCurve: (name) {
              remember();
              setState(() => c.setCurve(name));
              if (name != null) _playPreviewSnippet();
            },
            onCommit: _editEnd,
          ),
        );
      case _Panel.volume:
        final a = _audioSel;
        if (a != null) {
          return StudioPanel(
            title: 'Volume',
            height: 230,
            onDone: done,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              StudioSlider(
                label: 'Volume',
                value: a.volume,
                min: 0,
                max: 2,
                onChanged: (v) {
                  _editStart();
                  setState(() => a.volume = v);
                },
                onChangeEnd: (_) => _editEnd(),
                format: (v) => '${(v * 100).round()}%',
              ),
              StudioSlider(
                label: 'Fade in',
                value: a.fadeIn,
                min: 0,
                max: 5,
                onChanged: (v) => setState(() => a.fadeIn = v),
                format: (v) => '${v.toStringAsFixed(1)}s',
              ),
              StudioSlider(
                label: 'Fade out',
                value: a.fadeOut,
                min: 0,
                max: 5,
                onChanged: (v) => setState(() => a.fadeOut = v),
                format: (v) => '${v.toStringAsFixed(1)}s',
              ),
            ]),
          );
        }
        final pipVol = _pip;
        if (pipVol != null) {
          return StudioPanel(
            title: 'Volume',
            height: 150,
            onDone: done,
            child: Center(
              child: StudioSlider(
                label: 'Volume',
                value: pipVol.volume,
                min: 0,
                max: 2,
                onChanged: (v) {
                  _editStart();
                  setState(() => pipVol.volume = v);
                },
                onChangeEnd: (_) => _editEnd(),
                format: (v) => '${(v * 100).round()}%',
              ),
            ),
          );
        }
        if (c == null) return _toolbar();
        return StudioPanel(
          title: 'Volume',
          height: 230,
          onDone: done,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            StudioSlider(
              label: 'Volume',
              value: c.volume,
              min: 0,
              max: 2,
              onChanged: (v) {
                _editStart();
                setState(() => c.volume = v);
              },
              onChangeEnd: (_) => _editEnd(),
              format: (v) => '${(v * 100).round()}%',
            ),
            StudioSlider(
              label: 'Fade in',
              value: c.fadeAudioIn,
              min: 0,
              max: 5,
              onChanged: (v) => setState(() => c.fadeAudioIn = v),
              format: (v) => '${v.toStringAsFixed(1)}s',
            ),
            StudioSlider(
              label: 'Fade out',
              value: c.fadeAudioOut,
              min: 0,
              max: 5,
              onChanged: (v) => setState(() => c.fadeAudioOut = v),
              format: (v) => '${v.toStringAsFixed(1)}s',
            ),
          ]),
        );
      case _Panel.filters:
        final colorPip = _pip;
        final colorSeg = _segment;
        if (colorPip != null || colorSeg != null) {
          final filter = colorPip?.filter ?? colorSeg!.filter;
          final amount = colorPip?.filterAmount ?? colorSeg!.filterAmount;
          return StudioPanel(
            title: 'Filters',
            height: 200,
            onDone: done,
            child: StudioFilterPanel(
              thumb: c == null ? const ColoredBox(color: Color(0xFF2A2350)) : _thumb(c),
              filter: filter,
              amount: amount,
              onFilter: (f) {
                remember();
                setState(() {
                  if (colorPip != null) {
                    colorPip
                      ..filter = f
                      ..filterAmount = 1;
                  } else {
                    colorSeg!
                      ..filter = f
                      ..filterAmount = 1;
                  }
                });
              },
              onAmount: (v) => setState(() {
                if (colorPip != null) {
                  colorPip.filterAmount = v;
                } else {
                  colorSeg!.filterAmount = v;
                }
              }),
            ),
          );
        }
        if (c == null) return _toolbar();
        return StudioPanel(
          title: 'Filters',
          height: 200,
          onDone: done,
          onApplyAll: () => _applyAll((x) {
            x.filter = c.filter;
            x.filterAmount = c.filterAmount;
          }),
          child: StudioFilterPanel(
            thumb: _thumb(c),
            filter: c.filter,
            amount: c.filterAmount,
            onFilter: (f) {
              remember();
              setState(() {
                c.filter = f;
                c.filterAmount = 1;
              });
            },
            onAmount: (v) => setState(() => c.filterAmount = v),
          ),
        );
      case _Panel.adjust:
        final adjustTarget = _pip?.adjust ?? _segment?.adjust;
        if (adjustTarget != null) {
          return StudioPanel(
            title: 'Adjust',
            height: 220,
            onDone: done,
            child: StudioAdjustPanel(
              adjust: adjustTarget,
              onChanged: (k, v) {
                _editStart();
                setState(() => adjustTarget[k] = v);
              },
              onCommit: _editEnd,
            ),
          );
        }
        if (c == null) return _toolbar();
        return StudioPanel(
          title: 'Adjust',
          height: 220,
          onDone: done,
          onApplyAll: () => _applyAll((x) => x.adjust = Map.of(c.adjust)),
          child: StudioAdjustPanel(
            adjust: c.adjust,
            onChanged: (k, v) {
              _editStart();
              setState(() => c.adjust[k] = v);
            },
            onCommit: _editEnd,
          ),
        );
      case _Panel.effects:
        if (c == null) return _toolbar();
        return StudioPanel(
          title: 'Effects',
          onDone: done,
          onApplyAll: () => _applyAll((x) => x.effect = c.effect),
          child: StudioOptionStrip(
            options: studioEffects,
            selected: c.effect,
            icon: studioEffectTile,
            onPick: (e) {
              remember();
              setState(() => c.effect = e);
              if (e != 'none') _playPreviewSnippet();
            },
          ),
        );
      case _Panel.animation:
        final animPip = _pip;
        if (animPip != null) {
          return StudioPanel(
            title: 'Animations',
            height: 220,
            onDone: done,
            child: Column(children: [
              const _Label('In'),
              Expanded(
                child: StudioOptionStrip(
                  tile: 46,
                  options: const [('none', 'None'), ('fade', 'Fade in')],
                  selected: animPip.animIn,
                  onPick: (v) {
                    remember();
                    setState(() => animPip.animIn = v);
                  },
                ),
              ),
              const _Label('Out'),
              Expanded(
                child: StudioOptionStrip(
                  tile: 46,
                  options: const [('none', 'None'), ('fade', 'Fade out')],
                  selected: animPip.animOut,
                  onPick: (v) {
                    remember();
                    setState(() => animPip.animOut = v);
                  },
                ),
              ),
            ]),
          );
        }
        if (c == null) return _toolbar();
        return StudioPanel(
          title: 'Animation',
          height: 250,
          onDone: done,
          child: _AnimationPanel(clip: c, onChanged: (fn) {
            remember();
            setState(fn);
            _playPreviewSnippet();
          }),
        );
      case _Panel.transition:
        if (c == null) return _toolbar();
        return StudioPanel(
          title: 'Transition',
          height: 220,
          onDone: done,
          onApplyAll: () => _applyAll((x) {
            if (x != p.clips.last) {
              x.transition = c.transition;
              x.transitionDuration = c.transitionDuration;
            }
          }),
          child: Column(children: [
            Expanded(
              child: StudioOptionStrip(
                options: studioTransitions,
                selected: c.transition,
                icon: studioTransitionTile,
                onPick: (v) {
                  remember();
                  setState(() => c.transition = v);
                  final i = p.clips.indexOf(c);
                  if (i < p.clips.length - 1) {
                    t = math.max(0, p.starts[i + 1] - .6);
                    _play();
                  }
                },
              ),
            ),
            if (c.transition != 'none')
              StudioSlider(
                label: 'Duration',
                value: c.transitionDuration,
                min: .1,
                max: 2,
                onChanged: (v) => setState(() => c.transitionDuration = v),
                format: (v) => '${v.toStringAsFixed(1)}s',
              ),
            const SizedBox(height: 6),
          ]),
        );
      case _Panel.ratio:
        return StudioPanel(
          title: 'Aspect ratio',
          onDone: done,
          child: StudioOptionStrip(
            options: studioRatios,
            selected: p.ratio,
            icon: studioRatioTile,
            onPick: (r) {
              remember();
              setState(() => p.ratio = r);
            },
          ),
        );
      case _Panel.background:
        return StudioPanel(
          title: 'Background',
          height: 220,
          onDone: done,
          child: _BackgroundPanel(
            project: p,
            onChanged: (fn) {
              remember();
              setState(fn);
              if (p.clips.every((x) => x.fit == 'fill')) {
                for (final x in p.clips) {
                  x.fit = 'fit';
                }
                toast('Clips set to Fit so the background shows');
              }
            },
          ),
        );
      case _Panel.stickers:
        return StudioPanel(
          title: 'Stickers',
          height: 280,
          onDone: done,
          child: StudioStickerPanel(
            onEmoji: (e) => _addSticker(emoji: e),
            onAsset: (a) => _addSticker(asset: a),
          ),
        );
      case _Panel.audioMenu:
        return StudioPanel(
          title: 'Audio',
          height: 150,
          onDone: done,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              _tool(Icons.library_music_outlined, 'Sounds', _addMusic),
              _tool(Icons.graphic_eq_rounded, 'Sound FX', _addSoundEffect),
              _tool(Icons.video_file_outlined, 'Extract', () => _addAudioFile(extract: true)),
              _tool(Icons.mic_none_rounded, 'Voiceover', () => _open(_Panel.voiceover)),
              _tool(Icons.record_voice_over_outlined, 'Text to audio', () => _textToAudio()),
              _tool(Icons.audio_file_outlined, 'From files', () => _addAudioFile()),
              _tool(p.muteOriginal ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  p.muteOriginal ? 'Unmute clips' : 'Mute clips', () {
                remember();
                setState(() => p.muteOriginal = !p.muteOriginal);
              }, on: p.muteOriginal),
            ],
          ),
        );
      case _Panel.voiceover:
        return StudioPanel(
          title: 'Voiceover',
          height: 210,
          onDone: () {
            if (_recording) _toggleVoiceover();
            done();
          },
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_recording ? 'Recording from ${t.toStringAsFixed(1)}s — tap to stop' : 'Hold the playhead where you want to start, then tap',
                style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _toggleVoiceover,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 74,
                height: 74,
                padding: EdgeInsets.all(_recording ? 22 : 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    color: PhlioColors.danger,
                    borderRadius: BorderRadius.circular(_recording ? 6 : 40),
                  ),
                ),
              ),
            ),
          ]),
        );
      case _Panel.textStyle:
        final styled = _overlay;
        if (styled == null) return _toolbar();
        return StudioPanel(
          title: styled.isCaption ? 'Caption style' : 'Text style',
          height: 250,
          onDone: done,
          onApplyAll: styled.isCaption
              ? () {
                  remember();
                  setState(() {
                    for (final o in p.overlays.where((o) => o.isCaption)) {
                      o
                        ..style = styled.style
                        ..font = styled.font
                        ..color = styled.color
                        ..accent = styled.accent
                        ..size = styled.size
                        ..bold = styled.bold
                        ..x = styled.x
                        ..y = styled.y;
                    }
                  });
                  toast('Applied to all captions');
                }
              : null,
          child: _TextStyleControls(
            overlay: styled,
            onChanged: (fn) {
              remember();
              setState(fn);
            },
          ),
        );
      case _Panel.overlayAnim:
        final o = _overlay;
        if (o == null) return _toolbar();
        return StudioPanel(
          title: 'Animation',
          height: 200,
          onDone: done,
          child: StudioTextAnimPanel(
            overlay: o,
            onChanged: (fn) {
              remember();
              setState(fn);
              t = o.start;
              _play();
            },
          ),
        );
      case _Panel.export:
        return StudioPanel(
          title: 'Export settings',
          height: 300,
          onDone: done,
          child: StudioExportSettings(project: p, onChanged: (fn) => setState(fn)),
        );
      case _Panel.voice:
        final va = _audioSel;
        final vc = va == null ? c : null;
        if (va == null && vc == null) return _toolbar();
        return StudioPanel(
          title: 'Voice effects',
          height: 230,
          onDone: done,
          onApplyAll: vc == null
              ? null
              : () => _applyAll((x) {
                    x.voice = vc.voice;
                    x.denoise = vc.denoise;
                  }),
          child: StudioVoicePanel(
            voice: va?.voice ?? vc!.voice,
            denoise: va?.denoise ?? vc!.denoise,
            onVoice: (v) {
              remember();
              setState(() {
                if (va != null) {
                  va.voice = v;
                } else {
                  vc!.voice = v;
                }
              });
            },
            onDenoise: (v) {
              remember();
              setState(() {
                if (va != null) {
                  va.denoise = v;
                } else {
                  vc!.denoise = v;
                }
              });
            },
          ),
        );
      case _Panel.blend:
        final bp = _pip;
        if (bp == null) return _toolbar();
        return StudioPanel(
          title: 'Blend',
          height: 210,
          onDone: done,
          child: StudioBlendPanel(pip: bp, onChanged: (fn) {
            _editStart();
            setState(fn);
          }, onCommit: _editEnd),
        );
      case _Panel.mask:
        final mp = _pip;
        if (mp == null) return _toolbar();
        return StudioPanel(
          title: 'Mask',
          height: mp.mask == 'none' ? 140 : 330,
          onDone: done,
          child: SingleChildScrollView(
            child: StudioMaskPanel(pip: mp, onChanged: (fn) {
              _editStart();
              setState(fn);
              _editEnd();
            }, onCommit: _editEnd),
          ),
        );
      case _Panel.chroma:
        final cp = _pip;
        if (cp == null) return _toolbar();
        return StudioPanel(
          title: 'Chroma key',
          height: 220,
          onDone: done,
          child: StudioChromaPanel(pip: cp, onChanged: (fn) {
            _editStart();
            setState(fn);
            _editEnd();
          }, onCommit: _editEnd),
        );
      case _Panel.textMenu:
        return StudioPanel(
          title: 'Text',
          height: 150,
          onDone: done,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              _tool(Icons.text_fields_rounded, 'Add text', () => _addText()),
              _tool(Icons.closed_caption_outlined, 'Auto captions', _autoCaptions),
              _tool(Icons.emoji_emotions_outlined, 'Stickers', () => _open(_Panel.stickers)),
              _tool(Icons.record_voice_over_outlined, 'Text to audio', () => _textToAudio()),
            ],
          ),
        );
      case _Panel.segEffects:
        final current = _segment;
        return StudioPanel(
          title: 'Video effects',
          onDone: done,
          child: StudioOptionStrip(
            options: studioSegmentEffects,
            selected: current?.kind == 'effect' ? current!.effect ?? '' : '',
            icon: studioEffectTile,
            onPick: _pickSegmentEffect,
          ),
        );
      case _Panel.none:
        return _toolbar();
    }
  }

  /// Long-press reorder mode: clips shrink to tiles you drag into place.
  Widget _reorderStrip() => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Row(children: [
            const Expanded(
              child: Text('Drag clips to reorder',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => setState(() => _reorder = false),
              child: const Text('Done',
                  style: TextStyle(color: PhlioColors.brandPeach, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        SizedBox(
          height: 84,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: p.clips.length,
            proxyDecorator: (child, _, __) => Transform.scale(scale: 1.08, child: child),
            onReorder: (from, to) {
              remember();
              setState(() {
                if (to > from) to--;
                final c = p.clips.removeAt(from);
                p.clips.insert(to, c);
                _active = -1;
              });
              HapticFeedback.selectionClick();
              _seekPreview();
            },
            itemBuilder: (_, i) {
              final c = p.clips[i];
              return Container(
                key: ValueKey(c.id),
                width: 68,
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(fit: StackFit.expand, children: [
                  _thumb(c),
                  Positioned(
                    right: 4,
                    bottom: 3,
                    child: Text('${c.length.toStringAsFixed(1)}s',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            shadows: [Shadow(blurRadius: 3)])),
                  ),
                ]),
              );
            },
          ),
        ),
      ]);

  /// Plays ~1.5s around the playhead so you can see an effect/animation.
  void _playPreviewSnippet() {
    final c = _target;
    if (c == null) return;
    final start = p.starts[p.clips.indexOf(c)];
    if (t < start || t > start + c.length - .3) t = start;
    _play();
  }

  Widget _thumb(StudioClip c) {
    if (c.kind == 'image') {
      return Image.file(File(c.path), fit: BoxFit.cover, cacheWidth: 160);
    }
    final strip = c.fileId == null ? null : _strips[c.fileId];
    if (strip != null) {
      return RawImage(image: strip, fit: BoxFit.cover, alignment: Alignment.centerLeft);
    }
    return const ColoredBox(color: Color(0xFF2A2350));
  }

  Future<void> _crop() async {
    final c = _target;
    if (c == null) return;
    _pause();
    final i = p.clips.indexOf(c);
    final local = (t - p.starts[i]).clamp(0.0, c.length);
    final result = await Navigator.of(context).push<List<double>?>(MaterialPageRoute(
      builder: (_) => _CropScreen(
        media: _media(StudioClip.fromJson(c.toJson())..crop = null),
        aspect: _sourceAspect(c),
        initial: c.crop,
      ),
    ));
    if (result == null || !mounted) return;
    remember();
    setState(() => c.crop = result.length == 4 ? result : null);
    t = p.starts[i] + local;
    _seekPreview();
  }

  double _sourceAspect(StudioClip c) {
    var a = 1.0;
    final ctrl = _players[c.id];
    if (ctrl != null && ctrl.value.isInitialized && ctrl.value.size.width > 0) {
      a = ctrl.value.size.width / ctrl.value.size.height;
    } else if (c.kind == 'image') {
      a = p.aspect;
    }
    return c.turns.isOdd ? 1 / a : a;
  }
}

// =============================================================================
// Smaller pieces

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      );
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.options, required this.labels, required this.selected, required this.onPick});
  final List<String> options, labels;
  final String selected;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onPick(options[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: options[i] == selected ? Colors.white : const Color(0xFF1C2433),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(labels[i],
                      style: TextStyle(
                          color: options[i] == selected ? const Color(0xFF0B0F17) : Colors.white70,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ),
        ]),
      );
}

class _AnimationPanel extends StatelessWidget {
  const _AnimationPanel({required this.clip, required this.onChanged});
  final StudioClip clip;
  final void Function(VoidCallback fn) onChanged;
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
          child: Row(children: [
            const SizedBox(width: 18, child: RotatedBox(quarterTurns: 3, child: Text('IN', style: TextStyle(color: Colors.white38, fontSize: 10)))),
            Expanded(
              child: StudioOptionStrip(
                tile: 46,
                options: const [('none', 'None'), ('fade', 'Fade'), ('fade_white', 'Flash')],
                selected: clip.animIn,
                onPick: (v) => onChanged(() => clip.animIn = v),
              ),
            ),
            const SizedBox(width: 18, child: RotatedBox(quarterTurns: 3, child: Text('OUT', style: TextStyle(color: Colors.white38, fontSize: 10)))),
            Expanded(
              child: StudioOptionStrip(
                tile: 46,
                options: const [('none', 'None'), ('fade', 'Fade'), ('fade_white', 'Flash')],
                selected: clip.animOut,
                onPick: (v) => onChanged(() => clip.animOut = v),
              ),
            ),
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: StudioOptionStrip(
            tile: 46,
            options: const [
              ('none', 'Still'),
              ('zoom_in', 'Zoom in'),
              ('zoom_out', 'Zoom out'),
              ('pan_left', 'Pan left'),
              ('pan_right', 'Pan right'),
            ],
            selected: clip.motion,
            icon: (id, on) => Icon(
              switch (id) {
                'zoom_in' => Icons.zoom_in_rounded,
                'zoom_out' => Icons.zoom_out_rounded,
                'pan_left' => Icons.west_rounded,
                'pan_right' => Icons.east_rounded,
                _ => Icons.crop_square_rounded,
              },
              color: on ? Colors.white : Colors.white60,
            ),
            onPick: (v) => onChanged(() => clip.motion = v),
          ),
        ),
      ]);
}

class _BackgroundPanel extends StatelessWidget {
  const _BackgroundPanel({required this.project, required this.onChanged});
  final StudioProject project;
  final void Function(VoidCallback fn) onChanged;
  @override
  Widget build(BuildContext context) {
    final p = project;
    return Column(children: [
      const _Label('Blur'),
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            for (final level in const [.2, .45, .7, 1.0])
              GestureDetector(
                onTap: () => onChanged(() {
                  p.background = 'blur';
                  p.blur = level;
                }),
                child: Container(
                  width: 48,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(colors: [Color(0xFF3B2F7A), Color(0xFF8D78FF)]),
                    border: Border.all(
                        color: p.background == 'blur' && (p.blur - level).abs() < .01
                            ? Colors.white
                            : Colors.transparent,
                        width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: level * 4, sigmaY: level * 4),
                      child: const Icon(Icons.blur_on_rounded, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      const _Label('Colour'),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            for (final c in studioSwatches)
              GestureDetector(
                onTap: () => onChanged(() => p.background =
                    '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'),
                child: Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: p.background ==
                                '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'
                            ? Colors.white
                            : Colors.white24,
                        width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}

class _TextStyleControls extends StatelessWidget {
  const _TextStyleControls({required this.overlay, required this.onChanged});
  final StudioOverlay overlay;
  final void Function(VoidCallback fn) onChanged;
  @override
  Widget build(BuildContext context) {
    final o = overlay;
    Widget swatches(int current, void Function(int) pick) => SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [
              for (final c in studioSwatches)
                GestureDetector(
                  onTap: () => onChanged(() => pick(c)),
                  child: Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: current == c ? Colors.white : Colors.white24, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        );
    return ListView(padding: EdgeInsets.zero, children: [
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            for (final (id, label) in studioTextStyles)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: o.style == id,
                  onSelected: (_) => onChanged(() => o.style = id),
                  selectedColor: studioViolet,
                  backgroundColor: const Color(0xFF1C2433),
                  labelStyle: TextStyle(color: o.style == id ? Colors.white : Colors.white70),
                  side: BorderSide.none,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            for (final (id, label) in studioTextFonts)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label, style: TextStyle(fontFamily: id)),
                  selected: o.font == id,
                  onSelected: (_) => onChanged(() => o.font = id),
                  selectedColor: studioViolet,
                  backgroundColor: const Color(0xFF1C2433),
                  labelStyle: TextStyle(color: o.font == id ? Colors.white : Colors.white70),
                  side: BorderSide.none,
                ),
              ),
            for (final (id, icon) in const [
              ('left', Icons.format_align_left_rounded),
              ('center', Icons.format_align_center_rounded),
              ('right', Icons.format_align_right_rounded),
            ])
              IconButton(
                onPressed: () => onChanged(() => o.align = id),
                icon: Icon(icon, color: o.align == id ? Colors.white : Colors.white38),
              ),
          ],
        ),
      ),
      const _Label('Text colour'),
      swatches(o.color, (c) => o.color = c),
      const _Label('Accent (label, outline, glow)'),
      swatches(o.accent, (c) => o.accent = c),
    ]);
  }
}

/// Full-screen text entry over the preview (CapCut "Add text").
class _TextEditor extends StatefulWidget {
  const _TextEditor({required this.overlay});
  final StudioOverlay overlay;
  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final _controller = TextEditingController(text: widget.overlay.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.overlay;
    final width = MediaQuery.sizeOf(context).width;
    final layout = OverlayLayout(o..text = _controller.text, width);
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(children: [
          Row(children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 16)),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.pop(context, o..text = _controller.text),
              child: const Text('Done',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ]),
          Expanded(
            child: Center(
              child: Stack(alignment: Alignment.center, children: [
                // Live styled preview behind a transparent field.
                IgnorePointer(
                  child: CustomPaint(
                    size: layout.size,
                    painter: _CentredPainter(layout),
                  ),
                ),
                SizedBox(
                  width: width * .9,
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLines: null,
                    maxLength: 200,
                    textAlign: TextAlign.center,
                    cursorColor: Colors.white,
                    style: TextStyle(
                        color: Colors.transparent,
                        fontSize: o.size * width,
                        fontFamily: o.font,
                        fontWeight: o.bold ? FontWeight.w800 : FontWeight.w500,
                        height: 1.15),
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: 'Enter text',
                      hintStyle: TextStyle(color: Colors.white38),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
            ),
          ),
          Container(
            color: studioPanelBg,
            height: 170,
            child: _TextStyleControls(overlay: o, onChanged: (fn) => setState(fn)),
          ),
        ]),
      ),
    );
  }
}

class _CentredPainter extends CustomPainter {
  _CentredPainter(this.layout);
  final OverlayLayout layout;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    layout.paint(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CentredPainter old) => true;
}

/// Crop with a draggable frame and ratio presets.
class _CropScreen extends StatefulWidget {
  const _CropScreen({required this.media, required this.aspect, this.initial});
  final Widget media;
  final double aspect;
  final List<double>? initial;
  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  late Rect r = widget.initial == null
      ? const Rect.fromLTWH(0, 0, 1, 1)
      : Rect.fromLTWH(widget.initial![0], widget.initial![1], widget.initial![2], widget.initial![3]);
  double? lock; // w/h in output pixels

  void _preset(double? ratio) {
    setState(() {
      lock = ratio;
      if (ratio == null) return;
      // Largest centred rect of that ratio.
      var w = 1.0, h = widget.aspect / ratio;
      if (h > 1) {
        w = ratio / widget.aspect;
        h = 1;
      }
      r = Rect.fromCenter(center: const Offset(.5, .5), width: w, height: h);
    });
  }

  void _drag(int corner, Offset delta, Size box) {
    final d = Offset(delta.dx / box.width, delta.dy / box.height);
    var l = r.left, t = r.top, rr = r.right, b = r.bottom;
    if (corner == 4) {
      final moved = r.shift(d);
      final dx = moved.left < 0 ? -moved.left : moved.right > 1 ? 1 - moved.right : 0.0;
      final dy = moved.top < 0 ? -moved.top : moved.bottom > 1 ? 1 - moved.bottom : 0.0;
      setState(() => r = moved.shift(Offset(dx, dy)));
      return;
    }
    if (corner == 0 || corner == 3) l += d.dx;
    if (corner == 1 || corner == 2) rr += d.dx;
    if (corner == 0 || corner == 1) t += d.dy;
    if (corner == 2 || corner == 3) b += d.dy;
    l = l.clamp(0.0, rr - .08);
    rr = rr.clamp(l + .08, 1.0);
    t = t.clamp(0.0, b - .08);
    b = b.clamp(t + .08, 1.0);
    var next = Rect.fromLTRB(l, t, rr, b);
    if (lock != null) {
      final h = next.width * widget.aspect / lock!;
      next = corner < 2
          ? Rect.fromLTRB(next.left, next.bottom - h, next.right, next.bottom)
          : Rect.fromLTWH(next.left, next.top, next.width, h);
      if (next.top < 0 || next.bottom > 1) return;
    }
    setState(() => r = next);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white)),
              const Spacer(),
              const Text('Crop', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              const Spacer(),
              IconButton(
                onPressed: () {
                  final full = r.left < .001 && r.top < .001 && r.right > .999 && r.bottom > .999;
                  Navigator.pop(context, full ? <double>[] : [r.left, r.top, r.width, r.height]);
                },
                icon: const Icon(Icons.check_rounded, color: Colors.white),
              ),
            ]),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: widget.aspect,
                    child: LayoutBuilder(builder: (context, box) {
                      final size = Size(box.maxWidth, box.maxHeight);
                      final rect = Rect.fromLTWH(r.left * size.width, r.top * size.height,
                          r.width * size.width, r.height * size.height);
                      return Stack(clipBehavior: Clip.none, children: [
                        Positioned.fill(child: FittedBox(fit: BoxFit.fill, child: widget.media)),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(painter: _CropShade(rect)),
                          ),
                        ),
                        Positioned.fromRect(
                          rect: rect,
                          child: GestureDetector(
                            onPanUpdate: (d) => _drag(4, d.delta, size),
                            child: Container(color: Colors.transparent),
                          ),
                        ),
                        for (var i = 0; i < 4; i++)
                          Positioned(
                            left: (i == 0 || i == 3 ? rect.left : rect.right) - 16,
                            top: (i < 2 ? rect.top : rect.bottom) - 16,
                            child: GestureDetector(
                              onPanUpdate: (d) => _drag(i, d.delta, size),
                              child: Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                ),
                              ),
                            ),
                          ),
                      ]);
                    }),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final (label, ratio) in const [
                    ('Free', null),
                    ('1:1', 1.0),
                    ('4:5', .8),
                    ('9:16', 9 / 16),
                    ('16:9', 16 / 9),
                    ('3:4', .75),
                    ('4:3', 4 / 3),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: lock == ratio,
                        onSelected: (_) => _preset(ratio),
                        selectedColor: studioViolet,
                        backgroundColor: const Color(0xFF1C2433),
                        labelStyle: TextStyle(color: lock == ratio ? Colors.white : Colors.white70),
                        side: BorderSide.none,
                      ),
                    ),
                  TextButton(
                    onPressed: () => setState(() {
                      lock = null;
                      r = const Rect.fromLTWH(0, 0, 1, 1);
                    }),
                    child: const Text('Reset', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ),
          ]),
        ),
      );
}

class _CropShade extends CustomPainter {
  _CropShade(this.rect);
  final Rect rect;
  @override
  void paint(Canvas canvas, Size size) {
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: .55));
    canvas.drawRect(rect, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white);
    final grid = Paint()..color = Colors.white.withValues(alpha: .35);
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3, y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }
  }

  @override
  bool shouldRepaint(_CropShade old) => old.rect != rect;
}


/// One tile of a film strip, cover-fitted (cover picker preview).
class _StripFrame extends CustomPainter {
  _StripFrame(this.strip, this.index);
  final ui.Image strip;
  final int index;
  @override
  void paint(Canvas canvas, Size size) {
    final tileW = strip.width / 12, tileH = strip.height.toDouble();
    final src = Rect.fromLTWH(index * tileW, 0, tileW, tileH);
    final scale = math.max(size.width / tileW, size.height / tileH);
    final w = tileW * scale, h = tileH * scale;
    canvas.drawImageRect(strip, src,
        Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h),
        Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_StripFrame old) => old.index != index || old.strip != strip;
}
