// A live Space — X-style audio room in Phlio's palette.
//
// Host, co-hosts and speakers sit in the top grid with live speaking rings
// (driven by each participant's audio level, smoothed every frame);
// listeners below. Listeners can request to speak (the host approves from
// the people sheet, and the listener's mic button appears), react with
// emoji (they float up the screen and pop over the sender's avatar) and
// leave. Hosts can invite listeners up, move speakers back down and end
// the Space; when "Record Space" was on, a REC pill shows and the
// recording lands in Spaces → Recorded when it ends.
//
// Everything rides on one LiveKit room: roles come from participant
// metadata, speak/approve/reaction messages from the reliable data channel
// (topic "space"), and permission changes from the server.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:share_plus/share_plus.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../../features/profile/presentation/controllers/avatar_controller.dart';
import 'spaces.dart';

const _violet = PhlioColors.brandViolet;
const _peach = PhlioColors.brandPeach;
const _rec = Color(0xFFFF4F79);
const _topic = 'space';
const _reactions = ['❤️', '😂', '👏', '🔥', '💯', '🙌', '😮', '👍'];

/// Opens a Space full-screen with a slide-up transition.
Future<void> openSpace(
  BuildContext context, {
  String? spaceId,
  bool anonymous = false,
  String? scheduledId,
  String title = 'Space',
  List<String> topics = const [],
  bool record = false,
  bool create = false,
}) {
  final String endpoint;
  Map<String, dynamic>? body;
  if (create) {
    endpoint = '/realtime/live';
    body = {
      'title': title,
      'audio_only': true,
      'topics': topics,
      'record': record
    };
  } else if (scheduledId != null) {
    endpoint = '/realtime/spaces/scheduled/$scheduledId/start';
  } else {
    endpoint =
        '/realtime/live/$spaceId/join${anonymous ? '?anonymous=true' : ''}';
  }
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => SpaceRoomScreen(
        endpoint: endpoint,
        body: body,
        title: title,
        topics: topics,
        record: record),
    transitionsBuilder: (_, animation, __, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
            position: Tween(begin: const Offset(0, .12), end: Offset.zero)
                .animate(curved),
            child: child),
      );
    },
  ));
}

class SpaceRoomScreen extends ConsumerStatefulWidget {
  const SpaceRoomScreen({
    required this.endpoint,
    required this.title,
    this.body,
    this.topics = const [],
    this.record = false,
    super.key,
  });
  final String endpoint, title;
  final Map<String, dynamic>? body;
  final List<String> topics;
  final bool record;

  @override
  ConsumerState<SpaceRoomScreen> createState() => _SpaceRoomScreenState();
}

enum _Ask { none, pending }

