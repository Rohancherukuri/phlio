// Moments: 24-hour photos/videos (Instagram stories) and profile highlights.
//
//  * [momentRingsProvider] — who has a live moment (and whether you've seen
//    it). Every avatar with a profile id watches it and draws the Phlio
//    rim light when that person has something live ([MomentRingAvatar]).
//  * [momentFeedProvider] — the story rail: you, people you follow, then
//    suggestions.
//  * [MomentStoryViewer] — full-screen, auto-advancing player with progress
//    bars, tap / hold / swipe, replies (unless turned off) and owner tools.
//  * [MomentHighlightsRow] — highlight circles on a profile.

import '../media/smart_filter_editor.dart';
import '../media/smart_filters.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../design_system/widgets/phlio_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_player/video_player.dart';

import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../../design_system/widgets/phlio_fox.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../../features/rooms/data/datasources/messaging_api.dart';
import '../giphy/giphy_picker.dart';
import '../media/phlio_look_data.dart';
import '../media/phlio_look_view.dart';
import '../../features/social/presentation/widgets/moment_composer.dart' show openMomentComposer;
import 'moment_activity.dart';
import 'moment_meta.dart';
import '../content/mentions.dart' show MentionTextEditingController;
import 'stickers/sticker_responses.dart';
import '../media/story_fx_view.dart';
import 'package:flutter/services.dart';
import 'templates/template_media.dart';
import '../../features/profile/presentation/controllers/avatar_controller.dart' show MeAvatar;
import 'package:phlio/core/network/media_cache.dart';

// -- Data -------------------------------------------------------------------

/// `{user id or username: {unseen, fresh}}` for everyone with a live moment.
final momentRingsProvider = FutureProvider<Map<String, Map>>((ref) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  final refresh = Timer(const Duration(seconds: 60), ref.invalidateSelf);
  ref.onDispose(refresh.cancel);
  try {
    final data = (await getIt<ApiClient>().dio.get('/social/moments/active'))
        .data as Map;
    return {
      for (final entry in data.entries)
        entry.key.toString(): Map<String, dynamic>.from(entry.value as Map)
    };
  } catch (_) {
    return const {};
  }
});

/// Moments deleted in this session. Hidden everywhere straight away, even
/// before the rail / rings refetch (and from any list fetched just before).
final deletedMomentIds = <String>{};

final momentFeedProvider = FutureProvider.autoDispose<List<Map>>((ref) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  final groups = ((await getIt<ApiClient>().dio.get('/social/moments/feed')).data
          as List)
      .cast<Map>();
  return _withoutDeleted(groups);
});

List<Map> _withoutDeleted(List<Map> groups) {
  if (deletedMomentIds.isEmpty) return groups;
  return [
    for (final g in groups)
      if ((g['items'] as List? ?? const [])
          .any((m) => !deletedMomentIds.contains('${(m as Map)['id']}')))
        {
          ...g,
          'items': [
            for (final m in g['items'] as List)
              if (!deletedMomentIds.contains('${(m as Map)['id']}')) m
          ],
        }
  ];
}

final momentHighlightsProvider =
    FutureProvider.autoDispose.family<Map, String>((ref, user) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  return (await getIt<ApiClient>()
          .dio
          .get('/social/moments/highlights/${Uri.encodeComponent(user)}'))
      .data as Map;
});

void refreshMoments(WidgetRef ref) {
  ref.invalidate(momentRingsProvider);
  ref.invalidate(momentFeedProvider);
}

String _mid(Map item) => Uri.encodeComponent(item['id'].toString());

// -- Rim light ----------------------------------------------------------------

/// Phlio's take on the story ring: a violet → pink → peach rim with a soft
/// glow and a bright highlight that sweeps around it. Seen moments get a
/// quiet grey rim; a moment you just posted pulses brighter for a moment.
class RimLight extends StatefulWidget {
  const RimLight({
    required this.size,
    required this.child,
    this.unseen = true,
    this.fresh = false,
    super.key,
  });

  final double size;
  final bool unseen, fresh;
  final Widget child;

  /// Space the rim takes on each side; the child should be `size - 2 * inset`.
  static double insetFor(double size) => math.max(3.0, size * 0.075);

  @override
  State<RimLight> createState() => _RimLightState();
}

class _RimLightState extends State<RimLight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3600));

  @override
  void initState() {
    super.initState();
    if (widget.unseen || widget.fresh) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant RimLight old) {
    super.didUpdateWidget(old);
    final animate = widget.unseen || widget.fresh;
    if (animate && !_spin.isAnimating) _spin.repeat();
    if (!animate && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = RimLight.insetFor(widget.size);
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _RimPainter(
              _spin, widget.unseen || widget.fresh, widget.fresh),
          child: Padding(
            padding: EdgeInsets.all(inset),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter(this.spin, this.lit, this.fresh) : super(repaint: spin);
  final Animation<double> spin;
  final bool lit, fresh;

  static const _colors = [
    PhlioColors.brandViolet,
    PhlioColors.brandPink,
    PhlioColors.brandPeach,
    PhlioColors.brandViolet,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = math.max(2.0, size.width * 0.04);
    final radius = size.width / 2 - stroke / 2 - 0.5;
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (!lit) {
      canvas.drawCircle(
          center,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.2, stroke * 0.6)
            ..color = const Color(0xFF4A5263));
      return;
    }
    final turn = spin.value * 2 * math.pi;
    final gradient = SweepGradient(
        colors: _colors, transform: GradientRotation(turn));
    final pulse = fresh ? (0.6 + 0.4 * math.sin(spin.value * 2 * math.pi * 3)) : 0.55;
    // Outer glow ("rim light").
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 2.2
          ..shader = gradient.createShader(rect)
          ..color = Colors.white.withValues(alpha: pulse)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 1.4));
    // Crisp rim.
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..shader = gradient.createShader(rect));
    // Sweeping highlight.
    canvas.drawArc(
        rect,
        turn * 1.5 - math.pi / 2,
        math.pi / 3.2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke * 0.9
          ..color = Colors.white.withValues(alpha: 0.75)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.6));
  }

  @override
  bool shouldRepaint(covariant _RimPainter old) =>
      old.lit != lit || old.fresh != fresh;
}

/// Wraps an avatar with the rim light when [userId] has a live moment. Tap
/// opens their moments; long-press opens the profile. Without a live moment
/// it shows [plain] untouched, so layouts never shift.
class MomentRingAvatar extends ConsumerWidget {
  const MomentRingAvatar({
    required this.userId,
    required this.size,
    required this.plain,
    required this.ringed,
    this.onTapOverride,
    this.imageUrl,
    super.key,
  });

