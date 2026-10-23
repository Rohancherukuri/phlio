// Phlio Spaces — live audio conversations in Social.
//
//  * [SpacesBar]: the pill(s) at the top of the Posts feed — up to three
//    faces, "+N · Title" and a live equaliser. Tap to preview.
//  * [showSpacePreview]: the join sheet — REC badge, title, host/speakers
//    grid, "Listen anonymously" and Start Listening; ⋯ offers "Not
//    interested" and "Report".
//  * [showRecordSpaceInfo] / [showGetToKnowSpaces]: explainer sheets used
//    by Create your Space.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../../features/profile/presentation/controllers/avatar_controller.dart';
import 'realtime_screen.dart';

// -- Data ---------------------------------------------------------------------

/// Live audio Spaces, refreshed every 20 seconds while visible.
final liveSpacesProvider = FutureProvider.autoDispose<List<Map>>((ref) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  final timer = Timer(const Duration(seconds: 20), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  try {
    final items = ((await getIt<ApiClient>().dio.get('/realtime/live')).data
            as Map)['items'] as List;
    return items
        .whereType<Map>()
        .where((s) => s['audio_only'] == true)
        .toList();
  } catch (_) {
    return const []; // Audio server not configured: no Spaces bar.
  }
});

final spaceParticipantsProvider =
    FutureProvider.autoDispose.family<Map, String>((ref, id) async {
  final timer = Timer(const Duration(seconds: 10), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return (await getIt<ApiClient>().dio.get('/realtime/live/$id/participants'))
      .data as Map;
});

/// Spaces the viewer marked "Not interested" this session.
final hiddenSpacesProvider = StateProvider<Set<String>>((ref) => {});

const _violet = PhlioColors.brandViolet;
const _rec = Color(0xFFFF4F79);

// -- Feed bar -------------------------------------------------------------------

class SpacesBar extends ConsumerWidget {
  const SpacesBar({this.header, super.key});

  /// Optional heading shown only when there are live Spaces.
  final String? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hiddenSpacesProvider);
    final spaces = (ref.watch(liveSpacesProvider).valueOrNull ?? const [])
        .where((s) => !hidden.contains(s['id']))
        .toList();
    if (spaces.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(header!, style: PhlioTypography.title),
          ),
        for (final space in spaces.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SpacePill(space: space),
          ),
      ]),
    );
  }
}

class _SpacePill extends StatelessWidget {
  const _SpacePill({required this.space});
  final Map space;

  @override
  Widget build(BuildContext context) {
    final preview =
        ((space['preview'] as List?) ?? const []).whereType<Map>().toList();
    final count = (space['participants_count'] as num?)?.toInt() ??
        ((space['viewers'] as num?)?.toInt() ?? 0) + 1;
    final extra = count - preview.length;
    return Material(
      color: _violet.withValues(alpha: .18),
      shape: StadiumBorder(
          side: BorderSide(color: _violet.withValues(alpha: .35))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => showSpacePreview(context, space),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
          child: Row(children: [
            _FaceStack(people: preview, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  if (extra > 0)
                    TextSpan(
                        text: '+$extra · ',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: space['title'] as String? ?? 'Space'),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhlioTypography.bodyStrong
                    .copyWith(fontSize: 15, color: PhlioColors.textPrimary),
              ),
            ),
            const SizedBox(width: 10),
            const _Equaliser(),
          ]),
        ),
      ),
    );
  }
}