class _SpaceRoomScreenState extends ConsumerState<SpaceRoomScreen>
    with TickerProviderStateMixin {
  final _dio = getIt<ApiClient>().dio;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  String? _roomName, _hostId, _error, _ended;
  late String _title = widget.title;
  late List<String> _topics = widget.topics;
  late bool _record = widget.record;
  bool _host = false, _anonymous = false, _connecting = true, _closing = false;
  bool _micBusy = false;
  DateTime _startedAt = DateTime.now();
  _Ask _ask = _Ask.none;
  final Map<String, Map> _profiles = {};
  List<Map> _requests = const [];
  Timer? _clock, _profileTimer, _profileDebounce;
  final List<_Flying> _flying = [];
  final Map<String, (String, DateTime)> _badges = {};
  int _flyId = 0;
  String? _toast;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _connect();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _profileTimer?.cancel();
    _profileDebounce?.cancel();
    _toastTimer?.cancel();
    _events?.dispose();
    final room = _room;
    if (room != null) unawaited(room.dispose());
    super.dispose();
  }

  // -- connection ---------------------------------------------------------------

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
      _ended = null;
    });
    _events?.dispose();
    await _room?.dispose();
    _couldSpeak = null;
    final room = lk.Room(
        roomOptions: const lk.RoomOptions(
            defaultAudioCaptureOptions: lk.AudioCaptureOptions(
      noiseSuppression: true,
      echoCancellation: true,
      autoGainControl: true,
      highPassFilter: true,
    )));
    _room = room;
    final events = room.createListener();
    _events = events;
    events
      ..on<lk.ParticipantConnectedEvent>((_) {
        _loadProfilesSoon();
        _changed();
      })
      ..on<lk.ParticipantDisconnectedEvent>((_) => _changed())
      ..on<lk.ActiveSpeakersChangedEvent>((_) => _changed())
      ..on<lk.TrackMutedEvent>((_) => _changed())
      ..on<lk.TrackUnmutedEvent>((_) => _changed())
      ..on<lk.TrackPublishedEvent>((_) => _changed())
      ..on<lk.ParticipantMetadataUpdatedEvent>((_) => _changed())
      ..on<lk.ParticipantPermissionsUpdatedEvent>(_onPermissions)
      ..on<lk.DataReceivedEvent>(_onData)
      ..on<lk.RoomDisconnectedEvent>((event) {
        if (_closing || !mounted) return;
        final reason = event.reason?.name.toLowerCase() ?? '';
        setState(() => _ended = reason.contains('room') ||
                reason.contains('deleted') ||
                reason.contains('removed')
            ? 'ended'
            : 'lost');
      });
    _profileTimer?.cancel();
    try {
      // Reconnecting rejoins the same Space instead of creating a new one.
      final rejoin = _roomName;
      final data = (rejoin != null
              ? await _dio.post(
                  '/realtime/live/$rejoin/join${_anonymous ? '?anonymous=true' : ''}')
              : await _dio.post(widget.endpoint, data: widget.body))
          .data as Map;
      final me = ref.read(authControllerProvider).valueOrNull;
      _roomName = data['room'] as String;
      _host = data['host'] == true;
      _anonymous = data['anonymous'] == true;
      _hostId = data['host_id'] as String? ?? (_host ? me?.id : null);
      _record = data['record'] == true || _record;
      _title = data['title'] as String? ?? _title;
      _topics = ((data['topics'] as List?) ?? _topics).cast<String>();
      _startedAt = DateTime.tryParse(data['started_at'] as String? ?? '')
              ?.toLocal() ??
          DateTime.now();
      await room.connect(data['url'] as String, data['token'] as String);
      if (!mounted || _closing) {
        await room.disconnect();
        return;
      }
      await room.setSpeakerOn(true);
      if (_host) {
        await room.localParticipant?.setMicrophoneEnabled(true);
        unawaited(_loadRequests());
      }
      HapticFeedback.mediumImpact();
      unawaited(_loadProfiles());
      _profileTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        _loadProfiles();
        if (_host) _loadRequests();
      });
    } catch (e) {
      final payload = e is DioException ? e.response?.data : null;
      final message = payload is Map
          ? payload['detail'] ??
              (payload['error'] is Map ? payload['error']['message'] : null)
          : null;
      _error = message?.toString() ??
          'Could not join this Space. Check your connection and microphone permission.';
      await room.disconnect();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  bool? _couldSpeak;

  void _changed() {
    _checkLocalPermissions();
    if (mounted) setState(() {});
  }

  /// Promotion / demotion arrives as a permission change on our own
  /// participant; react once per change.
  void _checkLocalPermissions() {
    final local = _room?.localParticipant;
    if (local == null || _anonymous) return;
    final can = local.permissions.canPublish;
    final could = _couldSpeak;
    _couldSpeak = can;
    if (could == null || could == can || _host) return;
    if (can) {
      _ask = _Ask.none;
      HapticFeedback.heavyImpact();
      _showToast("You're a speaker now — tap the mic when you're ready");
    } else {
      unawaited(local.setMicrophoneEnabled(false));
      _showToast("You're listening again");
    }
  }

  void _loadProfilesSoon() {
    _profileDebounce?.cancel();
    _profileDebounce =
        Timer(const Duration(milliseconds: 700), () => _loadProfiles());
  }

  Future<void> _loadProfiles() async {
    final name = _roomName;
    if (name == null) return;
    try {
      final data =
          (await _dio.get('/realtime/live/$name/participants')).data as Map;
      for (final p in ((data['items'] as List?) ?? const []).whereType<Map>()) {
        _profiles[p['id'].toString()] = p;
      }
      _hostId ??= data['host_id'] as String?;
      _changed();
    } catch (_) {/* keep what we have */}
  }

  Future<void> _loadRequests() async {
    final name = _roomName;
    if (name == null || !_host) return;
    try {
      final data =
          (await _dio.get('/realtime/live/$name/requests')).data as Map;
      _requests = ((data['items'] as List?) ?? const []).whereType<Map>().toList();
      _changed();
    } catch (_) {}
  }

  // -- events ---------------------------------------------------------------------

  void _onPermissions(lk.ParticipantPermissionsUpdatedEvent event) =>
      _changed();

  void _onData(lk.DataReceivedEvent event) {
    if (event.topic != _topic) return;
    Map payload;
    try {
      payload = jsonDecode(utf8.decode(event.data)) as Map;
    } catch (_) {
      return;
    }
    switch (payload['type']) {
      case 'reaction':
        final from = event.participant?.identity;
        _addReaction(payload['emoji'] as String? ?? '❤️', from);
      case 'request':
        if (_host) {
          final user = payload['user'] as Map?;
          HapticFeedback.selectionClick();
          _showToast(
              '${user?['display_name'] ?? 'Someone'} wants to speak');
          unawaited(_loadRequests());
        }
      case 'request_cancelled':
        if (_host) unawaited(_loadRequests());
      case 'declined':
        setState(() => _ask = _Ask.none);
        _showToast('The host passed on your request this time');
      case 'removed':
        _showToast('The host moved you back to listening');
      case 'ended':
        if (mounted) setState(() => _ended = 'ended');
    }
  }

  void _addReaction(String emoji, String? from) {
    if (!mounted) return;
    final id = _flyId++;
    final rand = math.Random(id * 7919);
    setState(() {
      _flying.add(_Flying(id, emoji, rand.nextDouble(), rand.nextDouble()));
      if (from != null) _badges[from] = (emoji, DateTime.now());
    });
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      setState(() {
        _flying.removeWhere((f) => f.id == id);
        final badge = from == null ? null : _badges[from];
        if (badge != null &&
            DateTime.now().difference(badge.$2).inMilliseconds > 2400) {
          _badges.remove(from);
        }
      });
    });
  }

  void _showToast(String text) {
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // -- actions --------------------------------------------------------------------

  Future<void> _react(String emoji) async {
    final local = _room?.localParticipant;
    if (local == null || _anonymous) return;
    HapticFeedback.selectionClick();
    _addReaction(emoji, local.identity);
    try {
      await local.publishData(
          utf8.encode(jsonEncode({'type': 'reaction', 'emoji': emoji})),
          reliable: true,
          topic: _topic);
    } catch (_) {}
  }

  Future<void> _toggleMic() async {
    final local = _room?.localParticipant;
    if (local == null || _micBusy) return;
    setState(() => _micBusy = true);
    try {
      await local.setMicrophoneEnabled(!local.isMicrophoneEnabled());
      HapticFeedback.lightImpact();
    } catch (_) {
      _showToast('Allow microphone access to speak');
    } finally {
      if (mounted) setState(() => _micBusy = false);
    }
  }

  Future<void> _askToSpeak() async {
    final name = _roomName;
    if (name == null) return;
    final cancel = _ask == _Ask.pending;
    setState(() => _ask = cancel ? _Ask.none : _Ask.pending);
    HapticFeedback.selectionClick();
    try {
      if (cancel) {
        await _dio.delete('/realtime/live/$name/requests');
      } else {
        await _dio.post('/realtime/live/$name/requests');
        _showToast('Request sent — the host will bring you up');
      }
    } catch (_) {
      if (mounted) setState(() => _ask = cancel ? _Ask.pending : _Ask.none);
      _showToast('Could not reach the host. Try again.');
    }
  }

  Future<void> _stepDown() async {
    final name = _roomName, me = _room?.localParticipant?.identity;
    if (name == null || me == null) return;
    await _room?.localParticipant?.setMicrophoneEnabled(false);
    try {
      await _dio.delete('/realtime/live/$name/speakers/$me');
    } catch (_) {}
  }

  Future<void> _promote(String userId) async {
    final name = _roomName;
    if (name == null) return;
    try {
      await _dio.post('/realtime/live/$name/speakers/$userId');
      _requests = _requests.where((r) => r['id'] != userId).toList();
      _changed();
    } catch (_) {
      _showToast('They have left the Space');
    }
  }

  Future<void> _decline(String userId) async {
    final name = _roomName;
    if (name == null) return;
    setState(
        () => _requests = _requests.where((r) => r['id'] != userId).toList());
    try {
      await _dio.delete('/realtime/live/$name/requests/$userId');
    } catch (_) {}
  }

  Future<void> _demote(String userId) async {
    final name = _roomName;
    if (name == null) return;
    try {
      await _dio.delete('/realtime/live/$name/speakers/$userId');
    } catch (_) {}
  }

  Future<void> _share() async {
    await SharePlus.instance.share(ShareParams(
        text: 'Join me in "$_title" — a live Space on Phlio Social.'));
  }

  Future<void> _report() async {
    final name = _roomName;
    if (name == null) return;
    try {
      await _dio.post('/realtime/live/$name/report');
      _showToast('Thanks — our team will review this Space');
    } catch (_) {
      _showToast('Could not report. Please try again.');
    }
  }

  Future<void> _leave({bool confirmed = false}) async {
    if (_closing) return;
    if (_host && !confirmed && _ended == null) {
      final end = await _confirmEnd();
      if (end != true) return;
    }
    setState(() => _closing = true);
    final name = _roomName;
    try {
      await _room?.disconnect();
    } catch (_) {}
    if (_host && name != null && _ended == null) {
      try {
        await _dio.delete('/realtime/live/$name');
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool?> _confirmEnd() => showModalBottomSheet<bool>(
        context: context,
        backgroundColor: PhlioColors.surface,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('End this Space?',
                  style: PhlioTypography.headline.copyWith(fontSize: 22)),
              const SizedBox(height: 8),
              Text(
                  _record
                      ? 'Everyone will be removed. Your recording will be ready in Spaces → Recorded in a moment.'
                      : 'Everyone will be removed and the Space will close.',
                  textAlign: TextAlign.center,
                  style: PhlioTypography.body.copyWith(fontSize: 15)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: _rec,
                        shape: const StadiumBorder()),
                    onPressed: () => Navigator.pop(sheet, true),
                    child: const Text('End Space',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800))),
              ),
              const SizedBox(height: 8),
              TextButton(
                  onPressed: () => Navigator.pop(sheet, false),
                  child: const Text('Keep talking')),
            ]),
          ),
        ),
      );

  // -- people -----------------------------------------------------------------------

  String _roleOf(lk.Participant p) {
    if (p.identity == _hostId) return 'Host';
    String? role;
    try {
      role = (jsonDecode(p.metadata ?? '{}') as Map)['role'] as String?;
    } catch (_) {}
    if (!p.permissions.canPublish) return 'Listener';
    return role == 'cohost' ? 'Co-host' : 'Speaker';
  }

  bool _visible(lk.Participant p) =>
      !p.identity.startsWith('anon-') && !p.identity.startsWith('rec-');

  List<lk.Participant> get _everyone {
    final room = _room;
    if (room == null) return const [];
    final list = <lk.Participant>[
      if (room.localParticipant != null && !_anonymous) room.localParticipant!,
      ...room.remoteParticipants.values,
    ];
    return list.where(_visible).toList();
  }

  int get _anonymousCount =>
      (_room?.remoteParticipants.values ?? const <lk.RemoteParticipant>[])
          .where((p) => p.identity.startsWith('anon-'))
          .length +
      (_anonymous ? 1 : 0);

  Map _profile(lk.Participant p) =>
      _profiles[p.identity] ??
      {'id': p.identity, 'display_name': p.name.isEmpty ? 'Guest' : p.name};

  // -- build ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final people = _everyone;
    final order = {'Host': 0, 'Co-host': 1, 'Speaker': 2, 'Listener': 3};
    final speakers = people.where((p) => p.permissions.canPublish).toList()
      ..sort((a, b) => order[_roleOf(a)]!.compareTo(order[_roleOf(b)]!));
    final listeners =
        people.where((p) => !p.permissions.canPublish).toList();
    final local = _room?.localParticipant;
    final canSpeak = !_anonymous && (local?.permissions.canPublish ?? false);
    final connected = _room?.connectionState == lk.ConnectionState.connected;

    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: PhlioColors.backgroundDeep,
        body: Stack(children: [
          const Positioned.fill(child: _Aurora()),
          SafeArea(
            child: Column(children: [
              _header(connected),
              Expanded(
                child: _error != null
                    ? _errorView()
                    : _connecting
                        ? const _Joining()
                        : _body(speakers, listeners),
              ),
              if (!_connecting && _error == null)
                _bottomBar(canSpeak, local, people.length + _anonymousCount),
            ]),
          ),
          // Floating reactions.
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(children: [
                for (final f in _flying) _FlyingEmoji(key: ValueKey(f.id), f: f),
              ]),
            ),
          ),
          // Toast.
          Positioned(
            left: 20,
            right: 20,
            bottom: 120,
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                        position: Tween(
                                begin: const Offset(0, .3), end: Offset.zero)
                            .animate(a),
                        child: child)),
                child: _toast == null
                    ? const SizedBox.shrink()
                    : Center(
                        key: ValueKey(_toast),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          decoration: BoxDecoration(
                            color: PhlioColors.surfaceElevated
                                .withValues(alpha: .96),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: _violet.withValues(alpha: .35)),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: .35),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8))
                            ],
                          ),
                          child: Text(_toast!,
                              textAlign: TextAlign.center,
                              style: PhlioTypography.bodyStrong
                                  .copyWith(fontSize: 14.5)),
                        ),
                      ),
              ),
            ),
          ),
          if (_ended != null)
            Positioned.fill(
                child: _EndedOverlay(
                    lost: _ended == 'lost',
                    record: _record,
                    host: _host,
                    onReconnect: () {
                      _profileTimer?.cancel();
                      _connect();
                    },
                    onClose: () => _leave(confirmed: true))),
        ]),
      ),
    );
  }

  Widget _header(bool connected) {
    final elapsed = DateTime.now().difference(_startedAt);
    final h = elapsed.inHours,
        m = elapsed.inMinutes % 60,
        s = elapsed.inSeconds % 60;
    final clock = h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '$m:${s.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(children: [
        IconButton(
          tooltip: _host ? 'End Space' : 'Leave quietly',
          onPressed: _closing ? null : _leave,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
        ),
        const SizedBox(width: 2),
        if (!_connecting && _error == null) ...[
          const _LiveDot(),
          const SizedBox(width: 6),
          Text(connected ? 'LIVE' : 'RECONNECTING',
              style: PhlioTypography.label.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                  color: connected ? _rec : PhlioColors.warning)),
          const SizedBox(width: 8),
          Text(clock,
              style: PhlioTypography.label.copyWith(
                  color: PhlioColors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          if (_record) ...[const SizedBox(width: 10), const _RecPill()],
        ],
        const Spacer(),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_horiz_rounded, size: 28),
          color: PhlioColors.surfaceElevated,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          position: PopupMenuPosition.under,
          onSelected: (v) {
            if (v == 'share') _share();
            if (v == 'report') _report();
            if (v == 'down') _stepDown();
            if (v == 'end') _leave();
          },
          itemBuilder: (_) => [
            _menuItem('share', Icons.ios_share_rounded, 'Share this Space'),
            if (!_host &&
                (_room?.localParticipant?.permissions.canPublish ?? false))
              _menuItem('down', Icons.mic_off_outlined, 'Go back to listening'),
            if (!_host)
              _menuItem('report', Icons.outlined_flag_rounded,
                  'Report this Space',
                  danger: true),
            if (_host)
              _menuItem('end', Icons.stop_circle_outlined, 'End Space',
                  danger: true),
          ],
        ),
      ]),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
          {bool danger = false}) =>
      PopupMenuItem(
          value: value,
          height: 50,
          child: Row(children: [
            Icon(icon, color: danger ? PhlioColors.danger : null),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    fontSize: 15.5,
                    color: danger ? PhlioColors.danger : null)),
          ]));

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _violet.withValues(alpha: .16)),
              child: const Icon(Icons.wifi_tethering_error_rounded,
                  size: 38, color: _violet),
            ),
            const SizedBox(height: 18),
            Text(_error!,
                textAlign: TextAlign.center,
                style: PhlioTypography.bodyLarge),
            const SizedBox(height: 20),
            SizedBox(
                width: 200,
                child: GradientPillButton(
                    label: 'Try again', onPressed: _connect)),
          ]),
        ),
      );

  Widget _body(List<lk.Participant> speakers, List<lk.Participant> listeners) {
    final anon = _anonymousCount;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title,
                  style: PhlioTypography.displayMedium
                      .copyWith(fontSize: 26, height: 1.18)),
              if (_topics.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in _topics) _TopicChip(t),
                ]),
              ],
              const SizedBox(height: 26),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 14,
                crossAxisSpacing: 6,
                // Fixed height (ring + name + role) so large system font
                // sizes can't overflow the tile.
                mainAxisExtent: 148),
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                final p = speakers[i];
                return _PopIn(
                  key: ValueKey('s-${p.identity}'),
                  delay: i * 60,
                  child: _SpeakerTile(
                    participant: p,
                    profile: _profile(p),
                    role: _roleOf(p),
                    badge: _badges[p.identity],
                    onTap: () => _personSheet(p),
                  ),
                );
              },
              childCount: speakers.length,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 12),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              Text('Listeners',
                  style: PhlioTypography.title.copyWith(fontSize: 16)),
              const SizedBox(width: 8),
              Text('${listeners.length + anon}',
                  style: PhlioTypography.title.copyWith(
                      fontSize: 16, color: PhlioColors.textMuted)),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 40),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 6,
                mainAxisExtent: 100),
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                if (i == listeners.length) return _AnonTile(count: anon);
                final p = listeners[i];
                return _PopIn(
                  key: ValueKey('l-${p.identity}'),
                  delay: math.min(i, 8) * 40,
                  child: _ListenerTile(
                    profile: _profile(p),
                    me: p is lk.LocalParticipant,
                    badge: _badges[p.identity],
                    onTap: () => _personSheet(p),
                  ),
                );
              },
              childCount: listeners.length + (anon > 0 ? 1 : 0),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(bool canSpeak, lk.LocalParticipant? local, int count) {
    final micOn = local?.isMicrophoneEnabled() ?? false;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
      decoration: BoxDecoration(
        color: PhlioColors.surface.withValues(alpha: .92),
        border: Border(
            top: BorderSide(color: PhlioColors.border.withValues(alpha: .6))),
      ),
      child: Row(children: [
        // The primary action shrinks to fit narrow screens / big fonts.
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: canSpeak
                  ? _MicButton(
                      on: micOn,
                      busy: _micBusy,
                      participant: local!,
                      onTap: _toggleMic)
                  : _anonymous
                      ? const _AnonPill()
                      : _RequestButton(
                          pending: _ask == _Ask.pending, onTap: _askToSpeak),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _BarIcon(
          icon: Icons.people_alt_outlined,
          label: '$count',
          badge: _host ? _requests.length : 0,
          onTap: _peopleSheet,
        ),
        if (!_anonymous)
          _BarIcon(
            icon: Icons.favorite_border_rounded,
            onTap: _reactionTray,
            onLongPress: () => _react('❤️'),
          ),
        _BarIcon(icon: Icons.ios_share_rounded, onTap: _share),
        const SizedBox(width: 2),
        TextButton(
          onPressed: _closing ? null : _leave,
          style: TextButton.styleFrom(
              foregroundColor: _rec,
              minimumSize: const Size(48, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: Text(_host ? 'End' : 'Leave',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Future<void> _reactionTray() async {
    final emoji = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Reactions',
      barrierColor: Colors.black.withValues(alpha: .25),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialog, _, __) => SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 86, left: 16, right: 16),
            child: Material(
              color: PhlioColors.surfaceElevated,
              shape: StadiumBorder(
                  side: BorderSide(color: _violet.withValues(alpha: .35))),
              elevation: 12,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < _reactions.length; i++)
                    _PopIn(
                      delay: i * 30,
                      child: InkResponse(
                        radius: 26,
                        onTap: () => Navigator.pop(dialog, _reactions[i]),
                        child: Padding(
                          padding: const EdgeInsets.all(7),
                          child: Text(_reactions[i],
                              style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (_, a, __, child) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
              scale: Tween(begin: .9, end: 1.0).animate(
                  CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
              alignment: Alignment.bottomCenter,
              child: child)),
    );
    if (emoji != null) _react(emoji);
  }

  void _personSheet(lk.Participant p) {
    final profile = _profile(p);
    final role = _roleOf(p);
    final isMe = p is lk.LocalParticipant;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PhlioColors.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Avatar(profile: profile, size: 84),
            const SizedBox(height: 12),
            Text(profile['display_name'] as String? ?? '',
                style: PhlioTypography.headline),
            if (profile['username'] != null)
              Text('@${profile['username']}',
                  style: PhlioTypography.body
                      .copyWith(color: PhlioColors.textMuted)),
            const SizedBox(height: 6),
            Text(isMe ? '$role · you' : role,
                style: PhlioTypography.label.copyWith(color: _violet)),
            const SizedBox(height: 18),
            if (_host && !isMe && role == 'Listener')
              GradientPillButton(
                  label: 'Invite to speak',
                  onPressed: () {
                    Navigator.pop(sheet);
                    _promote(p.identity);
                  }),
            if (_host && !isMe && (role == 'Speaker' || role == 'Co-host'))
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                        side: const BorderSide(color: PhlioColors.border)),
                    onPressed: () {
                      Navigator.pop(sheet);
                      _demote(p.identity);
                    },
                    child: const Text('Move to listeners')),
              ),
          ]),
        ),
      ),
    );
  }

  void _peopleSheet() {
    if (_host) unawaited(_loadRequests());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PhlioColors.surface,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(builder: (context, update) {
        final people = _everyone;
        return FractionallySizedBox(
          heightFactor: .72,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              if (_host) ...[
                _SheetHeader('Requests', _requests.length),
                if (_requests.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                    child: Text(
                        'When listeners ask to speak, they show up here.',
                        style: PhlioTypography.body),
                  ),
                for (final r in _requests)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                    leading: _Avatar(profile: r, size: 44),
                    title: Text(r['display_name'] as String? ?? '',
                        style: PhlioTypography.bodyStrong),
                    subtitle: Text('Wants to speak',
                        style: PhlioTypography.caption
                            .copyWith(color: PhlioColors.textMuted)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          tooltip: 'Not now',
                          onPressed: () {
                            _decline(r['id'].toString());
                            update(() {});
                          },
                          icon: const Icon(Icons.close_rounded)),
                      const SizedBox(width: 4),
                      FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: _violet,
                              foregroundColor: PhlioColors.textOnBrand,
                              shape: const StadiumBorder()),
                          onPressed: () {
                            _promote(r['id'].toString());
                            update(() {});
                          },
                          child: const Text('Bring up',
                              style: TextStyle(fontWeight: FontWeight.w800))),
                    ]),
                  ),
                const SizedBox(height: 8),
              ],
              _SheetHeader('In this Space', people.length + _anonymousCount),
              for (final p in people)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: _Avatar(profile: _profile(p), size: 44),
                  title: Text(
                      (_profile(p)['display_name'] as String? ?? '') +
                          (p is lk.LocalParticipant ? ' (you)' : ''),
                      style: PhlioTypography.bodyStrong),
                  subtitle: Text(_roleOf(p),
                      style: PhlioTypography.caption
                          .copyWith(color: PhlioColors.textMuted)),
                  trailing: p.permissions.canPublish
                      ? Icon(
                          p.isMicrophoneEnabled()
                              ? Icons.mic_rounded
                              : Icons.mic_off_rounded,
                          color: p.isMicrophoneEnabled() ? _violet : _rec,
                          size: 20)
                      : null,
                  onTap: () {
                    Navigator.pop(sheet);
                    _personSheet(p);
                  },
                ),
              if (_anonymousCount > 0)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: const CircleAvatar(
                      radius: 22,
                      backgroundColor: PhlioColors.surfaceElevated,
                      child: Icon(Icons.visibility_off_outlined,
                          color: PhlioColors.textMuted)),
                  title: Text('$_anonymousCount anonymous',
                      style: PhlioTypography.bodyStrong),
                ),
            ],
          ),
        );
      }),
    );
  }
}

