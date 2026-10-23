import 'package:flutter/services.dart';
import 'content_owner_menu.dart';
import '../../../../shared/music/song_picker.dart';
import '../../../profile/presentation/controllers/avatar_controller.dart';
import 'video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../../app/config/app_config.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/content/content_surface.dart';
import '../../../../shared/content/social_comments_sheet.dart';
import '../controllers/video_library.dart';
import 'creator_follow_button.dart';

class SocialClipsView extends ConsumerStatefulWidget {
  const SocialClipsView(
      {super.key, this.query = '', this.initialClipId, this.onlyIds});
  final String query;

  /// Open on this clip (e.g. the tile tapped in the Explore grid).
  final String? initialClipId;

  /// Restrict the feed to these clip ids, in this order (e.g. Saved).
  final List<String>? onlyIds;
  @override
  ConsumerState<SocialClipsView> createState() => _SocialClipsViewState();
}

class _SocialClipsViewState extends ConsumerState<SocialClipsView> {
  int selected = 0;
  String catalogKey = '';
  PageController pages = PageController();
  bool autoScroll = false;
  bool _startApplied = false;
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  final _prefetched = <String>{};
  @override
  Widget build(BuildContext context) =>
      ref.watch(socialVideoCatalogProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
              child: TextButton(
                  onPressed: () => ref.invalidate(socialVideoCatalogProvider),
                  child: const Text('Could not load clips. Retry'))),
          data: (videos) {
            final only = widget.onlyIds;
            var clips = videos
                .where((v) =>
                    (only != null
                        ? only.contains(v.id) || only.contains(v.contentId)
                        : v.kind == 'clip') &&
                    v.title
                        .toLowerCase()
                        .contains(widget.query.trim().toLowerCase()))
                .toList();
            if (only != null) {
              int order(PlayableVideo v) {
                final i = only.indexOf(v.id);
                return i >= 0 ? i : only.indexOf(v.contentId ?? '');
              }
              clips.sort((a, b) => order(a).compareTo(order(b)));
            }
            final nextKey = clips.map((clip) => clip.id).join(',');
            if (catalogKey != nextKey) {
              catalogKey = nextKey;
              var start = 0;
              if (!_startApplied && widget.initialClipId != null) {
                final index =
                    clips.indexWhere((c) => c.id == widget.initialClipId);
                if (index >= 0) start = index;
              }
              _startApplied = true;
              selected = start;
              final old = pages;
              pages = PageController(initialPage: start);
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => old.dispose());
            }
            for (final clip in clips.skip(selected).take(3)) {
              final url = clip.thumbnailUrl;
              if (url != null && _prefetched.add(url)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted)
                    precacheImage(
                        NetworkImage(AppConfig.mediaUrl(url)), context,
                        onError: (_, __) {});
                });
              }
            }
            if (clips.isEmpty)
              return Center(
                  child: Text(widget.query.isEmpty
                      ? 'No clips yet.'
                      : 'No clips match your search.'));
            return PageView.builder(
                key: ValueKey(catalogKey),
                controller: pages,
                scrollDirection: Axis.vertical,
                itemCount: clips.length,
                onPageChanged: (i) => setState(() => selected = i),
                itemBuilder: (_, i) => _Reel(
                    key: ValueKey(clips[i].id),
                    clip: clips[i],
                    active: i == selected,
                    autoScroll: autoScroll,
                    onAutoScroll: (value) => setState(() => autoScroll = value),
                    onEnded: () {
                      if (mounted &&
                          selected == i &&
                          i + 1 < clips.length &&
                          pages.hasClients)
                        pages.animateToPage(i + 1,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic);
                    }));
          });
}

class _Reel extends ConsumerStatefulWidget {
  const _Reel(
      {super.key,
      required this.clip,
      required this.active,
      required this.autoScroll,
      required this.onAutoScroll,
      required this.onEnded});
  final PlayableVideo clip;
  final bool active, autoScroll;
  final ValueChanged<bool> onAutoScroll;
  final VoidCallback onEnded;
  @override
  ConsumerState<_Reel> createState() => _ReelState();
}

