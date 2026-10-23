import 'dart:ui';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../giphy/giphy_picker.dart';
import 'content_surface.dart' show engagementProvider;
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../../design_system/widgets/phlio_fox.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../../features/profile/presentation/controllers/avatar_controller.dart';

String commentUrl(String id) =>
    '/social/content/${id.contains('/') ? id.substring(id.indexOf('/') + 1) : id}/comments';
Map<String, dynamic> commentQuery(String id) =>
    {'platform': id.contains('/') ? id.split('/').first : 'social'};

/// The engagement-bar key for a comment thread id, so the comment count on
/// the bar refreshes as soon as a comment is posted or hidden.
String commentEngagementPath(String id) => id.contains('/') ? id : 'social/$id';

/// Refresh every surface that shows this thread's comment count: the
/// comment list (under both its bare and `platform/ref` keys) and the
/// engagement bar / details sheet / clips rail.
void refreshCommentCounts(WidgetRef ref, String id) {
  final path = commentEngagementPath(id);
  ref.invalidate(socialCommentsProvider(id));
  ref.invalidate(socialCommentsProvider(path));
  if (path.startsWith('social/')) {
    ref.invalidate(socialCommentsProvider(path.substring('social/'.length)));
  }
  ref.invalidate(engagementProvider(path));
}

final socialCommentsProvider =
    FutureProvider.autoDispose.family<List, String>((ref, id) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  return ((await getIt<ApiClient>()
          .dio
          .get(commentUrl(id), queryParameters: commentQuery(id)))
      .data as Map)['items'] as List;
});

Future<void> showSocialComments(BuildContext context, String id) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF111925),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SocialCommentsSheet(contentId: id),
    );

/// The same Social discussion surface, embedded after an item's details.
class ContentDiscussion extends StatelessWidget {
  const ContentDiscussion({required this.contentId, super.key});
  final String contentId;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF111925),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
            height: 520,
            child: SocialCommentsSheet(contentId: contentId, embedded: true)),
      );
}

class SocialCommentsSheet extends ConsumerStatefulWidget {
  const SocialCommentsSheet(
      {required this.contentId,
      this.embedded = false,
      this.onProfileTap,
      this.onPickerChanged,
      super.key});
  final String contentId;
  final bool embedded;
  final ValueChanged<bool>? onPickerChanged;
  final void Function(String)? onProfileTap;
  @override
  ConsumerState<SocialCommentsSheet> createState() =>
      _SocialCommentsSheetState();
}