class _FaceStack extends StatelessWidget {
  const _FaceStack({required this.people, required this.size});
  final List<Map> people;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return CircleAvatar(
          radius: size / 2,
          backgroundColor: _violet.withValues(alpha: .3),
          child: const Icon(Icons.graphic_eq_rounded, color: Colors.white));
    }
    final step = size * .7;
    return SizedBox(
      width: size + step * (people.length - 1),
      height: size,
      child: Stack(children: [
        for (var i = people.length - 1; i >= 0; i--)
          Positioned(
            left: i * step,
            child: Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(2),
              decoration:
                  const BoxDecoration(color: _violet, shape: BoxShape.circle),
              child: IgnorePointer(
                child: ContentAuthorAvatar(
                    author: people[i]['id'].toString(),
                    name: people[i]['display_name'] as String? ?? '',
                    imageUrl: people[i]['avatar_url'] as String?,
                    size: size - 4),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Three bouncing bars — the "live audio" glyph.
class _Equaliser extends StatefulWidget {
  const _Equaliser();
  @override
  State<_Equaliser> createState() => _EqualiserState();
}

class _EqualiserState extends State<_Equaliser>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 3.5,
              height: 6 +
                  12 *
                      (0.5 +
                          0.5 *
                              math.sin((_c.value * 2 * math.pi) + i * 1.7)),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                  color: _violet, borderRadius: BorderRadius.circular(2)),
            ),
        ]),
      );
}

// -- Preview / join sheet ---------------------------------------------------------

Future<void> showSpacePreview(BuildContext context, Map space) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (_) => FractionallySizedBox(
          heightFactor: .9, child: _SpacePreview(space: space)),
    );

class _SpacePreview extends ConsumerStatefulWidget {
  const _SpacePreview({required this.space});
  final Map space;
  @override
  ConsumerState<_SpacePreview> createState() => _SpacePreviewState();
}

class _SpacePreviewState extends ConsumerState<_SpacePreview> {
  bool anonymous = false;

  String get _id => widget.space['id'] as String;

  Future<void> _menu(String action) async {
    if (action == 'hide') {
      final messenger = ScaffoldMessenger.of(context);
      ref.read(hiddenSpacesProvider.notifier).state = {
        ...ref.read(hiddenSpacesProvider),
        _id
      };
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(
          content: Text("Got it — you won't see this Space again.")));
    } else {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      try {
        await getIt<ApiClient>().dio.post('/realtime/live/$_id/report');
        messenger.showSnackBar(const SnackBar(
            content: Text('Thanks — our team will review this Space.')));
      } catch (_) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Could not report. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    final isHost = me != null && me.id == widget.space['host_id'];
    final state = ref.watch(spaceParticipantsProvider(_id));
    final data = state.valueOrNull;
    final people =
        ((data?['items'] as List?) ?? const []).whereType<Map>().toList();
    final anonymousCount = (data?['anonymous'] as num?)?.toInt() ?? 0;
    final record = data?['record'] == true || widget.space['record'] == true;
    final title = (data?['title'] ?? widget.space['title'] ?? 'Space') as String;
    final topics = ((data?['topics'] ?? widget.space['topics']) as List?)
            ?.cast<String>() ??
        const <String>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, size: 28)),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz_rounded, size: 28),
            color: PhlioColors.surfaceElevated,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            position: PopupMenuPosition.under,
            onSelected: _menu,
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'hide',
                  height: 52,
                  child: Row(children: [
                    Icon(Icons.remove_circle_outline_rounded),
                    SizedBox(width: 16),
                    Text('Not interested in this Space',
                        style: TextStyle(fontSize: 16)),
                  ])),
              const PopupMenuItem(
                  value: 'report',
                  height: 52,
                  child: Row(children: [
                    Icon(Icons.outlined_flag_rounded, color: PhlioColors.danger),
                    SizedBox(width: 16),
                    Text('Report this Space',
                        style: TextStyle(
                            fontSize: 16, color: PhlioColors.danger)),
                  ])),
            ],
          ),
        ]),
        const SizedBox(height: 8),
        if (record) ...[const RecBadge(), const SizedBox(height: 12)],
        Text(title,
            style: PhlioTypography.displayMedium
                .copyWith(fontFamily: PhlioTypography.uiFamily, fontSize: 25)),
        if (topics.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final topic in topics)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: _violet.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(999)),
                child: Text(topic,
                    style: PhlioTypography.caption
                        .copyWith(color: PhlioColors.textPrimary)),
              ),
          ]),
        ],
        const SizedBox(height: 20),
        Expanded(
          child: state.isLoading && data == null
              ? const Center(child: CircularProgressIndicator())
              : state.hasError && data == null
                  ? Center(
                      child: TextButton(
                          onPressed: () =>
                              ref.invalidate(spaceParticipantsProvider(_id)),
                          child: const Text('This Space may have ended. Retry')))
                  : ShaderMask(
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.white, Colors.white, Colors.transparent],
                        stops: [0, .85, 1],
                      ).createShader(rect),
                      blendMode: BlendMode.dstIn,
                      child: GridView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 8,
                                childAspectRatio: .62),
                        itemCount: people.length + (anonymousCount > 0 ? 1 : 0),
                        itemBuilder: (_, i) => i == people.length
                            ? _AnonymousTile(count: anonymousCount)
                            : _ParticipantTile(person: people[i]),
                      ),
                    ),
        ),
        if (!isHost) ...[
          Row(children: [
            Expanded(
                child: Text('Listen anonymously',
                    style: PhlioTypography.title.copyWith(fontSize: 16))),
            Switch(
                value: anonymous,
                activeTrackColor: _violet,
                onChanged: (v) => setState(() => anonymous = v)),
          ]),
          Text(
              'While listening anonymously, you won\'t be visible, able to speak, or send reactions.',
              style: PhlioTypography.body
                  .copyWith(color: PhlioColors.textMuted, fontSize: 13.5)),
          const SizedBox(height: 16),
        ],
        GradientPillButton(
          label: isHost ? 'Rejoin your Space' : 'Start listening',
          onPressed: () {
            // The sheet lives on the root navigator: close it and open the
            // Space from the same navigator.
            final navigator = Navigator.of(context, rootNavigator: true);
            navigator.pop();
            navigator.push(MaterialPageRoute<void>(
                builder: (_) => RealtimeScreen(
                    endpoint:
                        '/realtime/live/$_id/join${anonymous && !isHost ? '?anonymous=true' : ''}',
                    title: title,
                    video: false,
                    rooms: true)));
          },
        ),
      ]),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.person});
  final Map person;
  @override
  Widget build(BuildContext context) {
    final role = person['role'] as String? ?? 'Listener';
    final muted = person['muted'] == true && role != 'Listener';
    return Column(children: [
      ContentAuthorAvatar(
          author: person['id'].toString(),
          name: person['display_name'] as String? ?? '',
          imageUrl: person['avatar_url'] as String?,
          size: 64),
      const SizedBox(height: 8),
      Text(person['display_name'] as String? ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PhlioTypography.bodyStrong.copyWith(fontSize: 14)),
      const SizedBox(height: 2),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (muted) ...[
          const Icon(Icons.mic_off_rounded, size: 14, color: _rec),
          const SizedBox(width: 3),
        ],
        Flexible(
            child: Text(role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PhlioTypography.caption
                    .copyWith(color: PhlioColors.textMuted))),
      ]),
    ]);
  }
}

