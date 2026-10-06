// Chat composer with the full messaging toolkit, matching the reference
// Discord-style composer:
//
//   [+] plain plus (no circle) — attach multiple documents, any size
//   [ text field "Message @user" ]
//   [😊] Foxy tray (unicode + emoji/stickers/GIFs)  [🎤] voice message
//
// Attachments are multi-picked by path (file_picker withData:false — Dio
// streams the upload later, so documents of large size work without
// ballooning memory). Stickers and GIFs come from the bundled Foxy pack
// and ride as pack attachments — no bytes, just the pack value id.
//
// Sending is pluggable: the caller receives text / files / voice events.
// Rooms uploads the files then posts the message; DMs keep the local
// paths for preview until a backend DM domain exists.

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/foxy_pack.dart';
import '../../domain/entities/room_message_entity.dart';
import 'attachment_preview.dart';

/// Telegram/Slack-style supported attachment set (blueprint section 8:
/// Rooms supports heavier files than Social).
const List<String> kSupportedAttachmentExtensions = [
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
  'mp4',
  'mov',
  'mkv',
  'webm',
  'avi',
  'mp3',
  'wav',
  'ogg',
  'm4a',
  'flac',
  'txt',
  'md',
  'json',
  'csv',
  'xml',
  'yaml',
  'log',
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'zip',
  'rar',
  '7z',
  'tar',
  'gz',
];

/// A file or pack item staged in the composer, waiting to be sent.
class StagedAttachment {
  const StagedAttachment({
    required this.kind,
    required this.name,
    this.path,
    this.size = 0,
    this.packId,
  });

  /// image | video | audio | document | sticker | gif
  final String kind;
  final String name;

  /// Local file path for picked files (null for Foxy pack items).
  final String? path;
  final int size;

  /// Foxy pack value id for sticker/gif attachments.
  final String? packId;

  bool get isPackItem => packId != null;

  /// Files at or above this size surface a "large file" hint in the chip
  /// row so the sender knows the upload may take a moment.
  static const int largeFileBytes = 25 * 1024 * 1024;

  bool get isLarge => size >= largeFileBytes;

