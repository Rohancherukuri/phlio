// Who watched your moment and what people said about it.
//
//   * [showMomentViewers] — the people icon: everyone who watched, newest
//     first with people who reacted at the top, their emoji on their
//     avatar, and whether they commented or answered a sticker.
//   * [showMomentComments] — the comments icon: the moment's public thread
//     (one level of replies). Write, reply, edit your own, delete your own
//     — the author can delete any.
//
// Every comment also lands in the moment author's DMs (and a reply lands
// in the DMs of the person replied to) — the server sends it.
//
// Backend: backend/app/api/v1/moments.py (viewers, reaction, comments).

import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../content/content_surface.dart' show showEndpointShare;
import '../content/mentions.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'moment_features.dart' show showMomentSettings, showProfilePeek, viewedClock;

const _sheetColor = PhlioColors.surface;

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
      barrierColor: Colors.black26,
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
  final search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  /// Search runs on the server (`?q=`), so it covers everyone who watched.
  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted || text.trim() == _query) return;
      _query = text.trim();
      _load();
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await getIt<ApiClient>().dio.get('/social/moments/${_momentId(widget.item)}/viewers',
          queryParameters: {if (_query.isNotEmpty) 'q': _query});
      if (!mounted) return;
      setState(() => data = res.data as Map);
      if (_query.isEmpty) widget.onCounts?.call(_counts!);
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
        initialChildSize: .58,
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
              IconButton(
                tooltip: 'Viewer notifications',
                onPressed: () => showMomentSettings(context),
                icon: const Icon(Icons.notifications_none_rounded, color: Colors.white70),
              ),
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
          if (data != null && ((data!['rewatches'] as num? ?? 0) > 0 || (data!['super_hearts'] as num? ?? 0) > 0))
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(children: [
                _Insight(icon: Icons.replay_rounded, value: '${data!['rewatches'] ?? 0}', label: 'Rewatches'),
                const SizedBox(width: 10),
                _Insight(icon: Icons.favorite_rounded, value: '${data!['super_hearts'] ?? 0}', label: 'Super hearts',
                    colour: const Color(0xFFFF3B5C)),
              ]),
            ),
          if (data != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: search,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search viewers',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                  filled: true,
                  fillColor: PhlioColors.surfaceElevated,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
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
                              _query.isNotEmpty
                                  ? 'No viewers match "$_query".'
                                  : reactedOnly ? 'No reactions yet.' : 'No one has watched this moment yet.',
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
    // When they watched (the latest time, Instagram-style "viewed at").
    final when = viewedClock(person['last_seen_at'] ?? person['seen_at']);
    final rewatches = (person['rewatches'] as num?)?.toInt() ?? 0;
    final superHeart = person['super_heart'] == true;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      onLongPress: () => showProfilePeek(context, person),
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
                child: superHeart
                    ? const Icon(Icons.favorite_rounded, size: 16, color: Color(0xFFFF3B5C))
                    : Text(reaction, style: const TextStyle(fontSize: 15)),
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
            if (superHeart) 'super heart' else if (reaction != null) 'reacted $reaction',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (rewatches > 0)
          Tooltip(
            message: 'Watched ${rewatches + 1} times',
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.replay_rounded, color: PhlioColors.brandViolet, size: 18),
                const SizedBox(width: 3),
                Text('$rewatches', style: const TextStyle(color: Colors.white70)),
              ]),
            ),
          ),
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

/// A small "12 Rewatches" tile above the viewer list.
class _Insight extends StatelessWidget {
  const _Insight({required this.icon, required this.value, required this.label, this.colour = PhlioColors.brandViolet});
  final IconData icon;
  final String value, label;
  final Color colour;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: PhlioColors.surfaceElevated, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(icon, color: colour, size: 20),
            const SizedBox(width: 8),
            Text(value, style: PhlioTypography.bodyStrong.copyWith(color: Colors.white)),
            const SizedBox(width: 6),
            Flexible(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 13))),
          ]),
        ),
      );
}

// -- comments -------------------------------------------------------------------------------

