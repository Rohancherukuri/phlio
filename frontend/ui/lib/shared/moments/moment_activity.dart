// Who watched your moment and what people said about it.
//
//   * [showMomentViewers] — the people icon: everyone who watched, newest
//     first with people who reacted at the top, their emoji on their
//     avatar, and whether they commented or answered a sticker.
//   * [showMomentComments] — the comments icon: the moment's public thread
//     (one level of replies). Write, reply, edit your own, delete your own
//     — the author can delete any.
//
// Backend: backend/app/api/v1/moments.py (viewers, reaction, comments).

import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/phlio_card.dart';

const _sheetColor = Color(0xFF15181E);

String _momentId(Map item) {
  final id = '${item['id']}';
  return id.startsWith('social_moment:') ? id.substring('social_moment:'.length) : id;
}

String _ago(Object? at) {
  final t = DateTime.tryParse('${at ?? ''}');
  return t == null ? '' : timeago.format(t, locale: 'en_short');
}

// -- viewers --------------------------------------------------------------------------------

/// [onCounts] gets the latest `{views, reactions, comments}` once loaded.
Future<void> showMomentViewers(BuildContext context, Map item,
        {VoidCallback? onComments, ValueChanged<Map<String, int>>? onCounts}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _sheetColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _ViewersSheet(item: item, onComments: onComments, onCounts: onCounts),
    );

class _ViewersSheet extends StatefulWidget {
  const _ViewersSheet({required this.item, this.onComments, this.onCounts});
  final Map item;
  final VoidCallback? onComments;
  final ValueChanged<Map<String, int>>? onCounts;
  @override
  State<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends State<_ViewersSheet> {
  Map? data;
  String? problem;
  bool reactedOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await getIt<ApiClient>().dio.get('/social/moments/${_momentId(widget.item)}/viewers');
      if (!mounted) return;
      setState(() => data = res.data as Map);
      widget.onCounts?.call(_counts!);
    } catch (_) {
      if (mounted) setState(() => problem = 'Could not load viewers.');
    }
  }

  Map<String, int>? get _counts => data == null
      ? null
      : {
          'views': (data!['count'] as num?)?.toInt() ?? 0,
          'reactions': (data!['reactions'] as num?)?.toInt() ?? 0,
          'comments': (data!['comments'] as num?)?.toInt() ?? 0,
        };

  @override
  Widget build(BuildContext context) {
    final people = [
      for (final p in (data?['people'] as List? ?? const []).cast<Map>())
        if (!reactedOnly || p['reaction'] != null) p
    ];
    return DraggableScrollableSheet(
        expand: false,
        initialChildSize: .62,
        minChildSize: .35,
        maxChildSize: .95,
        builder: (context, scroll) => Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(children: [
              const Icon(Icons.people_alt_outlined, color: Colors.white),
              const SizedBox(width: 10),
              Text(data == null ? 'Viewers' : '${data!['count']} viewer${data!['count'] == 1 ? '' : 's'}',
                  style: PhlioTypography.title.copyWith(color: Colors.white)),
              const Spacer(),
              if (widget.onComments != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onComments!();
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Colors.white70),
                  label: Text('${data?['comments'] ?? ''}', style: const TextStyle(color: Colors.white70)),
                ),
            ]),
          ),
          if (data != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: !reactedOnly,
                  onSelected: (_) => setState(() => reactedOnly = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Reactions · ${data!['reactions']}'),
                  selected: reactedOnly,
                  onSelected: (_) => setState(() => reactedOnly = true),
                ),
              ]),
            ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: data == null
                ? Center(
                    child: problem == null
                        ? const CircularProgressIndicator()
                        : Text(problem!, style: const TextStyle(color: Colors.white60)))
                : people.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                              reactedOnly ? 'No reactions yet.' : 'No one has watched this moment yet.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white60)),
                        ),
                      )
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: people.length,
                        itemBuilder: (_, i) => _ViewerTile(person: people[i]),
                      ),
          ),
        ]),
    );
  }
}

