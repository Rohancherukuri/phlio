// @mentions for every comment box in Phlio (Social posts, videos, clips,
// Stream, Book, Shop, News, moments).
//
//   * [mentionQuery] — the "@ro…" being typed just before the cursor.
//   * [searchMentionPeople] — people on Phlio matching it
//     (GET /social/comment-mentions, blocked accounts left out).
//   * [MentionSuggestions] — the list above the keyboard: photo, username,
//     name. Picking one calls [applyMention], which fills in "@username ".
//   * [MentionText] — comment text with @handles highlighted; tap one to
//     open that profile.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/widgets/phlio_card.dart';

/// Usernames are letters, digits, "_" and "." (not at the end).
final mentionPattern = RegExp(r'@([A-Za-z0-9_](?:[A-Za-z0-9_.]*[A-Za-z0-9_])?)');

const mentionColor = Color(0xFF9DB4FF);

/// The partial handle being typed right before the cursor ("" just after
/// "@"), or null when the cursor isn't in a mention.
String? mentionQuery(TextEditingController controller) {
  final text = controller.text;
  final at = controller.selection.isValid ? controller.selection.baseOffset : text.length;
  final before = text.substring(0, at.clamp(0, text.length));
  final m = RegExp(r'(?:^|[\s(])@([A-Za-z0-9_.]{0,30})$').firstMatch(before);
  return m?.group(1);
}

/// Replaces the "@partial" before the cursor with "@username ".
void applyMention(TextEditingController controller, String username) {
  final text = controller.text;
  final at = controller.selection.isValid ? controller.selection.baseOffset : text.length;
  final cut = at.clamp(0, text.length);
  final start = text.substring(0, cut).lastIndexOf('@');
  if (start < 0) return;
  final insert = '@$username ';
  final next = text.replaceRange(start, cut, insert);
  controller.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + insert.length));
}

Future<List<Map>> searchMentionPeople(String query) async {
  try {
    final res = await getIt<ApiClient>().dio.get('/social/comment-mentions', queryParameters: {'q': query});
    return (res.data as List).whereType<Map>().toList();
  } catch (_) {
    return const [];
  }
}

/// People matching the mention being typed (Instagram-style list).
class MentionSuggestions extends StatelessWidget {
  const MentionSuggestions({required this.people, required this.onPick, this.maxHeight = 220, super.key});
  final List people;
  final ValueChanged<Map> onPick;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1F27),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: people.length,
        itemBuilder: (_, i) {
          final p = people[i] as Map;
          final name = '${p['display_name'] ?? p['full_name'] ?? ''}';
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: PhlioAvatar(
                name: name.isEmpty ? '${p['username']}' : name,
                imageUrl: p['avatar_url'] as String?,
                size: 36,
                showMomentRing: false),
            title: Text('${p['username']}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            subtitle: name.isEmpty ? null : Text(name, style: const TextStyle(color: Colors.white54)),
            onTap: () => onPick(p),
          );
        },
      ),
    );
  }
}

/// Comment text with @mentions highlighted and tappable.
class MentionText extends StatefulWidget {
  const MentionText(this.text, {this.style, this.onMention, super.key});
  final String text;
  final TextStyle? style;

  /// Defaults to opening /creator/<username>.
  final ValueChanged<String>? onMention;

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  final _taps = <TapGestureRecognizer>[];

  void _clear() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in mentionPattern.allMatches(widget.text)) {
      if (m.start > 0 && RegExp(r'[A-Za-z0-9_.]').hasMatch(widget.text[m.start - 1])) continue; // an e-mail
      if (m.start > last) spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      final username = m.group(1)!;
      final tap = TapGestureRecognizer()
        ..onTap = () {
          if (widget.onMention != null) {
            widget.onMention!(username);
          } else {
            GoRouter.of(context).push('/creator/${Uri.encodeComponent(username)}');
          }
        };
      _taps.add(tap);
      spans.add(TextSpan(
          text: m.group(0),
          recognizer: tap,
          style: const TextStyle(color: mentionColor, fontWeight: FontWeight.w600)));
      last = m.end;
    }
    if (last < widget.text.length) spans.add(TextSpan(text: widget.text.substring(last)));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
