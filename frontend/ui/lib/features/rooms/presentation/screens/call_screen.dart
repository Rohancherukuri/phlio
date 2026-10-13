import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/realtime/realtime_screen.dart';
import '../../data/datasources/messaging_api.dart';
import '../controllers/messaging_controller.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen(
      {required this.callId,
      required this.name,
      required this.video,
      required this.incoming,
      super.key});
  final String callId, name;
  final bool video, incoming;
  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late MessagingApi api;
  Timer? timer;
  bool accepted = false, polling = false;
  String status = 'Calling…';
  @override
  void initState() {
    super.initState();
    api = ref.read(messagingApiProvider);
    Future.microtask(() async {
      if (!mounted) return;
      ref.read(activeCallProvider.notifier).state = true;
      try {
        if (widget.incoming) await api.action(widget.callId, 'accept');
        await poll();
        if (mounted)
          timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
      } catch (_) {
        if (mounted) setState(() => status = 'Could not answer this call.');
      }
    });
  }

  Future<void> poll() async {
    if (polling) return;
    polling = true;
    try {
      final call = await api.call(widget.callId, 0);
      if (!mounted) return;
      if (['ended', 'declined', 'missed'].contains(call['status'])) {
        Navigator.of(context).pop();
      } else if (call['status'] == 'accepted' && !accepted) {
        setState(() => accepted = true);
      }
    } catch (_) {
      if (mounted && !accepted) setState(() => status = 'Reconnecting…');
    } finally {
      polling = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    unawaited(api.action(widget.callId, 'end').catchError((_) {}));
    final active = ref.read(activeCallProvider.notifier);
    Future.microtask(() => active.state = false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => accepted
      ? RealtimeScreen(
          endpoint: '/realtime/calls/${widget.callId}/join',
          title: widget.name,
          video: widget.video)
      : Scaffold(
          appBar: AppBar(title: Text(widget.name)),
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircleAvatar(radius: 48, child: Icon(Icons.person, size: 48)),
            const SizedBox(height: 24),
            Text(status),
            const SizedBox(height: 32),
            FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.call_end),
                label: const Text('Cancel call')),
          ])));
}
