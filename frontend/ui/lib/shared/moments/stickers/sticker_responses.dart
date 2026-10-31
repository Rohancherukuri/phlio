// Moment stickers — live stickers in the moment viewer.
//
// [MomentStickersOverlay] draws a moment's sticker overlays on top of the
// viewer's tap zones, so polls, sliders, questions, countdowns, likes, add
// yours and links can be used. Totals come from
// GET /social/moments/{id}/responses and refresh after every answer
// (POST …/respond). The author sees results and who answered.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import '../../../design_system/colors.dart';
import '../../../design_system/widgets/phlio_card.dart' show PhlioAvatar;
import 'sticker_model.dart';
import 'sticker_tray.dart' show askText;
import 'sticker_views.dart';

/// Response totals for a moment, keyed by sticker id.
final momentResponsesProvider = FutureProvider.autoDispose.family<Map<String, StickerResponse>, String>((ref, momentId) async {
  final data = (await getIt<ApiClient>().dio.get('/social/moments/${Uri.encodeComponent(momentId)}/responses')).data as Map;
  return {for (final e in data.entries) '${e.key}': StickerResponse.fromJson(e.value as Map)};
});

/// The stickers of [item] (a moment JSON) that the viewer draws live:
/// interactive ones always; on videos every sticker (photos have the rest
/// baked in).
List<MomentSticker> liveStickers(Map item) {
  final video = item['media_kind'] == 'video';
  return [
    for (final raw in (item['overlays'] as List? ?? const []))
      if (raw is Map)
        if (MomentSticker.fromJson(raw) case final s?)
          if (s.interactive || (video && s.type != StickerType.foxy)) s
  ];
}

class MomentStickersOverlay extends ConsumerStatefulWidget {
  const MomentStickersOverlay({
    required this.item,
    required this.isAuthor,
    required this.onPause,
    required this.onResume,
    required this.onAnswer,
    this.onAddYours,
    super.key,
  });

  /// The moment (id, overlays, media_kind…).
  final Map item;
  final bool isAuthor;
  final VoidCallback onPause, onResume;

  /// Sends a question answer to the author's DMs.
  final Future<void> Function(String prompt, String answer) onAnswer;

  /// Starts a new moment for an "Add yours" prompt.
  final void Function(String prompt)? onAddYours;

  @override
  ConsumerState<MomentStickersOverlay> createState() => _MomentStickersOverlayState();
}

class _MomentStickersOverlayState extends ConsumerState<MomentStickersOverlay> {
  Map<String, StickerResponse>? _fresh; // totals returned by the last answer

  String get _id => '${widget.item['id']}';

  Future<void> _respond(MomentSticker s, Object value) async {
    try {
      final res = await getIt<ApiClient>().dio.post('/social/moments/${Uri.encodeComponent(_id)}/respond',
          data: {'sticker': s.id, 'value': value});
      final data = res.data as Map;
      if (mounted) setState(() => _fresh = {for (final e in data.entries) '${e.key}': StickerResponse.fromJson(e.value as Map)});
    } catch (_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Couldn\'t send that. Try again.')));
    }
  }

  Future<void> _ask(MomentSticker s) async {
    widget.onPause();
    final prompt = '${s.data['prompt'] ?? 'Question'}';
    final answer = await askText(context, prompt, 'Type your answer…');
    if (answer != null && answer.isNotEmpty) {
      await _respond(s, answer);
      await widget.onAnswer(prompt, answer);
    }
    widget.onResume();
  }

  Future<void> _results(MomentSticker s, StickerResponse? r) async {
    widget.onPause();
    final people = r?.people ?? const [];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .6),
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(_title(s, r), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            if (people.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No responses yet.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
              ),
            for (final p in people)
              ListTile(
                leading: PhlioAvatar(
                    name: '${(p['user'] as Map?)?['display_name'] ?? ''}',
                    imageUrl: (p['user'] as Map?)?['avatar_url'] as String?,
                    size: 40,
                    showMomentRing: false),
                title: Text('${(p['user'] as Map?)?['display_name'] ?? ''}', style: const TextStyle(color: Colors.white)),
                subtitle: Text(_value(s, p['value']), style: const TextStyle(color: Colors.white70)),
              ),
          ]),
        ),
      ),
    );
    widget.onResume();
  }

  String _title(MomentSticker s, StickerResponse? r) => switch (s.type) {
        StickerType.poll => '${s.data['question']} · ${r?.count ?? 0} votes',
        StickerType.question => '${s.data['prompt']} · ${r?.count ?? 0} answers',
        StickerType.slider => '${s.data['prompt']} · ${r?.count ?? 0} responses',
        StickerType.countdown => '${s.data['title']} · ${r?.count ?? 0} reminders',
        StickerType.addyours => '${s.data['prompt']} · ${r?.count ?? 0} added theirs',
        _ => '${r?.count ?? 0} responses',
      };

  String _value(MomentSticker s, Object? v) => switch (s.type) {
        StickerType.poll => () {
            final options = s.data['options'] as List? ?? const [];
            return v is int && v < options.length ? 'Voted “${options[v]}”' : 'Voted';
          }(),
        StickerType.slider => '${s.data['emoji'] ?? ''} ${((v as num? ?? 0) * 100).round()}%',
        StickerType.question => '$v',
        StickerType.countdown => 'Wants a reminder',
        _ => 'Responded',
      };

  @override
  Widget build(BuildContext context) {
    final stickers = liveStickers(widget.item);
    if (stickers.isEmpty) return const SizedBox.shrink();
    final needsTotals = stickers.any((s) => respondingStickers.contains(s.type));
    final totals = _fresh ?? (needsTotals ? ref.watch(momentResponsesProvider(_id)).valueOrNull : null) ?? const {};
    final actions = StickerActions(
      isAuthor: widget.isAuthor,
      respond: _respond,
      ask: _ask,
      addYours: (s) => widget.onAddYours?.call('${s.data['prompt'] ?? ''}'),
      openLink: (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      showResults: (s) => _results(s, totals[s.id]),
    );
    return LayoutBuilder(
      builder: (_, box) => MomentStickerLayer(
        stickers: stickers,
        canvasWidth: box.maxWidth,
        builder: (s) => MomentStickerView(s, response: totals[s.id], actions: actions),
      ),
    );
  }
}