class _AnonymousTile extends StatelessWidget {
  const _AnonymousTile({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
                color: PhlioColors.surfaceElevated, shape: BoxShape.circle),
            child: const Icon(Icons.visibility_off_outlined,
                color: PhlioColors.textMuted)),
        const SizedBox(height: 8),
        Text('+$count',
            style: PhlioTypography.bodyStrong.copyWith(fontSize: 14)),
        Text('Anonymous',
            style:
                PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
      ]);
}

// -- Shared pieces -------------------------------------------------------------

class RecBadge extends StatelessWidget {
  const RecBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: PhlioColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: PhlioColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 9,
              height: 9,
              decoration:
                  const BoxDecoration(color: _rec, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('REC',
              style: PhlioTypography.label.copyWith(
                  fontWeight: FontWeight.w800,
                  color: PhlioColors.textPrimary,
                  letterSpacing: .4)),
        ]),
      );
}

/// Full-width violet→peach pill (Phlio's primary CTA).
class GradientPillButton extends StatelessWidget {
  const GradientPillButton(
      {required this.label, required this.onPressed, super.key});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? .45 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
              gradient: PhlioColors.sunsetGradient,
              borderRadius: BorderRadius.circular(999)),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onPressed,
              child: SizedBox(
                height: 54,
                width: double.infinity,
                child: Center(
                  child: Text(label,
                      style: const TextStyle(
                          color: PhlioColors.textOnBrand,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ),
      );
}

// -- Explainer sheets -------------------------------------------------------------

Future<void> showRecordSpaceInfo(BuildContext context) => _explainer(context,
        badge: true,
        title: 'Record your Space',
        subtitle: 'Record it now, have anyone play it',
        points: const [
          (
            Icons.auto_awesome_outlined,
            'Grow your audience',
            'If they missed your live Space, they can listen to the recording anytime.'
          ),
          (
            Icons.edit_note_rounded,
            'Share your recording',
            'Keep the conversation going by posting your recorded Space.'
          ),
          (
            Icons.public_rounded,
            'Anyone can listen',
            'Anyone can play and share the public recording.'
          ),
        ],
        footnote:
            'Phlio keeps copies of Spaces for a limited time to review for spam and abuse.');

Future<void> showGetToKnowSpaces(BuildContext context) => _explainer(context,
        badge: false,
        title: 'Your voice, your Space',
        subtitle: 'Live audio conversations on Phlio Social',
        points: const [
          (
            Icons.mic_none_rounded,
            'You host the conversation',
            'Give it a title and up to three topics. You control your mic.'
          ),
          (
            Icons.groups_2_outlined,
            'People drop in to listen',
            'Your live Space appears at the top of everyone\'s Posts feed.'
          ),
          (
            Icons.visibility_off_outlined,
            'Listeners can stay anonymous',
            'Anonymous listeners are counted but never shown.'
          ),
        ],
        footnote: 'Audio only — your camera stays off.');

Future<void> _explainer(BuildContext context,
        {required bool badge,
        required String title,
        required String subtitle,
        required List<(IconData, String, String)> points,
        required String footnote}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: PhlioColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SpacesArt(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (badge) ...[
                          const RecBadge(),
                          const SizedBox(height: 12)
                        ],
                        Text(title,
                            style: PhlioTypography.displayMedium.copyWith(
                                fontFamily: PhlioTypography.uiFamily,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(subtitle,
                            style: PhlioTypography.bodyLarge
                                .copyWith(color: PhlioColors.textMuted)),
                        const SizedBox(height: 24),
                        for (final (icon, heading, body) in points)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 22),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(icon, color: _violet, size: 26),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(heading,
                                              style: PhlioTypography.title),
                                          const SizedBox(height: 4),
                                          Text(body,
                                              style: PhlioTypography.body
                                                  .copyWith(fontSize: 15)),
                                        ]),
                                  ),
                                ]),
                          ),
                        Center(
                          child: Text(footnote,
                              textAlign: TextAlign.center,
                              style: PhlioTypography.caption.copyWith(
                                  color: PhlioColors.textMuted, fontSize: 13)),
                        ),
                        const SizedBox(height: 16),
                        GradientPillButton(
                            label: 'Got it',
                            onPressed: () => Navigator.pop(sheet)),
                      ]),
                ),
              ]),
        ),
      ),
    );

/// Header art: halftone dot field, a violet disc with a mic and Foxy.
class _SpacesArt extends StatelessWidget {
  const _SpacesArt();
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 210,
        width: double.infinity,
        child: Stack(children: [
          Positioned.fill(
            child: CustomPaint(painter: _HalftonePainter()),
          ),
          Positioned(
            left: 28,
            top: 18,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _violet,
                  _violet.withValues(alpha: .75),
                ]),
              ),
              child: const Icon(Icons.mic_rounded,
                  size: 76, color: Color(0xFF1B1530)),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 0,
            child: Image.asset('assets/images/foxy/foxy_hello.png',
                height: 190,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        ]),
      );
}

class _HalftonePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size,
        Paint()..color = _violet.withValues(alpha: .22));
    final dot = Paint()..color = _violet.withValues(alpha: .35);
    const gap = 9.0;
    for (var y = 0.0; y < size.height; y += gap) {
      for (var x = (y ~/ gap).isEven ? 0.0 : gap / 2;
          x < size.width;
          x += gap) {
        // Dots grow toward the bottom-left, like printed halftone.
        final t = (y / size.height) * .7 + (1 - x / size.width) * .3;
        canvas.drawCircle(Offset(x, y), .6 + 2.1 * t, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