  /// Profile id/handle; may be empty when only the picture is known.
  final String userId;

  /// Avatar URL — also matches, so rings show wherever someone's photo does.
  final String? imageUrl;
  final double size;
  final Widget plain;
  final Widget Function(double innerSize) ringed;
  final VoidCallback? onTapOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rings = ref.watch(momentRingsProvider).valueOrNull;
    if (rings == null || rings.isEmpty) return plain;
    final state = (userId.isEmpty ? null : rings[userId]) ??
        (userId.isEmpty ? null : rings[userId.replaceFirst('@', '')]) ??
        (imageUrl == null || imageUrl!.isEmpty ? null : rings[imageUrl]);
    if (state == null) return plain;
    final owner = (state['user'] as String?) ?? userId;
    final inner = size - 2 * RimLight.insetFor(size);
    return Semantics(
      button: true,
      label: 'View moment',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTapOverride ?? () => openUserMoments(context, owner),
        onLongPress: () =>
            context.push('/creator/${Uri.encodeComponent(owner)}'),
        child: RimLight(
          size: size,
          unseen: state['unseen'] == true,
          fresh: state['fresh'] == true,
          child: ringed(inner),
        ),
      ),
    );
  }
}

// -- Opening the viewer -------------------------------------------------------

Future<void> openUserMoments(BuildContext context, String user) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final data = (await getIt<ApiClient>()
            .dio
            .get('/social/moments/user/${Uri.encodeComponent(user)}'))
        .data as Map;
    if ((data['items'] as List).isEmpty) {
      messenger?.showSnackBar(
          const SnackBar(content: Text('This moment has expired.')));
      return;
    }
    await navigator.push(_viewerRoute([data]));
  } catch (_) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Could not open this moment.')));
  }
}

/// Opens a list of `{author, items}` groups at [start] (story rail).
Future<void> openMomentGroups(BuildContext context, List<Map> groups,
        {int start = 0, bool highlight = false}) =>
    Navigator.of(context, rootNavigator: true)
        .push(_viewerRoute(groups, start: start, highlight: highlight));

Route<void> _viewerRoute(List<Map> groups,
        {int start = 0, bool highlight = false}) =>
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) =>
          MomentStoryViewer(groups: groups, start: start, highlight: highlight),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(CurvedAnimation(
                parent: animation, curve: Curves.easeOutCubic)),
            child: child),
      ),
    );

// -- Viewer -------------------------------------------------------------------

class MomentStoryViewer extends ConsumerStatefulWidget {
  const MomentStoryViewer(
      {required this.groups, this.start = 0, this.highlight = false, super.key});
  final List<Map> groups;
  final int start;

  /// Highlights don't mark moments as seen or show the 24-hour clock.
  final bool highlight;

  @override
  ConsumerState<MomentStoryViewer> createState() => _MomentStoryViewerState();
}

