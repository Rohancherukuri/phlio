import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../../design_system/widgets/phlio_fox.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';

final socialCommentsProvider =
    FutureProvider.autoDispose.family<List, String>((ref, id) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  return ((await getIt<ApiClient>().dio.get('/social/content/$id/comments'))
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

class SocialCommentsSheet extends ConsumerStatefulWidget {
  const SocialCommentsSheet(
      {required this.contentId,
      this.embedded = false,
      this.onProfileTap,
      super.key});
  final String contentId;
  final bool embedded;
  final void Function(String)? onProfileTap;
  @override
  ConsumerState<SocialCommentsSheet> createState() =>
      _SocialCommentsSheetState();
}

class _SocialCommentsSheetState extends ConsumerState<SocialCommentsSheet> {
  final text = TextEditingController();
  String? path, sticker, error;
  bool sending = false, stickers = false;
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

  Widget composer() {
    final user = ref.watch(authControllerProvider).valueOrNull;
    return SafeArea(
        top: false,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                  height: 52,
                  child: LayoutBuilder(
                      builder: (context, bounds) => SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
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
                              SizedBox(
                                  width:
                                      (bounds.maxWidth / 8).clamp(40.0, 64.0),
                                  child: IconButton(
                                      tooltip: 'Insert $emoji',
                                      onPressed: sending
                                          ? null
                                          : () => insertEmoji(emoji),
                                      icon: Text(emoji,
                                          style:
                                              const TextStyle(fontSize: 25)))),
                          ])))),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                PhlioAvatar(
                    name: user?.fullName ?? 'You',
                    imageUrl: user?.avatarUrl,
                    size: 34),
                const SizedBox(width: 8),
                Expanded(
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF303A4A)),
                            borderRadius: BorderRadius.circular(28)),
                        child: Row(children: [
                          Expanded(
                            child: TextField(
                                controller: text,
                                onChanged: (value) {
                                  setState(() {});
                                  searchMentions(value);
                                },
                                minLines: 1,
                                maxLines: 3,
                                maxLength: 2000,
                                style: const TextStyle(fontSize: 14),
                                decoration: const InputDecoration(
                                    counterText: '',
                                    hintText: 'What do you think?',
                                    filled: false,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none)),
                          ),
                          IconButton(
                              tooltip: 'Attach image',
                              visualDensity: VisualDensity.compact,
                              onPressed: sending ? null : () => pick(false),
                              icon: const Icon(Icons.image_outlined, size: 25)),
                          IconButton(
                              tooltip: 'Attach GIF',
                              visualDensity: VisualDensity.compact,
                              onPressed: sending ? null : () => pick(true),
                              icon:
                                  const Icon(Icons.gif_box_outlined, size: 25)),
                        ]))),
                IconButton(
                    tooltip: 'Stickers',
                    visualDensity: VisualDensity.compact,
                    onPressed: sending
                        ? null
                        : () => setState(() => stickers = !stickers),
                    icon: const Icon(Icons.card_giftcard_outlined, size: 26)),
                if (sending ||
                    text.text.trim().isNotEmpty ||
                    path != null ||
                    sticker != null)
                  IconButton(
                      tooltip: 'Post comment',
                      visualDensity: VisualDensity.compact,
                      onPressed: sending ? null : send,
                      icon: sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.arrow_upward_rounded,
                              color: Color(0xFF8D78FF))),
              ]),
            ])));
  }

  @override
  void dispose() {
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
      await getIt<ApiClient>()
          .dio
          .post('/social/content/${widget.contentId}/comments',
              data: FormData.fromMap({
                'text': text.text.trim(),
                if (sticker != null) 'sticker_id': sticker,
                if (path != null) 'image': await MultipartFile.fromFile(path!),
              }));
      ref.invalidate(socialCommentsProvider(widget.contentId));
      if (mounted)
        setState(() {
          text.clear();
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
                  child: comments.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) => Center(
                          child: TextButton(
                              onPressed: () => ref.invalidate(
                                  socialCommentsProvider(widget.contentId)),
                              child: const Text(
                                  'Could not load comments. Retry'))),
                      data: (items) => items.isEmpty
                          ? const Center(
                              child: Text('Start the conversation',
                                  style: TextStyle(color: Color(0xFF858D9E))))
                          : ListView.builder(
                              itemCount: items.length,
                              padding: const EdgeInsets.all(16),
                              itemBuilder: (context, i) {
                                final item = items[i] as Map,
                                    author = item['author'] as Map;
                                return Padding(
                                    padding: const EdgeInsets.only(bottom: 20),
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          GestureDetector(
                                              onTap: widget.onProfileTap == null
                                                  ? null
                                                  : () => widget.onProfileTap!(
                                                      author['id'] as String),
                                              child: PhlioAvatar(
                                                  name: author['display_name']
                                                      as String,
                                                  imageUrl: author['avatar_url']
                                                      as String?,
                                                  profileId: widget
                                                              .onProfileTap ==
                                                          null
                                                      ? author['id'] as String
                                                      : null,
                                                  size: 34)),
                                          const SizedBox(width: 12),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(
                                                    author['username']
                                                        as String,
                                                    style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700)),
                                                if ((item['text'] as String)
                                                    .isNotEmpty)
                                                  Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 4),
                                                      child: Text(
                                                          item['text']
                                                              as String,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 14,
                                                                  height:
                                                                      1.4))),
                                                if (item['image_url'] != null)
                                                  Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 8),
                                                      child: ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                          child: Image.network(
                                                              AppConfig.mediaUrl(
                                                                  item['image_url']
                                                                      as String),
                                                              height: 150,
                                                              fit: BoxFit
                                                                  .contain,
                                                              errorBuilder: (_,
                                                                      __,
                                                                      ___) =>
                                                                  const Text('Image unavailable')))),
                                                if (item['sticker_id'] != null)
                                                  PhlioStickerView(
                                                      stickerId:
                                                          item['sticker_id']
                                                              as String,
                                                      size: 80),
                                                for (final person
                                                    in (item['mentions'] as List? ??
                                                        []))
                                                  InkWell(
                                                      onTap: () => widget
                                                                  .onProfileTap !=
                                                              null
                                                          ? widget.onProfileTap!(
                                                              person['id']
                                                                  as String)
                                                          : context.push(
                                                              '/creator/${person['id']}'),
                                                      child: Text(
                                                          '@${person['username']}',
                                                          style: const TextStyle(
                                                              fontSize: 12,
                                                              color: Color(0xFF72A7FF)))),
                                                const SizedBox(height: 6),
                                                Text(
                                                    item['created_at']
                                                        .toString()
                                                        .split('T')
                                                        .first,
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            Color(0xFF858D9E))),
                                              ])),
                                        ]));
                              }))),
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
                  if (stickers)
                    SizedBox(
                        height: 80,
                        child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final s in PhlioStickers.catalog)
                                InkWell(
                                    onTap: () => setState(() {
                                          sticker = s.id;
                                          stickers = false;
                                        }),
                                    child: Tooltip(
                                        message: s.label,
                                        child: PhlioStickerView(
                                            stickerId: s.id, size: 64)))
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
