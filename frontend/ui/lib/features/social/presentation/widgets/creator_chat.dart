import 'package:flutter/material.dart';
import '../../../../design_system/colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../design_system/widgets/foxy_pack.dart';
import '../../../rooms/data/datasources/messaging_api.dart';
import '../../../rooms/presentation/widgets/chat_composer.dart';
import '../../../rooms/presentation/widgets/chat_policy.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';

final creatorChatProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, creator) async* {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  final api = ref.watch(messagingApiProvider);
  var disposed = false;
  ref.onDispose(() => disposed = true);
  while (!disposed) {
    final messages = await api.creatorChat(creator);
    if (disposed) return;
    yield messages;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
});

class CreatorChat extends StatelessWidget {
  const CreatorChat({required this.username, super.key});
  final String username;
  @override
  Widget build(BuildContext context) => Consumer(
        builder: (context, ref, _) {
          Future<void> send(
            String text,
            List<Map<String, dynamic>> attachments,
          ) async {
            await ref
                .read(messagingApiProvider)
                .sendCreatorChat(username, text, attachments);
            if (context.mounted) ref.invalidate(creatorChatProvider(username));
          }

          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.forum_outlined, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text('Public chat • Text, GIFs & stickers')),
                  ],
                ),
              ),
              Expanded(
                child: ref.watch(creatorChatProvider(username)).when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) => Center(
                        child: TextButton(
                          onPressed: () =>
                              ref.invalidate(creatorChatProvider(username)),
                          child: const Text('Could not load chat. Retry'),
                        ),
                      ),
                      data: (messages) => messages.isEmpty
                          ? const Center(
                              child: Text(
                                'Welcome to chat! Say hello to the community.',
                              ),
                            )
                          : ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.all(12),
                              itemCount: messages.length,
                              itemBuilder: (_, index) {
                                final message =
                                    messages[messages.length - 1 - index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: '${message['username']}: ',
                                              style: const TextStyle(
                                                color: PhlioColors.brandPurple,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            TextSpan(
                                              text: message['text'] as String,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Wrap(
                                        spacing: 6,
                                        children: [
                                          for (final item
                                              in message['attachments'] as List)
                                            if (FoxyPack.resolve(
                                                  item['value'] as String,
                                                ) !=
                                                null)
                                              Image.asset(
                                                FoxyPack.resolve(
                                                  item['value'] as String,
                                                )!
                                                    .assetPath,
                                                width: 70,
                                                height: 70,
                                              ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
              ),
              ChatComposer(
                audience: ChatAudience.publicChat,
                compact: true,
                hint: 'Send a chat message',
                onSendText: (text) => send(text, []),
                onSendVoice: (_, __) async {},
                onSendFiles: (files, text) => send(text, [
                  for (final f in files)
                    {'kind': f.kind, 'name': f.name, 'value': f.packId},
                ]),
              ),
            ],
          );
        },
      );
}