class _MomentStoryViewerState extends ConsumerState<MomentStoryViewer> {
  late final PageController _authors =
      PageController(initialPage: widget.start);
  ProviderContainer? _container;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container ??= ProviderScope.containerOf(context, listen: false);
  }
  late int _page = widget.start;
  double _drag = 0;

  void _next() {
    if (_page + 1 < widget.groups.length) {
      _authors.nextPage(
          duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _previous() {
    if (_page > 0) {
      _authors.previousPage(
          duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _authors.dispose();
    // Rings turn grey for what you just watched.
    _container?.invalidate(momentRingsProvider);
    _container?.invalidate(momentFeedProvider);
    super.dispose();
  }

  // Full screen: the moment runs edge to edge under the status bar; the
  // header and bottom bar float over it (Instagram / Bond layout).
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          onVerticalDragUpdate: (d) =>
              setState(() => _drag = math.max(0, _drag + d.delta.dy)),
          onVerticalDragEnd: (d) {
            if (_drag > 120 || (d.primaryVelocity ?? 0) > 900) {
              Navigator.of(context).maybePop();
            } else {
              setState(() => _drag = 0);
            }
          },
          child: Transform.translate(
            offset: Offset(0, _drag),
            child: Opacity(
              opacity: (1 - _drag / 600).clamp(0.4, 1.0),
              child: PageView.builder(
                controller: _authors,
                itemCount: widget.groups.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _AuthorMoments(
                  key: ValueKey('moment-author-$i'),
                  group: widget.groups[i],
                  active: i == _page,
                  highlight: widget.highlight,
                  onDone: _next,
                  onBack: _previous,
                ),
              ),
            ),
          ),
        ),
      ));
}

class _AuthorMoments extends ConsumerStatefulWidget {
  const _AuthorMoments({
    required this.group,
    required this.active,
    required this.highlight,
    required this.onDone,
    required this.onBack,
    super.key,
  });
  final Map group;
  final bool active, highlight;
  final VoidCallback onDone, onBack;

  @override
  ConsumerState<_AuthorMoments> createState() => _AuthorMomentsState();
}

class _AuthorMomentsState extends ConsumerState<_AuthorMoments>
    with SingleTickerProviderStateMixin {
  late final List<Map> items = [
    for (final raw in widget.group['items'] as List)
      if (!deletedMomentIds.contains('${(raw as Map)['id']}')) Map.from(raw)
  ];
  late int index = math.max(
      0,
      widget.highlight
          ? 0
          : items.indexWhere((m) => m['seen'] != true).clamp(0, items.length));
  late final AnimationController progress =
      AnimationController(vsync: this, duration: const Duration(seconds: 5))
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _forward();
        });
  VideoPlayerController? video;
  final reply = MentionTextEditingController();
  final replyFocus = FocusNode();
  bool paused = false, sending = false, recording = false;
  String? burst;
  final AudioPlayer _music = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _musicLine, _recordTicker;
  StreamSubscription<Duration>? _musicClip;
  int _recordSeconds = 0;

  /// Header subtitle alternates between the song and the reshare credit.
  bool _showReshare = false;

  Map get item => items[index.clamp(0, items.length - 1)];
  Map get author => widget.group['author'] as Map;
  bool get mine =>
      author['id'] == ref.read(authControllerProvider).valueOrNull?.id;

  @override
  void initState() {
    super.initState();
    if (index >= items.length) index = 0;
    replyFocus.addListener(() {
      if (replyFocus.hasFocus) {
        _pause();
      } else {
        // Keyboard dismissed (back button / swipe) with nothing typed.
        if (_replying && reply.text.trim().isEmpty && mounted) setState(() => _replying = false);
        _resume();
      }
    });
    if (widget.active) _show();
  }

  @override
  void didUpdateWidget(covariant _AuthorMoments old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _show();
    if (!widget.active && old.active) {
      progress.stop();
      video?.pause();
      _music.pause();
    }
  }

  @override
  void dispose() {
    progress.dispose();
    video?.dispose();
    reply.dispose();
    replyFocus.dispose();
    _musicLine?.cancel();
    _recordTicker?.cancel();
    _musicClip?.cancel();
    _music.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _show() async {
    progress
      ..stop()
      ..reset();
    final old = video;
    video = null;
    await old?.dispose();
    final current = item;
    await _music.stop();
    final song = current['music'];
    if (song is Map && current['media_kind'] != 'video' && song['url'] is String) {
      // The part chosen in the music editor (older moments: from 0:20).
      final start = (song['clip_start'] as num?)?.toDouble() ?? 20;
      final length = (song['clip_length'] as num?)?.toDouble() ?? 30;
      _musicClip?.cancel();
      _musicClip = _music.onPositionChanged.listen((p) {
        if (p.inMilliseconds / 1000 >= start + length) {
          _music.seek(Duration(milliseconds: (start * 1000).round()));
        }
      });
      unawaited(_music
          .play(UrlSource(AppConfig.mediaUrl(song['url'] as String)),
              position: Duration(milliseconds: (start * 1000).round()))
          .then((_) {
        if (paused || !widget.active) _music.pause();
      }, onError: (_) {}));
    }
    if (!widget.highlight && current['seen'] != true && !mine) {
      current['seen'] = true;
      unawaited(getIt<ApiClient>()
          .dio
          .put('/social/moments/${_mid(current)}/seen')
          .then((_) {}, onError: (_) {}));
    }
    if (current['media_kind'] == 'video') {
      final controller = VideoPlayerController.networkUrl(
          Uri.parse(AppConfig.mediaUrl(current['media_url'] as String)));
      video = controller;
      if (mounted) setState(() {});
      try {
        await controller.initialize();
        if (!mounted || video != controller) return;
        final length = controller.value.duration;
        progress.duration = length > Duration.zero
            ? (length > const Duration(seconds: 60)
                ? const Duration(seconds: 60)
                : length)
            : const Duration(seconds: 15);
        setState(() {});
        if (widget.active && !paused) {
          await controller.play();
          progress.forward();
        }
      } catch (_) {
        progress.duration = const Duration(seconds: 5);
        if (mounted && widget.active) progress.forward();
      }
    } else {
      progress.duration = const Duration(seconds: 5);
      if (mounted) setState(() {});
      if (widget.active && !paused) progress.forward();
    }
  }

  void _forward() {
    if (index + 1 < items.length) {
      setState(() => index++);
      _show();
    } else {
      widget.onDone();
    }
  }

  void _back() {
    if (index > 0) {
      setState(() => index--);
      _show();
    } else {
      widget.onBack();
    }
  }

  void _pause() {
    paused = true;
    progress.stop();
    video?.pause();
    _music.pause();
    if (mounted) setState(() {});
  }

  void _resume() {
    if (replyFocus.hasFocus || recording) return;
    paused = false;
    if (widget.active) {
      progress.forward();
      video?.play();
      if (item['music'] is Map && item['media_kind'] != 'video') _music.resume();
    }
    if (mounted) setState(() {});
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _send(String text,
      {List<Map<String, dynamic>> attachments = const []}) async {
    if ((text.trim().isEmpty && attachments.isEmpty) || sending) return;
    setState(() => sending = true);
    try {
      await ref.read(messagingApiProvider).send(
          author['username'] as String,
          text.trim().isEmpty
              ? 'Replied to your moment'
              : 'Replied to your moment: ${text.trim()}',
          attachments: attachments);
      reply.clear();
      replyFocus.unfocus();
      _say('Sent to ${author['display_name']}');
    } catch (_) {
      _say('Could not send. Try again.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _sendGif() async {
    _pause();
    final gif = await showGiphyPicker(context, kind: 'gif');
    if (gif != null) {
      await _send('', attachments: [
        {'kind': 'gif', 'name': gif.title, 'value': gif.reference}
      ]);
    }
    _resume();
  }

  Future<void> _sendPhoto() async {
    _pause();
    try {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 88);
      if (picked != null) {
        final uploaded = await ref
            .read(messagingApiProvider)
            .upload(author['username'] as String, [picked.path]);
        await _send('', attachments: uploaded);
      }
    } catch (_) {
      _say('Could not send the photo. Try again.');
    }
    _resume();
  }

  /// Hold the mic to record; release to send it straight to their DMs.
  Future<void> _startVoice() async {
    if (recording) return;
    try {
      if (!await _recorder.hasPermission()) {
        _say('Allow microphone access to send voice messages.');
        return;
      }
      _pause();
      final dir = Directory.systemTemp.path;
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: '$dir/moment_reply_${DateTime.now().millisecondsSinceEpoch}.m4a');
      setState(() {
        recording = true;
        _recordSeconds = 0;
      });
      _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
      });
    } catch (_) {
      _say('Microphone unavailable. Fully restart the app and try again.');
    }
  }

  Future<void> _stopVoice({bool cancel = false}) async {
    if (!recording) return;
    _recordTicker?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    final long = _recordSeconds >= 1;
    setState(() => recording = false);
    if (!cancel && long && path != null) {
      try {
        final uploaded = await ref
            .read(messagingApiProvider)
            .upload(author['username'] as String, [path]);
        await _send('', attachments: uploaded);
      } catch (_) {
        _say('Could not send the voice message.');
      }
    } else if (!cancel) {
      _say('Hold the mic to record a voice message.');
    }
    _resume();
  }

  /// Paper plane: send this moment to someone in DMs.
  Future<void> _shareMoment() async {
    _pause();
    final api = ref.read(messagingApiProvider);
    final people = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => SizedBox(
        height: MediaQuery.sizeOf(sheet).height * .6,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: api.destinations(),
          builder: (_, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Send to', style: PhlioTypography.title),
              ),
              for (final p in snapshot.data!)
                if (p['id'] != author['id'])
                  ListTile(
                    leading: PhlioAvatar(
                        name: p['display_name'] as String? ?? '',
                        imageUrl: p['avatar_url'] as String?,
                        size: 42,
                        showMomentRing: false),
                    title: Text(p['display_name'] as String? ?? ''),
                    subtitle: Text(p['recent'] == true
                        ? 'Recent chat'
                        : (p['relation'] ?? '@${p['username']}').toString()),
                    onTap: () => Navigator.pop(sheet, p),
                  ),
            ]);
          },
        ),
      ),
    );
    if (people != null) {
      try {
        await api.send(people['username'] as String,
            "Check out @${author['username']}'s moment on Phlio\nphlio://app/moments/${author['username']}");
        _say('Sent to ${people['display_name']}');
      } catch (_) {
        _say('Could not send. Try again.');
      }
    }
    _resume();
  }

  /// "About this story": the song, then Report / Mute (Instagram layout).
  Future<void> _about() async {
    if (mine) return _ownerMenu();
    _pause();
    final song = item['music'] is Map ? item['music'] as Map : null;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
                child: Text('About this moment',
                    style: PhlioTypography.headline.copyWith(fontSize: 22)),
              ),
              if (song != null) ...[
                _SheetCard(children: [
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: song['cover_url'] is String
                            ? CachedNetworkImage(cacheManager: PhlioMediaCache.images, 
                                imageUrl: AppConfig.mediaUrl(
                                    song['cover_url'] as String),
                                fit: BoxFit.cover)
                            : const ColoredBox(
                                color: PhlioColors.surfaceElevated,
                                child: Icon(Icons.music_note_rounded)),
                      ),
                    ),
                    title: Text('${song['title']} · ${song['artist']}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: const Text('Audio'),
                    onTap: () => Navigator.pop(sheet, 'song'),
                  ),
                ]),
                const SizedBox(height: 14),
              ],
              _SheetCard(children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                  leading: const Icon(Icons.report_gmailerrorred_rounded),
                  title: const Text('Report'),
                  onTap: () => Navigator.pop(sheet, 'report'),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                  leading: const Icon(Icons.notifications_off_outlined),
                  title: const Text('Mute'),
                  onTap: () => Navigator.pop(sheet, 'mute'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    final dio = getIt<ApiClient>().dio;
    try {
      if (action == 'song' && song?['path'] is String) {
        final router = GoRouter.of(context);
        Navigator.of(context).maybePop();
        router.push('/shared/${song!['path']}');
        return;
      } else if (action == 'report') {
        await dio.post('/social/moments/${_mid(item)}/report',
            data: {'reason': 'Inappropriate moment'});
        _say("Thanks for reporting. We'll take a look.");
      } else if (action == 'mute') {
        await dio.put(
            '/social/moments/mute/${Uri.encodeComponent(author['username'] as String)}',
            data: {'muted': true});
        refreshMoments(ref);
        _say("You won't see ${author['display_name']}'s moments in your rail.");
        widget.onDone();
        return;
      }
    } catch (_) {
      _say('Something went wrong. Try again.');
    }
    _resume();
  }

  /// React: saved on the moment (the author sees it in Viewers) and sent
  /// to their DMs. Tapping the same reaction again takes it back.
  Future<void> _react(String emoji) async {
    final current = item;
    final dio = getIt<ApiClient>().dio;
    if (current['my_reaction'] == emoji) {
      setState(() => current['my_reaction'] = null);
      try {
        await dio.delete('/social/moments/${_mid(current)}/reaction');
      } catch (_) {}
      return;
    }
    setState(() {
      burst = emoji;
      current['my_reaction'] = emoji;
    });
    try {
      await dio.put('/social/moments/${_mid(current)}/reaction', data: {'emoji': emoji});
    } catch (_) {}
    try {
      await ref.read(messagingApiProvider).send(
          author['username'] as String, '$emoji Reacted to your moment');
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => burst = null);
  }

  /// Viewers / Comments sheet is up (the moment shrinks to a card).
  bool _sheetOpen = false;

  /// People icon: who watched, with their reactions.
  Future<void> _openViewers() async {
    final current = item;
    _pause();
    setState(() => _sheetOpen = true);
    var thenComments = false;
    await showMomentViewers(context, current,
        onComments: () => thenComments = true,
        onCounts: (c) {
          if (!mounted) return;
          setState(() {
            current['view_count'] = c['views'];
            current['reaction_count'] = c['reactions'];
            current['comment_count'] = c['comments'];
          });
        });
    if (mounted) setState(() => _sheetOpen = false);
    if (thenComments && mounted) return _openComments();
    _resume();
  }

  /// Comments icon: the moment's comment thread.
  Future<void> _openComments() async {
    final current = item;
    _pause();
    setState(() => _sheetOpen = true);
    await showMomentComments(context, current, isAuthor: mine, owner: author['username'] as String?, onCount: (n) {
      if (mounted) setState(() => current['comment_count'] = n);
    });
    if (mounted) setState(() => _sheetOpen = false);
    _resume();
  }

  Future<void> _ownerMenu() async {
    _pause();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.favorite_border_rounded),
              title: const Text('Add to highlights'),
              onTap: () => Navigator.pop(sheet, 'highlight')),
          ListTile(
              leading: const Icon(Icons.remove_circle_outline_rounded),
              title: const Text('Remove from highlights'),
              onTap: () => Navigator.pop(sheet, 'unhighlight')),
          ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Viewers'),
              onTap: () => Navigator.pop(sheet, 'viewers')),
          ListTile(
              leading: const Icon(Icons.filter_vintage_outlined),
              title: const Text('Edit filters'),
              onTap: () => Navigator.pop(sheet, 'filters')),
          ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: PhlioColors.danger),
              title: const Text('Delete moment',
                  style: TextStyle(color: PhlioColors.danger)),
              onTap: () => Navigator.pop(sheet, 'delete')),
        ]),
      ),
    );
    final dio = getIt<ApiClient>().dio;
    try {
      if (action == 'highlight') {
        final title = await _askHighlightTitle();
        if (title != null) {
          await dio.post('/social/moments/${_mid(item)}/highlight',
              data: {'title': title});
          ref.invalidate(momentHighlightsProvider);
          _say('Added to "$title"');
        }
      } else if (action == 'unhighlight') {
        await dio.delete('/social/moments/${_mid(item)}/highlight');
        ref.invalidate(momentHighlightsProvider);
        _say('Removed from highlights');
      } else if (action == 'filters') {
        // Change the smart filters (and, for videos, the look) after posting.
        final current = FilterSpec.fromJson(item['filter_spec']) ??
            (() {
              final (look, effect) = splitMomentFilter(item['filter'] as String?);
              return FilterSpec(look: look, effect: effect == 'none' ? null : effect);
            })();
        final edited = await openSmartFilterEditor(context,
            media: _MomentMedia(item: {...item, 'filter_spec': null}, video: null), initial: current);
        if (edited != null) {
          final res = await dio.put('/social/filters/moments/${_mid(item)}', data: {'spec': edited.toJson()});
          final data = res.data as Map;
          setState(() {
            item['filter'] = data['filter'];
            item['filter_spec'] = data['filter_spec'];
          });
          refreshMoments(ref);
          _say('Filters updated');
        }
      } else if (action == 'viewers') {
        await _openViewers();
      } else if (action == 'delete') {
        final id = '${item['id']}';
        await dio.delete('/social/moments/${_mid(item)}');
        deletedMomentIds.add(id);
        // The viewer's own copy of this author's moments (swiping back to
        // them rebuilds from it).
        try {
          (widget.group['items'] as List).removeWhere((m) => '${(m as Map)['id']}' == id);
        } catch (_) {}
        refreshMoments(ref);
        ref.invalidate(momentHighlightsProvider);
        _say('Moment deleted');
        setState(() => items.removeAt(index));
        if (items.isEmpty) {
          widget.onDone();
          return;
        }
        index = index.clamp(0, items.length - 1);
        await _show();
        return;
      }
    } catch (_) {
      _say('Something went wrong. Try again.');
    }
    _resume();
  }

  Future<String?> _askHighlightTitle() {
    final controller = TextEditingController(text: 'Highlights');
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add to highlight'),
        content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            decoration: const InputDecoration(hintText: 'Highlight name')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  c,
                  controller.text.trim().isEmpty
                      ? 'Highlights'
                      : controller.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
  }

  /// Hold-to-record mic (voice reply to their DMs).
  Widget _micButton() => Tooltip(
        message: 'Hold to record a voice message',
        child: GestureDetector(
          onTap: () => _say('Hold the mic to record a voice message.'),
          onLongPressStart: (_) => _startVoice(),
          onLongPressEnd: (_) => _stopVoice(),
          onLongPressCancel: () => _stopVoice(cancel: true),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: recording ? 42 : 36,
            height: recording ? 42 : 36,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: recording ? PhlioColors.danger : Colors.transparent),
            child: const Icon(Icons.mic_none_rounded, color: Colors.white, size: 22),
          ),
        ),
      );

  /// Reply mode: the keyboard is up, the moment dims and the big
  /// reactions show (Instagram). Swipe down or tap the moment to leave.
  bool _replying = false;
  double _lastKeyboard = 0;

  void _startReply() {
    setState(() => _replying = true);
    // Focus after the field exists, then ask for the keyboard explicitly —
    // Android doesn't always raise it for a field that was just built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      replyFocus.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  void _endReply() {
    replyFocus.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (mounted) setState(() => _replying = false);
  }

  /// Someone else's moment, Instagram layout: a "Send message" pill, then
  /// like · comments · send on the right, all on one centre line. Tapping
  /// the pill enters reply mode: the pill takes the full width, the
  /// keyboard comes up, and photo / GIF / mic and Send appear inside it.
  Widget _viewerBar(Map current, bool allowComments, int comments) {
    final hasText = reply.text.trim().isNotEmpty;
    final liked = current['my_reaction'] == '❤️';
    const radius = BorderRadius.all(Radius.circular(26));
    BoxDecoration pillBox(double border) => BoxDecoration(
          color: const Color(0x14FFFFFF),
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: .55), width: border),
        );
    Widget frosted(Widget child) => ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: child),
        );

    if (!allowComments) {
      return Row(children: [
        Expanded(
          child: frosted(Container(
            height: 48,
            alignment: Alignment.center,
            decoration: pillBox(1),
            child: Text('Replies are turned off',
                style: PhlioTypography.body.copyWith(color: Colors.white60, fontSize: 15)),
          )),
        ),
        const SizedBox(width: _BarIcon.pillGap),
        ..._actions(current, liked, comments, allowComments: false),
      ]);
    }

    if (!_replying) {
      return Row(children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _startReply,
            child: frosted(Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.centerLeft,
              decoration: pillBox(1.1),
              child: const Text('Send message',
                  style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w500)),
            )),
          ),
        ),
        const SizedBox(width: _BarIcon.pillGap),
        ..._actions(current, liked, comments),
      ]);
    }

    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 150) _endReply();
      },
      child: frosted(Container(
        height: 50,
        padding: EdgeInsets.only(left: 20, right: hasText ? 5 : 8),
        decoration: pillBox(1.2),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: reply,
              focusNode: replyFocus,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white, fontSize: 15.5),
              textInputAction: TextInputAction.send,
              onSubmitted: (text) async {
                await _send(text);
                if (mounted) _endReply();
              },
              cursorColor: Colors.white,
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                fillColor: Colors.transparent,
                hintText: 'Send message',
                hintStyle: TextStyle(color: Colors.white70, fontSize: 15.5),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (hasText)
            TextButton(
              onPressed: sending
                  ? null
                  : () async {
                      await _send(reply.text);
                      if (mounted) _endReply();
                    },
              style: TextButton.styleFrom(foregroundColor: PhlioColors.brandPeach),
              child: sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
            )
          else ...[
            _PillIcon(tooltip: 'Send a photo', icon: Icons.image_outlined, onTap: _sendPhoto),
            _PillIcon(tooltip: 'Send a GIF', icon: Icons.gif_box_outlined, onTap: _sendGif),
            _micButton(),
          ],
        ]),
      )),
    );
  }

  /// like · comments · send — fixed 44 px slots, vertically centred on the
  /// pill, the last one flush with the right gutter.
  List<Widget> _actions(Map current, bool liked, int comments, {bool allowComments = true}) => [
        _BarIcon(
          tooltip: liked ? 'Unlike' : 'Like',
          onTap: () => _react('❤️'),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
            child: liked
                ? const Icon(Icons.favorite_rounded, key: ValueKey('liked'), color: Color(0xFFFF3B5C), size: _BarIcon.glyph)
                : const Icon(Icons.favorite_border_rounded,
                    key: ValueKey('like'), color: Colors.white, size: _BarIcon.glyph, shadows: _iconShadow),
          ),
        ),
        if (allowComments)
          _BarIcon(
            tooltip: 'Comments',
            onTap: _openComments,
            badge: comments,
            child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: _BarIcon.glyph - 1, shadows: _iconShadow),
          ),
        _BarIcon(
          tooltip: 'Send to someone',
          onTap: _shareMoment,
          // The plane's ink sits a touch high in its box; nudge it to the line.
          child: Transform.translate(
              offset: const Offset(0, 1), child: const PhlioSendIcon(color: Colors.white, size: _BarIcon.glyph - 1)),
        ),
      ];

  static const _iconShadow = [Shadow(color: Color(0x73000000), blurRadius: 10)];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final current = item;
    final created = DateTime.tryParse(current['created_at'] as String? ?? '');
    final allowComments = current['allow_comments'] != false;
    final insets = MediaQuery.paddingOf(context);
    // Read straight from the window, so no ancestor can hide the keyboard height.
    // (MediaQuery.viewInsetsOf also subscribes this build to keyboard changes.)
    final keyboard = math.max(
        MediaQuery.viewInsetsOf(context).bottom, MediaQueryData.fromView(View.of(context)).viewInsets.bottom);
    // Keyboard closed with the back button: leave reply mode too.
    if (_replying && _lastKeyboard > 0 && keyboard == 0 && reply.text.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _replying) _endReply();
      });
    }
    _lastKeyboard = keyboard;
    final barSpace = (mine ? 92.0 : 76.0) + insets.bottom;
    final comments = (current['comment_count'] as num?)?.toInt() ?? 0;
    // While Viewers / Comments is open the moment shrinks into a card at
    // the top (Bond style), so you still see what people are reacting to.
    return AnimatedScale(
      scale: _sheetOpen ? .4 : 1,
      alignment: Alignment(0, -1 + (insets.top + 24) / MediaQuery.sizeOf(context).height * 2),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_sheetOpen ? 34 : 0),
        child: Stack(fit: StackFit.expand, children: [
              _framedMediaFor(current, video),
              for (final layer in (current['overlays'] as List? ?? const []))
                if (current['media_kind'] == 'video')
                  _OverlayView(layer: Map.from(layer as Map)),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 130 + insets.top,
                child: const DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black54, Colors.transparent]))),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: barSpace + 90,
                child: const IgnorePointer(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black54, Colors.transparent]))),
                ),
              ),
              // Tap zones: left = back, right = forward, hold = pause.
              Row(children: [
                Expanded(
                    child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _back,
                        onLongPressStart: (_) => _pause(),
                        onLongPressEnd: (_) => _resume())),
                Expanded(
                    flex: 2,
                    child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _forward,
                        onLongPressStart: (_) => _pause(),
                        onLongPressEnd: (_) => _resume())),
              ]),
              // Live stickers (poll, slider, question, countdown, like, add
              // yours, link…) sit above the tap zones so they can be used.
              Positioned.fill(
                child: MomentStickersOverlay(
                  key: ValueKey('stickers-${current['id']}'),
                  item: current,
                  isAuthor: mine,
                  onPause: _pause,
                  onResume: _resume,
                  onAnswer: (prompt, answer) => _send('Answered “$prompt”: $answer'),
                  onAddYours: (prompt) {
                    _pause();
                    openMomentComposer(context, addYoursPrompt: prompt).then((_) => _resume());
                  },
                ),
              ),
              Positioned(
                left: 8,
                right: 4,
                top: insets.top + 6,
                child: Column(children: [
                  Row(children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: AnimatedBuilder(
                              animation: progress,
                              builder: (_, __) => LinearProgressIndicator(
                                minHeight: 2.4,
                                value: i < index
                                    ? 1
                                    : i == index
                                        ? progress.value
                                        : 0,
                                backgroundColor: Colors.white30,
                                valueColor: const AlwaysStoppedAnimation(
                                    Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    GestureDetector(
                      onTap: () {
                        final router = GoRouter.of(context);
                        Navigator.of(context).maybePop();
                        router.push(
                            '/creator/${Uri.encodeComponent(author['username'] as String? ?? author['id'] as String)}');
                      },
                      // Your own moments use your current profile photo
                      // (it may be newer than the copy stored with the
                      // moment); others use theirs. Instagram-style: a
                      // small round photo with a hairline ring.
                      child: Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: .8),
                        ),
                        child: mine
                            ? MeAvatar(
                                name: author['display_name'] as String? ?? '',
                                size: 34)
                            : PhlioAvatar(
                                name: author['display_name'] as String? ?? '',
                                imageUrl: author['avatar_url'] as String?,
                                size: 34,
                                showMomentRing: false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: [
                            Flexible(
                              child: Text(
                                  mine
                                      ? 'Your moment'
                                      : author['username'] as String? ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: PhlioTypography.bodyStrong.copyWith(
                                      color: Colors.white, fontSize: 15)),
                            ),
                            const SizedBox(width: 8),
                            if (created != null)
                              Text(timeago.format(created, locale: 'en_short'),
                                  style: PhlioTypography.body.copyWith(
                                      color: Colors.white70, fontSize: 14)),
                            if (current['ai_label'] == true) ...[
                              const SizedBox(width: 8),
                              const _Chip('AI info'),
                            ],
                          ]),
                          // Song · reshared from · mentions · effect · filter,
                          // a new one every 3 seconds (Instagram).
                          RotatingMeta(
                            key: ValueKey('meta-${current['id']}'),
                            paused: replyFocus.hasFocus || recording,
                            lines: momentMetaLines(
                              current,
                              playing: !paused,
                              onSong: _about,
                              onProfile: (username) {
                                final router = GoRouter.of(context);
                                Navigator.of(context).maybePop();
                                router.push('/creator/${Uri.encodeComponent(username)}');
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (paused && !recording)
                      const Padding(
                        padding: EdgeInsets.only(right: 2),
                        child: Icon(Icons.pause_rounded,
                            color: Colors.white70, size: 20),
                      ),
                    IconButton(
                        tooltip: 'About this moment',
                        onPressed: _about,
                        icon: const Icon(Icons.drag_handle_rounded,
                            color: Colors.white, size: 30)),
                  ]),
                ]),
              ),
              if ((current['caption'] as String? ?? '').isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: barSpace + 14,
                  child: Text(current['caption'] as String,
                      textAlign: TextAlign.center,
                      style: PhlioTypography.bodyLarge.copyWith(
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Colors.black87, blurRadius: 10)
                          ])),
                ),
              if (burst != null)
                Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: .4, end: 1.4),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.elasticOut,
                    builder: (_, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: Text(burst!, style: const TextStyle(fontSize: 96)),
                  ),
                ),
              if (recording)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: barSpace + 24,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(24)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.fiber_manual_record,
                            color: PhlioColors.danger, size: 14),
                        const SizedBox(width: 8),
                        Text(
                            '${_recordSeconds ~/ 60}:${(_recordSeconds % 60).toString().padLeft(2, '0')}  ·  Release to send',
                            style: const TextStyle(color: Colors.white)),
                      ]),
                    ),
                  ),
                ),
              // Reply mode: dim the moment, big reactions (Instagram 3 × 2).
              // Tap or swipe down to drop the keyboard and the reactions.
              if (!mine && _replying)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _endReply,
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) > 150) _endReply();
                    },
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      builder: (_, t, child) => ColoredBox(
                        color: Colors.black.withValues(alpha: .55 * t),
                        child: Opacity(opacity: t, child: Transform.scale(scale: .9 + .1 * t, child: child)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(bottom: keyboard + 80, top: insets.top + 80),
                        child: Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 34,
                            runSpacing: 28,
                            children: [
                              for (final e in const ['😂', '😮', '😍', '😢', '👏', '🔥'])
                                SizedBox(
                                  width: 76,
                                  child: GestureDetector(
                                    onTap: () {
                                      _endReply();
                                      _react(e);
                                    },
                                    child: Text(e, textAlign: TextAlign.center, style: const TextStyle(fontSize: 58)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        Positioned(
          left: 0,
          right: 0,
          bottom: keyboard > 0 ? keyboard : insets.bottom,
          child: Padding(
          padding: EdgeInsets.fromLTRB(12, 8, mine ? 8 : _BarIcon.rightPad, 10),
          child: mine
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  // Bond-style: ︿, then viewers and comments in the middle.
                  GestureDetector(
                    onTap: _openViewers,
                    child: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 26),
                  ),
                  Row(children: [
                    const SizedBox(width: 56),
                    Expanded(
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        _CountButton(
                          tooltip: 'Viewers',
                          icon: Icons.people_alt_outlined,
                          count: (current['view_count'] as num?)?.toInt() ?? 0,
                          badge: ((current['reaction_count'] as num?)?.toInt() ?? 0) > 0 ? '❤️' : null,
                          onTap: _openViewers,
                        ),
                        const SizedBox(width: 26),
                        _CountButton(
                          tooltip: 'Comments',
                          icon: Icons.chat_bubble_outline_rounded,
                          count: comments,
                          onTap: _openComments,
                        ),
                      ]),
                    ),
                    IconButton(
                        tooltip: widget.highlight ? 'Highlight options' : 'More',
                        onPressed: _ownerMenu,
                        icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 28)),
                  ]),
                ])
              : _viewerBar(current, allowComments, comments),
        ),
        ),
      ]),
      ),
    );
  }
}

