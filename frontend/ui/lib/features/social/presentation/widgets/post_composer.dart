import '../../../../shared/realtime/create_space_screen.dart';
import '../../../../design_system/colors.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../app/config/app_config.dart';
import '../../../../shared/music/song_picker.dart';
import '../../../../shared/giphy/giphy_picker.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../profile/presentation/controllers/avatar_controller.dart';
import '../controllers/feed_controller.dart';

class PostComposer extends ConsumerStatefulWidget {
  const PostComposer({super.key});
  @override
  ConsumerState<PostComposer> createState() => _PostComposerState();
}

class _PostComposerState extends ConsumerState<PostComposer> {
  final text = TextEditingController();
  final storage = const FlutterSecureStorage();
  final List<Map<String, dynamic>> media = [];
  Map? song;
  Map<String, dynamic>? poll;
  bool busy = false;
  static const accent = PhlioColors.brandOrange;
  final List<Map<String, dynamic>> pendingPosts = [];
  Map<String, dynamic> currentDraft() => {
        'text': text.text,
        'media': List<Map<String, dynamic>>.from(media),
        'song': song,
        'poll': poll == null ? null : jsonDecode(jsonEncode(poll))
      };
  void loadDraft(Map data) {
    text.text = data['text'] as String? ?? '';
    media
      ..clear()
      ..addAll((data['media'] as List? ?? [])
          .map((m) => Map<String, dynamic>.from(m as Map)));
    song = data['song'] as Map?;
    poll = data['poll'] == null
        ? null
        : Map<String, dynamic>.from(data['poll'] as Map);
  }

  void addPost() {
    if (text.text.trim().isEmpty && media.isEmpty) return;
    setState(() {
      pendingPosts.add(currentDraft());
      text.clear();
      media.clear();
      song = null;
      poll = null;
    });
  }

  void editPost(int index) {
    setState(() {
      final selected = pendingPosts[index];
      pendingPosts[index] = currentDraft();
      loadDraft(selected);
    });
  }

