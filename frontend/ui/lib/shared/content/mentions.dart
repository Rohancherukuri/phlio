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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart' show routerProvider;
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../moments/moments.dart' show MomentRingAvatar;

/// Usernames are letters, digits, "_" and "." (not at the end).
final mentionPattern = RegExp(r'@([A-Za-z0-9_](?:[A-Za-z0-9_.]*[A-Za-z0-9_])?)');

const mentionColor = Color(0xFF9DB4FF);

/// A text field controller that colours @mentions while you type — the
/// "@" turns blue the moment you type it, and the handle stays blue as it
/// grows. Use it for every comment / caption box.
class MentionTextEditingController extends TextEditingController {
  MentionTextEditingController({super.text});

  static final _live = RegExp(r'(?<![A-Za-z0-9_.])@[A-Za-z0-9_.]*');

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final value = text;
    if (!value.contains('@')) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _live.allMatches(value)) {
      if (m.start > last) spans.add(TextSpan(text: value.substring(last, m.start)));
      spans.add(TextSpan(
          text: m.group(0),
          style: const TextStyle(color: mentionColor, fontWeight: FontWeight.w600)));
      last = m.end;
    }
    if (last < value.length) spans.add(TextSpan(text: value.substring(last)));
    return TextSpan(style: style, children: spans);
  }
}

/// Opens a profile from a mention, also from places outside the app's
/// router (the full-screen video player sits above it).
void openMentionProfile(BuildContext context, String username) {
  final location = '/creator/${Uri.encodeComponent(username)}';
  final router = GoRouter.maybeOf(context);
  if (router != null) {
    router.push(location);
  } else {
    ProviderScope.containerOf(context, listen: false).read(routerProvider).push(location);
  }
}

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
  const MentionSuggestions({required this.people, required this.onPick, this.maxHeight = 260, super.key});
  final List people;
  final ValueChanged<Map> onPick;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    // Slides open as you type "@…" and closes when there's nothing to show.
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: people.isEmpty
          ? const SizedBox(width: double.infinity)
          : Container(
              constraints: BoxConstraints(maxHeight: maxHeight),
              decoration: BoxDecoration(
                color: const Color(0xFF151D29),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                border: Border.all(color: Colors.white.withValues(alpha: .07)),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: people.length,
                itemBuilder: (_, i) => MentionPersonRow(person: people[i] as Map, onPick: onPick, index: i),
              ),
            ),
    );
  }
}

/// One suggestion: circle photo (with the moment ring when they have a live
/// moment, exactly like the moments rail), name and @username.
class MentionPersonRow extends StatelessWidget {
  const MentionPersonRow({required this.person, required this.onPick, this.index = 0, super.key});
  final Map person;
  final ValueChanged<Map> onPick;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = person;
    final name = '${p['display_name'] ?? p['full_name'] ?? ''}';
    final shown = name.isEmpty ? '${p['username']}' : name;
    const size = 46.0;
    final plain = PhlioAvatar(name: shown, imageUrl: p['avatar_url'] as String?, size: size, showMomentRing: false);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 180 + 40 * (index < 6 ? index : 6)),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child)),
      child: InkWell(
        onTap: () => onPick(p),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(children: [
            MomentRingAvatar(
              userId: '${p['id'] ?? p['username'] ?? ''}',
              imageUrl: p['avatar_url'] as String?,
              size: size,
              plain: plain,
              // Tapping the photo picks the person here instead of opening
              // their moment, so the list behaves like one control.
              onTapOverride: () => onPick(p),
              ringed: (inner) => PhlioAvatar(name: shown, imageUrl: p['avatar_url'] as String?, size: inner, showMomentRing: false),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(shown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5)),
                Text('@${p['username']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ]),
            ),
          ]),
        ),
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
            openMentionProfile(context, username);
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