/// One of the right-hand actions on someone's moment: a fixed 44 px slot,
/// so like / comment / send line up at the right edge.
class _BarIcon extends StatelessWidget {
  const _BarIcon({required this.child, required this.onTap, required this.tooltip, this.badge = 0});
  final Widget child;
  final VoidCallback onTap;
  final String tooltip;
  final int badge;

  /// Every action is a [slot] × [height] box with its glyph centred, the
  /// same height as the "Send message" pill, so all of them share one centre
  /// line. Glyph-to-glyph spacing is slot − glyph (18 px); [pillGap] gives
  /// the same 18 px between the pill and the first glyph, and [rightPad]
  /// leaves 12 px after the last glyph — the same as the left gutter.
  static const double slot = 44, height = 48, glyph = 26;
  static const double pillGap = 18 - (slot - glyph) / 2;
  static const double rightPad = 12 - (slot - glyph) / 2;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            width: slot,
            height: height,
            child: Center(
              child: SizedBox.square(
                dimension: glyph,
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                  child,
                  if (badge > 0)
                    // Pinned to the glyph's corner, so it never shifts the icon.
                    Positioned(
                      right: -9,
                      top: -7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B5C),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: Colors.black, width: 1.2),
                        ),
                        child: Text(badge > 99 ? '99+' : '$badge',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 9.5, height: 1.2, fontWeight: FontWeight.w800)),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Icon with a count beside it (viewers, comments).