// =============================================================================
// Pieces

class _SheetHeader extends StatelessWidget {
  const _SheetHeader(this.title, this.count);
  final String title;
  final int count;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(children: [
          Text(title, style: PhlioTypography.title),
          const SizedBox(width: 8),
          Text('$count',
              style:
                  PhlioTypography.title.copyWith(color: PhlioColors.textMuted)),
        ]),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile, required this.size});
  final Map profile;
  final double size;
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ContentAuthorAvatar(
            author: profile['id'].toString(),
            name: profile['display_name'] as String? ?? '',
            imageUrl: profile['avatar_url'] as String?,
            size: size),
      );
}

class _TopicChip extends StatelessWidget {
  const _TopicChip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: _violet.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _violet.withValues(alpha: .28)),
        ),
        child: Text(label,
            style: PhlioTypography.caption.copyWith(
                color: PhlioColors.textPrimary, fontWeight: FontWeight.w600)),
      );
}

/// Speaker tile: avatar with a live, level-driven ring + ripples.
class _SpeakerTile extends StatefulWidget {
  const _SpeakerTile({
    required this.participant,
    required this.profile,
    required this.role,
    required this.onTap,
    this.badge,
  });
  final lk.Participant participant;
  final Map profile;
  final String role;
  final (String, DateTime)? badge;
  final VoidCallback onTap;
  @override
  State<_SpeakerTile> createState() => _SpeakerTileState();
}

