// Discord-style pieces for Phlio Rooms chat (rooms_screen.dart):
//
//   [DiscordReplyPreview]  the little elbow line from the avatar column up to
//                          "@Name the message they replied to"
//   [DiscordText]          message text with @mentions as blue chips
//   [DiscordSystemRow]     "📌 Name pinned a message to this channel.
//                          See all pinned messages."
//   [DiscordCallCard]      "Watching … together · Tap to join" (watch party),
//                          drawn like Discord's ongoing-call card
//   [DiscordReplyBar]      "Replying to Name ✕" above the composer
//   [showDiscordMessageActions]  long-press sheet: quick reactions, Reply,
//                          Pin / Unpin, Copy text, more reactions
//   [showRoomPins]         the pinned-messages sheet

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../shared/watch/watch_together.dart';
import '../../domain/entities/room_message_entity.dart';
import 'rooms_discord.dart' show authorColor, discordTime;

const _mentionBg = Color(0x335865F2);
const _mentionFg = Color(0xFFC9CDFB);

/// Text with Discord's mention chips ("@Alex Smith" on a soft blue).
class DiscordText extends StatelessWidget {
  const DiscordText(this.text, {this.style, super.key});
  final String text;
  final TextStyle? style;

  static final _mention = RegExp(r'@[A-Za-z0-9_.]+');

  @override
  Widget build(BuildContext context) {
    final base = style ?? PhlioTypography.body.copyWith(color: PhlioColors.textPrimary, height: 1.4);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _mention.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(color: _mentionBg, borderRadius: BorderRadius.circular(4)),
          child: Text(m.group(0)!, style: base.copyWith(color: _mentionFg, fontWeight: FontWeight.w600)),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

/// The reply line above a message: ┌─ (avatar) Name  the original text.
class DiscordReplyPreview extends StatelessWidget {
  const DiscordReplyPreview({required this.reply, this.onTap, super.key});
  final Map<String, dynamic> reply;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final author = '${reply['author_name'] ?? ''}';
    final kind = reply['kind'] as String?;
    final text = '${reply['text'] ?? ''}'.trim();
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 18, bottom: 2),
        child: Row(children: [
          // The elbow: down from here into the avatar below.
          const SizedBox(width: 34, height: 18, child: CustomPaint(painter: _Elbow())),
          const SizedBox(width: 4),
          if (reply['author_id'] != null) ...[
            PhlioAvatar(profileId: '${reply['author_id']}', name: author, size: 16, showMomentRing: false),
            const SizedBox(width: 5),
            Text(author,
                style: PhlioTypography.caption.copyWith(
                    fontWeight: FontWeight.w700, color: authorColor('${reply['author_id']}'))),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text.isNotEmpty
                  ? text
                  : kind == null
                      ? 'Original message was deleted'
                      : 'Tap to see attachment',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PhlioTypography.caption.copyWith(
                  color: PhlioColors.textSecondary, fontStyle: text.isEmpty ? FontStyle.italic : FontStyle.normal),
            ),
          ),
          if (text.isEmpty && kind != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.image_outlined, size: 14, color: PhlioColors.textMuted),
          ],
        ]),
      ),
    );
  }
}

class _Elbow extends CustomPainter {
  const _Elbow();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = PhlioColors.textMuted.withValues(alpha: .6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..moveTo(2, size.height)
      ..lineTo(2, size.height / 2 + 6)
      ..quadraticBezierTo(2, size.height / 2, 8, size.height / 2)
      ..lineTo(size.width, size.height / 2);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_Elbow old) => false;
}

/// "Name pinned a message to this channel. See all pinned messages."
class DiscordSystemRow extends StatelessWidget {
  const DiscordSystemRow({required this.message, this.onSeePins, super.key});
  final RoomMessageEntity message;
  final VoidCallback? onSeePins;

  @override
  Widget build(BuildContext context) {
    final pin = message.text.startsWith('phlio-system:pin:');
    final muted = PhlioTypography.body.copyWith(color: PhlioColors.textSecondary, height: 1.4);
    final bold = muted.copyWith(color: PhlioColors.textPrimary, fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 40,
          child: Icon(pin ? Icons.push_pin_rounded : Icons.info_outline_rounded, size: 20, color: PhlioColors.textMuted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: onSeePins,
            child: Text.rich(TextSpan(style: muted, children: [
              TextSpan(text: message.displayName, style: bold),
              if (pin) ...[
                const TextSpan(text: ' pinned '),
                TextSpan(text: 'a message', style: bold),
                const TextSpan(text: ' to this channel. See all '),
                TextSpan(text: 'pinned messages', style: bold),
                const TextSpan(text: '. '),
              ] else
                TextSpan(text: ' ${message.text.split(':').skip(2).join(':')} '),
              TextSpan(text: discordTime(message.createdAt), style: muted.copyWith(fontSize: 11)),
            ])),
          ),
        ),
      ]),
    );
  }
}