class _CountButton extends StatelessWidget {
  const _CountButton({
    required this.icon,
    required this.count,
    required this.onTap,
    required this.tooltip,
    this.badge,
    this.compact = false,
  });
  final IconData icon;
  final int count;
  final VoidCallback onTap;
  final String tooltip;
  final String? badge;
  final bool compact;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 30,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Stack(clipBehavior: Clip.none, children: [
                Icon(icon, color: Colors.white, size: compact ? 27 : 30),
                if (badge != null)
                  Positioned(right: -6, bottom: -4, child: Text(badge!, style: const TextStyle(fontSize: 12))),
              ]),
              if (count > 0 || !compact) ...[
                const SizedBox(width: 6),
                Text('$count',
                    style: TextStyle(
                        color: Colors.white, fontSize: compact ? 15 : 22, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
        ),
      );
}

class _PillIcon extends StatelessWidget {
  const _PillIcon(
      {required this.tooltip, required this.icon, required this.onTap});
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 24),
      );
}

class _SheetCard extends StatelessWidget {
  const _SheetCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: const Color(0xFF2A2E36),
            borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );
}

/// Little animated equalizer next to the song name.
class _EqualizerBars extends StatefulWidget {
  const _EqualizerBars({required this.playing});
  final bool playing;
  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void didUpdateWidget(covariant _EqualizerBars old) {
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
                height: 5 +
                    7 *
                        (0.5 +
                            0.5 *
                                math.sin(_beat.value * 2 * math.pi + i * 1.7)),
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2)),
              ),
          ],
        ),
      );
}

