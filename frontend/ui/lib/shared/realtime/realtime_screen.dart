import 'package:video_player/video_player.dart';
import '../../app/config/app_config.dart';
import '../../design_system/colors.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';

Future<void> openRealtime(BuildContext context,
        {required String endpoint,
        required String title,
        bool rooms = false,
        bool video = true,
        bool record = false,
        List<String> topics = const []}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
        builder: (_) => RealtimeScreen(
            endpoint: endpoint,
            title: title,
            rooms: rooms,
            video: video,
            record: record,
            topics: topics)));

/// One SFU connection per screen; adaptive subscriptions and simulcast are
/// managed by LiveKit, including reconnects after a network change.
class RealtimeScreen extends StatefulWidget {
  const RealtimeScreen(
      {required this.endpoint,
      required this.title,
      this.rooms = false,
      this.video = true,
      this.topics = const [],
      this.record = false,
      super.key});
  final String endpoint, title;
  final bool rooms, video;

  /// Spaces: host chose "Record Space" (shown as a REC badge to listeners).
  final bool record;
  final List<String> topics;
  @override
  State<RealtimeScreen> createState() => _RealtimeScreenState();
}

class _RealtimeScreenState extends State<RealtimeScreen> {
  bool fullscreen = false, sound = true, viewerPaused = false;
  final startedAt = DateTime.now();
  Timer? clock;
  void setFullscreen(bool value) {
    setState(() => fullscreen = value);
    unawaited(SystemChrome.setPreferredOrientations(value
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]));
    unawaited(SystemChrome.setEnabledSystemUIMode(
        value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge));
  }

  Future<void> subscriptions({bool? audio, bool? paused}) async {
    if (changing) return;
    setState(() => changing = true);
    final nextSound = audio ?? sound, nextPaused = paused ?? viewerPaused;
    try {
      for (final participant
          in room?.remoteParticipants.values ?? <lk.RemoteParticipant>[]) {
        for (final publication in participant.audioTrackPublications) {
          if (nextSound && !nextPaused) {
            await publication.subscribe();
          } else {
            await publication.unsubscribe();
          }
        }
        for (final publication in participant.videoTrackPublications) {
          if (nextPaused) {
            await publication.unsubscribe();
          } else {
            await publication.subscribe();
          }
        }
      }
      if (mounted)
        setState(() {
          sound = nextSound;
          viewerPaused = nextPaused;
        });
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not update playback. Try again.')));
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  lk.Room? room;
  bool connecting = true, publishing = false, host = false, closing = false;
  bool changing = false, front = true;
  String? error, roomName;
  final dio = getIt<ApiClient>().dio;

  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    connect();
  }

  Future<void> connect() async {
    setState(() {
      connecting = true;
      error = null;
    });
    final previous = room;
    previous?.removeListener(changed);
    await previous?.dispose();
    if (!mounted) return;
    final next = lk.Room(
        roomOptions:
            const lk.RoomOptions(adaptiveStream: true, dynacast: true));
    room = next;
    next.addListener(changed);
    try {
      final data = (await dio.post(widget.endpoint,
              data: widget.endpoint == '/realtime/live'
                  ? {
                      'title': widget.title,
                      'audio_only': !widget.video,
                      'topics': widget.topics,
                      'record': widget.record
                    }
                  : null))
          .data as Map;
      publishing = data['can_publish'] == true;
      host = data['host'] == true;
      roomName = data['room'] as String;
      if (!mounted) return;
      await next.connect(data['url'] as String, data['token'] as String);
      if (!mounted || closing) {
        await next.disconnect();
        return;
      }
      await next.setSpeakerOn(widget.video || widget.rooms);
      if (publishing) {
        // Joining a room starts muted; a live host/caller explicitly opted in.
        await next.localParticipant?.setMicrophoneEnabled(!widget.rooms);
        if (!mounted || closing) {
          await next.disconnect();
          return;
        }
        await next.localParticipant?.setCameraEnabled(widget.video);
        if (!mounted || closing) await next.disconnect();
      }
    } catch (e) {
      if (mounted) {
        final payload = e is DioException ? e.response?.data : null;
        final message = payload is Map
            ? payload['detail'] ??
                (payload['error'] is Map ? payload['error']['message'] : null)
            : null;
        error = message?.toString() ??
            'Could not connect. Check camera/microphone permissions and your connection.';
      }
      await next.disconnect();
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> change(Future<dynamic> Function() action) async {
    setState(() => changing = true);
    try {
      await action();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not change this setting. Check device permissions.')));
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  Future<void> leave() async {
    if (closing) return;
    setState(() => closing = true);
    await room?.disconnect();
    if (host && roomName != null) {
      try {
        await dio.delete('/realtime/live/$roomName');
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Connection lost. Your camera will stop; viewers will see that you left.')));
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    clock?.cancel();
    if (fullscreen) {
      unawaited(SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]));
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    room?.removeListener(changed);
    unawaited(room?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final local = room?.localParticipant;
    final participants = <lk.Participant>[
      ...?room?.remoteParticipants.values
          .where((p) => p.permissions.canPublish),
      if (publishing && local != null) local,
    ];
    final connected = room?.connectionState == lk.ConnectionState.connected;
    final status = connecting
        ? 'Connecting…'
        : connected
            ? widget.rooms
                ? '${participants.length} in voice'
                : host
                    ? 'You are live'
                    : 'Connected'
            : room?.connectionState == lk.ConnectionState.reconnecting
                ? 'Reconnecting…'
                : 'Session disconnected';
    return PopScope(
        canPop: closing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            if (fullscreen) {
              setFullscreen(false);
            } else {
              leave();
            }
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF080E16),
          appBar: fullscreen
              ? null
              : AppBar(
                  toolbarHeight:
                      MediaQuery.textScalerOf(context).scale(20) * 2 + 20,
                  automaticallyImplyLeading: false,
                  title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        Text(status,
                            style: TextStyle(
                                fontSize: 12,
                                color: connected
                                    ? const Color(0xFF68D7CD)
                                    : Colors.white60)),
                      ]),
                  actions: [
                      IconButton(
                          tooltip: 'Leave session',
                          onPressed: closing ? null : leave,
                          icon: const Icon(Icons.close))
                    ]),
          body: error != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: connecting ? null : connect,
                            child: const Text('Try again')),
                      ])))
              : connecting
                  ? const Center(child: CircularProgressIndicator())
                  : room?.connectionState == lk.ConnectionState.disconnected
                      ? Center(
                          child: FilledButton.icon(
                              onPressed: closing ? null : connect,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reconnect')))
                      : participants.isEmpty
                          ? const Center(child: Text('Waiting for the host…'))
                          : widget.rooms
                              ? LayoutBuilder(
                                  builder: (_, constraints) => GridView.builder(
                                      padding: const EdgeInsets.all(16),
                                      itemCount: participants.length,
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: constraints
                                                          .maxWidth >
                                                      700
                                                  ? 3
                                                  : constraints.maxWidth > 360
                                                      ? 2
                                                      : 1,
                                              mainAxisSpacing: 12,
                                              crossAxisSpacing: 12,
                                              childAspectRatio: .9),
                                      itemBuilder: (_, i) =>
                                          _ParticipantTile(participants[i])))
                              : Stack(fit: StackFit.expand, children: [
                                  _ParticipantTile(participants.first,
                                      full: true),
                                  if (!publishing)
                                    Center(
                                        child: IconButton(
                                            tooltip: viewerPaused
                                                ? 'Resume live'
                                                : 'Pause live',
                                            onPressed: changing
                                                ? null
                                                : () => subscriptions(
                                                    paused: !viewerPaused),
                                            icon: Icon(
                                                viewerPaused
                                                    ? Icons.play_arrow
                                                    : Icons.pause,
                                                color: Colors.white,
                                                size: 48))),
                                  Positioned(
                                      top: 12,
                                      left: 12,
                                      right: 12,
                                      child: SafeArea(
                                          child: Row(children: [
                                        IconButton(
                                            tooltip: fullscreen
                                                ? 'Minimize player'
                                                : 'Leave live',
                                            onPressed: () {
                                              if (fullscreen) {
                                                setFullscreen(false);
                                              } else {
                                                leave();
                                              }
                                            },
                                            icon: const Icon(
                                                Icons.keyboard_arrow_down,
                                                color: Colors.white)),
                                        const Spacer(),
                                        IconButton(
                                            tooltip: 'Playback settings',
                                            icon: const Icon(
                                                Icons.settings_outlined,
                                                color: Colors.white),
                                            onPressed: () =>
                                                showModalBottomSheet<void>(
                                                    context: context,
                                                    showDragHandle: true,
                                                    builder: (_) => SafeArea(
                                                            child: Column(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                              const ListTile(
                                                                  title: Text(
                                                                      'Live playback'),
                                                                  subtitle: Text(
                                                                      'Quality adapts automatically to your connection')),
                                                              ListTile(
                                                                  title: Text(sound
                                                                      ? 'Mute audio'
                                                                      : 'Enable audio'),
                                                                  leading: Icon(sound
                                                                      ? Icons
                                                                          .volume_up
                                                                      : Icons
                                                                          .volume_off),
                                                                  onTap: () {
                                                                    Navigator.pop(
                                                                        context);
                                                                    subscriptions(
                                                                        audio:
                                                                            !sound);
                                                                  }),
                                                            ])))),
                                      ]))),
                                  Positioned(
                                      bottom: 12,
                                      left: 12,
                                      right: 12,
                                      child: SafeArea(
                                          child: Row(children: [
                                        Container(
                                            padding: const EdgeInsets.all(8),
                                            color: Colors.black54,
                                            child: Text(
                                                '🔴 LIVE · ${DateTime.now().difference(startedAt).inMinutes}:${(DateTime.now().difference(startedAt).inSeconds % 60).toString().padLeft(2, '0')}')),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.person_outline,
                                            color: Colors.white),
                                        Text(
                                            ' ${room?.remoteParticipants.values.where((p) => !p.permissions.canPublish).length ?? 0}',
                                            style: const TextStyle(
                                                color: Colors.white)),
                                        const Spacer(),
                                        IconButton(
                                            tooltip: sound
                                                ? 'Mute audio'
                                                : 'Enable audio',
                                            onPressed: changing
                                                ? null
                                                : () => subscriptions(
                                                    audio: !sound),
                                            icon: Icon(
                                                sound
                                                    ? Icons.volume_up
                                                    : Icons.volume_off,
                                                color: Colors.white)),
                                        IconButton(
                                            tooltip: fullscreen
                                                ? 'Exit fullscreen'
                                                : 'Fullscreen',
                                            onPressed: () =>
                                                setFullscreen(!fullscreen),
                                            icon: Icon(
                                                fullscreen
                                                    ? Icons.fullscreen_exit
                                                    : Icons.fullscreen,
                                                color: Colors.white)),
                                      ]))),
                                  if (participants.length > 1 &&
                                      publishing &&
                                      local != null)
                                    Positioned(
                                        right: 16,
                                        top: 16,
                                        width: 110,
                                        height: 165,
                                        child: _ParticipantTile(local)),
                                ]),
          bottomNavigationBar: fullscreen && !publishing
              ? null
              : SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            if (publishing) ...[
                              IconButton.filledTonal(
                                  tooltip: local?.isMicrophoneEnabled() == true
                                      ? 'Mute microphone'
                                      : 'Unmute microphone',
                                  onPressed: !connected || changing
                                      ? null
                                      : () => change(() => local!
                                          .setMicrophoneEnabled(
                                              !local.isMicrophoneEnabled())),
                                  icon: Icon(
                                      local?.isMicrophoneEnabled() == true
                                          ? Icons.mic
                                          : Icons.mic_off)),
                              if (widget.video)
                                IconButton.filledTonal(
                                    tooltip: 'Toggle camera',
                                    onPressed: !connected || changing
                                        ? null
                                        : () => change(() => local!
                                            .setCameraEnabled(
                                                !local.isCameraEnabled())),
                                    icon: Icon(local?.isCameraEnabled() == true
                                        ? Icons.videocam
                                        : Icons.videocam_off)),
                              if (widget.video)
                                IconButton.filledTonal(
                                    tooltip: 'Switch camera',
                                    onPressed: !connected ||
                                            changing ||
                                            local?.isCameraEnabled() != true
                                        ? null
                                        : () => change(() async {
                                              for (final pub in local!
                                                  .videoTrackPublications) {
                                                final track = pub.track;
                                                if (track
                                                    is lk.LocalVideoTrack) {
                                                  await track.setCameraPosition(
                                                      front
                                                          ? lk.CameraPosition
                                                              .back
                                                          : lk.CameraPosition
                                                              .front);
                                                  front = !front;
                                                  break;
                                                }
                                              }
                                            }),
                                    icon: const Icon(Icons.cameraswitch)),
                            ],
                            FilledButton.icon(
                                style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFB83D52)),
                                onPressed: closing ? null : leave,
                                icon: const Icon(Icons.call_end),
                                label: Text(host ? 'End live' : 'Leave')),
                          ]))),
        ));
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile(this.participant, {this.full = false});
  final lk.Participant participant;
  final bool full;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: participant,
      builder: (context, child) {
        final tracks = participant.videoTrackPublications
            .where((p) => !p.muted && p.track is lk.VideoTrack);
        return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
                color: const Color(0xFF182231),
                borderRadius: BorderRadius.circular(full ? 0 : 18),
                border: Border.all(
                    width: 2,
                    color: participant.isSpeaking
                        ? const Color(0xFF68D7CD)
                        : Colors.transparent)),
            child: Stack(fit: StackFit.expand, children: [
              if (tracks.isNotEmpty)
                lk.VideoTrackRenderer(tracks.first.track as lk.VideoTrack,
                    fit: lk.VideoViewFit.cover)
              else
                Center(
                    child: CircleAvatar(
                        radius: 32,
                        backgroundColor: const Color(0xFF8D78FF),
                        child: Text(
                            participant.name.isEmpty
                                ? '?'
                                : participant.name.characters.first
                                    .toUpperCase(),
                            style: const TextStyle(fontSize: 28)))),
              Positioned(
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        Icon(
                            participant.isMicrophoneEnabled()
                                ? Icons.mic
                                : Icons.mic_off,
                            size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(participant.name,
                                overflow: TextOverflow.ellipsis))
                      ]))),
            ]));
      });
}