class _SpeakerTileState extends State<_SpeakerTile>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _level = ValueNotifier<double>(0);
  double _t = 0;

  @override
  void initState() {
    super.initState();
    Duration last = Duration.zero;
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - last).inMicroseconds / 1e6;
      last = elapsed;
      _t += dt;
      final p = widget.participant;
      final target = p.isSpeaking && p.isMicrophoneEnabled()
          ? (0.35 + p.audioLevel * 1.6).clamp(0.0, 1.0)
          : 0.0;
      // Fast attack, slower release — reads as a voice, not a flicker.
      final k = target > _level.value ? 14.0 : 5.0;
      final next = _level.value + (target - _level.value) * math.min(1.0, dt * k);
      if ((next - _level.value).abs() > 0.002 || target > 0) _level.value = next;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _level.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.participant;
    final muted = !p.isMicrophoneEnabled();
    final isHost = widget.role == 'Host';
    const size = 66.0;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(children: [
        SizedBox(
          width: size + 22,
          height: size + 22,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Positioned.fill(
              child: CustomPaint(
                  painter: _RingPainter(_level, () => _t, host: isHost)),
            ),
            _Avatar(profile: widget.profile, size: size),
            if (muted)
              Positioned(
                right: 8,
                bottom: 6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                      color: PhlioColors.backgroundDeep,
                      shape: BoxShape.circle,
                      border: Border.all(color: PhlioColors.border)),
                  child: const Icon(Icons.mic_off_rounded, size: 14, color: _rec),
                ),
              ),
            if (widget.badge != null)
              Positioned(top: -6, right: 0, child: _ReactionBadge(widget.badge!)),
          ]),
        ),
        const SizedBox(height: 4),
        Text(widget.profile['display_name'] as String? ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PhlioTypography.bodyStrong.copyWith(fontSize: 13.5)),
        const SizedBox(height: 1),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (isHost) ...[
            ShaderMask(
              shaderCallback: (r) => PhlioColors.sunsetGradient.createShader(r),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 12, color: Colors.white),
            ),
            const SizedBox(width: 3),
          ],
          Text(widget.role,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: PhlioTypography.caption.copyWith(
                  color: isHost ? _peach : PhlioColors.textMuted,
                  fontWeight: isHost ? FontWeight.w700 : null)),
        ]),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.level, this.time, {required this.host})
      : super(repaint: level);
  final ValueNotifier<double> level;
  final double Function() time;
  final bool host;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 11;
    final v = level.value;
    final t = time();
    // Ripples ride outward while they talk.
    if (v > 0.01) {
      for (var i = 0; i < 2; i++) {
        final phase = (t * 1.1 + i * .5) % 1.0;
        final rr = r + 3 + phase * 11 * (0.6 + v);
        canvas.drawCircle(
            c,
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = _violet.withValues(alpha: (1 - phase) * .45 * v));
      }
    }
    final rect = Rect.fromCircle(center: c, radius: r + 3);
    if (v > 0.01 || host) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 + v * 1.4
        ..shader = SweepGradient(
          transform: GradientRotation(t * 1.6),
          colors: const [_violet, PhlioColors.brandPink, _peach, _violet],
        ).createShader(rect);
      canvas.drawCircle(
          c,
          r + 3 + v * 1.5,
          ring
            ..color = Colors.white
                .withValues(alpha: host && v <= 0.01 ? .45 : 1));
      if (host && v <= 0.01) {
        canvas.drawCircle(
            c,
            r + 3,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.6
              ..color = _violet.withValues(alpha: .35));
      }
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.host != host;
}