/// The moment's photo / video; a video made with a template plays inside
/// the template's frame, under its overlay (templates/template_media.dart).
Widget _framedMediaFor(Map item, VideoPlayerController? video) {
  final media = _MomentMedia(item: item, video: video);
  final frame = item['media_kind'] == 'video' ? templateFrameOf(item['overlays'] as List?) : null;
  if (frame == null) return media;
  final (url, slot) = frame;
  return TemplateVideoFrame(
    slot: slot,
    overlay: CachedNetworkImageProvider(cacheManager: PhlioMediaCache.images, AppConfig.mediaUrl(url)),
    media: SizedBox(width: slot.size.width * 3, height: slot.size.height * 3, child: media),
  );
}

class _MomentMedia extends StatelessWidget {
  const _MomentMedia({required this.item, required this.video});
  final Map item;
  final VideoPlayerController? video;

  @override
  Widget build(BuildContext context) {
    final (look, effect) = splitMomentFilter(item['filter'] as String?);
    Widget child;
    if (item['media_kind'] == 'video') {
      final controller = video;
      final cover = item['cover_url'] as String?;
      child = controller != null && controller.value.isInitialized
          ? FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller)))
          : Stack(fit: StackFit.expand, children: [
              if (cover != null)
                CachedNetworkImage(cacheManager: PhlioMediaCache.images, 
                    imageUrl: AppConfig.mediaUrl(cover), fit: BoxFit.cover),
              const Center(child: CircularProgressIndicator()),
            ]);
    } else {
      child = CachedNetworkImage(cacheManager: PhlioMediaCache.images, 
        imageUrl: AppConfig.mediaUrl(item['media_url'] as String),
        fit: BoxFit.cover,
        placeholder: (_, __) =>
            const Center(child: CircularProgressIndicator()),
        errorWidget: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image_outlined,
                color: Colors.white38, size: 48)),
      );
    }
    // Smart filters (time, weather, place…), adjustments and story effects
    // are stored as data and drawn live.
    final smart = FilterSpec.fromJson(item['filter_spec']);
    Widget looked = PhlioLook(look: look, effect: effect, child: child);
    if (smart != null && (smart.fx != null || smart.adjust.isNotEmpty)) {
      looked = StoryFxLayer(
          fx: smart.fx,
          amount: smart.fxAmount,
          adjust: smart.adjust,
          stamp: DateTime.tryParse('${item['created_at']}')?.toLocal(),
          child: looked);
    }
    if (smart == null || smart.overlays.isEmpty) return looked;
    return Stack(fit: StackFit.expand, children: [looked, SmartFilterLayer(spec: smart)]);
  }
}