class SocialLiveScreen extends StatefulWidget {
  const SocialLiveScreen({super.key});
  @override
  State<SocialLiveScreen> createState() => _SocialLiveScreenState();
}

class _SocialLiveScreenState extends State<SocialLiveScreen> {
  int selected = 0;
  late Future<List> sessions;
  Future<List> load() async => ((await getIt<ApiClient>().dio.get([
            '/realtime/live',
            '/realtime/history',
            '/realtime/recordings'
          ][selected]))
      .data as Map)['items'] as List;
  @override
  void initState() {
    super.initState();
    sessions = load();
  }

  void refresh() => setState(() => sessions = load());
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Live sessions'), actions: [
        IconButton(
            tooltip: 'Refresh',
            onPressed: refresh,
            icon: const Icon(Icons.refresh))
      ]),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              for (final entry in ['Live now', 'Past sessions', 'Recordings']
                  .asMap()
                  .entries)
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                            label: Text(entry.value),
                            selected: selected == entry.key,
                            onSelected: (_) => setState(() {
                                  selected = entry.key;
                                  sessions = load();
                                })))),
            ])),
        Expanded(
            child: FutureBuilder<List>(
                future: sessions,
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return Center(
                        child: TextButton(
                            onPressed: refresh,
                            child: const Text(
                                'Could not load sessions. Try again')));
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  if (snapshot.data!.isEmpty)
                    return Center(
                        child: Text(selected == 0
                            ? 'No one is live right now.'
                            : selected == 1
                                ? 'Ended sessions will appear here.'
                                : 'No recordings available.'));
                  return RefreshIndicator(
                      onRefresh: () async {
                        refresh();
                        await sessions;
                      },
                      child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final item in snapshot.data!)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: selected == 1
                                          ? null
                                          : () async {
                                              if (selected == 0)
                                                await openRealtime(context,
                                                    endpoint:
                                                        '/realtime/live/${item['id']}/join',
                                                    title: item['title'],
                                                    video: item['audio_only'] !=
                                                        true,
                                                    rooms: item['audio_only'] ==
                                                        true);
                                              else
                                                await Navigator.of(context)
                                                    .push(MaterialPageRoute(
                                                        builder: (_) =>
                                                            RecordedSessionScreen(
                                                                item: item)));
                                              if (mounted) refresh();
                                            },
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (selected != 1)
                                              ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  child: AspectRatio(
                                                      aspectRatio: 16 / 9,
                                                      child: Stack(
                                                          fit: StackFit.expand,
                                                          children: [
                                                            if (item[
                                                                    'thumbnail_url'] !=
                                                                null)
                                                              Image.network(
                                                                  AppConfig
                                                                      .mediaUrl(
                                                                          item[
                                                                              'thumbnail_url']),
                                                                  fit: BoxFit
                                                                      .cover,
                                                                  errorBuilder: (_,
                                                                          __,
                                                                          ___) =>
                                                                      const ColoredBox(
                                                                          color: PhlioColors
                                                                              .surface))
                                                            else
                                                              const ColoredBox(
                                                                  color: PhlioColors
                                                                      .surface),
                                                            Center(
                                                                child: Icon(
                                                                    item['audio_only'] ==
                                                                            true
                                                                        ? Icons
                                                                            .mic_none
                                                                        : Icons
                                                                            .play_circle_outline,
                                                                    size: 48,
                                                                    color: Colors
                                                                        .white)),
                                                            Positioned(
                                                                left: 10,
                                                                top: 10,
                                                                child: Container(
                                                                    padding: const EdgeInsets
                                                                        .symmetric(
                                                                        horizontal:
                                                                            8,
                                                                        vertical:
                                                                            4),
                                                                    decoration: BoxDecoration(
                                                                        color: selected == 0
                                                                            ? Colors
                                                                                .red
                                                                            : PhlioColors
                                                                                .brandPurple,
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                                5)),
                                                                    child: Text(
                                                                        selected == 0
                                                                            ? 'LIVE'
                                                                            : 'RECORDED',
                                                                        style: const TextStyle(
                                                                            color: Colors.white,
                                                                            fontWeight: FontWeight.bold,
                                                                            fontSize: 11)))),
                                                          ]))),
                                            const SizedBox(height: 10),
                                            Text(item['title'],
                                                style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            const SizedBox(height: 4),
                                            Text(
                                                '${item['name']}' +
                                                    (selected == 0
                                                        ? ' ? ${item['viewers']} ${item['audio_only'] == true ? 'listening' : 'watching'}'
                                                        : ''),
                                                style: const TextStyle(
                                                    color: PhlioColors
                                                        .textSecondary)),
                                            if (selected == 1)
                                              Text(
                                                  'Ended ? ${item['ended_at'] == null ? '' : DateTime.parse(item['ended_at']).toLocal()}',
                                                  style: const TextStyle(
                                                      color:
                                                          PhlioColors.textMuted,
                                                      fontSize: 12)),
                                            if (selected == 1)
                                              const Text(
                                                  'No replay was recorded',
                                                  style: TextStyle(
                                                      color:
                                                          PhlioColors.textMuted,
                                                      fontSize: 12)),
                                            if (selected == 2)
                                              Text(item['attribution'] ?? '',
                                                  style: const TextStyle(
                                                      color:
                                                          PhlioColors.textMuted,
                                                      fontSize: 11)),
                                          ]))),
                          ]));
                })),
      ]));
}