class _ReelState extends ConsumerState<_Reel> with WidgetsBindingObserver {
  VideoPlayerController? player;
  bool ready = false,
      failed = false,
      muted = false,
      paused = false,
      busy = false,
      foreground = true;
  double speed = 1;
  bool controlsOpen = false, advanced = false;
  String get path => 'social/${widget.clip.id}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(covariant _Reel old) {
    super.didUpdateWidget(old);
    player?.setLooping(!widget.autoScroll);
    if (!widget.active) advanced = false;
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    sync();
  }

  Future<void> sync() async {
    final play =
        widget.active && TickerMode.of(context) && foreground && !controlsOpen;
    if (!play) {
      await player?.pause();
      return;
    }
    if (player != null) {
      if (ready && !paused) await player!.play();
      return;
    }
    final p = VideoPlayerController.networkUrl(
        Uri.parse(AppConfig.mediaUrl(widget.clip.url)));
    player = p;
    try {
      await p.initialize();
      if (!mounted || player != p) return;
      await p.setLooping(!widget.autoScroll);
      p.addListener(completed);
      await p.setVolume(muted ? 0 : 1);
      setState(() => ready = true);
      if (widget.active && TickerMode.of(context) && foreground && !paused)
        await p.play();
      if (getIt.isRegistered<ApiClient>()) {
        try {
          await getIt<ApiClient>().dio.put('/content/$path/actions/viewed');
          ref.invalidate(engagementProvider(path));
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player?.dispose();
    super.dispose();
  }

  void completed() {
    final value = player?.value;
    if (value != null &&
        value.isInitialized &&
        widget.autoScroll &&
        widget.active &&
        foreground &&
        !controlsOpen &&
        !advanced &&
        value.duration > Duration.zero &&
        value.position >= value.duration) {
      advanced = true;
      widget.onEnded();
    }
  }

  Future<void> about() async {
    if (controlsOpen) return;
    controlsOpen = true;
    await player?.pause();
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (_) => _ClipAbout(clip: widget.clip));
    if (!mounted) return;
    controlsOpen = false;
    if (choice == 'playback') {
      await controls();
    } else if (choice != null) {
      try {
        final api = getIt<ApiClient>().dio;
        if (choice == 'report') {
          await api.post('/social/clips/${widget.clip.id}/report');
        } else {
          await api.put('/social/clips/${widget.clip.id}/preference',
              data: {'preference': choice});
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(choice == 'report'
                ? 'Report submitted.'
                : choice == 'interested'
                    ? 'Preference saved. Similar clips will appear higher in your feed.'
                    : 'This clip will be hidden.')));
        if (choice != 'report') ref.invalidate(socialVideoCatalogProvider);
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Could not save. Please try again.')));
      }
    }
    if (mounted) sync();
  }

  Future<void> controls() async {
    if (controlsOpen) return;
    controlsOpen = true;
    await player?.pause();
    if (!mounted) return;
    var autoAdvance = widget.autoScroll;
    final fullscreen = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
            builder: (c, update) => SafeArea(
                    child: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(
                      leading: const Icon(Icons.fullscreen),
                      title: const Text('View fullscreen'),
                      enabled: ready,
                      onTap: ready ? () => Navigator.pop(c, true) : null),
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(children: [
                        const Icon(Icons.speed),
                        const SizedBox(width: 16),
                        const Text('Speed'),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 4,
                                children: [
                              for (final rate in [.5, 1.0, 1.5, 2.0])
                                ChoiceChip(
                                    label: Text('${rate}x'),
                                    selected: speed == rate,
                                    onSelected: ready
                                        ? (_) async {
                                            try {
                                              await player!
                                                  .setPlaybackSpeed(rate);
                                              if (mounted) {
                                                setState(() => speed = rate);
                                                update(() {});
                                              }
                                            } catch (_) {}
                                          }
                                        : null)
                            ]))
                      ])),
                  SwitchListTile(
                      secondary: const Icon(Icons.autorenew),
                      title: const Text('Auto scroll'),
                      value: autoAdvance,
                      onChanged: (value) {
                        autoAdvance = value;
                        widget.onAutoScroll(value);
                        player?.setLooping(!value);
                        advanced = false;
                        update(() {});
                      }),
                  ListTile(
                      leading: const Icon(Icons.closed_caption_outlined),
                      title: const Text('Closed captions'),
                      subtitle: const Text(
                          'This clip has no caption track. Automatic transcription is not configured.'),
                      enabled: false),
                  const SizedBox(height: 16),
                ])))));
    if (!mounted) return;
    if (fullscreen == true && player != null && ready) {
      await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => _ClipFullscreen(player: player!)));
    }
    if (mounted) {
      controlsOpen = false;
      sync();
    }
  }

  Future<void> sheet(bool comments) async {
    await player?.pause();
    if (!mounted) return;
    if (comments)
      await showSocialComments(context, widget.clip.id);
    else
      await showContentShare(context, path);
    if (mounted) sync();
  }

  Future<void> action(String verb) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await getIt<ApiClient>()
          .dio
          .put('/content/$path/${verb == 'like' ? 'like' : 'actions/$verb'}');
      ref.invalidate(engagementProvider(path));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update. Try again.')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(engagementProvider(path)).valueOrNull;
    // Fixed-width rail cells keep every icon centred on the same axis,
    // even when a liker stack sits to the left of the heart.
    Widget rail(IconData icon, String label, VoidCallback tap) => Container(
        width: 56,
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(children: [
          IconButton(
              tooltip: label,
              onPressed: tap,
              icon: Icon(icon,
                  color: icon == Icons.favorite
                      ? const Color(0xFFFF2851)
                      : Colors.white,
                  size: 28)),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white))
        ]));
    return GestureDetector(
        onLongPress: controls,
        onTap: () async {
          setState(() => paused = !paused);
          if (paused)
            await player?.pause();
          else
            sync();
        },
        child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: ColoredBox(
                color: Colors.black,
                child: Stack(fit: StackFit.expand, children: [
                  if (ready)
                    FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                            width: player!.value.size.width,
                            height: player!.value.size.height,
                            child: VideoPlayer(player!)))
                  else if (widget.clip.thumbnailUrl != null)
                    VideoThumbnail(url: widget.clip.thumbnailUrl),
                  const IgnorePointer(
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.center,
                                  end: Alignment.bottomCenter,
                                  colors: [
                        Colors.transparent,
                        Colors.black87
                      ])))),
                  if (paused)
                    const Center(
                        child: Icon(Icons.play_arrow_rounded,
                            size: 64, color: Colors.white70)),
                  if (failed)
                    Center(
                        child: TextButton(
                            onPressed: () async {
                              await player?.dispose();
                              player = null;
                              setState(() => failed = false);
                              sync();
                            },
                            child: const Text('Retry playback'))),
                  Positioned(
                      top: 8,
                      left: 8,
                      child: IconButton(
                          tooltip: muted ? 'Unmute' : 'Mute',
                          onPressed: () {
                            setState(() => muted = !muted);
                            player?.setVolume(muted ? 0 : 1);
                          },
                          icon: Icon(
                              muted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: Colors.white))),
                  Positioned(
                      right: 8,
                      top: 72,
                      bottom: 12,
                      child: Align(
                          alignment: Alignment.bottomRight,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                // Like: liker preview to the left of the
                                // heart; the heart stays in the rail column.
                                Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 14),
                                          child: LikersAvatarStack(
                                              path: path,
                                              size: 20,
                                              ringColor: Colors.black54)),
                                      rail(
                                          data?['liked_by_me'] == true
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          formatEngagementCount(
                                              data?['count'] as num? ?? 0),
                                          () => action('like')),
                                    ]),
                                rail(
                                    Icons.chat_bubble_outline_rounded,
                                    // Same live count as every other
                                    // surface; refreshed on comment/delete.
                                    formatEngagementCount(
                                        data?['comments_count'] as num? ??
                                            ref
                                                .watch(socialCommentsProvider(
                                                    widget.clip.id))
                                                .valueOrNull
                                                ?.length ??
                                            0),
                                    () => sheet(true)),
                                rail(
                                    Icons.repeat_rounded,
                                    formatEngagementCount(
                                        data?['reposts_count'] as num? ?? 0),
                                    () => action('reposted')),
                                rail(
                                    Icons.ios_share_rounded,
                                    formatEngagementCount(
                                        data?['shares_count'] as num? ?? 0),
                                    () => sheet(false)),
                                rail(
                                    data?['saved_by_me'] == true
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                    formatEngagementCount(
                                        data?['bookmarks_count'] as num? ?? 0),
                                    () => action('saved')),
                                rail(Icons.notes, '', about),
                              ])))),
                  Positioned(
                      top: 8,
                      right: 8,
                      child: ContentOwnerMenu(
                          id: widget.clip.id,
                          owner: widget.clip.creator,
                          text: widget.clip.title,
                          video: true)),
                  Positioned(
                      left: 16,
                      right: 80,
                      bottom: 22,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              ContentAuthorAvatar(
                                  author: widget.clip.creator,
                                  name: widget.clip.creator,
                                  imageUrl: widget.clip.avatarUrl,
                                  size: 36),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: InkWell(
                                      onTap: () => context.push(
                                          '/creator/${widget.clip.creator}'),
                                      child: Text('@${widget.clip.creator}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700)))),
                              CreatorFollowButton(creator: widget.clip.creator)
                            ]),
                            const SizedBox(height: 8),
                            Text(widget.clip.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    height: 1.4)),
                            const SizedBox(height: 6),
                            ContentSongBadge(
                                kind: 'clip', target: widget.clip.id),
                            if (widget.clip.songTitle?.trim().isNotEmpty ==
                                true)
                              Text(
                                  '♫ ${widget.clip.songTitle}${widget.clip.songArtist == null ? '' : ' · ${widget.clip.songArtist}'}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            if (widget.clip.attribution != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(widget.clip.attribution!,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white60))),
                          ])),
                ]))));
  }
}