/// Text / mention / sticker layers stored with video moments.
class _OverlayView extends StatelessWidget {
  const _OverlayView({required this.layer});
  final Map layer;
  @override
  Widget build(BuildContext context) {
    final x = (layer['x'] as num? ?? .5).toDouble();
    final y = (layer['y'] as num? ?? .5).toDouble();
    final text = layer['text'] as String? ?? '';
    final alignment = Alignment(x * 2 - 1, y * 2 - 1);
    if (layer['type'] == 'sticker' && layer['sticker'] is String) {
      return Align(
        alignment: alignment,
        child: PhlioStickerView(
            stickerId: layer['sticker'] as String,
            size: 110 * ((layer['size'] as num? ?? 26) / 26),
            interactive: false),
      );
    }
    if (text.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: alignment,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: layer['style'] == 'pill' || layer['type'] == 'mention'
              ? Colors.black.withValues(alpha: .45)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _hex(layer['color'] as String?) ?? Colors.white,
                fontSize: (layer['size'] as num? ?? 24).toDouble(),
                fontWeight: FontWeight.w700,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 6)])),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.white24, borderRadius: BorderRadius.circular(10)),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 11)),
      );
}

Color? _hex(String? value) {
  if (value == null || !value.startsWith('#') || value.length != 7) return null;
  final parsed = int.tryParse(value.substring(1), radix: 16);
  return parsed == null ? null : Color(0xFF000000 | parsed);
}

