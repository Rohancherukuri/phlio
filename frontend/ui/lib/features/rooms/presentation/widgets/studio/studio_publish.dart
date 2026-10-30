// Export progress + "Ready to share" for Phlio Studio.
//
// Export: uploads (done by the editor's prepare callback), then a server
// render job polled for progress, then the file is downloaded.
// Publish: send it in this chat, send to other chats, share as a moment or
// an experience, save to the gallery, or hand it to another app.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../../../core/di/service_locator.dart';
import '../../../../../core/network/api_client.dart';
import '../../../../../design_system/colors.dart';
import '../../../../../design_system/widgets/phlio_card.dart';
import '../../../../profile/presentation/widgets/snap_audience.dart';
import '../../../../social/presentation/widgets/moment_composer.dart';
import '../../../data/datasources/messaging_api.dart';
import '../chat_composer.dart';

const _violet = PhlioColors.brandViolet;

String _err(Object e) {
  if (e is DioException && e.response?.data is Map) {
    final d = e.response!.data as Map;
    if (d['detail'] is String) return d['detail'] as String;
  }
  if (e is FormatException) return e.message;
  return 'Something went wrong. Try again.';
}

// =============================================================================
// Export progress

class StudioExportScreen extends StatefulWidget {
  const StudioExportScreen({
    required this.peer,
    required this.prepare,
    required this.dio,
    super.key,
  });
  final String peer;
  final Future<Map<String, dynamic>> Function(void Function(double, String) report) prepare;
  final Dio dio;
  @override
  State<StudioExportScreen> createState() => _StudioExportScreenState();
}

class _StudioExportScreenState extends State<StudioExportScreen> with SingleTickerProviderStateMixin {
  late final _messaging = MessagingApi(widget.dio);
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  double _progress = 0, _shown = 0;
  String _stage = 'Getting ready';
  String? _error;
  bool _cancelled = false;
  Timer? _ease;

  @override
  void initState() {
    super.initState();
    // Smooth the bar between server updates.
    _ease = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!mounted) return;
      final next = _shown + (_progress - _shown) * .12;
      if ((next - _shown).abs() > .0005) setState(() => _shown = next);
    });
    _run();
  }

  @override
  void dispose() {
    _cancelled = true;
    _ease?.cancel();
    _spin.dispose();
    super.dispose();
  }

  void _report(double p, String stage) {
    if (!mounted) return;
    setState(() {
      _progress = math.max(_progress, p);
      _stage = stage;
    });
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _progress = 0;
      _shown = 0;
    });
    try {
      final plan = await widget.prepare(_report);
      if (_cancelled) return;
      final job = (await widget.dio.post('${_messaging.peerPath(widget.peer)}/studio/jobs', data: plan))
          .data as Map;
      final id = job['id'] as String;
      Map status = job;
      while (!_cancelled) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
        status = (await widget.dio.get('${_messaging.peerPath(widget.peer)}/studio/jobs/$id')).data as Map;
        final p = (status['progress'] as num?)?.toDouble() ?? 0;
        _report(.3 + p * .65, status['stage'] as String? ?? 'Rendering');
        if (status['status'] == 'done' || status['status'] == 'failed') break;
      }
      if (_cancelled) return;
      if (status['status'] == 'failed') {
        throw FormatException(status['error'] as String? ?? 'Could not render this project.');
      }
      final result = status['result'] as Map;
      _report(.96, 'Downloading your edit');
      final cached = await _messaging.localFile(result['url'] as String);
      final dir = await Directory.systemTemp.createTemp('phlio_studio_');
      final out = await File(cached).copy('${dir.path}/phlio_${DateTime.now().millisecondsSinceEpoch}'
          '${(result['name'] as String).substring((result['name'] as String).lastIndexOf('.'))}');
      _report(1, 'Done');
      HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      Navigator.of(context).pop(StagedAttachment(
        kind: result['kind'] as String,
        name: out.path.split(Platform.pathSeparator).last,
        path: out.path,
        size: await out.length(),
      ));
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_shown * 100).clamp(0, 100).round();
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: .86),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 168,
                height: 168,
                child: AnimatedBuilder(
                  animation: _spin,
                  builder: (_, __) => CustomPaint(
                    painter: _RingPainter(_error != null ? 0 : _shown, _spin.value, _error != null),
                    child: Center(
                      child: _error != null
                          ? const Icon(Icons.error_outline_rounded, color: PhlioColors.danger, size: 48)
                          : Text('$pct%',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                  fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Text(_error ?? _stage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _error != null ? Colors.white : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                  _error != null
                      ? 'Your project is still here.'
                      : 'Keep Phlio open while we put it together.',
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 26),
              if (_error != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to edit', style: TextStyle(color: Colors.white70))),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _violet, shape: const StadiumBorder()),
                    onPressed: _run,
                    child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ])
              else
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white60))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.spin, this.error);
  final double value, spin;
  final bool error;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = Colors.white10);
    if (error) return;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
        rect,
        -math.pi / 2,
        math.max(.02, value) * 2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            transform: GradientRotation(-math.pi / 2),
            colors: const [Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFFFB58F), Color(0xFF8D78FF)],
          ).createShader(rect));
    // A soft comet orbiting while it works.
    final a = spin * 2 * math.pi;
    canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * (r + 16), 3,
        Paint()..color = Colors.white.withValues(alpha: .5));
  }

  @override
  bool shouldRepaint(_RingPainter old) => true;
}

