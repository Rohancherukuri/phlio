// Attachments in the Foxy (Agent) chat: the "+" sheet that picks photos,
// clips, audio and documents, the tray of pending files above the
// composer (upload progress, remove), and how sent files render in the
// user's bubble.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../domain/entities/agent_attachment_entity.dart';

/// Upload caps per kind (mirror the backend's `LIMITS`).
const agentAttachmentLimits = {
  AgentAttachmentKind.image: 10 * 1000 * 1000,
  AgentAttachmentKind.video: 100 * 1000 * 1000,
  AgentAttachmentKind.audio: 25 * 1000 * 1000,
  AgentAttachmentKind.document: 20 * 1000 * 1000,
  AgentAttachmentKind.text: 2 * 1000 * 1000,
};

const maxAgentAttachments = 10;

IconData agentAttachmentIcon(AgentAttachmentKind kind, String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (kind) {
    AgentAttachmentKind.image => Icons.image_outlined,
    AgentAttachmentKind.video => Icons.movie_outlined,
    AgentAttachmentKind.audio => Icons.graphic_eq_rounded,
    AgentAttachmentKind.text => ext == 'csv' ? Icons.table_rows_outlined : Icons.notes_rounded,
    AgentAttachmentKind.document => switch (ext) {
        'pdf' => Icons.picture_as_pdf_outlined,
        'xlsx' => Icons.grid_on_rounded,
        'pptx' => Icons.slideshow_outlined,
        _ => Icons.description_outlined,
      },
  };
}

Color agentAttachmentTint(AgentAttachmentKind kind, String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (kind) {
    AgentAttachmentKind.image => const Color(0xFF7FB8FF),
    AgentAttachmentKind.video => const Color(0xFFB794FF),
    AgentAttachmentKind.audio => const Color(0xFF6FD6B5),
    AgentAttachmentKind.text => const Color(0xFFC4C8D2),
    AgentAttachmentKind.document => switch (ext) {
        'pdf' => const Color(0xFFFF8A80),
        'xlsx' => const Color(0xFF7AD99A),
        'pptx' => const Color(0xFFFFB074),
        _ => const Color(0xFF8AB4FF),
      },
  };
}

// ---------------------------------------------------------------------------
// Picker sheet

enum _Source { newChat, camera, photos, recordClip, videos, documents, text, audio }

/// Shows the "+" sheet: start a new chat, or add photos, clips, audio and
/// documents. Returns the picked local file paths.
Future<List<String>> showAgentAttachSheet(
  BuildContext context, {
  int max = maxAgentAttachments,
  VoidCallback? onNewChat,
}) async {
  final source = await showModalBottomSheet<_Source>(
    context: context,
    backgroundColor: PhlioColors.surfaceElevated,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => _AttachSheet(showNewChat: onNewChat != null, canAttach: max > 0),
  );
  if (source == null) return const [];
  if (source == _Source.newChat) {
    onNewChat?.call();
    return const [];
  }
  if (max <= 0) return const [];
  try {
    final picker = ImagePicker();
    switch (source) {
      case _Source.camera:
        final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 2560);
        return [if (x != null) x.path];
      case _Source.photos:
        final xs = await picker.pickMultiImage(imageQuality: 90, maxWidth: 2560, limit: max > 1 ? max : null);
        return [for (final x in xs.take(max)) x.path];
      case _Source.recordClip:
        final x = await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 2));
        return [if (x != null) x.path];
      case _Source.videos:
        return _files(FileType.custom, agentVideoExtensions, max);
      case _Source.documents:
        return _files(FileType.custom, agentDocumentExtensions, max);
      case _Source.text:
        return _files(FileType.custom, agentTextExtensions, max);
      case _Source.audio:
        return _files(FileType.custom, agentAudioExtensions, max);
      case _Source.newChat:
        return const [];
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Couldn\'t open that. Check the app\'s camera and storage permissions.')));
    }
    return const [];
  }
}

Future<List<String>> _files(FileType type, List<String> extensions, int max) async {
  final picked = await FilePicker.pickFiles(
    type: type,
    allowedExtensions: extensions,
    allowMultiple: max > 1,
  );
  if (picked == null) return const [];
  return [for (final f in picked.files.take(max)) if (f.path != null) f.path!];
}

