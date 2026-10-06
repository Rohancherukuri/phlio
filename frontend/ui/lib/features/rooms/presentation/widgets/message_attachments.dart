// Document preview cards + the reaction overlay for room messages.
//
// A message's attachments render as preview cards inside the thread:
//   - images  → rounded visual preview (local file right after picking,
//               network once the upload lands)
//   - documents → branded file card (type-colored icon, name, size) with
//               a tap-through preview sheet
//   - stickers/GIFs → the bundled Foxy asset itself
//
// Reactions (emoji, Foxy stickers, Foxy GIFs) render as floating chips on
// top of the preview cards — put a sticker or GIF on a document, Discord-
// style — and long-press (or the + chip) opens the Foxy picker.

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../app/config/app_config.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/foxy_pack.dart';
import '../../domain/entities/room_message_entity.dart';
import 'attachment_preview.dart';

/// Renders the attachments of one message, with the reaction overlay row
/// docked on the last card. `onReact` toggles a reaction; `reactions`
/// carries the current state from the backend.
class MessageAttachmentView extends StatelessWidget {
  const MessageAttachmentView({
    super.key,
    required this.attachments,
    required this.reactions,
    required this.onReact,
  });

  final List<MessageAttachmentEntity> attachments;
  final List<MessageReactionEntity> reactions;
  final void Function(String kind, String value) onReact;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    // Attachment widths adapt to the pane — the two-pane room layout leaves
    // ~190dp on narrow phones, so fixed card widths would RenderFlex-
    // overflow (a recurring bug class in this codebase).
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < attachments.length; i++)
                  Padding(
                    // Room for the reaction row floating over the bottom edge.
                    padding: EdgeInsets.only(
                      top: PhlioSpacing.sm,
                      bottom:
                          i == attachments.length - 1 && reactions.isNotEmpty
                              ? 18
                              : 0,
                    ),
                    child: _buildCard(context, attachments[i], maxW),
                  ),
              ],
            ),
            if (reactions.isNotEmpty)
              Positioned(
                left: PhlioSpacing.sm,
                bottom: -6,
                child: ReactionChipsRow(
                  reactions: reactions,
                  onReact: onReact,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCard(
      BuildContext context, MessageAttachmentEntity attachment, double maxW) {
    if (attachment.isSticker) {
      final item = FoxyPack.resolve(attachment.value);
      return ClipRRect(
        borderRadius: PhlioRadii.lgRadius,
        child: Image.asset(
          item?.assetPath ?? 'assets/stickers/sticker_foxy_happy.png',
          width: attachment.kind == 'gif' ? 120 : 96,
          height: attachment.kind == 'gif' ? 120 : 96,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => _docCard(context, attachment, maxW),
        ),
      );
    }
    if (attachment.kind == 'video' ||
        attachment.kind == 'audio' ||
        attachment.kind == 'document' ||
        !AttachmentPreviewPolicy.canPreview(attachment.size)) {
      return AttachmentPreview(
          key: ValueKey(attachment.id), attachment: attachment);
    }
    if (attachment.isImage) {
      return _ImagePreviewCard(attachment: attachment, maxW: maxW);
    }
    return _docCard(context, attachment, maxW);
  }

  Widget _docCard(BuildContext context, MessageAttachmentEntity attachment,
          double maxW) =>
      AttachmentPreview(key: ValueKey(attachment.id), attachment: attachment);
}

/// Rounded image preview for `image` attachments; prefers the just-picked
/// local file, falls back to the served upload, degrades to a doc card.
class _ImagePreviewCard extends StatelessWidget {
  const _ImagePreviewCard({required this.attachment, required this.maxW});

  final MessageAttachmentEntity attachment;
  final double maxW;

  @override
  Widget build(BuildContext context) {
    final imgW = (220.0).clamp(0.0, maxW);
    final imgH = imgW * 160 / 220;
    final hasLocal = attachment.localPath != null;
    final hasUrl = attachment.url.isNotEmpty;

    Widget image;
    if (hasLocal) {
      image = Image.file(
        File(attachment.localPath!),
        width: imgW,
        height: imgH,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            hasUrl ? _networkImage(imgW, imgH) : _fallback(imgW, imgH),
      );
    } else if (hasUrl) {
      image = SizedBox(
        width: imgW,
        height: imgH,
        child: _networkImage(imgW, imgH),
      );
    } else {
      image = _fallback(imgW, imgH);
    }

    return GestureDetector(
      onTap: () => _showLightbox(context),
      child: ClipRRect(
        borderRadius: PhlioRadii.mdRadius,
        child: image,
      ),
    );
  }

  Widget _networkImage(double w, double h) {
    final url = AppConfig.mediaUrl(attachment.url);
    return Image.network(
      url,
      width: w,
      height: h,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _fallback(w, h),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _ImageSkeleton(width: w, height: h),
    );
  }

  Widget _fallback(double w, double h) => Container(
        width: w,
        height: h,
        color: PhlioColors.surfaceElevated,
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined,
            size: 28, color: PhlioColors.textMuted),
      );

  void _showLightbox(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, __, ___) => _ImageLightbox(attachment: attachment),
      ),
    );
  }
}

