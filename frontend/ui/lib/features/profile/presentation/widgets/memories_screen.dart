import 'snap_decorations.dart';
import '../../../../shared/moments/stickers/sticker_model.dart';
import 'dart:convert';
import 'snap_audience.dart';
import '../../../../shared/content/memory_photo.dart';
import '../../../../shared/content/content_surface.dart';
import 'snap_camera_screen.dart';
import 'snap_archive.dart';
import 'snap_send_view.dart';
import 'package:video_player/video_player.dart';
import '../../../../shared/media/phlio_look_data.dart';
import '../../../../shared/media/phlio_look_view.dart';
import 'dart:async';
import '../../../rooms/data/datasources/messaging_api.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../../design_system/widgets/phlio_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';

final memoriesProvider = FutureProvider.autoDispose<List<Map>>((ref) async {
  ref.watch(authControllerProvider.select((value) => value.valueOrNull?.id));
  final timer = Timer(const Duration(seconds: 30), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ((await getIt<ApiClient>().dio.get('/social/memories')).data as List)
      .cast<Map>();
});

class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen(
      {super.key, this.openCamera = false, this.kind = 'snap',});
  final bool openCamera;
  final String kind;
  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesState();
}

class _MemoriesState extends ConsumerState<MemoriesScreen> {
  SnapAudience audience = const SnapAudience();
  XFile? snap;

  /// The captured snap is a video (hold-to-record) and its filter.
  bool snapVideo = false;
  String snapFilter = 'normal';
  bool grid = false;
  int selected = 0;
  String? burst;
  final seen = <String>{};
  final reply = TextEditingController();
  final pager = PageController();
  Future<void> viewMemory(Map item) async {
    final id = item['id'] as String;
    if (item['unread'] != true || !seen.add(id)) return;
    try {
      await getIt<ApiClient>().dio.put('/social/memories/$id/seen');
      ref.invalidate(memoriesProvider);
    } catch (_) {
      seen.remove(id);
    }
  }

  Future<void> react(Map item, String emoji) async {
    try {
      await getIt<ApiClient>().dio.put(
        '/social/memories/${item['id']}/reaction',
        data: {'emoji': emoji},
      );
      if (!mounted) return;
      setState(() => burst = emoji);
      ref.invalidate(memoriesProvider);
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (mounted) setState(() => burst = null);
    } catch (_) {
      if (mounted) message('Could not send reaction. Try again.');
    }
  }

  Future<void> sendReply(Map item) async {
    if (reply.text.trim().isEmpty || busy) return;
    setState(() => busy = true);
    try {
      await ref.read(messagingApiProvider).send(
            item['author']['username'] as String,
            'Reply to your memory: ${reply.text.trim()}',
          );
      reply.clear();
      if (mounted) message('Reply sent in messages.');
    } catch (_) {
      if (mounted) message('Could not send reply. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  final caption = TextEditingController();
  final decorations = <MomentSticker>[];

  Future<void> decorate() async {
    if (decorations.length >= 20) { message("You can add up to 20 decorations."); return; }
    final item = await pickSnapDecoration(context);
    if (!mounted || item == null) return;
    setState(() {
      if (item.type == StickerType.music) decorations.removeWhere((s) => s.type == StickerType.music);
      decorations.add(item);
    });
  }
  bool busy = false, picking = false;
  @override
  void initState() {
    super.initState();
    if (widget.openCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) capture();
      });
    }
  }

  @override
  void dispose() {
    caption.dispose();
    reply.dispose();
    pager.dispose();
    super.dispose();
  }

  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> capture() async {
    if (picking || busy) return;
    picking = true;
    try {
      final result = await Navigator.of(context).push<Object>(MaterialPageRoute(
          builder: (_) => SnapCameraScreen(audience: audience),),);
      if (!mounted) return;
      if (result == true) {
        // The camera's grid button: your saved snaps.
        openArchive();
        return;
      }
      final capture = result is SnapCapture ? result : null;
      if (capture != null) audience = capture.audience;
      if (mounted && capture != null) {
        setState(() {
          snap = capture.photo;
          snapVideo = capture.video;
          snapFilter = capture.filter;
          decorations.clear();
          caption.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        message(
          'Camera could not open. Allow camera access in phone settings and try again.',
        );
      }
    } finally {
      picking = false;
    }
  }

  /// "Your snaps": every snap you've shared, by month, with reactions.
  void openArchive() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SnapArchiveScreen(onCamera: capture)));

