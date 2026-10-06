import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/messaging_api.dart';

final dmConversationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(messagingApiProvider).conversations(),
);

final dmPeerProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, peer) => ref.watch(messagingApiProvider).peer(peer),
);

final dmHistoryProvider =
    StreamProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, peer) async* {
    final api = ref.watch(messagingApiProvider);
    var disposed = false;
    ref.onDispose(() => disposed = true);
    while (!disposed) {
      final messages = await api.messages(peer);
      if (disposed) return;
      yield messages;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  },
);

final activeCallProvider = StateProvider<bool>((ref) => false);
