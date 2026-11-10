import 'dm_media_studio.dart';
import '../../../../shared/giphy/giphy_picker.dart';
// Shared composer with audience-specific attachment menus and validation.
// Public creator chat supports text and pack GIFs/stickers; private Messages
// supports media and editing; Rooms retains documents and archives.

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../../design_system/widgets/phlio_icons.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phlio/shared/location/location_message.dart';
import 'package:phlio/shared/location/location_service.dart';
import 'package:phlio/shared/location/location_share_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/pay/dm_pay_sheet.dart';
import '../../../../shared/pay/phlio_currency.dart';

import '../../../../app/platform/phlio_platform.dart';
import '../../../../app/shell/platform_home_screen.dart' show switchPlatform;
import 'draw_screen.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/foxy_pack.dart';
import '../../domain/entities/room_message_entity.dart';
import 'attachment_preview.dart';
import 'chat_policy.dart';
import 'message_media_editor.dart';

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
    this.videoEdits,
  });

  /// image | video | audio | document | sticker | gif
  final String kind;
  final String name;

  /// Local file path for picked files (null for Foxy pack items).
  final String? path;
  final int size;

  /// Foxy pack value id for sticker/gif attachments.
  final String? packId;
  final Map<String, dynamic>? videoEdits;

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
  (label: 'Image', icon: Icons.image_outlined, color: PhlioColors.brandBlue),
  (
    label: 'Video',
    icon: Icons.videocam_outlined,
    color: PhlioColors.brandPurple
  ),
  (label: 'Audio', icon: Icons.headset_outlined, color: PhlioColors.success),
  (label: 'GIF', icon: Icons.gif_box_outlined, color: PhlioColors.brandPeach),
  (
    label: 'Document',
    icon: Icons.description_outlined,
    color: PhlioColors.brandBlue
  ),
  (
    label: 'PDF',
    icon: Icons.picture_as_pdf_outlined,
    color: PhlioColors.danger
  ),
  (label: 'Excel', icon: Icons.table_view_outlined, color: PhlioColors.success),
  (label: 'Word', icon: Icons.article_outlined, color: PhlioColors.brandBlue),
  (label: 'PPT', icon: Icons.slideshow_outlined, color: PhlioColors.brandPeach),
  (
    label: 'Text/JSON',
    icon: Icons.data_object_outlined,
    color: PhlioColors.textSecondary
  ),
  (
    label: 'Sticker',
    icon: Icons.emoji_emotions_outlined,
    color: PhlioColors.brandPeach
  ),
  (
    label: 'Archive',
    icon: Icons.folder_zip_outlined,
    color: PhlioColors.brandPeach
  ),
];