  Future<void> publish() async {
    if (busy || snap == null) return;
    setState(() => busy = true);
    try {
      await getIt<ApiClient>().dio.post(
            '/social/memories',
            data: FormData.fromMap({
              'caption': caption.text.trim(),
              'decorations': jsonEncode(decorations.map((s) => s.toJson()).toList()),
              'audience': audience.mode,
              'recipients': jsonEncode(audience.recipients),
              'kind': widget.kind,
              // The filter travels as data and is drawn live everywhere.
              'filter': snapFilter,
              'file': await MultipartFile.fromFile(
                snap!.path,
                filename: snap!.name,
                contentType: snapVideo
                    ? DioMediaType('video', 'mp4')
                    : snap!.path.toLowerCase().endsWith('.png')
                        ? DioMediaType('image', 'png')
                        : DioMediaType('image', 'jpeg'),
              ),
            }),
          );
      if (!mounted) return;
      setState(() {
        snap = null;
        decorations.clear();
        caption.clear();
      });
      ref.invalidate(memoriesProvider);
      ref.invalidate(sharedStoriesProvider);
      message('${widget.kind[0].toUpperCase()}${widget.kind.substring(1)} shared with ${audience.label}.');
    } catch (_) {
      if (mounted) {
        message(
          'Could not share your memory. Your photo is still here; try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(Map memory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete memory?'),
        content: const Text(
          'This removes the snap from your Memories and friends\' view.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await getIt<ApiClient>().dio.delete('/social/memories/${memory['id']}');
      ref.invalidate(memoriesProvider);
    } catch (_) {
      if (mounted) message('Could not delete. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: snap != null ? null : AppBar(
          backgroundColor: Colors.black,
          title:
              Text(widget.kind == 'snap' ? 'Memories' : 'New ${widget.kind}'),
          centerTitle: true,
          actions: [
            if (snap == null) ...[
              IconButton(
                tooltip: 'Your snaps',
                onPressed: openArchive,
                icon: const Icon(Icons.grid_view_rounded),
              ),
              IconButton(
                tooltip: 'Take a snap',
                onPressed: capture,
                icon: const Icon(Icons.photo_camera_outlined),
              ),
            ],
          ],
        ),
        body: snap != null
            // Locket-style "Send to…": preview, quick-add pill, send, people.
            ? SnapSendView(
                file: snap!,
                video: snapVideo,
                filter: snapFilter,
                decorations: decorations,
                caption: caption,
                audience: audience,
                busy: busy,
                media: snapMediaPreview(
                  path: snap!.path,
                  video: snapVideo,
                  filter: snapFilter,
                  videoPlayer: SnapVideoPreview(key: ValueKey(snap!.path), path: snap!.path, filter: snapFilter),
                ),
                onChanged: () => setState(() {}),
                onAudience: (value) => setState(() => audience = value),
                onDiscard: () => setState(() {
                  snap = null;
                  decorations.clear();
                  caption.clear();
                }),
                onSend: publish,
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(memoriesProvider.future),
                child: ref.watch(memoriesProvider).when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) => Center(
                        child: TextButton(
                          onPressed: () => ref.invalidate(memoriesProvider),
                          child: const Text(
                            'Could not load Memories. Retry',
                          ),
                        ),
                      ),
                      data: memoryFeed,
                    ),
              ),
      ),
    );
  }

  Widget photo(Map item, {bool autoplay = false}) => ClipRRect(
      borderRadius: BorderRadius.circular(64),
      child: MemoryPhoto(item['image_url'] as String,
          decorations: (item['decorations'] as List?) ?? const [],
          isVideo: item['media_kind'] == 'video',
          filter: item['filter'] as String?,
          autoplay: autoplay),);

  Widget memoryFeed(List<Map> items) {
    // Friends' active snaps lead the stack; the creator's archive follows.
    final me = ref.read(authControllerProvider).valueOrNull?.id;
    // Experiences (weekly dumps) live in their own screen.
    items = items.where((m) => (m['kind'] ?? 'snap') != 'experience').toList();
    items = [
      ...items.where((m) => m['author']['id'] != me),
      ...items.where((m) => m['author']['id'] == me),
    ];

    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.auto_awesome, color: Color(0xffffb18d), size: 72),
          const SizedBox(height: 32),
          const Text(
            'Introducing Memories',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          const ListTile(
            leading: Icon(Icons.photo_camera_outlined),
            title: Text('Share in the moment'),
            subtitle: Text('Take a snap and share it with your friends.'),
          ),
          const ListTile(
            leading: Icon(Icons.timelapse),
            title: Text('A day with friends'),
            subtitle: Text('Friends can view your snaps for 24 hours.'),
          ),
          const ListTile(
            leading: Icon(Icons.collections_outlined),
            title: Text('Keep your memories'),
            subtitle: Text(
              'Your own snaps stay in your archive until you delete them.',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: capture, child: const Text('Take a snap')),
          const SizedBox(height: 16),
          const Text(
            'No snaps yet. Capture your first memory.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    if (grid) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: .8,
        ),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () {
            setState(() {
              selected = i;
              grid = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && pager.hasClients) pager.jumpToPage(i);
            });
          },
          child: photo(items[i]),
        ),
      );
    }
    selected = selected.clamp(0, items.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !grid) {
        viewMemory(items[selected.clamp(0, items.length - 1)]);
      }
    });
    return PageView.builder(
      controller: pager,
      itemCount: items.length,
      onPageChanged: (i) {
        setState(() {
          selected = i;
          burst = null;
          reply.clear();
        });
        viewMemory(items[i]);
      },
      itemBuilder: (context, index) {
        final item = items[index];
        final mine = item['author']['id'] ==
            ref.watch(authControllerProvider).valueOrNull?.id;
        return LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              children: [
                SizedBox(
                  height: (constraints.maxHeight * .52).clamp(230.0, 480.0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      for (var depth = 2; depth >= 1; depth--)
                        if (index + depth < items.length)
                          Positioned.fill(
                            left: 20,
                            right: 20,
                            bottom: 28,
                            child: Transform.translate(
                              offset: Offset(depth * 5, -depth * 9),
                              child: Transform.rotate(
                                angle: depth == 2 ? .12 : -.10,
                                child: photo(items[index + depth]),
                              ),
                            ),
                          ),
                      Positioned.fill(
                        top: 14,
                        bottom: 0,
                        child: photo(item, autoplay: true),
                      ),
                      if (burst != null)
                        Center(
                          child: Text(
                            burst!,
                            key: ValueKey(burst),
                            style: const TextStyle(fontSize: 86),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '@${item['author']['username']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if ((item['caption'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      item['caption'] as String,
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    for (final emoji in [
                      '\u{1F602}',
                      '\u{2764}\u{FE0F}',
                      '\u{1F338}',
                      '\u{1F44F}',
                    ])
                      InkWell(
                        borderRadius: BorderRadius.circular(32),
                        onTap: () => react(item, emoji),
                        child: Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xff202020),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    IconButton.filledTonal(
                      tooltip: 'Take a snap',
                      onPressed: capture,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                if ((item['reactions'] as List? ?? []).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      // Your own snap: see who reacted, and when.
                      onTap: mine
                          ? () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => SnapDetailScreen(item: item)))
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          (item['reactions'] as List)
                                  .map((r) => r['emoji'])
                                  .join(' ') +
                              (mine ? '  ·  See reactions' : ''),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                if (!mine)
                  TextField(
                    controller: reply,
                    maxLength: 1000,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => sendReply(item),
                    decoration: InputDecoration(
                      hintText: 'Reply to ${item['author']['username']}...',
                      counterText: '',
                      suffixIcon: IconButton(
                        tooltip: 'Send reply',
                        onPressed: busy ? null : () => sendReply(item),
                        icon: const PhlioSendIcon(),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                    ),
                  ),
                if (mine)
                  TextButton.icon(
                    onPressed: () => remove(item),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete memory'),
                  ),
                Text(
                  '${index + 1} / ${items.length}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class MemoryCameraButton extends ConsumerWidget {
  const MemoryCameraButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref
            .watch(memoriesProvider)
            .valueOrNull
            ?.where((m) => m['unread'] == true)
            .length ??
        0;
    return IconButton(
      tooltip: 'Memories',
      onPressed: () => Navigator.of(context, rootNavigator: true)
          .push(MaterialPageRoute(builder: (_) => const MemoriesScreen())),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(Icons.photo_camera_outlined),
      ),
    );
  }
}

/// The recorded snap video, looping with its filter, before sharing.
class SnapVideoPreview extends StatefulWidget {
  const SnapVideoPreview({required this.path, required this.filter, super.key});
  final String path;
  final String filter;
  @override
  State<SnapVideoPreview> createState() => _SnapVideoPreviewState();
}

class _SnapVideoPreviewState extends State<SnapVideoPreview> {
  late final VideoPlayerController player = VideoPlayerController.file(File(widget.path));

  @override
  void initState() {
    super.initState();
    player.initialize().then((_) async {
      await player.setLooping(true);
      await player.play();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!player.value.isInitialized) return const Center(child: CircularProgressIndicator());
    final (look, effect) = splitMomentFilter(widget.filter);
    return PhlioLook(
      look: look,
      effect: effect,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
            width: player.value.size.width,
            height: player.value.size.height,
            child: VideoPlayer(player)),
      ),
    );
  }
}
