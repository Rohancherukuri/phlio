import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../data/datasources/messaging_api.dart';
import '../controllers/messaging_controller.dart';

class IncomingCallBanner extends ConsumerStatefulWidget {
  const IncomingCallBanner({required this.router, super.key});
  final GoRouter router;
  @override
  ConsumerState<IncomingCallBanner> createState() => _IncomingCallBannerState();
}

class _IncomingCallBannerState extends ConsumerState<IncomingCallBanner> {
  Timer? _timer;
  Map<String, dynamic>? _call;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (!mounted || _busy) return;
    if (ref.read(authControllerProvider).valueOrNull == null ||
        ref.read(activeCallProvider)) {
      if (_call != null) setState(() => _call = null);
      return;
    }
    _busy = true;
    try {
      final calls = await ref.read(messagingApiProvider).incoming();
      if (mounted && !ref.read(activeCallProvider))
        setState(() => _call = calls.isEmpty ? null : calls.first);
    } catch (_) {
      /* A transient poll failure must not interrupt the current page. */
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_call == null ||
        ref.watch(activeCallProvider) ||
        ref.watch(authControllerProvider).valueOrNull == null) {
      return const SizedBox.shrink();
    }
    final call = _call!;
    final name = (call['caller'] as Map)['full_name'] as String;
    return SafeArea(
        child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
                elevation: 12,
                color: PhlioColors.roomsSidebar,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(call['video'] == true
                            ? 'Incoming video call'
                            : 'Incoming voice call'),
                        const SizedBox(height: 12),
                        Wrap(spacing: 12, runSpacing: 8, children: [
                          FilledButton.icon(
                              icon: const Icon(Icons.call),
                              label: const Text('Accept'),
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      ref
                                          .read(activeCallProvider.notifier)
                                          .state = true;
                                      setState(() => _call = null);
                                      try {
                                        await widget.router.push(
                                            '/call/${call['id']}',
                                            extra: {
                                              'name': name,
                                              'video': call['video'],
                                              'incoming': true,
                                            });
                                      } finally {
                                        if (mounted)
                                          ref
                                              .read(activeCallProvider.notifier)
                                              .state = false;
                                      }
                                    }),
                          OutlinedButton.icon(
                              icon: const Icon(Icons.call_end),
                              label: const Text('Decline'),
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      _busy = true;
                                      try {
                                        await ref
                                            .read(messagingApiProvider)
                                            .action(call['id'] as String,
                                                'decline');
                                        if (mounted)
                                          setState(() => _call = null);
                                      } catch (_) {
                                        /* Retain banner so the user can retry. */
                                      } finally {
                                        _busy = false;
                                      }
                                    }),
                        ]),
                      ]),
                )),
          )),
    ));
  }
}