  String get sizeLabel {
    if (size <= 0) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Attachment categories offered by the + menu — Telegram/Slack-style type
/// picking: pick the kind first, then the files.
const List<({String label, IconData icon, Color color})> kAttachmentTypes = [
  (label: 'Image', icon: Icons.image_outlined, color: Color(0xFF6E7CFF)),
  (label: 'Video', icon: Icons.videocam_outlined, color: Color(0xFFB57BFF)),
  (label: 'Audio', icon: Icons.headset_outlined, color: Color(0xFF3DC9B0)),
  (label: 'GIF', icon: Icons.gif_box_outlined, color: Color(0xFFFF8A4C)),
  (
    label: 'Document',
    icon: Icons.description_outlined,
    color: Color(0xFF4C8DFF)
  ),
  (label: 'PDF', icon: Icons.picture_as_pdf_outlined, color: Color(0xFFF5636B)),
  (label: 'Excel', icon: Icons.table_view_outlined, color: Color(0xFF33C481)),
  (label: 'Word', icon: Icons.article_outlined, color: Color(0xFF4C8DFF)),
  (label: 'PPT', icon: Icons.slideshow_outlined, color: Color(0xFFFF9F45)),
  (
    label: 'Text/JSON',
    icon: Icons.data_object_outlined,
    color: Color(0xFFA8B0C2)
  ),
  (
    label: 'Sticker',
    icon: Icons.emoji_emotions_outlined,
    color: Color(0xFFFF8A4C)
  ),
  (label: 'Archive', icon: Icons.folder_zip_outlined, color: Color(0xFFDDC35A)),
];

Future<String?> showAttachmentTypeMenu(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text('Attach', style: PhlioTypography.headline),
            ),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              mainAxisSpacing: 12,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
              children: [
                for (final type in kAttachmentTypes)
                  GestureDetector(
                    onTap: () => Navigator.of(sheetContext).pop(type.label),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: type.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(type.icon, color: type.color, size: 24),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          type.label,
                          style: PhlioTypography.caption.copyWith(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// A quick-reaction emoji set for the tray.
const List<String> kEmojiSet = [
  '😀',
  '😂',
  '🥲',
  '😍',
  '😎',
  '🤔',
  '😴',
  '🥳',
  '😭',
  '😡',
  '🤯',
  '🫠',
  '🙌',
  '👏',
  '👍',
  '👎',
  '❤️',
  '🔥',
  '✨',
  '🎉',
  '💯',
  '🦊',
  '☕',
  '🍕',
  '🎮',
  '🎨',
  '🎧',
  '⚽',
  '🚀',
  '🧠',
  '💡',
  '🌱',
];

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.hint,
    required this.onSendText,
    required this.onSendFiles,
    required this.onSendVoice,
    super.key,
    this.compact = false,
    this.surfaceColor = PhlioColors.surfaceInput,
  });

  final String hint;

  /// Plain text message.
  final FutureOr<void> Function(String) onSendText;

  /// One or more staged attachments (picked files and/or Foxy pack items)
  /// plus any caption text. The callback does the actual delivery
  /// (upload + post for rooms, in-memory append for DMs); the composer
  /// awaits it to show the sending state.
  final Future<void> Function(List<StagedAttachment> files, String text)
      onSendFiles;

  /// Voice note — receives the recorded duration label ("0:07") and, when
  /// recording succeeded, the local audio file path for playback.
  final FutureOr<void> Function(String duration, String? audioPath) onSendVoice;

  /// Tighter paddings for the two-pane room layout.
  final bool compact;
  final Color surfaceColor;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  bool _showEmojiTray = false;
  bool _foxyTrayTab = false; // false: unicode emoji, true: Foxy pack
  final List<StagedAttachment> _staged = [];
  bool _isSending = false;
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  final AudioRecorder _recorder = AudioRecorder();

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _recordTimer?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  bool get _canSend =>
      !_isSending &&
      !_isRecording &&
      (_staged.isNotEmpty || _textController.text.trim().isNotEmpty);

  Future<void> _send() async {
    if (_isSending) return;
    if (_isRecording) {
      final duration = _formatDuration(_recordSeconds);
      final path = await _stopRecording();
      try {
        await widget.onSendVoice(duration, path);
      } catch (_) {
        _showSendError();
      }
      return;
    }
    if (_staged.isNotEmpty) {
      setState(() => _isSending = true);
      try {
        await widget.onSendFiles(
          List<StagedAttachment>.unmodifiable(_staged),
          _textController.text.trim(),
        );
        if (!mounted) return;
        setState(() {
          _staged.clear();
          _textController.clear();
          _showEmojiTray = false;
        });
      } catch (_) {
        _showSendError();
      } finally {
        if (mounted) setState(() => _isSending = false);
      }
      return;
    }
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSending = true);
    try {
      await widget.onSendText(text);
      if (!mounted) return;
      _textController.clear();
      setState(() => _showEmojiTray = false);
    } catch (_) {
      _showSendError();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showSendError() {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not send your message. Please try again.')),
      );
  }

  Future<void> _pickAttachments() async {
    final pickedType = await showAttachmentTypeMenu(context);
    if (pickedType == null) return; // sheet dismissed

    // Stickers and GIFs come from the bundled Foxy pack — no file system.
    if (pickedType == 'Sticker' || pickedType == 'GIF') {
      final item = await showFoxyPicker(
        context,
        initialTab: pickedType == 'GIF'
            ? FoxyReactionKind.gif
            : FoxyReactionKind.sticker,
        title: pickedType == 'GIF' ? 'Foxy GIFs' : 'Foxy stickers',
      );
      if (item == null || !mounted) return;
      setState(() {
        _staged.add(StagedAttachment(
          kind: pickedType == 'GIF' ? 'gif' : 'sticker',
          name: item.label,
          packId: item.id,
        ));
      });
      return;
    }

    try {
      // Scope the picker to the picked category where the platform
      // supports it, else fall back to the full safe set. Multi-select
      // everywhere; bytes stay on disk (Dio streams the upload).
      final (type, extensions) = switch (pickedType) {
        'Image' => (FileType.image, const <String>[]),
        'Video' => (FileType.video, const <String>[]),
        'Audio' => (FileType.audio, const <String>[]),
        'GIF' => (FileType.custom, const <String>['gif']),
        'PDF' => (FileType.custom, const <String>['pdf']),
        'Excel' => (FileType.custom, const <String>['xls', 'xlsx', 'csv']),
        'Word' => (FileType.custom, const <String>['doc', 'docx', 'txt', 'md']),
        'PPT' => (FileType.custom, const <String>['ppt', 'pptx']),
        'Text/JSON' => (
            FileType.custom,
            const <String>['txt', 'md', 'json', 'csv', 'xml', 'yaml']
          ),
        'Archive' => (
            FileType.custom,
            const <String>['zip', 'rar', '7z', 'tar', 'gz']
          ),
        _ => (FileType.custom, kSupportedAttachmentExtensions),
      };
      final result = await FilePicker.pickFiles(
        type: type,
        allowedExtensions: extensions.isEmpty ? null : extensions,
        allowMultiple: true,
        withData: false,
      );
      final picked =
          result?.files.where((f) => f.path != null).toList() ?? const [];
      if (picked.isEmpty || !mounted) return;
      setState(() {
        for (final file in picked) {
          _staged.add(StagedAttachment(
            kind: switch (pickedType) {
              'Image' => 'image',
              'Video' => 'video',
              'Audio' => 'audio',
              _ => attachmentKindForName(file.name),
            },
            name: file.name,
            path: file.path,
            size: file.size,
          ));
        }
      });
    } on MissingPluginException {
      // The picker's native plugin only registers on a full rebuild — a
      // hot reload right after `pub add` hits this.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File picker needs one full app restart to install — '
              'stop and run again, it will work after that.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the file picker.')),
      );
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isSending) return;
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Microphone permission is needed for voice messages.')),
        );
        return;
      }
      final path =
          '${Directory.systemTemp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordSeconds++);
      });
    } catch (_) {
      // MissingPluginException lands here when the app was hot-reloaded
      // after adding the record package instead of fully restarted; other
      // failures are device quirks. Either way: explain, never crash.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice messages need one full app restart to install — '
              'stop and run again, they will work after that.'),
        ),
      );
    }
  }

  /// Stops the recorder; returns the recorded file path (null on failure).
  Future<String?> _stopRecording() async {
    _recordTimer?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordSeconds = 0;
      });
    }
    return path;
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Staged attachment chips — files, documents, stickers, GIFs.
        if (_staged.isNotEmpty) _stagedChips(),
        // Foxy / unicode emoji tray.
        if (_showEmojiTray) _tray(),
        // Input row.
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.compact ? 12 : PhlioSpacing.lg,
            0,
            widget.compact ? 12 : PhlioSpacing.lg,
            widget.compact ? PhlioSpacing.sm : PhlioSpacing.lg,
          ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: PhlioSpacing.md,
              vertical: widget.compact ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: widget.surfaceColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _isRecording
                    ? PhlioColors.danger
                    : PhlioColors.borderSubtle,
              ),
            ),
            child: _isRecording ? _recordingRow() : _inputRow(),
          ),
        ),
      ],
    );
  }

  Widget _stagedChips() {
    final anyLarge = _staged.any((f) => f.isLarge);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.compact ? 12 : PhlioSpacing.lg,
        0,
        widget.compact ? 12 : PhlioSpacing.lg,
        PhlioSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 124,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _staged.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: PhlioSpacing.sm),
              itemBuilder: (context, index) {
                final staged = _staged[index];
                return _StagedChip(
                  staged: staged,
                  onRemove: () => setState(() => _staged.removeAt(index)),
                );
              },
            ),
          ),
          if (anyLarge)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: PhlioSpacing.xs),
              child: Row(
                children: [
                  const Icon(Icons.cloud_upload_outlined,
                      size: 12, color: PhlioColors.brandOrange),
                  const SizedBox(width: 4),
                  Text(
                    'Large file — the upload streams in the background',
                    style: PhlioTypography.caption.copyWith(
                      fontSize: 10,
                      color: PhlioColors.brandOrange,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tray() {
    return Container(
      height: 168,
      margin: EdgeInsets.fromLTRB(
        widget.compact ? 12 : PhlioSpacing.lg,
        0,
        widget.compact ? 12 : PhlioSpacing.lg,
        PhlioSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: PhlioColors.surfaceElevated,
        borderRadius: PhlioRadii.lgRadius,
        border: Border.all(color: PhlioColors.borderSubtle),
      ),
      child: Column(
        children: [
          // Segmented switch: unicode emoji / the Foxy pack.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                PhlioSpacing.sm, PhlioSpacing.xs, PhlioSpacing.sm, 0),
            child: Row(
              children: [
                _trayToggle('Emoji', !_foxyTrayTab,
                    () => setState(() => _foxyTrayTab = false)),
                const SizedBox(width: PhlioSpacing.xs),
                _trayToggle('Foxy', _foxyTrayTab,
                    () => setState(() => _foxyTrayTab = true)),
                const Spacer(),
                Text(
                  _foxyTrayTab ? 'Tap to attach' : 'Tap to add',
                  style: PhlioTypography.caption.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
          Expanded(
            child: !_foxyTrayTab
                ? GridView.builder(
                    padding: const EdgeInsets.all(PhlioSpacing.sm),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                    ),
                    itemCount: kEmojiSet.length,
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: () {
                          _textController.text += kEmojiSet[index];
                          _textController.selection =
                              TextSelection.fromPosition(
                            TextPosition(offset: _textController.text.length),
                          );
                        },
                        child: Center(
                          child: Text(kEmojiSet[index],
                              style: const TextStyle(fontSize: 22)),
                        ),
                      );
                    },
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(PhlioSpacing.sm),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                      mainAxisSpacing: 2,
                    ),
                    itemCount: FoxyPack.emoji.length,
                    itemBuilder: (context, index) {
                      final item = FoxyPack.emoji[index];
                      return GestureDetector(
                        onTap: () => setState(() {
                          _staged.add(StagedAttachment(
                            kind: 'sticker',
                            name: item.label,
                            packId: item.id,
                          ));
                        }),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Image.asset(
                            item.assetPath,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.pets_rounded,
                              color: PhlioColors.brandOrange,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _trayToggle(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? PhlioColors.brandViolet.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                selected ? PhlioColors.brandViolet : PhlioColors.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: PhlioTypography.caption.copyWith(
            fontSize: 11,
            color: selected ? PhlioColors.textPrimary : PhlioColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _inputRow() {
    return Row(
      children: [
        // Plain + (no circle) — attach documents.
        GestureDetector(
          onTap: _isSending ? null : _pickAttachments,
          child: const Icon(Icons.add_rounded,
              size: 26, color: PhlioColors.textSecondary),
        ),
        Expanded(
          child: TextField(
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            controller: _textController,
            focusNode: _focusNode,
            style: PhlioTypography.body,
            enabled: !_isSending,
            onTap: () => setState(() => _showEmojiTray = false),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle:
                  PhlioTypography.body.copyWith(color: PhlioColors.textMuted),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: PhlioSpacing.sm,
                vertical: PhlioSpacing.sm,
              ),
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        // Emoji tray toggle.
        GestureDetector(
          onTap: () => setState(() => _showEmojiTray = !_showEmojiTray),
          child: Icon(
            Icons.emoji_emotions_outlined,
            size: 22,
            color: _showEmojiTray
                ? PhlioColors.brandOrange
                : PhlioColors.textSecondary,
          ),
        ),
        const SizedBox(width: PhlioSpacing.sm),
        // Mic — voice message recording.
        GestureDetector(
          onLongPress: _startRecording,
          onTap: _startRecording,
          child: const Icon(Icons.mic_none_rounded,
              size: 22, color: PhlioColors.textSecondary),
        ),
        const SizedBox(width: PhlioSpacing.xs),
        // Send — submits text, staged attachments or the recorded voice note.
        GestureDetector(
          onTap: _canSend ? _send : null,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: _canSend ? PhlioColors.sunsetGradient : null,
              color: _canSend ? null : PhlioColors.surfaceElevated,
              shape: BoxShape.circle,
            ),
            child: _isSending
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PhlioColors.textOnBrand,
                    ),
                  )
                : Icon(
                    Icons.send_rounded,
                    size: 17,
                    color: _canSend
                        ? PhlioColors.textOnBrand
                        : PhlioColors.textMuted,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _recordingRow() {
    return Row(
      children: [
        const Icon(Icons.graphic_eq_rounded,
            size: 20, color: PhlioColors.danger),
        const SizedBox(width: PhlioSpacing.sm),
        Expanded(
          child: Text(
            'Recording voice message · ${_formatDuration(_recordSeconds)}',
            style: PhlioTypography.body.copyWith(color: PhlioColors.danger),
          ),
        ),
        GestureDetector(
          onTap: () async {
            await _stopRecording(); // discarded — file dropped
          },
          child: const Icon(Icons.close_rounded,
              size: 20, color: PhlioColors.textSecondary),
        ),
        const SizedBox(width: PhlioSpacing.sm),
        GestureDetector(
          onTap: _send,
          child: Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              gradient: PhlioColors.sunsetGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.send_rounded,
                color: PhlioColors.textOnBrand, size: 16),
          ),
        ),
      ],
    );
  }
}

/// One staged attachment chip in the composer: doc-type icon or the Foxy
/// pack art, name · size, removable.
class _StagedChip extends StatelessWidget {
  const _StagedChip({required this.staged, required this.onRemove});

  final StagedAttachment staged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: PhlioColors.roomsInput,
          borderRadius: PhlioRadii.mdRadius,
          border: Border.all(color: PhlioColors.borderSubtle)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
            child: Stack(children: [
          Positioned.fill(
              child: AttachmentPreview(
            key: ValueKey(staged.path ?? staged.packId),
            compact: true,
            attachment: MessageAttachmentEntity(
                id: staged.path ?? staged.packId ?? staged.name,
                kind: staged.kind,
                name: staged.name,
                size: staged.size,
                localPath: staged.path,
                value: staged.packId ?? ''),
          )),
          Positioned(
              top: 0,
              right: 0,
              child: IconButton.filledTonal(
                  tooltip: 'Remove ${staged.name}',
                  onPressed: onRemove,
                  constraints:
                      const BoxConstraints.tightFor(width: 28, height: 28),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded, size: 16))),
        ])),
        Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
            child: Text(staged.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11))),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
                staged.isPackItem ? 'Foxy pack' : attachmentSize(staged.size),
                style: const TextStyle(
                    fontSize: 10, color: PhlioColors.textSecondary))),
      ]),
    );
  }
}