class _SocialCommentsSheetState extends ConsumerState<SocialCommentsSheet> {
  final text = TextEditingController();
  final composerFocus = FocusNode();
  final expandedThreads = <String>{};
  String? path, sticker, error;
  Map? replying;
  bool sending = false;
  String? pickerKind;
  List people = [];
  int mentionRequest = 0;
  void insertEmoji(String emoji) {
    final selection = text.selection;
    final start = selection.isValid ? selection.start : text.text.length;
    final end = selection.isValid ? selection.end : text.text.length;
    final value = text.text.replaceRange(start, end, emoji);
    if (value.length > 2000) return;
    text.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: start + emoji.length));
    setState(() {});
  }

  String age(Map item) {
    final date = DateTime.tryParse(item['created_at'].toString());
    if (date == null) return '';
    final elapsed = DateTime.now().difference(date);
    if (elapsed.inDays >= 7) return '${elapsed.inDays ~/ 7}w';
    if (elapsed.inDays > 0) return '${elapsed.inDays}d';
    if (elapsed.inHours > 0) return '${elapsed.inHours}h';
    if (elapsed.inMinutes > 0) return '${elapsed.inMinutes}m';
    return 'now';
  }

  Future<void> translate(Map item) async {
    final locale = Localizations.localeOf(context).languageCode;
    try {
      final opened = await launchUrl(
          Uri.https('translate.google.com', '/', {
            'sl': 'auto',
            'tl': locale,
            'text': item['text'] as String,
            'op': 'translate'
          }),
          mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('Unavailable');
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not open translation. Try again.');
    }
  }

  Future<void> react(Map item) async {
    try {
      await getIt<ApiClient>().dio.put(
          '${commentUrl(widget.contentId)}/${item['id']}/like',
          queryParameters: {
            ...commentQuery(widget.contentId),
            'liked': item['liked_by_me'] != true
          });
      ref.invalidate(socialCommentsProvider(widget.contentId));
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not update reaction. Try again.');
    }
  }

  Widget commentTile(Map item, {bool highlighted = false}) {
    final author = item['author'] as Map;
    final me = ref.read(authControllerProvider).valueOrNull;
    return GestureDetector(
        onLongPress: highlighted ? null : () => commentMenu(item),
        child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            color: highlighted ? const Color(0xFF272A30) : Colors.transparent,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                  onTap: highlighted
                      ? null
                      : () {
                          if (widget.onProfileTap != null) {
                            widget.onProfileTap!(author['id'] as String);
                          } else {
                            context.push(author['id'] == me?.id
                                ? '/profile'
                                : '/creator/${author['id']}');
                          }
                        },
                  child: author['id'] == me?.id
                      ? MeAvatar(name: me!.fullName, size: 34)
                      : PhlioAvatar(
                          name: author['display_name'] as String? ?? 'User',
                          imageUrl: author['avatar_url'] as String?,
                          size: 34)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Wrap(spacing: 6, children: [
                      Text(
                          author['username'] as String? ??
                              author['display_name'] as String? ??
                              'User',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(age(item),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12))
                    ]),
                    if ((item['text'] as String? ?? '').isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(item['text'] as String,
                              style:
                                  const TextStyle(fontSize: 14, height: 1.35))),
                    if (item['image_url'] != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                  AppConfig.mediaUrl(
                                      item['image_url'] as String),
                                  height: 180,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      const Text('Image unavailable')))),
                    if (item['sticker_id'] != null)
                      PhlioStickerView(
                          stickerId: item['sticker_id'] as String, size: 150),
                    if (!highlighted)
                      Wrap(spacing: 16, children: [
                        TextButton(
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 32),
                                foregroundColor: Colors.white60),
                            onPressed: () {
                              setState(() => replying = item);
                              composerFocus.requestFocus();
                            },
                            child: const Text('Reply')),
                        if ((item['text'] as String? ?? '').isNotEmpty)
                          TextButton(
                              style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 32),
                                  foregroundColor: Colors.white60),
                              onPressed: () => translate(item),
                              child: const Text('See translation')),
                      ]),
                  ])),
              const SizedBox(width: 6),
              Column(children: [
                IconButton(
                    tooltip: 'Like comment',
                    visualDensity: VisualDensity.compact,
                    onPressed: highlighted ? null : () => react(item),
                    icon: Icon(
                        item['liked_by_me'] == true
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 20,
                        color: item['liked_by_me'] == true
                            ? Colors.pinkAccent
                            : Colors.white60)),
                Text('${item['likes_count'] ?? 0}',
                    style: const TextStyle(fontSize: 12, color: Colors.white60))
              ]),
            ])));
  }

  Future<void> commentMenu(Map item) async {
    FocusScope.of(context).unfocus();
    final mine = (item['author'] as Map)['id'] ==
        ref.read(authControllerProvider).valueOrNull?.id;
    final action = await showGeneralDialog<String>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss comment actions',
        barrierColor: Colors.black26,
        transitionDuration: const Duration(milliseconds: 220),
        transitionBuilder: (context, animation, secondary, child) =>
            FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                    scale: Tween<double>(begin: .95, end: 1).animate(
                        CurvedAnimation(
                            parent: animation, curve: Curves.easeOutCubic)),
                    child: child)),
        pageBuilder: (dialogContext, _, __) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
            child: SafeArea(
                child: Center(
                    child: Material(
                        color: Colors.transparent,
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child:
                                          commentTile(item, highlighted: true)),
                                  const SizedBox(height: 12),
                                  Container(
                                      width: 220,
                                      decoration: BoxDecoration(
                                          color: const Color(0xFF252A32),
                                          borderRadius:
                                              BorderRadius.circular(24)),
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                                leading: const Icon(
                                                    Icons.send_outlined),
                                                title: const Text('Share'),
                                                onTap: () => Navigator.pop(
                                                    dialogContext, 'share')),
                                            if (mine)
                                              ListTile(
                                                  leading: const Icon(
                                                      Icons
                                                          .delete_outline_rounded,
                                                      color: Colors.redAccent),
                                                  title: const Text('Delete',
                                                      style: TextStyle(
                                                          color: Colors
                                                              .redAccent)),
                                                  onTap: () => Navigator.pop(
                                                      dialogContext,
                                                      'delete')),
                                            ListTile(
                                                leading: const Icon(
                                                    Icons.report_outlined,
                                                    color: Colors.redAccent),
                                                title: const Text('Report',
                                                    style: TextStyle(
                                                        color:
                                                            Colors.redAccent)),
                                                onTap: () => Navigator.pop(
                                                    dialogContext, 'report')),
                                            if (!mine)
                                              ListTile(
                                                  leading:
                                                      const Icon(Icons.block),
                                                  title: const Text('Block'),
                                                  onTap: () => Navigator.pop(
                                                      dialogContext, 'block')),
                                          ])),
                                ])))))));
    if (!mounted || action == null) return;
    try {
      if (action == 'share') {
        await SharePlus.instance.share(ShareParams(
            text:
                '${(item['author'] as Map)['username']}: ${item['text']}\nphlio://app/shared/${widget.contentId.contains('/') ? widget.contentId : 'social/${widget.contentId}'}'));
      } else if (action == 'delete') {
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
                    title: const Text('Delete comment?'),
                    content: const Text(
                        'This removes your comment and any replies to it.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Delete'))
                    ]));
        if (confirmed != true) return;
        await getIt<ApiClient>().dio.delete(
            '${commentUrl(widget.contentId)}/${item['id']}',
            queryParameters: commentQuery(widget.contentId));
        refreshCommentCounts(ref, widget.contentId);
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Comment deleted.')));
      } else if (action == 'report') {
        await getIt<ApiClient>().dio.post(
            '${commentUrl(widget.contentId)}/${item['id']}/report',
            queryParameters: commentQuery(widget.contentId));
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Comment reported.')));
      } else if (action == 'block') {
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
                    title: const Text('Block this account?'),
                    content: const Text(
                        'Their comments will no longer appear for you.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Block'))
                    ]));
        if (confirmed != true) return;
        await getIt<ApiClient>()
            .dio
            .put('/social/blocks/${(item['author'] as Map)['id']}');
        refreshCommentCounts(ref, widget.contentId);
      }
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not complete this action. Try again.');
    }
  }

  Widget composer() {
    final user = ref.watch(authControllerProvider).valueOrNull;
    return SafeArea(
        top: false,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (replying != null)
                Row(children: [
                  Expanded(
                      child: Text(
                          'Replying to ${(replying!['author'] as Map)['display_name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                  IconButton(
                      tooltip: 'Cancel reply',
                      onPressed: () => setState(() => replying = null),
                      icon: const Icon(Icons.close, size: 18))
                ]),
              if (pickerKind == null)
                SizedBox(
                    height: 56,
                    child: Row(children: [
                      for (final emoji in [
                        '❤️',
                        '🙌',
                        '🔥',
                        '👏',
                        '🙏',
                        '🚩',
                        '😮',
                        '😂'
                      ])
                        Expanded(
                            child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints:
                                    const BoxConstraints(minHeight: 44),
                                tooltip: 'Insert $emoji',
                                onPressed:
                                    sending ? null : () => insertEmoji(emoji),
                                icon: Text(emoji,
                                    textScaler: TextScaler.noScaling,
                                    style: const TextStyle(fontSize: 25)))),
                    ])),
              // Avatar · [text · image · GIF] pill · gift (or send).
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                MeAvatar(name: user?.fullName ?? 'You', size: 38),
                const SizedBox(width: 10),
                Expanded(
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: Colors.transparent,
                            border: Border.all(color: const Color(0xFF3A4352)),
                            borderRadius: BorderRadius.circular(28)),
                        child: Row(children: [
                          Expanded(
                            child: TextField(
                                controller: text,
                                focusNode: composerFocus,
                                onChanged: (value) {
                                  setState(() {});
                                  searchMentions(value);
                                },
                                minLines: 1,
                                maxLines: 3,
                                maxLength: 2000,
                                style: const TextStyle(
                                    fontSize: 15, color: Color(0xFFF1F3F8)),
                                decoration: const InputDecoration(
                                    counterText: '',
                                    hintText: 'What do you think of this?',
                                    hintMaxLines: 1,
                                    isDense: true,
                                    hintStyle: TextStyle(
                                        color: Color(0xFF9AA1AE), fontSize: 15),
                                    filled: false,
                                    contentPadding: EdgeInsets.fromLTRB(
                                        16, 13, 4, 13),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none)),
                          ),
                          _ComposerIcon(
                              tooltip: 'Add a photo',
                              icon: Icons.image_outlined,
                              asset: 'assets/images/chat_icons/image.svg',
                              onTap: sending ? null : pickPhoto),
                          _ComposerIcon(
                              tooltip: 'GIFs and stickers',
                              icon: Icons.gif_box_outlined,
                              active: pickerKind != null,
                              onTap: sending ? null : () => pickGiphy('gif')),
                          const SizedBox(width: 6),
                        ]))),
                const SizedBox(width: 6),
                if (sending ||
                    text.text.trim().isNotEmpty ||
                    path != null ||
                    sticker != null)
                  IconButton(
                      tooltip: 'Post comment',
                      onPressed: sending ? null : send,
                      icon: sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.arrow_upward_rounded,
                              size: 26, color: Color(0xFF8D78FF)))
                else
                  IconButton(
                      tooltip: 'Send a gift',
                      onPressed: () => showCreatorGiftsPlaceholder(context),
                      icon: const Icon(Icons.card_giftcard_rounded,
                          size: 28, color: Color(0xFFF1F3F8))),
              ]),
            ])));
  }

  @override
  void dispose() {
    composerFocus.dispose();
    text.dispose();
    super.dispose();
  }

  Future<void> searchMentions(String value) async {
    final token = ++mentionRequest;
    final match = RegExp(r'@([A-Za-z0-9_]*)$').firstMatch(value);
    if (match == null) {
      setState(() => people = []);
      return;
    }
    try {
      final result = await getIt<ApiClient>()
          .dio
          .get('/social/comment-mentions', queryParameters: {'q': match[1]});
      if (mounted && token == mentionRequest)
        setState(() => people = result.data as List);
    } catch (_) {
      if (mounted && token == mentionRequest) setState(() => people = []);
    }
  }

  void closePicker() {
    setState(() => pickerKind = null);
    widget.onPickerChanged?.call(false);
  }

  Future<void> pickGiphy(String kind) async {
    FocusScope.of(context).unfocus();
    setState(() => pickerKind = pickerKind == kind ? null : kind);
    widget.onPickerChanged?.call(pickerKind != null);
  }

  /// Image button: choose from the photo gallery, take a photo, or pick a
  /// file from local storage.
  Future<void> pickPhoto() async {
    FocusScope.of(context).unfocus();
    final source = await showModalBottomSheet<String>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Photo gallery'),
                  onTap: () => Navigator.pop(sheet, 'gallery')),
              ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take a photo'),
                  onTap: () => Navigator.pop(sheet, 'camera')),
              ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: const Text('Browse files'),
                  onTap: () => Navigator.pop(sheet, 'files')),
              const SizedBox(height: 8),
            ])));
    if (source == null || !mounted) return;
    if (source == 'files') return pick(false);
    try {
      final image = await ImagePicker().pickImage(
          source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 90);
      if (image == null || !mounted) return;
      if (await image.length() > 10 * 1024 * 1024) {
        setState(() => error = 'Choose an image or GIF under 10 MB.');
        return;
      }
      setState(() {
        path = image.path;
        error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Could not open ${source == 'camera' ? 'the camera' : 'your gallery'}. Check app permissions.');
      }
    }
  }

  Future<void> pick(bool gif) async {
    final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions:
            gif ? ['gif'] : ['jpg', 'jpeg', 'png', 'webp', 'gif']);
    if (picked == null || !mounted) return;
    if (picked.files.single.size > 10 * 1024 * 1024) {
      setState(() => error = 'Choose an image or GIF under 10 MB.');
      return;
    }
    setState(() {
      path = picked.files.single.path;
      error = null;
    });
  }

  Future<void> send() async {
    if (sending ||
        (text.text.trim().isEmpty && path == null && sticker == null)) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await getIt<ApiClient>().dio.post(commentUrl(widget.contentId),
          queryParameters: commentQuery(widget.contentId),
          data: FormData.fromMap({
            'text': text.text.trim(),
            if (replying != null) 'parent_id': replying!['id'],
            if (sticker != null) 'sticker_id': sticker,
            if (path != null) 'image': await MultipartFile.fromFile(path!),
          }));
      refreshCommentCounts(ref, widget.contentId);
      if (mounted)
        setState(() {
          text.clear();
          if (replying != null) expandedThreads.add(replying!['id'].toString());
          replying = null;
          path = null;
          sticker = null;
          people = [];
        });
    } catch (_) {
      if (mounted)
        setState(() => error =
            'Comment could not be sent. Your draft is saved here—try again.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = ref.watch(socialCommentsProvider(widget.contentId));
    return LayoutBuilder(builder: (context, constraints) {
      final inset =
          widget.embedded ? 0.0 : MediaQuery.viewInsetsOf(context).bottom;
      final height = (widget.embedded
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height * .82)
          .clamp(
              0.0, (constraints.maxHeight - inset).clamp(0.0, double.infinity));
      return Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: SizedBox(
            height: height,
            child: Column(children: [
              if (!widget.embedded) const SizedBox(height: 10),
              if (!widget.embedded)
                Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white38,
                        borderRadius: BorderRadius.circular(8))),
              Padding(
                  padding: EdgeInsets.all(widget.embedded ? 8 : 16),
                  child: Text(
                      'Comments${comments.hasValue ? ' · ${comments.value!.length}' : ''}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700))),
              const Divider(height: 1),
              Expanded(
                  child: pickerKind != null
                      ? Column(children: [
                          Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                  tooltip: 'Close GIF picker',
                                  icon: const Icon(Icons.close),
                                  onPressed: closePicker)),
                          Expanded(
                              child: GiphyPicker(
                                  key: ValueKey(pickerKind),
                                  initialKind: pickerKind!,
                                  onSelected: (item) => setState(() {
                                        sticker = item.reference;
                                        path = null;
                                        pickerKind = null;
                                        widget.onPickerChanged?.call(false);
                                      }))),
                        ])
                      : comments.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (_, __) => Center(
                              child: TextButton(
                                  onPressed: () => ref.invalidate(
                                      socialCommentsProvider(widget.contentId)),
                                  child: const Text(
                                      'Could not load comments. Retry'))),
                          data: (rawItems) {
                            final items = <dynamic>[];
                            final visited = <String>{};
                            void append(dynamic item) {
                              if (!visited.add(item['id'].toString())) return;
                              items.add(item);
                              if (!expandedThreads
                                  .contains(item['id'].toString())) return;
                              for (final child in rawItems
                                  .where((r) => r['parent_id'] == item['id'])) {
                                append(child);
                              }
                            }

                            for (final item in rawItems
                                .where((r) => r['parent_id'] == null)) {
                              append(item);
                            }
                            final ids = rawItems.map((r) => r['id']).toSet();
                            for (final item in rawItems.where((r) =>
                                r['parent_id'] != null &&
                                !ids.contains(r['parent_id']))) {
                              append(item);
                            }
                            return items.isEmpty
                                ? const Center(
                                    child: Text('Start the conversation',
                                        style: TextStyle(
                                            color: Color(0xFF858D9E))))
                                : ListView.builder(
                                    itemCount: items.length,
                                    padding: const EdgeInsets.all(16),
                                    itemBuilder: (context, i) {
                                      final item = items[i] as Map;
                                      return Padding(
                                          padding: EdgeInsets.only(
                                              left: item['parent_id'] == null
                                                  ? 0
                                                  : 34),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                commentTile(item),
                                                if (rawItems.any((r) =>
                                                    r['parent_id'] ==
                                                    item['id']))
                                                  Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              left: 46),
                                                      child: TextButton(
                                                          onPressed: () =>
                                                              setState(() {
                                                                final id = item[
                                                                        'id']
                                                                    .toString();
                                                                if (!expandedThreads
                                                                    .remove(id))
                                                                  expandedThreads
                                                                      .add(id);
                                                              }),
                                                          child: Text(expandedThreads
                                                                  .contains(item[
                                                                          'id']
                                                                      .toString())
                                                              ? 'Hide replies'
                                                              : 'View ${rawItems.where((r) => r['parent_id'] == item['id']).length} replies'))),
                                              ]));
                                    });
                          })),
              ConstrainedBox(
                key: const ValueKey('comment-composer'),
                constraints: BoxConstraints(maxHeight: height * .55),
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (people.isNotEmpty)
                    SizedBox(
                        height: 80,
                        child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final p in people)
                                TextButton(
                                    onPressed: () {
                                      final value = text.text.replaceFirst(
                                          RegExp(r'@[A-Za-z0-9_]*$'),
                                          '@${p['username']} ');
                                      text.value = TextEditingValue(
                                          text: value,
                                          selection: TextSelection.collapsed(
                                              offset: value.length));
                                      setState(() => people = []);
                                    },
                                    child: Text('@${p['username']}'))
                            ])),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(error!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.orangeAccent))),
                  if (path != null || sticker != null)
                    SizedBox(
                        height: 70,
                        child: Row(children: [
                          if (path != null)
                            Image.file(File(path!),
                                width: 65, height: 65, fit: BoxFit.cover),
                          if (sticker != null)
                            PhlioStickerView(stickerId: sticker!, size: 60),
                          IconButton(
                              tooltip: 'Remove attachment',
                              onPressed: () => setState(() {
                                    path = null;
                                    sticker = null;
                                  }),
                              icon: const Icon(Icons.close)),
                        ])),
                  composer(),
                ])),
              ),
            ]),
          ));
    });
  }
}