// =============================================================================
// Publish

class StudioPublishScreen extends StatefulWidget {
  const StudioPublishScreen({required this.peer, required this.attachment, required this.onSend, super.key});
  final String peer;
  final StagedAttachment attachment;
  final Future<void> Function(StagedAttachment) onSend;
  @override
  State<StudioPublishScreen> createState() => _StudioPublishScreenState();
}

class _StudioPublishScreenState extends State<StudioPublishScreen> {
  final _dio = getIt<ApiClient>().dio;
  late final _messaging = MessagingApi(_dio);
  VideoPlayerController? _player;
  final Set<String> _done = {};
  String? _busy;

  StagedAttachment get a => widget.attachment;
  bool get _video => a.kind == 'video';

  @override
  void initState() {
    super.initState();
    if (_video) {
      _player = VideoPlayerController.file(File(a.path!))
        ..setLooping(true)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _player!.play();
          }
        });
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _work(String key, Future<void> Function() action, String success) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    HapticFeedback.selectionClick();
    try {
      await _player?.pause();
      await action();
      if (!mounted) return;
      setState(() => _done.add(key));
      if (success.isNotEmpty) _toast(success);
    } catch (e) {
      if (mounted) _toast(_err(e));
    } finally {
      if (mounted) setState(() => _busy = null);
      if (_video && mounted) _player?.play();
    }
  }

  Future<void> _sendHere() => _work('here', () => widget.onSend(a), 'Sent in this chat');

  Future<void> _sendTo() async {
    final people = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PhlioColors.surface,
      showDragHandle: true,
      builder: (_) => _PeoplePicker(api: _messaging, exclude: widget.peer),
    );
    if (people == null || people.isEmpty || !mounted) return;
    await _work('others', () async {
      var sent = 0;
      for (final user in people) {
        final files = await _messaging.upload(user, [a.path!]);
        await _messaging.send(user, '', attachments: files);
        sent++;
      }
      if (sent == 0) throw const FormatException('Nothing was sent.');
    }, 'Sent to ${people.length == 1 ? people.single : '${people.length} chats'}');
  }

  Future<void> _moment() => _work('moment', () async {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MomentComposerScreen(initialPath: a.path, initialVideo: _video)));
      }, '');

  Future<void> _experience() async {
    final caption = TextEditingController();
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PhlioColors.surface,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Post as experience',
              style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Experiences stay on your profile for the people you choose.',
              style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 14),
          TextField(
            controller: caption,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(hintText: 'Write a caption…'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _violet, shape: const StadiumBorder()),
              onPressed: () => Navigator.pop(sheet, true),
              child: const Text('Choose audience', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
    if (go != true || !mounted) {
      caption.dispose();
      return;
    }
    final audience = await pickSnapAudience(context, const SnapAudience());
    if (audience == null || !mounted) {
      caption.dispose();
      return;
    }
    await _work('experience', () async {
      await _dio.post('/social/memories',
          data: FormData.fromMap({
            'kind': 'experience',
            'caption': caption.text,
            'audience': audience.mode,
            'recipients': jsonEncode(audience.recipients),
            'file': await MultipartFile.fromFile(a.path!,
                filename: a.name,
                contentType: DioMediaType(_video ? 'video' : 'image', _video ? 'mp4' : 'jpeg')),
          }),
          options: Options(
              sendTimeout: const Duration(minutes: 5), receiveTimeout: const Duration(minutes: 5)));
    }, 'Experience posted');
    caption.dispose();
  }

  Future<void> _save() => _work('save', () async {
        final permission = await PhotoManager.requestPermissionExtend();
        if (!permission.isAuth && !permission.hasAccess) {
          throw const FormatException('Allow Phlio to add to your photos to save.');
        }
        if (_video) {
          await PhotoManager.editor.saveVideo(File(a.path!), title: a.name);
        } else {
          await PhotoManager.editor.saveImage(await File(a.path!).readAsBytes(), filename: a.name);
        }
      }, 'Saved to your gallery');

  Future<void> _more() => _work('more', () async {
        await SharePlus.instance.share(ShareParams(files: [XFile(a.path!)]));
      }, '');

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final media = _video
        ? (player != null && player.value.isInitialized
            ? GestureDetector(
                onTap: () => setState(() => player.value.isPlaying ? player.pause() : player.play()),
                child: AspectRatio(aspectRatio: player.value.aspectRatio, child: VideoPlayer(player)),
              )
            : const AspectRatio(aspectRatio: 9 / 16, child: Center(child: CircularProgressIndicator())))
        : Image.file(File(a.path!), fit: BoxFit.contain);
    final sizeMb = (a.size / 1e6).toStringAsFixed(a.size > 10e6 ? 0 : 1);
    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      body: SafeArea(
        child: Column(children: [
          Row(children: [
            IconButton(
                tooltip: 'Back to edit',
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
            const Spacer(),
            TextButton(
              // Close publish and the editor, back to the chat.
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Done',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            const SizedBox(width: 6),
          ]),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 6),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: media,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.check_circle_rounded, color: PhlioColors.success, size: 18),
            const SizedBox(width: 6),
            Text('${_video ? 'Video' : 'Photo'} ready · $sizeMb MB',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 14,
              children: [
                _Target(
                    icon: Icons.send_rounded,
                    label: 'Send here',
                    gradient: true,
                    busy: _busy == 'here',
                    done: _done.contains('here'),
                    onTap: _sendHere),
                _Target(
                    icon: Icons.forward_to_inbox_rounded,
                    label: 'Send to…',
                    busy: _busy == 'others',
                    done: _done.contains('others'),
                    onTap: _sendTo),
                _Target(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Moment',
                    busy: _busy == 'moment',
                    onTap: _moment),
                _Target(
                    icon: Icons.collections_rounded,
                    label: 'Experience',
                    busy: _busy == 'experience',
                    done: _done.contains('experience'),
                    onTap: _experience),
                _Target(
                    icon: Icons.download_rounded,
                    label: 'Save',
                    busy: _busy == 'save',
                    done: _done.contains('save'),
                    onTap: _save),
                _Target(icon: Icons.ios_share_rounded, label: 'More', busy: _busy == 'more', onTap: _more),
              ],
            ),
          ),
          const SizedBox(height: 22),
        ]),
      ),
    );
  }
}