  String get draftKey =>
      'post_draft_${ref.read(authControllerProvider).valueOrNull?.id}';
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void error(Object e) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is DioException
              ? (e.response?.data is Map
                  ? '${e.response?.data['detail'] ?? 'Could not save. Please try again.'}'
                  : 'Could not connect. Your draft is still here.')
              : 'Could not complete this action. Please try again.')));
  }

  Future<void> saveDraft() async {
    await storage.write(
        key: draftKey,
        value: jsonEncode({...currentDraft(), 'pending': pendingPosts}));
  }

  Future<void> close() async {
    if (pendingPosts.isNotEmpty ||
        text.text.isNotEmpty ||
        media.isNotEmpty ||
        song != null ||
        poll != null) {
      final save = await showDialog<bool>(
          context: context,
          builder: (c) =>
              AlertDialog(title: const Text('Save draft?'), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Discard')),
                TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Save'))
              ]));
      if (save == null) return;
      if (save) {
        try {
          await saveDraft();
        } catch (e) {
          error(e);
          return;
        }
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> restore() async {
    try {
      final raw = await storage.read(key: draftKey);
      if (!mounted) return;
      if (raw == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No saved draft yet.')));
        return;
      }
      final data = jsonDecode(raw) as Map;
      setState(() {
        loadDraft(data);
        pendingPosts
          ..clear()
          ..addAll((data['pending'] as List? ?? [])
              .map((p) => Map<String, dynamic>.from(p as Map)));
      });
    } catch (e) {
      error(e);
    }
  }

  Future<void> upload(String path, {bool audio = false}) async {
    setState(() => busy = true);
    try {
      final result = await ref.read(musicApiProvider).post(
          '/social/composer/upload',
          data: FormData.fromMap({'file': await MultipartFile.fromFile(path)}));
      if (!mounted) return;
      setState(() {
        if (audio) {
          song = result.data as Map;
        } else {
          media.add(Map<String, dynamic>.from(result.data as Map));
        }
      });
    } catch (e) {
      error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> photo(ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(source: source);
      if (image != null && mounted) await upload(image.path);
    } catch (e) {
      error(e);
    }
  }

  Future<void> music() async {
    final source = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.audio_file),
                  title: const Text('From device'),
                  onTap: () => Navigator.pop(c, 'local')),
              ListTile(
                  leading: const Icon(Icons.music_note),
                  title: const Text('From Spotify'),
                  onTap: () => Navigator.pop(c, 'spotify'))
            ])));
    if (!mounted || source == null) return;
    try {
      if (source == 'local') {
        final picked = await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['mp3', 'm4a', 'wav', 'ogg', 'aac', 'flac']);
        final path = picked?.files.single.path;
        if (path != null && mounted) await upload(path, audio: true);
      } else {
        final selected = await showSongPicker(context);
        if (selected == null || !mounted) return;
        await ref.read(musicApiProvider).put('/music/selection',
            data: {'id': selected['id'], 'context': 'post'});
        if (mounted) setState(() => song = selected);
      }
    } catch (e) {
      error(e);
    }
  }

  Future<void> post() async {
    setState(() => busy = true);
    try {
      // Move the active post into the queue once. Successfully published
      // entries are removed immediately so retrying a later failure is safe.
      if (text.text.trim().isNotEmpty || media.isNotEmpty) {
        pendingPosts.add(currentDraft());
        text.clear();
        media.clear();
        song = null;
        poll = null;
      }
      pendingPosts.removeWhere((p) =>
          (p['text'] as String).trim().isEmpty && (p['media'] as List).isEmpty);
      while (pendingPosts.isNotEmpty) {
        final draft = pendingPosts.first;
        await ref.read(musicApiProvider).post('/social/posts', data: {
          'text': (draft['text'] as String).trim(),
          'tags': <String>[],
          'media': draft['media'],
          if (draft['song'] != null) 'music_id': (draft['song'] as Map)['id'],
          if (draft['poll'] != null) 'poll': draft['poll'],
        });
        pendingPosts.removeAt(0);
        ref.invalidate(feedControllerProvider);
        try {
          await saveDraft();
        } catch (_) {}
      }
      ref.invalidate(feedControllerProvider);
      // Publishing succeeded: draft cleanup must not cause a duplicate retry.
      try {
        await storage.delete(key: draftKey);
      } catch (_) {}
      if (mounted) Navigator.pop(context);
    } catch (e) {
      error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> choiceImage(int index) async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null || !mounted || poll == null) return;
      final targetPoll = poll;
      setState(() => busy = true);
      final result = await ref.read(musicApiProvider).post(
          '/social/composer/upload',
          data: FormData.fromMap(
              {'file': await MultipartFile.fromFile(image.path)}));
      if (mounted && identical(poll, targetPoll))
        setState(() => (poll!['choices'] as List)[index]['image_url'] =
            result.data['url']);
    } catch (e) {
      error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget pollEditor() {
    final choices = poll!['choices'] as List;
    return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            border: Border.all(color: PhlioColors.border),
            borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          for (var i = 0; i < choices.length; i++)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  IconButton(
                      tooltip: 'Image for choice ${i + 1}',
                      onPressed: busy ? null : () => choiceImage(i),
                      icon: choices[i]['image_url'] == null
                          ? const Icon(Icons.image_outlined, color: accent)
                          : Image.network(
                              AppConfig.mediaUrl(
                                  choices[i]['image_url'] as String),
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover)),
                  Expanded(
                      child: TextFormField(
                          key: ObjectKey(choices[i]),
                          initialValue: choices[i]['text'] as String,
                          enabled: !busy,
                          maxLength: 80,
                          onChanged: (value) => choices[i]['text'] = value,
                          decoration: InputDecoration(
                              hintText: 'Choice ${i + 1}',
                              counterText: 'What’s happening?',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12))))),
                  if (i == 0)
                    IconButton(
                        tooltip: 'Remove poll',
                        onPressed:
                            busy ? null : () => setState(() => poll = null),
                        icon: const Icon(Icons.close))
                  else if (i == choices.length - 1 && choices.length < 4)
                    IconButton(
                        tooltip: 'Add choice',
                        onPressed: busy
                            ? null
                            : () => setState(() => choices.add({'text': ''})),
                        icon: const Icon(Icons.add, color: accent))
                  else if (i >= 2)
                    IconButton(
                        tooltip: 'Remove choice',
                        onPressed: busy
                            ? null
                            : () => setState(() => choices.removeAt(i)),
                        icon: const Icon(Icons.remove_circle_outline))
                  else
                    const SizedBox(width: 48),
                ])),
          const Divider(),
          DropdownButtonFormField<int>(
              initialValue: poll!['minutes'] as int,
              decoration: const InputDecoration(
                  labelText: 'Poll length', border: InputBorder.none),
              items: const [
                DropdownMenuItem(value: 60, child: Text('1 hour')),
                DropdownMenuItem(value: 1440, child: Text('1 day')),
                DropdownMenuItem(value: 4320, child: Text('3 days')),
                DropdownMenuItem(value: 10080, child: Text('7 days'))
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() => poll!['minutes'] = value)),
        ]));
  }

  Widget threadRow(String name,
          {required bool connected, required Widget child}) =>
      Stack(children: [
        if (connected)
          Positioned(
              left: 20,
              top: 47,
              bottom: 5,
              child: Container(width: 2, color: PhlioColors.borderSubtle)),
        ConstrainedBox(
            constraints: BoxConstraints(minHeight: connected ? 90 : 42),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MeAvatar(name: name, size: 42),
              const SizedBox(width: 12),
              Expanded(
                  child: Padding(
                      padding: EdgeInsets.only(bottom: connected ? 24 : 0),
                      child: child)),
            ])),
      ]);

  Widget tool(IconData icon, String label, VoidCallback? action) => Expanded(
      child: SizedBox(
          height: 44,
          child: IconButton(
              tooltip: label,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: busy ? null : action,
              icon: Icon(icon,
                  size: 23,
                  color: busy || action == null
                      ? PhlioColors.textMuted
                      : accent))));
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !busy) close();
        },
        child: Theme(
            data: Theme.of(context),
            child: Scaffold(
                backgroundColor: PhlioColors.background,
                appBar: AppBar(
                    backgroundColor: PhlioColors.background,
                    surfaceTintColor: PhlioColors.background,
                    leading: IconButton(
                        tooltip: 'Close',
                        onPressed: busy ? null : close,
                        icon: const Icon(Icons.close)),
                    actions: [
                      TextButton(
                          onPressed: busy ? null : restore,
                          child: const Text('Drafts',
                              style: TextStyle(
                                  color: accent, fontWeight: FontWeight.bold))),
                      Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: PhlioColors.textOnBrand),
                              onPressed: busy ||
                                      (pendingPosts.isEmpty &&
                                          text.text.trim().isEmpty &&
                                          media.isEmpty)
                                  ? null
                                  : post,
                              child: Text(busy
                                  ? 'Postingâ€¦'
                                  : pendingPosts.isNotEmpty
                                      ? 'Post all'
                                      : 'Post')))
                    ]),
                body: SafeArea(
                    top: false,
                    child: Column(children: [
                      Expanded(
                          child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(children: [
                                for (var i = 0; i < pendingPosts.length; i++)
                                  threadRow(user?.fullName ?? 'You',
                                      connected: true,
                                      child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                                child: InkWell(
                                                    onTap: busy
                                                        ? null
                                                        : () => editPost(i),
                                                    child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                vertical: 10),
                                                        child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                  (pendingPosts[i]
                                                                                  ['text']
                                                                              as String)
                                                                          .isEmpty
                                                                      ? 'Media post'
                                                                      : pendingPosts[i]
                                                                              ['text']
                                                                          as String,
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          19,
                                                                      height:
                                                                          1.45,
                                                                      color: PhlioColors
                                                                          .textSecondary)),
                                                              if ((pendingPosts[
                                                                              i]
                                                                          [
                                                                          'media']
                                                                      as List)
                                                                  .isNotEmpty)
                                                                Text(
                                                                    '${(pendingPosts[i]['media'] as List).length} attachments',
                                                                    style: const TextStyle(
                                                                        color: PhlioColors
                                                                            .textMuted)),
                                                              if (pendingPosts[
                                                                          i][
                                                                      'poll'] !=
                                                                  null)
                                                                const Text(
                                                                    'Poll',
                                                                    style: TextStyle(
                                                                        color:
                                                                            accent)),
                                                              if (pendingPosts[
                                                                          i][
                                                                      'song'] !=
                                                                  null)
                                                                Text(
                                                                    '${pendingPosts[i]['song']['title']}',
                                                                    style: const TextStyle(
                                                                        color:
                                                                            accent)),
                                                            ])))),
                                            IconButton(
                                                tooltip: 'Remove post ${i + 1}',
                                                onPressed: busy
                                                    ? null
                                                    : () => setState(() =>
                                                        pendingPosts
                                                            .removeAt(i)),
                                                icon: const Icon(Icons.close,
                                                    size: 18,
                                                    color:
                                                        PhlioColors.textMuted)),
                                          ])),
                                threadRow(user?.fullName ?? 'You',
                                    connected: false,
                                    child: Column(children: [
                                      TextField(
                                          controller: text,
                                          onChanged: (_) => setState(() {}),
                                          maxLength: 2000,
                                          minLines: 1,
                                          maxLines: null,
                                          style: const TextStyle(
                                              fontSize: 20,
                                              color: PhlioColors.textPrimary),
                                          decoration: InputDecoration(
                                              hintText: poll != null
                                                  ? 'Ask a question...'
                                                  : 'What’s happening?',
                                              filled: false,
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 9),
                                              enabledBorder: InputBorder.none,
                                              focusedBorder: InputBorder.none,
                                              disabledBorder: InputBorder.none,
                                              errorBorder: InputBorder.none,
                                              focusedErrorBorder:
                                                  InputBorder.none,
                                              border: InputBorder.none,
                                              counterText: '')),
                                      if (poll != null) pollEditor(),
                                      for (final item in media)
                                        Stack(children: [
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 12),
                                              child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  child: Image.network(
                                                      AppConfig.mediaUrl(
                                                          item['url']
                                                              as String),
                                                      errorBuilder: (_, __,
                                                              ___) =>
                                                          const Text(
                                                              'Image unavailable')))),
                                          Positioned(
                                              right: 0,
                                              top: 0,
                                              child: IconButton.filled(
                                                  tooltip: 'Remove attachment',
                                                  onPressed: busy
                                                      ? null
                                                      : () => setState(() =>
                                                          media.remove(item)),
                                                  icon:
                                                      const Icon(Icons.close)))
                                        ]),
                                      if (song != null)
                                        ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: const Icon(
                                                Icons.music_note,
                                                color: accent),
                                            title: Text('${song!['title']}'),
                                            subtitle: Text(
                                                song!['source'] == 'local'
                                                    ? 'From device'
                                                    : 'Spotify'),
                                            trailing: IconButton(
                                                tooltip: 'Remove song',
                                                onPressed: busy
                                                    ? null
                                                    : () => setState(
                                                        () => song = null),
                                                icon: const Icon(Icons.close)))
                                    ]))
                              ]))),
                      const Divider(height: 1),
                      const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          child: Row(children: [
                            Icon(Icons.public, color: accent, size: 18),
                            SizedBox(width: 12),
                            Text('Everyone can reply',
                                style: TextStyle(color: accent))
                          ])),
                      const Divider(height: 1),
                      Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Row(children: [
                            tool(Icons.image_outlined, 'Photos',
                                () => photo(ImageSource.gallery)),
                            tool(Icons.camera_alt_outlined, 'Camera',
                                () => photo(ImageSource.camera)),
                            tool(
                                Icons.mic_none_outlined,
                                'Create Space',
                                () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const CreateSpaceScreen()))),
                            tool(Icons.gif_box_outlined, 'GIF', () async {
                              final gif = await showGiphyPicker(context);
                              if (gif != null && mounted)
                                setState(() => media
                                    .add({'url': gif.url, 'kind': 'image'}));
                            }),
                            tool(
                                Icons.ballot_outlined,
                                'Add poll',
                                () => setState(() => poll ??= {
                                      'choices': [
                                        {'text': ''},
                                        {'text': ''}
                                      ],
                                      'minutes': 1440
                                    })),
                            tool(Icons.location_on_outlined,
                                'Location tagging is not available', null),
                            tool(Icons.music_note_outlined, 'Add music', music),
                            tool(
                                Icons.add_circle_outline,
                                'Add another post',
                                text.text.trim().isEmpty && media.isEmpty
                                    ? null
                                    : addPost)
                          ]))
                    ])))));
  }
}