class _ListenerTile extends StatelessWidget {
  const _ListenerTile(
      {required this.profile, required this.onTap, this.me = false, this.badge});
  final Map profile;
  final bool me;
  final (String, DateTime)? badge;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: me
                  ? const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: PhlioColors.sunsetGradient)
                  : null,
              child: _Avatar(profile: profile, size: 52),
            ),
            if (badge != null)
              Positioned(top: -8, right: -8, child: _ReactionBadge(badge!)),
          ]),
          const SizedBox(height: 6),
          Text(me ? 'You' : (profile['display_name'] as String? ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PhlioTypography.caption.copyWith(
                  color: PhlioColors.textPrimary,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

class _AnonTile extends StatelessWidget {
  const _AnonTile({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
              color: PhlioColors.surfaceElevated, shape: BoxShape.circle),
          child: const Icon(Icons.visibility_off_outlined,
              color: PhlioColors.textMuted, size: 22),
        ),
        const SizedBox(height: 6),
        Text('+$count anon',
            style: PhlioTypography.caption
                .copyWith(color: PhlioColors.textMuted)),
      ]);
}

class _ReactionBadge extends StatelessWidget {
  const _ReactionBadge(this.badge);
  final (String, DateTime) badge;
  String get emoji => badge.$1;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey('${badge.$1}${badge.$2.millisecondsSinceEpoch}'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.elasticOut,
        builder: (_, v, child) => Transform.scale(scale: v, child: child),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: PhlioColors.surfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(color: _violet.withValues(alpha: .4)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .3), blurRadius: 8)
            ],
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 16)),
        ),
      );
}