class _Target extends StatelessWidget {
  const _Target({
    required this.icon,
    required this.label,
    required this.onTap,
    this.gradient = false,
    this.busy = false,
    this.done = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool gradient, busy, done;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 82,
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradient ? PhlioColors.sunsetGradient : null,
                color: gradient ? null : const Color(0xFF1C2433),
                border: done ? Border.all(color: PhlioColors.success, width: 2) : null,
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Icon(done ? Icons.check_rounded : icon,
                      color: gradient ? PhlioColors.textOnBrand : Colors.white, size: 26),
            ),
            const SizedBox(height: 7),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

/// Pick people (recent chats first) to send the edit to.
class _PeoplePicker extends StatefulWidget {
  const _PeoplePicker({required this.api, required this.exclude});
  final MessagingApi api;
  final String exclude;
  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  late final Future<List<Map<String, dynamic>>> _people = widget.api.destinations();
  final _picked = <String>{};
  String _q = '';

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        heightFactor: .8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded), hintText: 'Search'),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _people,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return snap.hasError
                      ? const Center(child: Text('Could not load your chats.'))
                      : const Center(child: CircularProgressIndicator());
                }
                final list = snap.data!
                    .where((p) => p['username'] != widget.exclude)
                    .where((p) =>
                        _q.isEmpty ||
                        '${p['username']} ${p['display_name'] ?? p['full_name'] ?? ''}'
                            .toLowerCase()
                            .contains(_q))
                    .toList();
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final person = list[i];
                    final user = person['username'].toString();
                    final name = (person['display_name'] ?? person['full_name'] ?? user).toString();
                    final on = _picked.contains(user);
                    return ListTile(
                      onTap: () => setState(() => on ? _picked.remove(user) : _picked.add(user)),
                      leading: PhlioAvatar(
                          name: name, imageUrl: person['avatar_url'] as String?, size: 44, showMomentRing: false),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('@$user', style: const TextStyle(color: Colors.white54)),
                      trailing: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: on ? _violet : Colors.transparent,
                          border: Border.all(color: on ? _violet : Colors.white38, width: 2),
                        ),
                        child: on ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _violet, shape: const StadiumBorder()),
                  onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked.toList()),
                  child: Text(_picked.isEmpty ? 'Choose people' : 'Send to ${_picked.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ]),
      );
}
