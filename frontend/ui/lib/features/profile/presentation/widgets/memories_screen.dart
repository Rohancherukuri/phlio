import 'dart:convert';
import 'snap_audience.dart';
import '../../../../shared/content/memory_photo.dart';
import '../../../../shared/content/content_surface.dart';
import 'snap_camera_screen.dart';
import 'dart:async';
import '../../../rooms/data/datasources/messaging_api.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
        setState(() => grid = true);
        return;
      }
      final capture =
          result is ({XFile photo, SnapAudience audience}) ? result : null;
      final photo = capture?.photo;
      if (capture != null) audience = capture.audience;
      if (mounted && photo != null) {
        setState(() {
          snap = photo;
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

  Future<void> publish() async {
    if (busy || snap == null) return;
    setState(() => busy = true);
    try {
      await getIt<ApiClient>().dio.post(
            '/social/memories',
            data: FormData.fromMap({
              'caption': caption.text.trim(),
              'audience': audience.mode,
              'recipients': jsonEncode(audience.recipients),
              'kind': widget.kind,
              'file': await MultipartFile.fromFile(
                snap!.path,
                filename: snap!.name,
                contentType: DioMediaType('image', 'jpeg'),
              ),
            }),
          );
      if (!mounted) return;
      setState(() {
        snap = null;
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
          IconButton(
            tooltip: grid ? "Stack view" : "Grid view",
            onPressed: () => setState(() => grid = !grid),
            icon: Icon(grid ? Icons.layers_outlined : Icons.grid_view_rounded),
          ),
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
        appBar: AppBar(
          backgroundColor: Colors.black,
          title:
              Text(widget.kind == 'snap' ? 'Memories' : 'New ${widget.kind}'),
          centerTitle: true,
        ),
        body: snap != null
            ? SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.file(
                            File(snap!.path),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: caption,
                        enabled: !busy,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          hintText: 'Add a caption...',
                        ),
                      ),
                    ),
                    TextButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                final value =
                                    await pickSnapAudience(context, audience);
                                if (mounted && value != null) {
                                  setState(() => audience = value);
                                }
                              },
                        icon: const Icon(Icons.people_outline),
                        label: Text(audience.label),),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          TextButton(
                            onPressed:
                                busy ? null : () => setState(() => snap = null),
                            child: const Text('Discard'),
                          ),
                          TextButton.icon(
                            onPressed: busy ? null : capture,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retake'),
                          ),
                          FilledButton.icon(
                            onPressed: busy ? null : publish,
                            icon: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_upward),
                            label: Text(busy ? 'Sharing...' : 'Share ${widget.kind}'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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

  Widget photo(Map item) => ClipRRect(
      borderRadius: BorderRadius.circular(64),
      child: MemoryPhoto(item['image_url'] as String),);

  Widget memoryFeed(List<Map> items) {
    // Friends' active snaps lead the stack; the creator's archive follows.
    final me = ref.read(authControllerProvider).valueOrNull?.id;
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
                        child: photo(item),
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
                    child: Text(
                      (item['reactions'] as List)
                          .map((r) => r['emoji'])
                          .join(' '),
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
                        icon: const Icon(Icons.send_outlined),
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
