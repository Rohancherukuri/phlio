import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';

Future<void> openRealtime(BuildContext context,
        {required String endpoint,
        required String title,
        bool rooms = false,
        bool video = true}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
        builder: (_) => RealtimeScreen(
            endpoint: endpoint, title: title, rooms: rooms, video: video)));

/// One SFU connection per screen; adaptive subscriptions and simulcast are
/// managed by LiveKit, including reconnects after a network change.
class RealtimeScreen extends StatefulWidget {
  const RealtimeScreen(
      {required this.endpoint,
      required this.title,
      this.rooms = false,
      this.video = true,
      super.key});
  final String endpoint, title;
  final bool rooms, video;
  @override
  State<RealtimeScreen> createState() => _RealtimeScreenState();
}

class _RealtimeScreenState extends State<RealtimeScreen> {
  lk.Room? room;
  bool connecting = true, publishing = false, host = false, closing = false;
  bool changing = false, front = true;
  String? error, roomName;
  final dio = getIt<ApiClient>().dio;

  @override
  void initState() {
    super.initState();
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
                  ? {'title': widget.title}
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
          if (!didPop) leave();
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF080E16),
          appBar: AppBar(
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
                                  if (participants.length > 1 &&
                                      publishing &&
                                      local != null)
                                    Positioned(
                                        right: 16,
                                        top: 16,
                                        width: 110,
                                        height: 165,
                                        child: _ParticipantTile(local)),
                                  if (roomName?.startsWith('social-') == true)
                                    Positioned(
                                        left: 16,
                                        top: 16,
                                        child: Chip(
                                            backgroundColor:
                                                const Color(0xFFB52E73),
                                            label: Text(
                                                'LIVE · ${room?.remoteParticipants.length ?? 0}',
                                                style: const TextStyle(
                                                    color: Colors.white)))),
                                ]),
          bottomNavigationBar: SafeArea(
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
                              icon: Icon(local?.isMicrophoneEnabled() == true
                                  ? Icons.mic
                                  : Icons.mic_off)),
                          IconButton.filledTonal(
                              tooltip: 'Toggle camera',
                              onPressed: !connected || changing
                                  ? null
                                  : () => change(() => local!.setCameraEnabled(
                                      !local.isCameraEnabled())),
                              icon: Icon(local?.isCameraEnabled() == true
                                  ? Icons.videocam
                                  : Icons.videocam_off)),
                          IconButton.filledTonal(
                              tooltip: 'Switch camera',
                              onPressed: !connected ||
                                      changing ||
                                      local?.isCameraEnabled() != true
                                  ? null
                                  : () => change(() async {
                                        for (final pub
                                            in local!.videoTrackPublications) {
                                          final track = pub.track;
                                          if (track is lk.LocalVideoTrack) {
                                            await track.setCameraPosition(front
                                                ? lk.CameraPosition.back
                                                : lk.CameraPosition.front);
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
  late Future<List> sessions;
  Future<List> load() async =>
      ((await getIt<ApiClient>().dio.get('/realtime/live')).data
          as Map)['items'] as List;
  @override
  void initState() {
    super.initState();
    sessions = load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Live now'), actions: [
        IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(() => sessions = load()),
            icon: const Icon(Icons.refresh)),
      ]),
      body: FutureBuilder<List>(
          future: sessions,
          builder: (_, snapshot) {
            if (snapshot.hasError)
              return const Center(
                  child: Text(
                      'Could not load live sessions. Tap refresh to retry.'));
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            if (snapshot.data!.isEmpty)
              return const Center(
                  child: Text(
                      'No one is live yet. Start a live from the + button.'));
            return ListView(children: [
              for (final live in snapshot.data!)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.live_tv)),
                  title: Text(live['title']),
                  subtitle:
                      Text('${live['name']} · ${live['viewers']} watching'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await openRealtime(context,
                        endpoint: '/realtime/live/${live['id']}/join',
                        title: live['title']);
                    if (mounted) setState(() => sessions = load());
                  },
                )
            ]);
          }));
}