class _ImageSkeleton extends StatelessWidget {
  const _ImageSkeleton({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: PhlioColors.surfaceElevated,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: PhlioColors.brandOrange),
      ),
    );
  }
}

/// Full-screen tap-to-dismiss viewer for image attachments.
class _ImageLightbox extends StatelessWidget {
  const _ImageLightbox({required this.attachment});

  final MessageAttachmentEntity attachment;

  @override
  Widget build(BuildContext context) {
    final Widget hero = attachment.localPath != null
        ? Image.file(File(attachment.localPath!), fit: BoxFit.contain)
        : Image.network(
            AppConfig.mediaUrl(attachment.url),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(48),
              child: Icon(Icons.image_not_supported_outlined,
                  size: 48, color: PhlioColors.textMuted),
            ),
          );
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        alignment: Alignment.center,
        child: InteractiveViewer(maxScale: 4, child: hero),
      ),
    );
  }
}

/// The floating reaction chips over a document card, plus the "+" chip
/// that opens the Foxy picker. Grouped by (kind, value) with counts.
class ReactionChipsRow extends StatelessWidget {
  const ReactionChipsRow(
      {super.key, required this.reactions, required this.onReact});

  final List<MessageReactionEntity> reactions;
  final void Function(String kind, String value) onReact;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, int>{};
    final order = <String>[];
    for (final reaction in reactions) {
      final key = '${reaction.kind}:${reaction.value}';
      if (!grouped.containsKey(key)) order.add(key);
      grouped[key] = (grouped[key] ?? 0) + 1;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: BoxDecoration(
        color: PhlioColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: PhlioColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final key in order) ...[
            _ReactionChip(
              kind: key.split(':').first,
              value: key.split(':').last,
              count: grouped[key]!,
              onTap: () {
                final kind = key.split(':').first;
                final value = key.split(':').last;
                onReact(kind, value);
              },
            ),
            const SizedBox(width: 4),
          ],
          _addChip(context),
        ],
      ),
    );
  }

  Widget _addChip(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final item = await showFoxyPicker(
          context,
          title: 'React with Foxy',
        );
        if (item != null) onReact(item.kind.name, item.id);
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          color: PhlioColors.surfaceElevated,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.add_rounded,
            size: 14, color: PhlioColors.textSecondary),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.kind,
    required this.value,
    required this.count,
    required this.onTap,
  });

  final String kind;
  final String value;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parsedKind = FoxyReactionKind.values.any((k) => k.name == kind)
        ? FoxyReactionKind.values.byName(kind)
        : FoxyReactionKind.emoji;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: PhlioColors.brandOrange.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FoxyReactionChipContent(kind: parsedKind, value: value, size: 15),
            if (count > 1) ...[
              const SizedBox(width: 3),
              Text(
                '$count',
                style: PhlioTypography.caption.copyWith(
                  fontSize: 10,
                  color: PhlioColors.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Long-press target wrapper: opens the Foxy picker on any message row so
/// plain text messages can take reactions too.
Future<void> showReactionPickerAndReact(
  BuildContext context, {
  required void Function(String kind, String value) onReact,
}) async {
  final item = await showFoxyPicker(context, title: 'React with Foxy');
  if (item != null) onReact(item.kind.name, item.id);
}