class _AttachSheet extends StatelessWidget {
  const _AttachSheet({required this.showNewChat, required this.canAttach});

  final bool showNewChat;
  final bool canAttach;

  @override
  Widget build(BuildContext context) {
    const options = [
      (_Source.photos, Icons.photo_library_outlined, 'Photos', Color(0xFF7FB8FF)),
      (_Source.recordClip, Icons.videocam_outlined, 'Record clip', Color(0xFFFF8FB1)),
      (_Source.videos, Icons.video_library_outlined, 'Videos', Color(0xFFB794FF)),
      (_Source.documents, Icons.picture_as_pdf_outlined, 'Documents', Color(0xFFFF8A80)),
      (_Source.text, Icons.notes_rounded, 'Text & CSV', Color(0xFFC4C8D2)),
      (_Source.audio, Icons.graphic_eq_rounded, 'Audio', Color(0xFF6FD6B5)),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(PhlioSpacing.lg, 0, PhlioSpacing.lg, PhlioSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showNewChat) ...[
              InkWell(
                borderRadius: PhlioRadii.lgRadius,
                onTap: () => Navigator.pop(context, _Source.newChat),
                child: Container(
                  padding: const EdgeInsets.all(PhlioSpacing.md),
                  decoration: BoxDecoration(
                    borderRadius: PhlioRadii.lgRadius,
                    gradient: LinearGradient(colors: [
                      PhlioColors.brandOrange.withValues(alpha: 0.16),
                      PhlioColors.brandViolet.withValues(alpha: 0.12),
                    ]),
                    border: Border.all(color: PhlioColors.brandOrange.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, gradient: PhlioColors.brandGradient),
                        child: const Icon(Icons.add_comment_outlined,
                            color: PhlioColors.textOnBrand, size: 22),
                      ),
                      const SizedBox(width: PhlioSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Start a new chat',
                                style: PhlioTypography.body.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('Fresh conversation with Foxy — this one stays in your chats.',
                                style: PhlioTypography.caption
                                    .copyWith(color: PhlioColors.textSecondary)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: PhlioColors.textMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: PhlioSpacing.lg),
            ],
            Text('Add to chat', style: PhlioTypography.title),
            const SizedBox(height: 4),
            Text('Foxy can read photos, clips, audio, PDFs, Word, Excel, PowerPoint and text files.',
                style: PhlioTypography.caption.copyWith(color: PhlioColors.textSecondary)),
            const SizedBox(height: PhlioSpacing.lg),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: PhlioSpacing.md,
              crossAxisSpacing: PhlioSpacing.sm,
              childAspectRatio: 0.82,
              children: [
                for (final (source, icon, label, tint) in options)
                  InkWell(
                    borderRadius: PhlioRadii.lgRadius,
                    onTap: canAttach ? () => Navigator.pop(context, source) : null,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: tint.withValues(alpha: 0.16),
                            border: Border.all(color: tint.withValues(alpha: 0.35)),
                          ),
                          child: Icon(icon, color: tint, size: 26),
                        ),
                        const SizedBox(height: 8),
                        Text(label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PhlioTypography.caption.copyWith(color: PhlioColors.textPrimary)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending tray

/// A picked file on its way to `/agent/files`.
class AgentPendingAttachment {
  AgentPendingAttachment(this.path)
      : name = path.split(RegExp(r'[\\/]')).last,
        kind = agentAttachmentKindOf(path.split(RegExp(r'[\\/]')).last);

  final String path;
  final String name;
  final AgentAttachmentKind kind;
  double progress = 0;
  AgentAttachmentEntity? uploaded;
  String? error;

  bool get uploading => uploaded == null && error == null;
}

class AgentPendingTray extends StatelessWidget {
  const AgentPendingTray({super.key, required this.items, required this.onRemove, required this.onRetry});

  final List<AgentPendingAttachment> items;
  final void Function(AgentPendingAttachment item) onRemove;
  final void Function(AgentPendingAttachment item) onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PhlioSpacing.lg),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: PhlioSpacing.sm),
        itemBuilder: (context, i) => _PendingChip(
          item: items[i],
          onRemove: () => onRemove(items[i]),
          onRetry: () => onRetry(items[i]),
        ),
      ),
    );
  }
}

class _PendingChip extends StatelessWidget {
  const _PendingChip({required this.item, required this.onRemove, required this.onRetry});

  final AgentPendingAttachment item;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isImage = item.kind == AgentAttachmentKind.image;
    final tint = agentAttachmentTint(item.kind, item.name);
    Widget body;
    if (isImage) {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(File(item.path), width: 68, height: 68, fit: BoxFit.cover,
            cacheWidth: 200,
            errorBuilder: (_, __, ___) => _FileTile(item.kind, item.name, tint, width: 68)),
      );
    } else {
      body = Container(
        width: 172,
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: PhlioColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: PhlioColors.borderSubtle),
        ),
        child: Row(
          children: [
            _FileTile(item.kind, item.name, tint, width: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhlioTypography.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text(
                    item.error != null
                        ? 'Tap to retry'
                        : item.uploaded != null
                            ? formatAgentFileSize(item.uploaded!.size)
                            : 'Uploading…',
                    style: PhlioTypography.caption.copyWith(
                        color: item.error != null ? PhlioColors.danger : PhlioColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: item.error != null ? onRetry : null,
      child: SizedBox(
        width: isImage ? 76 : 180,
        height: 76,
        child: Stack(
          children: [
            Positioned(left: 0, bottom: 0, child: body),
            if (item.uploading)
              Positioned(
                left: 0,
                bottom: 0,
                width: isImage ? 68 : 172,
                height: 68,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: isImage ? 0.35 : 0.0),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Align(
                    alignment: isImage ? Alignment.center : const Alignment(0.86, 0),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        value: item.progress > 0.02 && item.progress < 0.99 ? item.progress : null,
                        color: PhlioColors.brandOrange,
                      ),
                    ),
                  ),
                ),
              ),
            if (item.error != null && isImage)
              const Positioned(
                left: 0,
                bottom: 0,
                width: 68,
                height: 68,
                child: Icon(Icons.refresh_rounded, color: Colors.white),
              ),
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: PhlioColors.surfaceInput,
                    shape: BoxShape.circle,
                    border: Border.all(color: PhlioColors.border),
                  ),
                  child: const Icon(Icons.close_rounded, size: 14, color: PhlioColors.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile(this.kind, this.name, this.tint, {required this.width});

  final AgentAttachmentKind kind;
  final String name;
  final Color tint;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ext = name.contains('.') ? name.split('.').last.toUpperCase() : '';
    return Container(
      width: width,
      height: width,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(agentAttachmentIcon(kind, name), color: tint, size: width * 0.46),
          if (width >= 40 && ext.isNotEmpty && ext.length <= 4)
            Text(ext, style: TextStyle(color: tint, fontSize: 8.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// In the transcript

/// Files the user sent, shown above their message text.
class AgentAttachmentsView extends StatelessWidget {
  const AgentAttachmentsView({super.key, required this.attachments});

  final List<AgentAttachmentEntity> attachments;

  @override
  Widget build(BuildContext context) {
    final images = attachments.where((a) => a.kind == AgentAttachmentKind.image).toList();
    final files = attachments.where((a) => a.kind != AgentAttachmentKind.image).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (images.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in images)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: a.localPath != null
                      ? Image.file(File(a.localPath!),
                          width: images.length == 1 ? 200 : 96,
                          height: images.length == 1 ? 200 : 96,
                          fit: BoxFit.cover,
                          cacheWidth: 400,
                          errorBuilder: (_, __, ___) =>
                              _FileTile(a.kind, a.name, agentAttachmentTint(a.kind, a.name), width: 96))
                      : _FileTile(a.kind, a.name, agentAttachmentTint(a.kind, a.name), width: 96),
                ),
            ],
          ),
        for (final a in files)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 260),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: PhlioColors.surfaceElevated,
                borderRadius: PhlioRadii.lgRadius,
                border: Border.all(color: PhlioColors.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FileTile(a.kind, a.name, agentAttachmentTint(a.kind, a.name), width: 42),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PhlioTypography.body.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            a.extension,
                            formatAgentFileSize(a.size),
                            if (a.pages != null) '${a.pages} pages',
                          ].join(' · '),
                          style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