class _ClipFullscreen extends StatefulWidget {
  const _ClipFullscreen({required this.player});
  final VideoPlayerController player;
  @override
  State<_ClipFullscreen> createState() => _ClipFullscreenState();
}

class _ClipFullscreenState extends State<_ClipFullscreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    widget.player.play();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) widget.player.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.player.pause();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
          child: Stack(children: [
        Center(
            child: AspectRatio(
                aspectRatio: widget.player.value.aspectRatio,
                child: VideoPlayer(widget.player))),
        Positioned(
            top: 8,
            left: 8,
            child: IconButton(
                tooltip: 'Exit fullscreen',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.fullscreen_exit, color: Colors.white))),
        Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder(
                valueListenable: widget.player,
                builder: (context, value, _) =>
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          tooltip: value.isPlaying ? 'Pause' : 'Play',
                          onPressed: () => value.isPlaying
                              ? widget.player.pause()
                              : widget.player.play(),
                          icon: Icon(
                              value.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white)),
                      VideoProgressIndicator(widget.player,
                          allowScrubbing: true)
                    ])))
      ])));
}

class _ClipAbout extends StatefulWidget {
  const _ClipAbout({required this.clip});
  final PlayableVideo clip;
  @override
  State<_ClipAbout> createState() => _ClipAboutState();
}