/// A watch party in the channel, like Discord's ongoing-call card.
class DiscordCallCard extends StatelessWidget {
  const DiscordCallCard({required this.message, required this.roomId, required this.roomName, super.key});
  final RoomMessageEntity message;
  final String roomId, roomName;

  @override
  Widget build(BuildContext context) {
    final title = message.text.split('\n').first.replaceFirst('🍿 ', '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Material(
        color: PhlioColors.roomsSidebar,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openWatchTogether(context, WatchCtx('room', roomId, title: roomName)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.smart_display_rounded, color: Color(0xFF3DD68C), size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textPrimary)),
                  Text('${message.displayName} · ${discordTime(message.createdAt)} — Tap to join',
                      style: PhlioTypography.caption.copyWith(color: PhlioColors.textSecondary)),
                ]),
              ),
              PhlioAvatar(profileId: message.authorId, name: message.displayName, size: 34, showMomentRing: false),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Replying to Name" with ✕, above the room composer.
class DiscordReplyBar extends StatelessWidget {
  const DiscordReplyBar({required this.message, required this.onCancel, super.key});
  final RoomMessageEntity message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
        color: PhlioColors.roomsSidebar,
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Replying to '),
                TextSpan(
                    text: message.displayName,
                    style: TextStyle(fontWeight: FontWeight.w800, color: authorColor(message.authorId))),
              ]),
              style: PhlioTypography.caption.copyWith(color: PhlioColors.textSecondary),
            ),
          ),
          IconButton(
            tooltip: 'Cancel reply',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.cancel_rounded, size: 20, color: PhlioColors.textMuted),
            onPressed: onCancel,
          ),
        ]),
      );
}

/// Long-press a message: quick reactions, Reply, Pin, Copy.
Future<void> showDiscordMessageActions(
  BuildContext context, {
  required RoomMessageEntity message,
  required void Function(String emoji) onReact,
  required VoidCallback onMoreReactions,
  required VoidCallback onReply,
  required VoidCallback onPin,
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: PhlioColors.roomsSidebar,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final e in const ['👍', '❤️', '😂', '😮', '😢', '🔥'])
                InkResponse(
                  onTap: () {
                    Navigator.pop(sheet);
                    onReact(e);
                  },
                  child: Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: PhlioColors.surfaceElevated, shape: BoxShape.circle),
                    child: Text(e, style: const TextStyle(fontSize: 22)),
                  ),
                ),
              InkResponse(
                onTap: () {
                  Navigator.pop(sheet);
                  onMoreReactions();
                },
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(color: PhlioColors.surfaceElevated, shape: BoxShape.circle),
                  child: const Icon(Icons.add_reaction_outlined),
                ),
              ),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.reply_rounded),
            title: const Text('Reply'),
            onTap: () {
              Navigator.pop(sheet);
              onReply();
            },
          ),
          ListTile(
            leading: Icon(message.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
            title: Text(message.pinned ? 'Unpin message' : 'Pin message'),
            onTap: () {
              Navigator.pop(sheet);
              onPin();
            },
          ),
          if (message.text.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy text'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.text));
                Navigator.pop(sheet);
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Copied message text')));
              },
            ),
        ]),
      ),
    );

/// Pinned messages, newest first.
Future<void> showRoomPins(BuildContext context, String roomId) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: PhlioColors.roomsSidebar,
      builder: (sheet) => SafeArea(
        child: FutureBuilder(
          future: getIt<ApiClient>().dio.get('/rooms/$roomId/pins'),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
            }
            final items = ((snap.data!.data as Map)['items'] as List).cast<Map>();
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
                Row(children: [
                  const Icon(Icons.push_pin_rounded, size: 18, color: PhlioColors.brandLavender),
                  const SizedBox(width: 8),
                  Text('Pinned messages', style: PhlioTypography.title),
                ]),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  Text('Nothing pinned yet. Long-press a message to pin it.',
                      style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted)),
                for (final m in items)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: PhlioColors.surfaceElevated, borderRadius: BorderRadius.circular(12)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (m['author_id'] != null)
                        PhlioAvatar(profileId: '${m['author_id']}', name: '${m['author_name']}', size: 32, showMomentRing: false),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${m['author_name']}',
                              style: PhlioTypography.label.copyWith(
                                  fontWeight: FontWeight.w700, color: authorColor('${m['author_id']}'))),
                          const SizedBox(height: 2),
                          DiscordText('${m['text'] ?? ''}'.isEmpty ? 'Attachment' : '${m['text']}'),
                        ]),
                      ),
                    ]),
                  ),
              ]),
            );
          },
        ),
      ),
    );