/// A 40px icon button for the comment composer pill.
class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon(
      {required this.tooltip,
      required this.icon,
      required this.onTap,
      this.asset,
      this.active = false});
  final String tooltip;
  final IconData icon;
  final String? asset;
  final VoidCallback? onTap;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF8D78FF) : const Color(0xFFF1F3F8);
    return IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
        icon: asset == null
            ? Icon(icon, size: 27, color: color)
            : SvgPicture.asset(asset!,
                width: 26,
                height: 26,
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn)));
  }
}

/// Placeholder for creator gifts — shows what is coming, sends nothing yet.
Future<void> showCreatorGiftsPlaceholder(BuildContext context) =>
    showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.card_giftcard_rounded,
                    size: 44, color: Color(0xFFFFB58F)),
                const SizedBox(height: 12),
                const Text('Gifts are coming soon',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text(
                    'Soon you\'ll be able to cheer on creators by sending them gifts right from the comments.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFC4C8D2), height: 1.4)),
                const SizedBox(height: 20),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final gift in const ['🌹', '☕', '🎉', '💎', '🚀'])
                        Opacity(
                            opacity: .55,
                            child: Container(
                                width: 52,
                                height: 52,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    color: const Color(0xFF202A3A),
                                    borderRadius: BorderRadius.circular(16)),
                                child: Text(gift,
                                    style: const TextStyle(fontSize: 26)))),
                    ]),
                const SizedBox(height: 20),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        onPressed: () => Navigator.pop(sheet),
                        child: const Text('Got it'))),
              ]),
            )));
