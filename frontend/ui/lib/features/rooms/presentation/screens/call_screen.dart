import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../data/datasources/messaging_api.dart';
import '../controllers/messaging_controller.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen(
      {required this.callId,
      required this.name,
      required this.video,
      required this.incoming,
      super.key});
  final String callId;
  final String name;
  final bool video;
  final bool incoming;
  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  final _local = RTCVideoRenderer();
  final _remote = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _stream;
  late final MessagingApi _api;
  late final Future<void> _preparing;
  Timer? _pollTimer;
  Timer? _clock;
  final List<RTCIceCandidate> _pending = [];
  String? _peerId;
  bool _busy = false;
  bool _closing = false;
  bool _finished = false;
  bool _offered = false;
  bool _remoteSet = false;
  bool _muted = false;
  bool _cameraOff = false;
  bool _connected = false;
  bool _renderersReady = false;
  int _cursor = 0;
  int _seconds = 0;
  int _networkFailures = 0;
  String _status = 'Preparing your call…';

  @override
  void initState() {
    super.initState();
    _api = ref.read(messagingApiProvider);
    // Defer provider updates until after the route has finished building.
    Future.microtask(() {
      if (mounted) ref.read(activeCallProvider.notifier).state = true;
    });
    _preparing = _prepare();
  }

  void _assertOpen() {
    if (_closing || _finished) throw StateError('Call closed');
  }

  Future<void> _prepare() async {
    try {
      await Future.wait([_local.initialize(), _remote.initialize()]);
      _renderersReady = true;
      _assertOpen();
      final config = await _api.callConfig();
      _assertOpen();
      _stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true
        },
        'video': widget.video
            ? {'facingMode': 'user', 'width': 1280, 'height': 720}
            : false,
      });
      _assertOpen();
      _local.srcObject = _stream;
      _pc = await createPeerConnection(config);
      _assertOpen();
      _pc!.onIceCandidate = (candidate) {
        if (!_closing &&
            !_finished &&
            candidate.candidate?.isNotEmpty == true) {
          unawaited(_sendSignal('candidate', candidate.toMap()));
        }
      };
      _pc!.onTrack = (event) {
        if (!mounted || _closing || _finished || event.streams.isEmpty) return;
        _remote.srcObject = event.streams.first;
        setState(() {});
      };
      _pc!.onConnectionState = (state) {
        if (!mounted || _closing || _finished) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          setState(() {
            _connected = true;
            _status = 'Connected';
          });
          _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() => _seconds++);
          });
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          setState(() => _status = 'Connection interrupted…');
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          unawaited(
              _finish('Could not connect. Try again on a different network.'));
        }
      };
      for (final track in _stream!.getTracks()) {
        await _pc!.addTrack(track, _stream!);
      }
      _assertOpen();
      if (widget.incoming) await _api.action(widget.callId, 'accept');
      _assertOpen();
      if (mounted)
        setState(() => _status = widget.incoming ? 'Connecting…' : 'Ringing…');
      _pollTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_poll()));
      await _poll();
    } catch (_) {
      if (!_closing)
        await _finish(
            'Could not start the call. Check microphone/camera access and your connection.');
    }
  }

  Future<void> _sendSignal(String kind, Map<String, dynamic> payload) async {
    try {
      await _api.signal(widget.callId, kind, payload);
    } catch (_) {
      if (!_closing && !_finished)
        await _finish('Call connection was interrupted. Please try again.');
    }
  }

  Future<void> _poll() async {
    if (_busy || _closing || _finished) return;
    _busy = true;
    try {
      final call = await _api.call(widget.callId, _cursor);
      if (_closing || _finished) return;
      if (_peerId == null && mounted) {
        setState(() => _peerId =
            call[widget.incoming ? 'caller_id' : 'recipient_id'] as String?);
      }
      _networkFailures = 0;
      final status = call['status'] as String;
      if (['ended', 'declined', 'missed'].contains(status)) {
        await _finish(
            status == 'declined'
                ? 'Call declined'
                : status == 'missed'
                    ? 'No answer'
                    : 'Call ended',
            notify: false);
        return;
      }
      if (status == 'accepted' && !widget.incoming && !_offered) {
        _offered = true;
        if (mounted) setState(() => _status = 'Connecting…');
        final offer = await _pc!.createOffer();
        await _pc!.setLocalDescription(offer);
        await _sendSignal('offer', offer.toMap());
      }
      for (final raw in (call['signals'] as List? ?? [])) {
        if (_closing || _finished) return;
        final signal = raw as Map;
        final payload = Map<String, dynamic>.from(signal['payload'] as Map);
        if (signal['kind'] == 'candidate') {
          final candidate = RTCIceCandidate(
              payload['candidate'] as String?,
              payload['sdpMid'] as String?,
              (payload['sdpMLineIndex'] as num?)?.toInt());
          if (_remoteSet) {
            await _pc!.addCandidate(candidate);
          } else {
            _pending.add(candidate);
          }
        } else {
          await _pc!.setRemoteDescription(RTCSessionDescription(
              payload['sdp'] as String?, payload['type'] as String?));
          _remoteSet = true;
          for (final candidate in _pending) {
            await _pc!.addCandidate(candidate);
          }
          _pending.clear();
          if (signal['kind'] == 'offer') {
            final answer = await _pc!.createAnswer();
            await _pc!.setLocalDescription(answer);
            await _sendSignal('answer', answer.toMap());
          }
        }
        _cursor = signal['seq'] as int;
      }
    } catch (_) {
      if (!_closing && !_finished && ++_networkFailures >= 5)
        await _finish('Connection lost. Please try again.');
    } finally {
      _busy = false;
    }
  }

  Future<void> _release() async {
    _pollTimer?.cancel();
    _clock?.cancel();
    final stream = _stream;
    _stream = null;
    final pc = _pc;
    _pc = null;
    if (_renderersReady) {
      _local.srcObject = null;
      _remote.srcObject = null;
    }
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    }
    await pc?.close();
    await pc?.dispose();
  }

  Future<void> _finish(String status, {bool notify = true}) async {
    if (_finished) return;
    _finished = true;
    if (mounted)
      setState(() {
        _status = status;
        _connected = false;
      });
    await _release();
    if (notify) {
      try {
        await _api.action(widget.callId, 'end');
      } catch (_) {/* Server heartbeat expires abandoned calls. */}
    }
  }

  @override
  void dispose() {
    _closing = true;
    _pollTimer?.cancel();
    _clock?.cancel();
    final active = ref.read(activeCallProvider.notifier);
    Future.microtask(() => active.state = false);
    unawaited(_api.action(widget.callId, 'end').catchError((Object _) {}));
    unawaited(_preparing.then((_) async {
      await _release();
      await _local.dispose();
      await _remote.dispose();
    }));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: PhlioColors.roomsChat,
        appBar: AppBar(
            backgroundColor: PhlioColors.roomsChat,
            title: Text(widget.video ? 'Video call' : 'Voice call')),
        body: SafeArea(
            child: Column(children: [
          Expanded(
              child: Stack(fit: StackFit.expand, children: [
            if (widget.video &&
                _renderersReady &&
                _remote.srcObject != null &&
                !_finished)
              RTCVideoView(_remote,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain)
            else
              Center(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PhlioAvatar(
                              profileId: _peerId, name: widget.name, size: 100),
                          const SizedBox(height: 24),
                          Text(widget.name,
                              textAlign: TextAlign.center,
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 12),
                          Text(_status, textAlign: TextAlign.center),
                        ],
                      ))),
            if (widget.video &&
                _renderersReady &&
                _stream != null &&
                !_cameraOff &&
                !_finished)
              Positioned(
                  right: 16,
                  top: 16,
                  width: 100,
                  height: 140,
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: RTCVideoView(_local, mirror: true))),
          ])),
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(
                    _connected
                        ? '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}'
                        : _status,
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      IconButton.filledTonal(
                          tooltip:
                              _muted ? 'Unmute microphone' : 'Mute microphone',
                          onPressed: _stream == null || _finished
                              ? null
                              : () => setState(() {
                                    _muted = !_muted;
                                    for (final track
                                        in _stream!.getAudioTracks()) {
                                      track.enabled = !_muted;
                                    }
                                  }),
                          icon: Icon(_muted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded)),
                      if (widget.video)
                        IconButton.filledTonal(
                            tooltip: _cameraOff
                                ? 'Turn camera on'
                                : 'Turn camera off',
                            onPressed: _stream == null || _finished
                                ? null
                                : () => setState(() {
                                      _cameraOff = !_cameraOff;
                                      for (final track
                                          in _stream!.getVideoTracks()) {
                                        track.enabled = !_cameraOff;
                                      }
                                    }),
                            icon: Icon(_cameraOff
                                ? Icons.videocam_off_rounded
                                : Icons.videocam_rounded)),
                      IconButton.filled(
                          style: IconButton.styleFrom(
                              backgroundColor: PhlioColors.danger),
                          tooltip: _finished ? 'Close call' : 'Hang up',
                          icon: const Icon(Icons.call_end_rounded),
                          onPressed: () async {
                            await _finish('Call ended');
                            if (context.mounted) Navigator.of(context).pop();
                          }),
                    ]),
              ])),
        ])),
      );
}