class _ClipAboutState extends State<_ClipAbout> {
  final question = TextEditingController();
  bool sending = false;
  String? answer, conversation;
  @override
  void dispose() {
    question.dispose();
    super.dispose();
  }

  Future<void> ask() async {
    final text = question.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      final response =
          await getIt<ApiClient>().dio.post('/agent/messages', data: {
        'text':
            'About this clip by @${widget.clip.creator}: ${widget.clip.title}. Question: $text',
        if (conversation != null) 'conversation_id': conversation,
      });
      if (!mounted) return;
      setState(() {
        answer = response.data['text'] as String;
        conversation = response.data['conversation_id'] as String;
      });
    } catch (_) {
      if (mounted)
        setState(() => answer = 'Foxy could not connect. Please try again.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .82),
              child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('About this clip',
                            style: TextStyle(
                                fontSize: 21, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 20),
                        Text(widget.clip.title,
                            style: const TextStyle(fontSize: 18, height: 1.45)),
                        const SizedBox(height: 20),
                        Row(children: [
                          Expanded(
                              child: TextField(
                                  controller: question,
                                  maxLength: 1200,
                                  onSubmitted: (_) => ask(),
                                  textInputAction: TextInputAction.send,
                                  decoration: InputDecoration(
                                      hintText: 'Ask Foxy AI...',
                                      counterText: '',
                                      prefixIcon:
                                          const Icon(Icons.auto_awesome),
                                      filled: true,
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(32),
                                          borderSide: BorderSide.none)))),
                          IconButton(
                              tooltip: 'Ask Foxy AI',
                              onPressed: sending ? null : ask,
                              icon: sending
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.send_outlined))
                        ]),
                        if (answer != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: SelectableText(answer!)),
                        const SizedBox(height: 16),
                        const Divider(),
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.play_circle_outline),
                            title: const Text('Playback'),
                            onTap: () => Navigator.pop(context, 'playback')),
                        const Divider(),
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.check_circle_outline),
                            title: const Text('Interested'),
                            onTap: () => Navigator.pop(context, 'interested')),
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.cancel_outlined),
                            title: const Text('Not interested'),
                            onTap: () =>
                                Navigator.pop(context, 'not_interested')),
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.report_outlined,
                                color: Colors.redAccent),
                            title: const Text('Report',
                                style: TextStyle(color: Colors.redAccent)),
                            onTap: () => Navigator.pop(context, 'report')),
                      ])))));
}