/// Staggered scale + fade entrance.
class _PopIn extends StatelessWidget {
  const _PopIn({required this.child, this.delay = 0, super.key});
  final Widget child;
  final int delay;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 420 + delay),
        curve: Interval(delay / (420 + delay), 1, curve: Curves.easeOutBack),
        builder: (_, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(scale: .6 + .4 * v, child: child),
        ),
        child: child,
      );
}

class _Flying {
  _Flying(this.id, this.emoji, this.x, this.sway);
  final int id;
  final String emoji;
  final double x, sway;
}

class _FlyingEmoji extends StatelessWidget {
  const _FlyingEmoji({required this.f, super.key});
  final _Flying f;
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 2500),
      builder: (_, t, child) {
        final rise = Curves.easeOutCubic.transform(t);
        final x = size.width * (0.55 + 0.32 * f.x) +
            math.sin(t * math.pi * (2 + f.sway * 2)) * 18;
        final y = size.height - 120 - rise * size.height * 0.48;
        final scale = t < .15
            ? Curves.easeOutBack.transform(t / .15) * 1.15
            : 1.15 - 0.15 * ((t - .15) / .85);
        final opacity = t > .7 ? 1 - (t - .7) / .3 : 1.0;
        return Positioned(
          left: x - 20,
          top: y,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: Text(f.emoji, style: const TextStyle(fontSize: 34)),
    );
  }
}