class _ViewerTile extends StatelessWidget {
  const _ViewerTile({required this.person});
  final Map person;

  @override
  Widget build(BuildContext context) {
    final reaction = person['reaction'] as String?;
    final comments = (person['comments'] as num?)?.toInt() ?? 0;
    final responses = (person['responses'] as num?)?.toInt() ?? 0;
    final when = _ago(person['reacted_at'] ?? person['seen_at']);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      leading: SizedBox(
        width: 48,
        height: 48,
        child: Stack(clipBehavior: Clip.none, children: [
          PhlioAvatar(
              name: person['display_name'] as String? ?? '',
              imageUrl: person['avatar_url'] as String?,
              size: 46,
              showMomentRing: false),
          if (reaction != null)
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: _sheetColor, shape: BoxShape.circle),
                child: Text(reaction, style: const TextStyle(fontSize: 15)),
              ),
            ),
        ]),
      ),
      title: Text(person['display_name'] as String? ?? '',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      subtitle: Text(
          [
            '@${person['username']}',
            if (when.isNotEmpty) when,
            if (reaction != null) 'reacted $reaction',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (responses > 0)
          Tooltip(
            message: 'Answered your stickers',
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.how_to_vote_outlined, color: Colors.white54, size: 18),
                const SizedBox(width: 3),
                Text('$responses', style: const TextStyle(color: Colors.white54)),
              ]),
            ),
          ),
        if (comments > 0)
          Tooltip(
            message: 'Commented',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 3),
              Text('$comments', style: const TextStyle(color: Colors.white70)),
            ]),
          ),
      ]),
    );
  }
}

// -- comments -------------------------------------------------------------------------------

