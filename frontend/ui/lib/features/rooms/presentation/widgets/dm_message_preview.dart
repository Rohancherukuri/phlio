// One DM message drawn the way the chat draws it, for previews (long-press a
// chat in the inbox). Shared posts / clips / videos / products are content
// cards, profiles profile cards, places and live locations map cards,
// payments receipts, Blend and Watch together their cards; photos, videos,
// GIFs, stickers and voice messages show the real attachment.
//
// Mirrors `_DmThreadState._bubble` in dm_thread.dart (without reactions,
// replies or sticker overlays).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../shared/blend/blend.dart';
import '../../../../shared/content/content_surface.dart';
import '../../../../shared/location/location_message.dart';
import '../../../../shared/pay/payment_message.dart';
import '../../../../shared/social/profile_share_card.dart';
import '../../../../shared/watch/watch_together.dart';
import '../../data/datasources/messaging_api.dart';
import '../../domain/entities/room_message_entity.dart';
import 'attachment_preview.dart';
import 'dm_media_album.dart';

class DmMessagePreview extends ConsumerWidget {
  const DmMessagePreview({required this.message, required this.mine, required this.peer, super.key});
  final Map<String, dynamic> message;
  final bool mine;

  /// The other person's username (Watch together cards).
  final String peer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = '${message['text'] ?? ''}';
    final attachments = [
      for (final raw in message['attachments'] as List? ?? const []) Map<String, dynamic>.from(raw as Map),
    ];
    if (attachments.isEmpty) {
      if (blendIdIn(text) case final blend?) return BlendInviteCard(blendId: blend, mine: mine);
      if (isWatchMessage(text)) return WatchChatCard(text: text, w: WatchCtx('dm', peer), compact: true);
      if (parsePaymentMessage(text) case final payment?) return PaymentMessageCard(payment: payment, mine: mine);
      if (sharedProfileName(text) case final profile?) return ProfileShareCard(username: profile, mine: mine);
      if (sharedContentPath(text) case final shared?) {
        final caption = sharedContentCaption(text);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            SharedContentCard(path: shared, mine: mine),
            if (caption.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: mine ? PhlioColors.brandViolet : PhlioColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(caption, style: PhlioTypography.bodyLarge),
              ),
          ],
        );
      }
    }
    final location = parseLocationMessage(text);
    final cardOnly = attachments.isEmpty && location != null;
    return Container(
      padding: attachments.isEmpty && !cardOnly
          ? const EdgeInsets.symmetric(horizontal: 15, vertical: 10)
          : const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: attachments.isNotEmpty || cardOnly
            ? Colors.transparent
            : mine
                ? PhlioColors.brandViolet
                : const Color(0xFF262A33),
        borderRadius: BorderRadius.circular(22),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (location != null)
              locationCard(location, mine: mine, width: 220)
            else if (text.isNotEmpty)
              SharedContentText(text, mine: mine, style: PhlioTypography.body.copyWith(color: Colors.white)),
            if (attachments.isNotEmpty)
              DmMediaAlbum(
                attachments: attachments,
                tileBuilder: (data, height) => Padding(
                  padding: EdgeInsets.only(top: height == null ? 6 : 0),
                  child: AttachmentPreview(
                    key: ValueKey('preview-${data['id']}'),
                    previewHeight: height,
                    mediaOnly: const ['image', 'gif', 'sticker', 'video'].contains(data['kind']),
                    attachment: MessageAttachmentEntity(
                      id: '${data['id']}',
                      kind: '${data['kind']}',
                      name: data['name'] as String? ?? '',
                      size: (data['size'] as num?)?.toInt() ?? 0,
                      mime: data['mime'] as String? ?? '',
                      url: data['url'] as String? ?? '',
                      value: data['value'] as String? ?? '',
                    ),
                    loadPrivateFile: (data['url'] as String? ?? '').isEmpty
                        ? null
                        : () => ref.read(messagingApiProvider).localFile(data['url'] as String),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