class _MicButton extends StatefulWidget {
  const _MicButton(
      {required this.on,
      required this.busy,
      required this.participant,
      required this.onTap});
  final bool on, busy;
  final lk.Participant participant;
  final VoidCallback onTap;
  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _level = ValueNotifier<double>(0);
  double _t = 0;
  @override
  void initState() {
    super.initState();
    Duration last = Duration.zero;
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - last).inMicroseconds / 1e6;
      last = elapsed;
      _t += dt;
      final target = widget.on
          ? (widget.participant.audioLevel * 2.2).clamp(0.0, 1.0)
          : 0.0;
      final k = target > _level.value ? 16.0 : 5.0;
      _level.value += (target - _level.value) * math.min(1.0, dt * k);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _level.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.on ? 'Mute microphone' : 'Unmute microphone',
        child: GestureDetector(
          onTap: widget.busy ? null : widget.onTap,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(
                  child: CustomPaint(
                      painter:
                          _RingPainter(_level, () => _t, host: false))),
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: widget.on ? PhlioColors.sunsetGradient : null,
                  color: widget.on ? null : PhlioColors.surfaceElevated,
                  border: widget.on
                      ? null
                      : Border.all(color: PhlioColors.border),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (c, a) =>
                      ScaleTransition(scale: a, child: c),
                  child: Icon(
                    widget.on ? Icons.mic_rounded : Icons.mic_off_rounded,
                    key: ValueKey(widget.on),
                    color: widget.on ? PhlioColors.textOnBrand : _rec,
                    size: 26,
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _RequestButton extends StatefulWidget {
  const _RequestButton({required this.pending, required this.onTap});
  final bool pending;
  final VoidCallback onTap;
  @override
  State<_RequestButton> createState() => _RequestButtonState();
}

class _RequestButtonState extends State<_RequestButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didUpdateWidget(_RequestButton old) {
    super.didUpdateWidget(old);
    if (widget.pending && !_wave.isAnimating) _wave.repeat();
    if (!widget.pending) _wave.stop();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        color: widget.pending
            ? _violet.withValues(alpha: .18)
            : PhlioColors.surfaceElevated,
        shape: StadiumBorder(
            side: BorderSide(
                color: widget.pending
                    ? _violet.withValues(alpha: .6)
                    : PhlioColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedBuilder(
                animation: _wave,
                builder: (_, child) => Transform.rotate(
                  angle: widget.pending
                      ? math.sin(_wave.value * math.pi * 2) * .35
                      : 0,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
                child: const Icon(Icons.back_hand_outlined,
                    size: 20, color: _peach),
              ),
              const SizedBox(width: 8),
              Text(widget.pending ? 'Requested' : 'Request',
                  style: PhlioTypography.bodyStrong.copyWith(fontSize: 15)),
            ]),
          ),
        ),
      );
}

class _AnonPill extends StatelessWidget {
  const _AnonPill();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: PhlioColors.surfaceElevated,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.visibility_off_outlined,
              size: 18, color: PhlioColors.textMuted),
          const SizedBox(width: 8),
          Text('Anonymous',
              style: PhlioTypography.label
                  .copyWith(color: PhlioColors.textSecondary)),
        ]),
      );
}

