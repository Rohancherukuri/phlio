import '../../../../shared/giphy/giphy_picker.dart';
// Shared composer with audience-specific attachment menus and validation.
// Public creator chat supports text and pack GIFs/stickers; private Messages
// supports media and editing; Rooms retains documents and archives.

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

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
    this.compact = false,
    this.audience = ChatAudience.rooms,
    this.surfaceColor = PhlioColors.surfaceInput,
  });

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

    // Stickers and GIFs come from the bundled Foxy pack — no file system.
    if (pickedType == 'Sticker' || pickedType == 'GIF') {
      final item = await showGiphyPicker(context,
          kind: pickedType == 'GIF' ? 'gif' : 'sticker');
      if (item == null || !mounted) return;
      setState(() {
        _staged.add(
          StagedAttachment(
            kind: item.kind,
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
            padding: widget.audience == ChatAudience.directMessage &&
                    !_isRecording
                ? const EdgeInsets.fromLTRB(6, 6, 8, 6)
                : EdgeInsets.symmetric(
                    horizontal: PhlioSpacing.md,
                    vertical: widget.compact ? 4 : 6,
                  ),
            decoration: widget.audience == ChatAudience.directMessage
                ? BoxDecoration(
                    // Messages: borderless pill, like the reference.
                    color: const Color(0xFF26292F),
                    borderRadius: BorderRadius.circular(32),
                    border: _isRecording
                        ? Border.all(color: PhlioColors.danger)
                        : null,
                  )
                : BoxDecoration(
                    color: widget.surfaceColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isRecording
                          ? PhlioColors.danger
                          : PhlioColors.borderSubtle,
                    ),
                  ),
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
                  !_foxyTrayTab,
                  () => setState(() => _foxyTrayTab = false),
                ),
                const SizedBox(width: PhlioSpacing.xs),
                _trayToggle(
                  'Foxy',
                  _foxyTrayTab,
                  () => setState(() => _foxyTrayTab = true),
                ),
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
    Widget action(String label, String icon, VoidCallback tap) => IconButton(
        tooltip: label,
        onPressed: _isSending ? null : tap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 42, height: 46),
        icon: _svg(icon));
    final typing = _canSend || _isSending;
    return Row(children: [
      Material(
        color: const Color(0xFF3F5BF6),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _isSending ? null : _camera,
          child: Tooltip(
              message: 'Camera',
              child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(child: _svg('camera', size: 24)))),
        ),
      ),
      Expanded(
          child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 4,
              maxLength: 4000,
              enabled: !_isSending,
              textInputAction: TextInputAction.send,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                  hintText: 'Message…',
                  hintStyle: TextStyle(color: Color(0xFF9EA3AD), fontSize: 16),
                  counterText: '',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
              style: const TextStyle(fontSize: 16, color: Colors.white))),
      if (typing)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Material(
            color: const Color(0xFF3F5BF6),
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: _isSending ? null : _send,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
        action('Voice message', 'mic', _startRecording),
        action('Photos and videos', 'image',
            () => _pickAttachments(type: 'Image')),
        action('Stickers', 'sticker', () {
          _focusNode.unfocus();
          _pickAttachments(type: 'Sticker');
        }),
        Builder(
            builder: (buttonContext) => action(
                _moreOpen ? 'Close' : 'More',
                _moreOpen ? 'close_circle' : 'plus_circle',
                () => _openMoreMenu(buttonContext))),
      ],
    ]);
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

  Future<void> _shareLocation() async {
    final place = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: const Text('Share a location'),
              content: TextField(
                  controller: place,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (v) => Navigator.pop(dialog, v.trim()),
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.location_on_outlined),
                      hintText: 'Place, address or landmark')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, place.text.trim()),
                    child: const Text('Share')),
              ],
            ));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    place.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    try {
      await widget.onSendText(
          '📍 $value\nhttps://maps.google.com/?q=${Uri.encodeComponent(value)}');
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

  Widget _inputRow() {
    return Row(
      children: [
        // Attachments follow the conversation policy.
        GestureDetector(
          onTap: _isSending ? null : _pickAttachments,
          child: const Icon(
            Icons.add_rounded,
            size: 26,
            color: PhlioColors.textSecondary,
          ),
        ),
        Expanded(
          child: TextField(
            minLines: 1,
            maxLines: 4,
            maxLength: 4000,
            textInputAction: TextInputAction.send,
            controller: _textController,
            focusNode: _focusNode,
            style: PhlioTypography.body,
            enabled: !_isSending,
            onTap: () => setState(() => _showEmojiTray = false),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: widget.hint,
              counterText: '',
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
        if (widget.audience != ChatAudience.publicChat)
          GestureDetector(
            onLongPress: _startRecording,
            onTap: _startRecording,
            child: const Icon(
              Icons.mic_none_rounded,
              size: 22,
              color: PhlioColors.textSecondary,
            ),
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
            child: const Icon(
              Icons.send_rounded,
              color: PhlioColors.textOnBrand,
              size: 16,
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
                    top: 0,
                    left: 0,
                    child: IconButton.filledTonal(
                      tooltip: 'Edit media',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit, size: 18),
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