Future<String?> showAttachmentTypeMenu(
  BuildContext context, {
  ChatAudience audience = ChatAudience.rooms,
}) {
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
                for (final type in kAttachmentTypes.where(
                  (t) =>
                      audience == ChatAudience.rooms ||
                      (audience == ChatAudience.publicChat
                              ? ['Sticker', 'GIF']
                              : ['Image', 'Video', 'Audio', 'GIF', 'Sticker'])
                          .contains(t.label),
                ))
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
    this.dmPeer,
    this.compact = false,
    this.audience = ChatAudience.rooms,
    this.surfaceColor = PhlioColors.surfaceInput,
  });

  final String? dmPeer;
  final String hint;

  /// Plain text message.
  final FutureOr<void> Function(String) onSendText;

  /// One or more staged attachments (picked files and/or Foxy pack items)
  /// plus any caption text. The callback does the actual delivery
  /// (upload + post for Rooms and private Messages); the composer
  /// awaits it to show the sending state.
  final Future<void> Function(List<StagedAttachment> files, String text)
      onSendFiles;

  /// Voice note — receives the recorded duration label ("0:07") and, when
  /// recording succeeded, the local audio file path for playback.
  final FutureOr<void> Function(String duration, String? audioPath) onSendVoice;

  /// Tighter paddings for the two-pane room layout.
  final bool compact;
  final ChatAudience audience;
  final Color surfaceColor;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  bool _showEmojiTray = false;
  // Smile tray tab: 0 unicode emoji, 1 the animated Foxy sticker pack,
  // 2 the Foxy face pack.
  int _trayTab = 0;
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
        if (widget.audience == ChatAudience.publicChat) return;
        if (path != null && widget.audience == ChatAudience.directMessage) {
          final error = dmMediaError(path, await File(path).length());
          if (error != null) {
            _mediaError(error);
            return;
          }
        }
        await widget.onSendVoice(duration, path);
      } catch (error) {
        _showSendError(error);
      }
      return;
    }
    if (_staged.isNotEmpty) {
      if (_staged.length > 10) {
        _mediaError('Attach up to ten items.');
        return;
      }
      for (final attachment in _staged) {
        if (widget.audience == ChatAudience.publicChat &&
            !attachment.isPackItem) {
          _mediaError('Chat supports text, GIFs and predefined stickers only.');
          return;
        }
        if (widget.audience == ChatAudience.directMessage &&
            attachment.path != null) {
          final error = dmMediaError(attachment.name, attachment.size);
          if (error != null) {
            _mediaError(error);
            return;
          }
        }
      }
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
      } catch (error) {
        _showSendError(error);
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
    } catch (error) {
      _showSendError(error);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showSendError([Object? error]) {
    final detail = error is DioException && error.response?.data is Map
        ? (error.response!.data as Map)['detail']
        : null;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            detail is String
                ? detail
                : 'Could not send your message. Please try again.',
          ),
        ),
      );
    }
  }

  void _mediaError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _editAttachment(int index) async {
    if (_isSending) return;
    final original = _staged[index];
    if (widget.dmPeer != null) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DmMediaStudio(
                peer: widget.dmPeer!,
                initial: original,
                onSend: (edited) async {
                  await widget.onSendFiles([edited], '');
                  // The edit replaces the original that was waiting here.
                  if (mounted && _staged.contains(original)) {
                    setState(() => _staged.remove(original));
                  }
                },
              )));
      return;
    }
    final edited = await Navigator.of(context).push<StagedAttachment>(
      MaterialPageRoute(
        builder: (_) => MessageMediaEditor(attachment: original),
      ),
    );
    if (!mounted || edited == null) return;
    final error = dmMediaError(edited.name, edited.size);
    if (error != null) {
      _mediaError(error);
      return;
    }
    final current = _staged.indexOf(original);
    if (current >= 0) setState(() => _staged[current] = edited);
  }

  Future<void> _pickAttachments({String? type}) async {
    final pickedType = type ??
        await showAttachmentTypeMenu(context, audience: widget.audience);
    if (pickedType == null) return; // sheet dismissed

    // Stickers come from the Foxy sheet (animated Foxy, the pack, or a
    // GIPHY search from inside it); GIFs from GIPHY. No file system.
    if (pickedType == 'Sticker') {
      final id = await showFoxyStickerSheet(context);
      if (id == null || !mounted) return;
      final giphyKind = id.startsWith('giphy:') ? id.split(':')[1] : null;
      setState(() {
        _staged.add(
          StagedAttachment(
            kind: giphyKind ?? 'sticker',
            name: giphyKind != null
                ? 'GIPHY'
                : (FoxyPack.resolve(id)?.label ??
                    (FoxyPuppetStickers.parse(id) != null
                        ? FoxyPuppetStickers.labelOf(id)
                        : 'Foxy sticker')),
            packId: id,
          ),
        );
      });
      return;
    }
    if (pickedType == 'GIF') {
      final item = await showGiphyPicker(context, kind: 'gif');
      if (item == null || !mounted) return;
      setState(() {
        _staged.add(
          StagedAttachment(
            // The picker's Foxy tab hands back an animated Foxy sticker.
            kind: item.isFoxy ? 'sticker' : item.kind,
            name: item.title,
            packId: item.reference,
          ),
        );
      });
      return;
    }

    try {
      // Scope the picker to the picked category where the platform
      // supports it, else fall back to the full safe set. Multi-select
      // everywhere; bytes stay on disk (Dio streams the upload).
      final (type, extensions) = switch (pickedType) {
        'Media' => (FileType.media, const <String>[]),
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
          if (_staged.length >= 10) {
            _mediaError('Attach up to ten items.');
            break;
          }
          if (widget.audience == ChatAudience.directMessage) {
            final error = dmMediaError(file.name, file.size);
            if (error != null) {
              _mediaError(error);
              continue;
            }
          }
          _staged.add(
            StagedAttachment(
              kind: switch (pickedType) {
                'Image' => 'image',
                'Video' => 'video',
                'Audio' => 'audio',
                _ => attachmentKindForName(file.name),
              },
              name: file.name,
              path: file.path,
              size: file.size,
            ),
          );
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
    if (_isRecording ||
        _isSending ||
        widget.audience == ChatAudience.publicChat) {
      return;
    }
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Microphone permission is needed for voice messages.'),
          ),
        );
        return;
      }
      final path =
          '${Directory.systemTemp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc, noiseSuppress: true, echoCancel: true),
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
            // DMs sit a little higher off the bottom edge.
            widget.audience == ChatAudience.directMessage
                ? 18
                : widget.compact
                    ? PhlioSpacing.sm
                    : PhlioSpacing.lg,
          ),
          child: Container(
            padding:
                widget.audience == ChatAudience.directMessage && !_isRecording
                    ? const EdgeInsets.fromLTRB(4, 4, 6, 4)
                    : _isRecording
                        ? EdgeInsets.symmetric(
                            horizontal: PhlioSpacing.md,
                            vertical: widget.compact ? 4 : 6,
                          )
                        : const EdgeInsets.symmetric(vertical: 4),
            decoration: widget.audience == ChatAudience.directMessage
                ? BoxDecoration(
                    // Messages: borderless pill, like the reference.
                    color: const Color(0xFF262626),
                    borderRadius: BorderRadius.circular(999),
                    border: _isRecording
                        ? Border.all(color: PhlioColors.danger)
                        : null,
                  )
                : _isRecording
                    ? BoxDecoration(
                        color: widget.surfaceColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: PhlioColors.danger),
                      )
                    // Rooms: no box around the composer (Discord-style);
                    // the buttons and the input pill float on the chat.
                    : null,
            child: _isRecording
                ? _recordingRow()
                : widget.audience == ChatAudience.directMessage
                    ? _dmInputRow()
                    : _inputRow(),
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
                  onEdit: widget.audience == ChatAudience.directMessage &&
                          staged.path != null &&
                          ['image', 'video'].contains(staged.kind) &&
                          !staged.name.toLowerCase().endsWith('.gif')
                      ? () => _editAttachment(index)
                      : null,
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
                  const Icon(
                    Icons.cloud_upload_outlined,
                    size: 12,
                    color: PhlioColors.brandOrange,
                  ),
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
              PhlioSpacing.sm,
              PhlioSpacing.xs,
              PhlioSpacing.sm,
              0,
            ),
            child: Row(
              children: [
                _trayToggle(
                  'Emoji',
                  _trayTab == 0,
                  () => setState(() => _trayTab = 0),
                ),
                const SizedBox(width: PhlioSpacing.xs),
                _trayToggle(
                  'Foxy',
                  _trayTab == 1,
                  () => setState(() => _trayTab = 1),
                ),
                const SizedBox(width: PhlioSpacing.xs),
                _trayToggle(
                  'Faces',
                  _trayTab == 2,
                  () => setState(() => _trayTab = 2),
                ),
                const Spacer(),
                Text(
                  _trayTab != 0 ? 'Tap to attach' : 'Tap to add',
                  style: PhlioTypography.caption.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
          Expanded(
            child: _trayTab == 1
                ? _foxyStickerGrid()
                : _trayTab == 0
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
                          child: Text(
                            kEmojiSet[index],
                            style: const TextStyle(fontSize: 22),
                          ),
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
                          _staged.add(
                            StagedAttachment(
                              kind: 'sticker',
                              name: item.label,
                              packId: item.id,
                            ),
                          );
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

  /// The animated Foxy sticker pack (the rigged mascot), live in the tray.
  Widget _foxyStickerGrid() {
    final ids = FoxyPuppetStickers.ids;
    return GridView.builder(
      padding: const EdgeInsets.all(PhlioSpacing.xs),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: ids.length,
      itemBuilder: (context, index) {
        final id = ids[index];
        return Tooltip(
          message: FoxyPuppetStickers.labelOf(id),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              rememberSticker(id);
              setState(() {
                _staged.add(
                  StagedAttachment(
                    kind: 'sticker',
                    name: FoxyPuppetStickers.labelOf(id),
                    packId: id,
                  ),
                );
              });
            },
            child: LayoutBuilder(
              builder: (context, box) => Center(
                child: FoxyStickerView(
                    id: id, size: box.biggest.shortestSide - 4),
              ),
            ),
          ),
        );
      },
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

  Future<void> _camera() async {
    try {
      final photo = await ImagePicker().pickImage(source: ImageSource.camera);
      if (photo == null || !mounted) return;
      final size = await photo.length();
      if (!mounted) return;
      final error = dmMediaError(photo.name, size);
      if (error != null) {
        _mediaError(error);
        return;
      }
      if (_staged.length >= 10) {
        _mediaError('Attach up to ten items.');
        return;
      }
      setState(() => _staged.add(StagedAttachment(
          kind: 'image', name: photo.name, path: photo.path, size: size)));
    } catch (_) {
      if (mounted)
        _mediaError(
            'Could not open the camera. Check camera permission and try again.');
    }
  }

  static const _iconDir = 'assets/images/chat_icons';
  bool _moreOpen = false;

  Widget _svg(String name, {double size = 26, Color color = Colors.white}) =>
      SvgPicture.asset('$_iconDir/$name.svg',
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn));

  /// Messages composer: [camera] Message…  mic · photo · sticker · (+)
  /// While typing, the trailing icons give way to a Send button.
  Widget _dmInputRow() {
    // Plain 40×40 hit boxes (not IconButton: Material 3 pads those to a
    // 48 px tap target, which pushed icons out of line and out of view).
    Widget action(String label, String icon, VoidCallback tap) => _ComposerIcon(
        tooltip: label,
        onTap: _isSending ? null : tap,
        child: _svg(icon, size: 24, color: Colors.white));
    final typing = _canSend || _isSending;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      // Instagram-style pill: 48 tall, camera · Message… · 2 actions (+ swipe) · (+)
      Material(
        color: const Color(0xFF7B5CFF),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _isSending ? null : _camera,
          child: Tooltip(
              message: 'Camera',
              child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(child: _svg('camera', size: 22)))),
        ),
      ),
      Expanded(
          child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 4,
              inputFormatters: [LengthLimitingTextInputFormatter(4000)],
              enabled: !_isSending,
              textInputAction: TextInputAction.send,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                  hintText: 'Message…',
                  hintMaxLines: 1,
                  hintStyle: TextStyle(color: Color(0xFF8E8E93), fontSize: 16),
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      EdgeInsets.fromLTRB(12, 9, 6, 9)),
              style: const TextStyle(fontSize: 16, color: Colors.white))),
      if (typing)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Material(
            color: const Color(0xFF7B5CFF),
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: _isSending ? null : _send,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Send',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
              ),
            ),
          ),
        )
      else ...[
        // Quick actions scroll sideways (with soft edge fades) so the
        // message field always keeps its room; "+" stays pinned.
        _ScrollableActions(
          maxVisible: 2,
          itemWidth: 40,
          children: [
            action('Voice message', 'mic', _startRecording),
            action('Photos and videos', 'image',
                () => _pickAttachments(type: 'Media')),
            if (widget.dmPeer != null)
              // Pay this person: ₹ in India, $ in the US, € in the euro area…
              Consumer(
                builder: (context, ref, _) {
                  final currency = ref.watch(userCurrencyProvider);
                  return _ComposerIcon(
                    tooltip: 'Send money',
                    onTap: _isSending ? null : _openPay,
                    child: CurrencyGlyph(
                        currency: currency, size: 23, color: Colors.white),
                  );
                },
              ),
            action('Stickers', 'sticker', () {
              _focusNode.unfocus();
              _pickAttachments(type: 'Sticker');
            }),
          ],
        ),
        Builder(
            builder: (buttonContext) => action(
                _moreOpen ? 'Close' : 'More',
                _moreOpen ? 'close_circle' : 'plus_circle',
                () => _openMoreMenu(buttonContext))),
      ],
    ]);
  }

  /// Opens the DM pay sheet; a completed payment is announced in the chat.
  Future<void> _openPay() async {
    _focusNode.unfocus();
    final message = await showDmPaySheet(context, username: widget.dmPeer!);
    if (message == null || !mounted) return;
    try {
      await widget.onSendText(message);
    } catch (error) {
      _showSendError(error);
    }
  }

  /// The "+" menu: Location · AI images · Draw · Foxy AI, floating just
  /// above the composer's right edge.
  Future<void> _openMoreMenu(BuildContext buttonContext) async {
    _focusNode.unfocus();
    final box = buttonContext.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final bottom = screen.height - origin.dy + 14;
    setState(() => _moreOpen = true);
    final choice = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 170),
      pageBuilder: (dialogContext, _, __) => Stack(children: [
        Positioned(
          right: 16,
          bottom: bottom,
          child: _MoreMenu(
              svg: _svg,
              onSelected: (value) => Navigator.pop(dialogContext, value)),
        ),
      ]),
      transitionBuilder: (_, animation, __, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          alignment: Alignment.bottomRight,
          scale: Tween(begin: .9, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _moreOpen = false);
    switch (choice) {
      case 'location':
        await _shareLocation();
      case 'ai_image':
        _comingSoon('AI images',
            'Describe an image and Foxy will create it for you, right here in the chat.');
      case 'draw':
        final path = await openDrawScreen(context);
        if (path == null || !mounted) return;
        final size = await File(path).length();
        if (!mounted) return;
        setState(() => _staged.add(StagedAttachment(
            kind: 'image', name: 'Drawing.png', path: path, size: size)));
      case 'foxy':
        switchPlatform(context, PhlioPlatform.agent);
        context.go('/home');
    }
  }

  /// Opens "Send location": a place once, or (in DMs) live location.
  Future<void> _shareLocation() async {
    final pick = await openLocationShare(context, allowLive: widget.dmPeer != null);
    if (pick == null || !mounted) return;
    try {
      switch (pick) {
        case PlacePick(:final place):
          await widget.onSendText(placeMessage(place));
        case LivePick(:final minutes, :final from):
          final id = await LiveLocationSharer.instance.start(widget.dmPeer!, minutes, from);
          await widget.onSendText(liveMessage(id, from.latitude, from.longitude));
      }
    } catch (error) {
      _showSendError(error);
    }
  }

  void _comingSoon(String title, String body) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (sheet) => SafeArea(
              child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _svg('ai_image', size: 40, color: PhlioColors.brandViolet),
              const SizedBox(height: 12),
              Text('$title are coming soon', style: PhlioTypography.title),
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center, style: PhlioTypography.body),
              const SizedBox(height: 20),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: () => Navigator.pop(sheet),
                      child: const Text('Got it'))),
            ]),
          )));

  /// Rooms composer, Discord-style:  (+)  ( Message #channel   ☺ )  (🎙/➤)
  /// Round buttons on a shared 40 px grid; no border around the field.
  Widget _inputRow() {
    const extent = 40.0;
    Widget round({
      required String tooltip,
      required Widget child,
      VoidCallback? onTap,
      Gradient? gradient,
      Color? color,
    }) =>
        Tooltip(
          message: tooltip,
          child: DecoratedBox(
            decoration: BoxDecoration(
                shape: BoxShape.circle, gradient: gradient, color: color),
            child: Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox.square(
                    dimension: extent, child: Center(child: child)),
              ),
            ),
          ),
        );
    Widget glyph(String name, {Color color = PhlioColors.textSecondary}) =>
        SvgPicture.asset('assets/images/rooms_icons/$name.svg',
            width: 22,
            height: 22,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn));

    final showMic = widget.audience != ChatAudience.publicChat &&
        !_canSend &&
        !_isSending;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Attachments follow the conversation policy.
        round(
          tooltip: 'Attach',
          color: PhlioColors.surfaceElevated,
          onTap: _isSending ? null : _pickAttachments,
          child: glyph('plus', color: PhlioColors.textPrimary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: extent),
            decoration: BoxDecoration(
              color: widget.surfaceColor,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4000,
                    textInputAction: TextInputAction.send,
                    controller: _textController,
                    focusNode: _focusNode,
                    style: PhlioTypography.body
                        .copyWith(color: PhlioColors.textPrimary),
                    cursorColor: PhlioColors.brandViolet,
                    enabled: !_isSending,
                    onTap: () => setState(() => _showEmojiTray = false),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      counterText: '',
                      isDense: true,
                      filled: false,
                      hintMaxLines: 1,
                      hintStyle: PhlioTypography.body
                          .copyWith(color: PhlioColors.textMuted),
                      // Override the app theme's outlined fields: no box.
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.fromLTRB(16, 10, 4, 10),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                // Emoji / Foxy tray toggle, inside the pill.
                SizedBox.square(
                  dimension: extent,
                  child: InkResponse(
                    radius: 20,
                    onTap: () =>
                        setState(() => _showEmojiTray = !_showEmojiTray),
                    child: Center(
                      child: glyph('smile',
                          color: _showEmojiTray
                              ? PhlioColors.brandOrange
                              : PhlioColors.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Mic when idle; the send button once there is something to send.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: showMic
              ? KeyedSubtree(
                  key: const ValueKey('mic'),
                  child: round(
                    tooltip: 'Voice message',
                    color: PhlioColors.surfaceElevated,
                    onTap: _startRecording,
                    child: glyph('mic', color: PhlioColors.textPrimary),
                  ),
                )
              : KeyedSubtree(
                  key: const ValueKey('send'),
                  child: round(
                    tooltip: 'Send',
                    gradient: _canSend || _isSending
                        ? PhlioColors.sunsetGradient
                        : null,
                    color: _canSend || _isSending
                        ? null
                        : PhlioColors.surfaceElevated,
                    onTap: _canSend ? _send : null,
                    child: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: PhlioColors.textOnBrand,
                            ),
                          )
                        // The plane points up-right, so nudge it down-left
                        // a hair to sit optically centred in the circle.
                        : Transform.translate(
                            offset: const Offset(-1, 1),
                            child: PhlioSendIcon(
                              size: 19,
                              color: _canSend
                                  ? PhlioColors.textOnBrand
                                  : PhlioColors.textMuted,
                            ),
                          ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _recordingRow() {
    return Row(
      children: [
        const Icon(
          Icons.graphic_eq_rounded,
          size: 20,
          color: PhlioColors.danger,
        ),
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
          child: const Icon(
            Icons.close_rounded,
            size: 20,
            color: PhlioColors.textSecondary,
          ),
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
            child: const Center(
              child: PhlioSendIcon(
                color: PhlioColors.textOnBrand,
                size: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One staged attachment chip in the composer: doc-type icon or the Foxy
/// pack art, name · size, removable.
class _StagedChip extends StatelessWidget {
  const _StagedChip({
    required this.staged,
    required this.onRemove,
    this.onEdit,
  });

  final StagedAttachment staged;
  final VoidCallback onRemove;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PhlioColors.roomsInput,
        borderRadius: PhlioRadii.mdRadius,
        border: Border.all(color: PhlioColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
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
                      value: staged.packId ?? '',
                    ),
                  ),
                ),
                if (onEdit != null)
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Tooltip(
                      message: 'Edit in Studio',
                      child: Material(
                        color: Colors.black.withValues(alpha: .62),
                        shape: const StadiumBorder(),
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: onEdit,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 9, vertical: 5),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.content_cut_rounded,
                                  size: 15, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Edit',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton.filledTonal(
                    tooltip: 'Remove ${staged.name}',
                    onPressed: onRemove,
                    constraints:
                        const BoxConstraints.tightFor(width: 28, height: 28),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close_rounded, size: 16),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
            child: Text(
              staged.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              staged.isPackItem ? 'Foxy pack' : attachmentSize(staged.size),
              style: const TextStyle(
                fontSize: 10,
                color: PhlioColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.svg, required this.onSelected});
  final Widget Function(String name, {double size, Color color}) svg;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF2A2D33),
        elevation: 12,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: IntrinsicWidth(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (value, icon, label) in const [
                    ('location', 'location', 'Location'),
                    ('ai_image', 'ai_image', 'AI images'),
                    ('draw', 'draw', 'Draw'),
                    ('foxy', 'foxy_ai', 'Foxy AI'),
                  ])
                    InkWell(
                      onTap: () => onSelected(value),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 44, 16),
                        child: Row(children: [
                          svg(icon, size: 28),
                          const SizedBox(width: 22),
                          Text(label,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500)),
                        ]),
                      ),
                    ),
                ]),
          ),
        ),
      );
}


/// A row of composer actions that shows [maxVisible] at a time and scrolls
/// sideways for the rest, fading its edges to hint there is more.
class _ScrollableActions extends StatefulWidget {
  const _ScrollableActions({
    required this.children,
    required this.maxVisible,
    required this.itemWidth,
  });

  final List<Widget> children;
  final int maxVisible;
  final double itemWidth;

  @override
  State<_ScrollableActions> createState() => _ScrollableActionsState();
}

class _ScrollableActionsState extends State<_ScrollableActions> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// After a swipe, settle so whole icons show — never half of one.
  bool _snap(ScrollNotification n) {
    if (n is ScrollEndNotification && _controller.hasClients) {
      final p = _controller.position;
      final target = (p.pixels / widget.itemWidth).round() * widget.itemWidth;
      final clamped = target.clamp(0.0, p.maxScrollExtent);
      if ((clamped - p.pixels).abs() > 0.5) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_controller.hasClients) {
            _controller.animateTo(clamped,
                duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
          }
        });
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.children.length;
    final visible = count < widget.maxVisible ? count : widget.maxVisible;
    return SizedBox(
      width: widget.itemWidth * visible,
      height: 40,
      child: NotificationListener<ScrollNotification>(
        onNotification: _snap,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final c in widget.children) SizedBox(width: widget.itemWidth, child: c),
          ]),
        ),
      ),
    );
  }
}


/// One composer action: a fixed 40×40 box, icon centred, circular ripple.
class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon({required this.tooltip, required this.onTap, required this.child});

  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          containedInkWell: false,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(child: Opacity(opacity: onTap == null ? 0.4 : 1, child: child)),
          ),
        ),
      ),
    );
  }
}