class _BarIcon extends StatelessWidget {
  const _BarIcon(
      {required this.icon,
      required this.onTap,
      this.label,
      this.badge = 0,
      this.onLongPress});
  final IconData icon;
  final String? label;
  final int badge;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: onTap,
        onLongPress: onLongPress,
        radius: 26,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Stack(clipBehavior: Clip.none, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 24, color: PhlioColors.textPrimary),
              if (label != null) ...[
                const SizedBox(width: 4),
                Text(label!,
                    style: PhlioTypography.label.copyWith(
                        color: PhlioColors.textSecondary,
                        fontWeight: FontWeight.w700)),
              ],
            ]),
            if (badge > 0)
              Positioned(
                right: -8,
                top: -6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: _rec, borderRadius: BorderRadius.circular(99)),
                  child: Text('$badge',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
        ),
      );
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => SizedBox(
          width: 14,
          height: 14,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 6 + 8 * _c.value,
              height: 6 + 8 * _c.value,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _rec.withValues(alpha: .45 * (1 - _c.value))),
            ),
            Container(
                width: 7,
                height: 7,
                decoration:
                    const BoxDecoration(color: _rec, shape: BoxShape.circle)),
          ]),
        ),
      );
}

class _RecPill extends StatelessWidget {
  const _RecPill();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _rec.withValues(alpha: .6)),
        ),
        child: Text('REC',
            style: PhlioTypography.caption.copyWith(
                color: _rec, fontWeight: FontWeight.w800, letterSpacing: .6)),
      );
}

class _Joining extends StatelessWidget {
  const _Joining();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SpaceEqualiser(height: 34, bars: 5),
          const SizedBox(height: 18),
          Text('Tuning in…',
              style: PhlioTypography.title
                  .copyWith(color: PhlioColors.textSecondary)),
        ]),
      );
}

class _EndedOverlay extends StatelessWidget {
  const _EndedOverlay(
      {required this.lost,
      required this.record,
      required this.host,
      required this.onReconnect,
      required this.onClose});
  final bool lost, record, host;
  final VoidCallback onReconnect, onClose;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        builder: (_, v, child) => Container(
          color: PhlioColors.backgroundDeep.withValues(alpha: .82 * v),
          child: Opacity(
              opacity: v,
              child: Transform.translate(
                  offset: Offset(0, 24 * (1 - v)), child: child)),
        ),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(28),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            decoration: BoxDecoration(
              color: PhlioColors.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _violet.withValues(alpha: .3)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: PhlioColors.sunsetGradient),
                child: Icon(
                    lost ? Icons.wifi_off_rounded : Icons.graphic_eq_rounded,
                    size: 34,
                    color: PhlioColors.textOnBrand),
              ),
              const SizedBox(height: 16),
              Text(lost ? 'Connection lost' : 'This Space has ended',
                  style: PhlioTypography.headline.copyWith(fontSize: 22)),
              const SizedBox(height: 8),
              Text(
                lost
                    ? 'We lost the audio connection. You can jump back in.'
                    : record
                        ? 'It was recorded — find it in Spaces → Recorded in a moment.'
                        : 'Thanks for tuning in.',
                textAlign: TextAlign.center,
                style: PhlioTypography.body.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 22),
              if (lost) ...[
                GradientPillButton(label: 'Reconnect', onPressed: onReconnect),
                const SizedBox(height: 6),
              ],
              lost
                  ? TextButton(onPressed: onClose, child: const Text('Leave'))
                  : GradientPillButton(label: 'Done', onPressed: onClose),
            ]),
          ),
        ),
      );
}

/// Slow, soft colour fields drifting behind the room.
class _Aurora extends StatefulWidget {
  const _Aurora();
  @override
  State<_Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<_Aurora> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 18))
        ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _AuroraPainter(_c)),
      );
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t) : super(repaint: t);
  final Animation<double> t;
  @override
  void paint(Canvas canvas, Size size) {
    final a = t.value * 2 * math.pi;
    void blob(Offset c, double r, Color color) {
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              color,
              color.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: c, radius: r)));
    }

    blob(
        Offset(size.width * (.2 + .08 * math.sin(a)),
            size.height * (.08 + .04 * math.cos(a))),
        size.width * .75,
        _violet.withValues(alpha: .20));
    blob(
        Offset(size.width * (.95 + .06 * math.cos(a * 1.3)),
            size.height * (.22 + .05 * math.sin(a * .7))),
        size.width * .6,
        PhlioColors.brandPink.withValues(alpha: .10));
    blob(
        Offset(size.width * (.5 + .1 * math.sin(a * .6)),
            size.height * (.9 + .03 * math.cos(a))),
        size.width * .8,
        _peach.withValues(alpha: .07));
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => false;
}