/// [onCount] gets the number of comments each time the list loads.
Future<void> showMomentComments(BuildContext context, Map item, {required bool isAuthor, ValueChanged<int>? onCount}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _sheetColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _CommentsSheet(item: item, isAuthor: isAuthor, onCount: onCount),
    );

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.item, required this.isAuthor, this.onCount});
  final Map item;
  final bool isAuthor;
  final ValueChanged<int>? onCount;
  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  List<Map> items = [];
  bool loading = true, sending = false, allow = true;
  String? problem;
  Map? replyTo, editing;

  String get _base => '/social/moments/${_momentId(widget.item)}/comments';

  @override
  void initState() {
    super.initState();
    allow = widget.item['allow_comments'] != false;
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = (await getIt<ApiClient>().dio.get(_base)).data as Map;
      if (!mounted) return;
      setState(() {
        items = (data['items'] as List).cast<Map>();
        allow = data['allow_comments'] != false;
        loading = false;
      });
      widget.onCount?.call(items.length);
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          problem = 'Could not load comments.';
        });
      }
    }
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    final dio = getIt<ApiClient>().dio;
    try {
      if (editing != null) {
        await dio.put('$_base/${editing!['id']}', data: {'text': text});
      } else {
        await dio.post(_base, data: {'text': text, if (replyTo != null) 'reply_to': replyTo!['id']});
      }
      _text.clear();
      setState(() {
        replyTo = null;
        editing = null;
      });
      await _load();
    } catch (_) {
      _say(allow || widget.isAuthor ? 'Could not post your comment. Try again.' : 'Comments are turned off.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _delete(Map c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete comment?'),
        content: Text(c['reply_to'] == null ? 'Replies to it are deleted too.' : 'This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: PhlioColors.danger),
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await getIt<ApiClient>().dio.delete('$_base/${c['id']}');
      await _load();
    } catch (_) {
      _say('Could not delete the comment.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = allow || widget.isAuthor;
    return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: Column(children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(children: [
                const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text(loading ? 'Comments' : '${items.length} comment${items.length == 1 ? '' : 's'}',
                    style: PhlioTypography.title.copyWith(color: Colors.white)),
              ]),
            ),
            const Divider(height: 1, color: Colors.white12),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              problem ?? (canWrite ? 'No comments yet. Start the conversation.' : 'Comments are turned off.'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white60),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _CommentTile(
                            comment: items[i],
                            onReply: canWrite
                                ? () {
                                    setState(() {
                                      editing = null;
                                      replyTo = items[i];
                                    });
                                    _focus.requestFocus();
                                  }
                                : null,
                            onEdit: items[i]['mine'] == true
                                ? () {
                                    setState(() {
                                      replyTo = null;
                                      editing = items[i];
                                      _text.text = '${items[i]['text']}';
                                    });
                                    _focus.requestFocus();
                                  }
                                : null,
                            onDelete: items[i]['can_delete'] == true ? () => _delete(items[i]) : null,
                          ),
                        ),
            ),
            if (!canWrite)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('The author turned off comments for this moment.', style: TextStyle(color: Colors.white54)),
              )
            else
              SafeArea(
                top: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (replyTo != null || editing != null)
                    Container(
                      color: Colors.white.withValues(alpha: .05),
                      padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            editing != null
                                ? 'Editing your comment'
                                : 'Replying to @${(replyTo!['user'] as Map?)?['username'] ?? ''}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() {
                            if (editing != null) _text.clear();
                            replyTo = null;
                            editing = null;
                          }),
                          icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                        ),
                      ]),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _text,
                          focusNode: _focus,
                          maxLength: 500,
                          minLines: 1,
                          maxLines: 4,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: replyTo != null ? 'Write a reply…' : 'Add a comment…',
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: .07),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        onPressed: sending ? null : _send,
                        style: IconButton.styleFrom(backgroundColor: PhlioColors.brandPeach),
                        icon: sending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(editing != null ? Icons.check_rounded : Icons.arrow_upward_rounded, color: Colors.black),
                      ),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, this.onReply, this.onEdit, this.onDelete});
  final Map comment;
  final VoidCallback? onReply, onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final user = comment['user'] as Map? ?? const {};
    final reply = comment['reply_to'] != null;
    final edited = comment['edited_at'] != null;
    const meta = TextStyle(color: Colors.white54, fontSize: 12.5, fontWeight: FontWeight.w600);
    return Padding(
      padding: EdgeInsets.fromLTRB(reply ? 64 : 16, 8, 12, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PhlioAvatar(
            name: user['display_name'] as String? ?? '',
            imageUrl: user['avatar_url'] as String?,
            size: reply ? 30 : 40,
            showMomentRing: false),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(user['display_name'] as String? ?? user['username'] as String? ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              if (comment['by_author'] == true) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: PhlioColors.brandPeach.withValues(alpha: .2), borderRadius: BorderRadius.circular(6)),
                  child: const Text('Author', style: TextStyle(color: PhlioColors.brandPeach, fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
              ],
              const SizedBox(width: 6),
              Text(_ago(comment['created_at']), style: meta),
            ]),
            if (reply && comment['reply_to_user'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Row(children: [
                  const Icon(Icons.subdirectory_arrow_right_rounded, color: Colors.white38, size: 14),
                  Text(' @${comment['reply_to_user']}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ]),
              ),
            const SizedBox(height: 3),
            Text('${comment['text']}', style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3)),
            const SizedBox(height: 6),
            Wrap(spacing: 16, children: [
              if (edited)
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.sync_rounded, color: Colors.white38, size: 13),
                  SizedBox(width: 3),
                  Text('Edited', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ]),
              if (onReply != null) GestureDetector(onTap: onReply, child: const Text('Reply', style: meta)),
              if (onEdit != null)
                GestureDetector(
                  onTap: onEdit,
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.edit_outlined, color: Colors.white54, size: 14),
                    SizedBox(width: 3),
                    Text('Edit', style: meta),
                  ]),
                ),
              if (onDelete != null) GestureDetector(onTap: onDelete, child: const Text('Delete', style: meta)),
            ]),
          ]),
        ),
      ]),
    );
  }
}