/// [onCount] gets the number of comments each time the list loads.
Future<void> showMomentComments(BuildContext context, Map item,
        {required bool isAuthor, String? owner, ValueChanged<int>? onCount}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _sheetColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      barrierColor: Colors.black26,
      builder: (_) => _CommentsSheet(item: item, isAuthor: isAuthor, owner: owner, onCount: onCount),
    );

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.item, required this.isAuthor, this.owner, this.onCount});
  final Map item;
  final bool isAuthor;

  /// The moment author's username.
  final String? owner;
  final ValueChanged<int>? onCount;
  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _text = MentionTextEditingController();
  final _focus = FocusNode();
  List<Map> items = [];
  bool loading = true, sending = false, allow = true;
  String? problem;
  Map? replyTo, editing;

  /// People matching the "@…" being typed.
  List<Map> people = [];
  int _mentionRequest = 0;

  String get _base => '/social/moments/${_momentId(widget.item)}/comments';

  Future<void> _searchMentions() async {
    final token = ++_mentionRequest;
    final query = mentionQuery(_text);
    if (query == null) {
      if (people.isNotEmpty) setState(() => people = []);
      return;
    }
    final found = await searchMentionPeople(query);
    if (mounted && token == _mentionRequest) setState(() => people = found);
  }

  void _startEdit(Map c) {
    setState(() {
      replyTo = null;
      editing = c;
      _text.text = '${c['text']}';
    });
    _focus.requestFocus();
  }

  /// Hold a comment: Share, Edit, Delete, Report, Block (Clips layout).
  Future<void> _menu(Map c) async {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    final user = c['user'] as Map? ?? const {};
    final mine = c['mine'] == true;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PhlioColors.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .06), borderRadius: BorderRadius.circular(16)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PhlioAvatar(
                  name: user['display_name'] as String? ?? '',
                  imageUrl: user['avatar_url'] as String?,
                  size: 32,
                  showMomentRing: false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${user['username'] ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('${c['text']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
                ]),
              ),
            ]),
          ),
          ListTile(
              leading: const Icon(Icons.send_outlined, color: Colors.white),
              title: const Text('Share', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(sheet, 'share')),
          if (mine)
            ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.white),
                title: const Text('Edit', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(sheet, 'edit')),
          if (c['can_delete'] == true)
            ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: PhlioColors.danger),
                title: const Text('Delete', style: TextStyle(color: PhlioColors.danger)),
                onTap: () => Navigator.pop(sheet, 'delete')),
          if (!mine)
            ListTile(
                leading: const Icon(Icons.report_outlined, color: PhlioColors.danger),
                title: const Text('Report', style: TextStyle(color: PhlioColors.danger)),
                onTap: () => Navigator.pop(sheet, 'report')),
          if (!mine)
            ListTile(
                leading: const Icon(Icons.block_rounded, color: PhlioColors.danger),
                title: Text('Block @${user['username'] ?? ''}', style: const TextStyle(color: PhlioColors.danger)),
                onTap: () => Navigator.pop(sheet, 'block')),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    final dio = getIt<ApiClient>().dio;
    try {
      switch (action) {
        case 'share':
          final owner = widget.owner ?? '';
          await showEndpointShare(context,
              endpoint: '$_base/${c['id']}/share',
              link: 'phlio://app/moments/$owner',
              quote: '@${user['username']}: ${c['text']}');
        case 'edit':
          _startEdit(c);
        case 'delete':
          await _delete(c);
        case 'report':
          await dio.post('$_base/${c['id']}/report', data: {'reason': 'Comment'});
          _say('Thanks — we\'ll review this comment.');
        case 'block':
          final ok = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              title: Text('Block @${user['username']}?'),
              content: const Text('They won\'t be able to find your profile or see your moments, and their comments disappear for you.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Block')),
              ],
            ),
          );
          if (ok != true) return;
          await dio.put('/social/blocks/${user['id']}');
          await _load();
          _say('Blocked @${user['username']}');
      }
    } catch (_) {
      _say('Could not complete this. Try again.');
    }
  }

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
          height: MediaQuery.sizeOf(context).height * .58,
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
                            onEdit: items[i]['mine'] == true ? () => _startEdit(items[i]) : null,
                            onDelete: items[i]['can_delete'] == true ? () => _delete(items[i]) : null,
                            onHold: () => _menu(items[i]),
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
                  MentionSuggestions(
                    people: people,
                    maxHeight: 200,
                    onPick: (p) {
                      applyMention(_text, '${p['username']}');
                      _mentionRequest++;
                      setState(() => people = []);
                    },
                  ),
                  if (people.isEmpty && editing == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                        for (final e in const ['❤️', '🙌', '🔥', '👏', '😢', '😍', '😮', '😂'])
                          GestureDetector(
                            onTap: () {
                              final sel = _text.selection;
                              final at = sel.isValid ? sel.start : _text.text.length;
                              final end = sel.isValid ? sel.end : _text.text.length;
                              _text.value = TextEditingValue(
                                  text: _text.text.replaceRange(at, end, e),
                                  selection: TextSelection.collapsed(offset: at + e.length));
                            },
                            child: Text(e, style: const TextStyle(fontSize: 27)),
                          ),
                      ]),
                    ),
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
                          onChanged: (_) => _searchMentions(),
                          maxLength: 500,
                          minLines: 1,
                          maxLines: 4,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: replyTo != null
                                ? 'Reply to ${(replyTo!['user'] as Map?)?['username'] ?? ''}…'
                                : widget.isAuthor || widget.owner == null
                                    ? 'Add a comment…'
                                    : 'Add a comment for ${widget.owner}…',
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
  const _CommentTile({required this.comment, this.onReply, this.onEdit, this.onDelete, this.onHold});
  final Map comment;
  final VoidCallback? onReply, onEdit, onDelete, onHold;

  @override
  Widget build(BuildContext context) {
    final user = comment['user'] as Map? ?? const {};
    final reply = comment['reply_to'] != null;
    final edited = comment['edited_at'] != null;
    const meta = TextStyle(color: Colors.white54, fontSize: 12.5, fontWeight: FontWeight.w600);
    return GestureDetector(
      onLongPress: onHold,
      behavior: HitTestBehavior.opaque,
      child: Padding(
      padding: EdgeInsets.fromLTRB(reply ? 64 : 16, 8, 12, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onLongPress: () => showProfilePeek(context, user),
          child: PhlioAvatar(
              name: user['display_name'] as String? ?? '',
              imageUrl: user['avatar_url'] as String?,
              size: reply ? 30 : 40,
              showMomentRing: false),
        ),
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
            MentionText('${comment['text']}', style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3)),
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
    ),
    );
  }
}