class RecordedSessionScreen extends StatefulWidget {
  const RecordedSessionScreen({super.key, required this.item});
  final Map item;
  @override
  State<RecordedSessionScreen> createState() => _RecordedSessionScreenState();
}

class _RecordedSessionScreenState extends State<RecordedSessionScreen>
    with WidgetsBindingObserver {
  late final VideoPlayerController player;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    player = VideoPlayerController.networkUrl(
        Uri.parse(AppConfig.mediaUrl(widget.item['media_url'])));
    initialize();
  }

  Future<void> initialize() async {
    try {
      await player.initialize();
      if (mounted) {
        setState(() => error = null);
        await player.play();
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load recording.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) player.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.item['title'])),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (error != null)
          TextButton(onPressed: initialize, child: Text('$error Try again'))
        else if (!player.value.isInitialized)
          const Center(child: CircularProgressIndicator())
        else
          ValueListenableBuilder(
              valueListenable: player,
              builder: (context, value, _) => Column(children: [
                    AspectRatio(
                        aspectRatio: value.aspectRatio,
                        child: VideoPlayer(player)),
                    VideoProgressIndicator(player, allowScrubbing: true),
                    IconButton(
                        tooltip: value.isPlaying ? 'Pause' : 'Play',
                        onPressed: () =>
                            value.isPlaying ? player.pause() : player.play(),
                        icon: Icon(
                            value.isPlaying ? Icons.pause : Icons.play_arrow))
                  ])),
        const SizedBox(height: 16),
        Text(widget.item['title'],
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(widget.item['attribution'] ?? ''),
        Text(widget.item['source_url'] ?? ''),
      ]));
}