/// Looks shared by the composer (Restyle / Effects) and the viewer: GPU
/// shader grades (see shared/media/phlio_look_data.dart). The matrices
/// below are kept for old moments' names and non-shader fallbacks.
final momentFilters = phlioLookNames.keys.toList();

ColorFilter? momentFilter(String? name) => switch (name) {
      'warm' => const ColorFilter.matrix([
          1.1, 0, 0, 0, 12, //
          0, 1.0, 0, 0, 4,
          0, 0, 0.88, 0, -6,
          0, 0, 0, 1, 0,
        ]),
      'cool' => const ColorFilter.matrix([
          0.9, 0, 0, 0, -4, //
          0, 1.0, 0, 0, 2,
          0, 0, 1.12, 0, 12,
          0, 0, 0, 1, 0,
        ]),
      'mono' => const ColorFilter.matrix([
          0.33, 0.59, 0.11, 0, 0, //
          0.33, 0.59, 0.11, 0, 0,
          0.33, 0.59, 0.11, 0, 0,
          0, 0, 0, 1, 0,
        ]),
      'vivid' => const ColorFilter.matrix([
          1.25, -0.1, -0.1, 0, -6, //
          -0.1, 1.25, -0.1, 0, -6,
          -0.1, -0.1, 1.25, 0, -6,
          0, 0, 0, 1, 0,
        ]),
      'fade' => const ColorFilter.matrix([
          0.85, 0, 0, 0, 24, //
          0, 0.85, 0, 0, 24,
          0, 0, 0.85, 0, 26,
          0, 0, 0, 1, 0,
        ]),
      _ => null,
    };

// -- Highlights row -------------------------------------------------------------

/// Highlight circles under a profile. [onNew] adds the leading "New" circle
/// (your own profile only).
class MomentHighlightsRow extends ConsumerWidget {
  const MomentHighlightsRow({required this.user, this.onNew, super.key});
  final String user;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(momentHighlightsProvider(user)).valueOrNull;
    final highlights = (data?['highlights'] as List? ?? const []).cast<Map>();
    if (highlights.isEmpty && onNew == null) return const SizedBox.shrink();
    final author = data?['author'] as Map?;
    return SizedBox(
      height: 98,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (onNew != null)
            _HighlightCircle(
              label: 'New',
              onTap: onNew!,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: PhlioColors.border, width: 1.5),
                ),
                child: const Icon(Icons.add_rounded,
                    color: PhlioColors.textSecondary),
              ),
            ),
          for (var i = 0; i < highlights.length; i++)
            _HighlightCircle(
              label: highlights[i]['title'] as String? ?? '',
              onTap: () => openMomentGroups(
                context,
                [
                  for (final h in highlights)
                    {'author': author ?? const {}, 'items': h['items']}
                ],
                start: i,
                highlight: true,
              ),
              child: ClipOval(
                child: CachedNetworkImage(cacheManager: PhlioMediaCache.images, 
                  imageUrl: AppConfig.mediaUrl(
                      highlights[i]['cover_url'] as String? ?? ''),
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: PhlioColors.surfaceElevated,
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: PhlioColors.brandPeach),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HighlightCircle extends StatelessWidget {
  const _HighlightCircle(
      {required this.label, required this.child, required this.onTap});
  final String label;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 14),
          child: SizedBox(
            width: 68,
            child: Column(children: [
              Container(
                width: 66,
                height: 66,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: PhlioColors.border.withValues(alpha: .9),
                      width: 1.2),
                ),
                child: SizedBox.expand(child: child),
              ),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PhlioTypography.caption),
            ]),
          ),
        ),
      );
}
