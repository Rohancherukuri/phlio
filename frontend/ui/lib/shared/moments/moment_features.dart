// Built-in Phlio features for moments, posts and chats.
//
//   * [showMomentTour]        the "What's new" pages (illustration, title,
//                             description and a "how to" row; Next / Done).
//   * [showMomentPeek]        long-press a moment ring: a preview of their
//                             moment that does NOT mark it seen, with View
//                             profile / Mute.
//   * [SuperHeartBurst]       hearts that fly up when you press and hold Like.
//   * [showMomentDurationPicker] 12 / 24 / 48 hours.
//   * [showMomentSettings]    default length, viewer alerts, spotlight.
//   * [showProfilePeek]       long-press an avatar (comments): a profile card.
//   * [showChatPreview]       long-press a chat: read it without marking it
//                             read, then Pin / Delete / Mute messages / calls.
//   * [showPostQuickMenu]     long-press a post on a profile: Pin to your
//                             main grid, Like, Comment, Share.
//
// Backend: backend/app/api/v1/moments.py (duration, spotlight, settings,
// viewers?q=, reaction.super), social.py (PUT /posts/{id}/pin, profile_only),
// messaging.py (PUT /peers/{peer}/prefs, DELETE /peers/{peer}/conversation).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_player/video_player.dart';

import '../../app/config/app_config.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../core/network/media_cache.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/phlio_card.dart';
import '../content/content_surface.dart' show SharedContentText;
import '../pay/payment_message.dart' show PaymentMessageCard, parsePaymentMessage;
import 'moments.dart' show openUserMoments;

/// The lengths a moment can have, in hours.
const momentDurations = [12, 24, 48];

const _heart = Color(0xFFFF3B5C);

String _mid(Map item) {
  final id = '${item['id']}';
  return Uri.encodeComponent(id.startsWith('social_moment:') ? id.substring('social_moment:'.length) : id);
}

String _two(int n) => n.toString().padLeft(2, '0');

/// `2:14 PM`.
String clockTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${_two(t.minute)} ${t.hour < 12 ? 'AM' : 'PM'}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// When a viewer watched: "Viewed 2:14 PM", "Viewed yesterday, 9:10 PM",
/// "Viewed 3 Dec, 9:10 PM".
String viewedClock(Object? at) {
  final t = DateTime.tryParse('${at ?? ''}')?.toLocal();
  if (t == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  final when = diff == 0
      ? clockTime(t)
      : diff == 1
          ? 'yesterday, ${clockTime(t)}'
          : '${t.day} ${_months[t.month - 1]}, ${clockTime(t)}';
  return 'Viewed $when';
}

String _dayTime(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime(t.year, t.month, t.day).difference(today).inDays;
  final day = switch (diff) { 0 => 'today', 1 => 'tomorrow', -1 => 'yesterday', _ => '${t.day} ${_months[t.month - 1]}' };
  return '$day at ${clockTime(t)}';
}

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

String _problem(Object error, String fallback) {
  try {
    final data = (error as dynamic).response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
  } catch (_) {}
  return fallback;
}

// -- feature tour ----------------------------------------------------------------------------

class MomentFeature {
  const MomentFeature(this.icon, this.colour, this.title, this.body, this.howIcon, this.how);
  final IconData icon;
  final Color colour;
  final String title, body;
  final IconData howIcon;
  final String how;
}

const momentFeatures = <MomentFeature>[
  MomentFeature(Icons.visibility_off_outlined, PhlioColors.brandViolet, 'Peek at moments',
      "See a preview of someone's moment without showing up in their viewer list.",
      Icons.touch_app_outlined, 'Press and hold a moment ring'),
  MomentFeature(Icons.timelapse_rounded, PhlioColors.brandPeach, 'Choose how long it lasts',
      'Keep a moment up for 12, 24 or 48 hours. 24 hours is the default.',
      Icons.more_horiz_rounded, 'Tap ••• on your moment, then Moment length'),
  MomentFeature(Icons.favorite_rounded, _heart, 'Super hearts',
      'Send a burst of hearts to show you really loved a moment.',
      Icons.favorite_border_rounded, 'Press and hold the heart on a moment'),
  MomentFeature(Icons.replay_rounded, PhlioColors.brandBlue, 'Rewatch insights',
      'See how many times people came back to watch your moment again.',
      Icons.people_alt_outlined, 'Open Viewers on your moment'),
  MomentFeature(Icons.schedule_rounded, PhlioColors.success, 'See when it was viewed',
      'Every viewer shows the time they last watched your moment.',
      Icons.people_alt_outlined, 'Open Viewers on your moment'),
  MomentFeature(Icons.manage_search_rounded, PhlioColors.brandPink, 'Search your viewers',
      'Find someone in your viewer list by name or username.',
      Icons.search_rounded, 'Viewers, then the search bar'),
  MomentFeature(Icons.notifications_active_outlined, PhlioColors.warning, 'Viewer alerts',
      'Get a notification when the people you pick view your moments.',
      Icons.notifications_none_rounded, 'Viewers, then the bell'),
  MomentFeature(Icons.groups_2_outlined, PhlioColors.brandViolet, 'Moment lists',
      'Share to different audiences: close friends, family, your team.',
      Icons.star_outline_rounded, 'Share to Close Friends, then Lists'),
  MomentFeature(Icons.auto_awesome_rounded, PhlioColors.brandPeach, 'Spotlight your moment',
      'Put your moment at the front of the rail for your followers. Once every 7 days.',
      Icons.more_horiz_rounded, 'Tap ••• on your moment, then Spotlight'),
  MomentFeature(Icons.push_pin_outlined, PhlioColors.brandBlue, 'Pin up to 6 posts',
      'Keep your favourite posts at the top of your profile.',
      Icons.touch_app_outlined, 'Press and hold a post on your profile'),
  MomentFeature(Icons.person_pin_outlined, PhlioColors.success, 'Post only to your profile',
      "Share a post on your profile without it showing in your followers' feeds.",
      Icons.edit_square, 'New post, then Profile only'),
  MomentFeature(Icons.text_fields_rounded, PhlioColors.brandPink, 'Fonts for your bio',
      'Give your bio a look of its own with the moment fonts.',
      Icons.edit_outlined, 'Edit profile, then Bio font'),
  MomentFeature(Icons.mark_chat_read_outlined, PhlioColors.warning, 'Read chats quietly',
      'Preview messages without marking them as read. Pin and mute from there too.',
      Icons.touch_app_outlined, 'Press and hold a chat in Messages'),
];

const _tourKey = 'phlio_whats_new_v1';

/// Opens the tour once per device (the first time [context] gets here).
Future<void> maybeShowMomentTour(BuildContext context) async {
  const storage = FlutterSecureStorage();
  try {
    if (await storage.read(key: _tourKey) != null) return;
    await storage.write(key: _tourKey, value: '1');
  } catch (_) {
    return;
  }
  if (context.mounted) await showMomentTour(context);
}

Future<void> showMomentTour(BuildContext context, {int start = 0}) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => _Tour(start: start)));

class _Tour extends StatefulWidget {
  const _Tour({this.start = 0});
  final int start;
  @override
  State<_Tour> createState() => _TourState();
}

class _TourState extends State<_Tour> {
  late final pages = PageController(initialPage: widget.start);
  late int page = widget.start;

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = page == momentFeatures.length - 1;
    return Scaffold(
      backgroundColor: PhlioColors.background,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: PhlioColors.textPrimary)),
              const Spacer(),
              Text("What's new", style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textSecondary)),
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Skip', style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textMuted))),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: pages,
              itemCount: momentFeatures.length,
              onPageChanged: (i) {
                HapticFeedback.selectionClick();
                setState(() => page = i);
              },
              itemBuilder: (_, i) => _TourPage(momentFeatures[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < momentFeatures.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: i == page ? PhlioColors.textPrimary : PhlioColors.border,
                      borderRadius: BorderRadius.circular(3)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: PhlioColors.brandViolet,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: () => last
                    ? Navigator.of(context).pop()
                    : pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic),
                child: Text(last ? 'Done' : 'Next', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TourPage extends StatelessWidget {
  const _TourPage(this.f);
  final MomentFeature f;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              _TourArt(f),
              const SizedBox(height: 36),
              Text(f.title,
                  textAlign: TextAlign.center,
                  style: PhlioTypography.headline.copyWith(fontSize: 26, color: PhlioColors.textPrimary)),
              const SizedBox(height: 12),
              Text(f.body,
                  textAlign: TextAlign.center,
                  style: PhlioTypography.bodyLarge.copyWith(color: PhlioColors.textSecondary, height: 1.4)),
              const SizedBox(height: 26),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: f.colour.withValues(alpha: .16), shape: BoxShape.circle),
                    child: Icon(f.howIcon, color: f.colour, size: 19),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('How to', style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
                      const SizedBox(height: 2),
                      Text(f.how, style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textPrimary)),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );
}

/// A little phone with the feature's icon, drawn from shapes (no photos).
class _TourArt extends StatelessWidget {
  const _TourArt(this.f);
  final MomentFeature f;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 230,
        height: 230,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            width: 230,
            height: 230,
            decoration: BoxDecoration(color: f.colour.withValues(alpha: .08), shape: BoxShape.circle),
          ),
          Container(
            width: 118,
            height: 200,
            decoration: BoxDecoration(
              color: PhlioColors.surfaceElevated,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: PhlioColors.border, width: 2),
            ),
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, border: Border.all(color: i == 0 ? f.colour : PhlioColors.border, width: 2)),
                  ),
              ]),
              const SizedBox(height: 12),
              for (final w in [.9, .7, .8, .5])
                FractionallySizedBox(
                  widthFactor: w,
                  child: Container(
                    height: 8,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: PhlioColors.border, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
            ]),
          ),
          Positioned(
            right: 26,
            bottom: 34,
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: f.colour,
                shape: BoxShape.circle,
                border: Border.all(color: PhlioColors.background, width: 5),
              ),
              child: Icon(f.icon, color: Colors.white, size: 34),
            ),
          ),
        ]),
      );
}

// -- peek (preview a moment without being seen) ---------------------------------------------

/// Long-press someone's picture (a ring, the rail, a comment avatar): their
/// live moments play in a card, NOT marked as seen. [showProfile] adds
/// "View profile" (off on their own profile page). [data] is a
/// `GET /social/moments/user/...` result you already have.
Future<void> showMomentPeek(BuildContext context, String user,
    {VoidCallback? onWatch, VoidCallback? onMuted, bool showProfile = true, Map? data}) async {
  HapticFeedback.mediumImpact();
  final router = GoRouter.maybeOf(context);
  final action = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close preview',
    barrierColor: Colors.black.withValues(alpha: .72),
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (_, a, __, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
          scale: Tween<double>(begin: .92, end: 1).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child),
    ),
    pageBuilder: (dialog, _, __) => _MomentPeek(user: user, showProfile: showProfile, initial: data),
  );
  if (!context.mounted) return;
  if (action == 'watch') {
    if (onWatch != null) {
      onWatch();
    } else {
      await openUserMoments(context, user);
    }
  } else if (action == 'profile') {
    router?.push('/creator/${Uri.encodeComponent(user)}');
  } else if (action == 'mute') {
    try {
      await getIt<ApiClient>()
          .dio
          .put('/social/moments/mute/${Uri.encodeComponent(user)}', data: {'muted': true});
      onMuted?.call();
      if (context.mounted) _say(context, "You won't see their moments in your rail.");
    } catch (_) {
      if (context.mounted) _say(context, 'Could not mute. Try again.');
    }
  }
}

class _MomentPeek extends StatefulWidget {
  const _MomentPeek({required this.user, this.showProfile = true, this.initial});
  final String user;
  final bool showProfile;
  final Map? initial;
  @override
  State<_MomentPeek> createState() => _MomentPeekState();
}

class _MomentPeekState extends State<_MomentPeek> with SingleTickerProviderStateMixin {
  Map? data;
  bool failed = false;
  int index = 0;
  VideoPlayerController? video;

  /// Each moment plays for 5 s (videos: their length, up to 15 s), then the next.
  late final AnimationController progress = AnimationController(vsync: this, duration: const Duration(seconds: 5))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _step(1);
    });

  List<Map> get items => (data?['items'] as List? ?? const []).cast<Map>();

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _ready(widget.initial!);
    } else {
      // GET /user/... never marks anything seen; only the full viewer does.
      getIt<ApiClient>().dio.get('/social/moments/user/${Uri.encodeComponent(widget.user)}').then((r) {
        if (mounted) _ready(r.data as Map);
      }, onError: (_) {
        if (mounted) setState(() => failed = true);
      });
    }
  }

  void _ready(Map d) {
    final list = (d['items'] as List? ?? const []).cast<Map>();
    final unseen = list.indexWhere((m) => m['seen'] != true);
    setState(() {
      data = d;
      index = unseen < 0 ? 0 : unseen;
    });
    _play();
  }

  Future<void> _play() async {
    progress
      ..stop()
      ..reset();
    final old = video;
    video = null;
    await old?.dispose();
    if (!mounted || items.isEmpty) return;
    final item = items[index];
    if (item['media_kind'] == 'video' && item['media_url'] is String) {
      final c = VideoPlayerController.networkUrl(Uri.parse(AppConfig.mediaUrl(item['media_url'] as String)));
      video = c;
      setState(() {});
      try {
        await c.initialize();
        if (!mounted || video != c) return;
        await c.setVolume(0); // a quiet preview
        final length = c.value.duration;
        progress.duration =
            length > Duration.zero && length < const Duration(seconds: 15) ? length : const Duration(seconds: 15);
        setState(() {});
        await c.play();
      } catch (_) {
        progress.duration = const Duration(seconds: 5);
      }
    } else {
      progress.duration = const Duration(seconds: 5);
      setState(() {});
    }
    if (mounted) progress.forward();
  }

  void _step(int by) {
    final next = index + by;
    if (next < 0 || next >= items.length) {
      if (by > 0) progress.stop(); // stay on the last one
      return;
    }
    setState(() => index = next);
    _play();
  }

  @override
  void dispose() {
    progress.dispose();
    video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(size.width * .74, 340.0);
    final author = (data?['author'] as Map?) ?? const {};
    final item = items.isEmpty ? null : items[index.clamp(0, items.length - 1)];
    final picture = item == null
        ? null
        : (item['media_kind'] == 'video' ? item['cover_url'] : (item['media_url'] ?? item['cover_url'])) as String?;
    final created = DateTime.tryParse('${item?['created_at'] ?? ''}');
    final playing = video != null && video!.value.isInitialized;
    final caption = '${item?['caption'] ?? ''}'.trim();
    return SafeArea(
      child: Center(
        child: Material(
          type: MaterialType.transparency,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              // Left third: back. Middle: open the moment. Right third: next.
              onTapUp: item == null
                  ? null
                  : (d) {
                      final x = d.localPosition.dx / width;
                      if (x < .3) {
                        _step(-1);
                      } else if (x > .7) {
                        _step(1);
                      } else {
                        Navigator.pop(context, 'watch');
                      }
                    },
              onLongPressStart: (_) {
                progress.stop();
                video?.pause();
              },
              onLongPressEnd: (_) {
                progress.forward();
                video?.play();
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: width,
                  height: math.min(width * 16 / 9, size.height * .62),
                  color: PhlioColors.surfaceElevated,
                  child: Stack(fit: StackFit.expand, children: [
                    if (picture != null)
                      phlioNetworkImage(AppConfig.mediaUrl(picture),
                          fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    if (playing)
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: video!.value.size.width,
                          height: video!.value.size.height,
                          child: VideoPlayer(video!),
                        ),
                      )
                    else if (item != null && picture == null && item['media_kind'] == 'video')
                      const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    if (data == null && !failed) const Center(child: CircularProgressIndicator()),
                    if (failed || (data != null && items.isEmpty))
                      Center(
                          child: Text(failed ? 'Could not load this moment.' : 'No live moments right now.',
                              style: const TextStyle(color: Colors.white70))),
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 90,
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0x99000000), Color(0x00000000)]))),
                    ),
                    if (items.isNotEmpty)
                      Positioned(
                        left: 10,
                        right: 10,
                        top: 10,
                        child: Row(children: [
                          for (var i = 0; i < items.length; i++)
                            Expanded(
                              child: Container(
                                height: 3,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                clipBehavior: Clip.antiAlias,
                                decoration:
                                    BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2)),
                                child: i < index
                                    ? const ColoredBox(color: Colors.white)
                                    : i == index
                                        ? AnimatedBuilder(
                                            animation: progress,
                                            builder: (_, __) => FractionallySizedBox(
                                              alignment: Alignment.centerLeft,
                                              widthFactor: progress.value,
                                              child: const ColoredBox(color: Colors.white),
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                              ),
                            ),
                        ]),
                      ),
                    if (author.isNotEmpty)
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 22,
                        child: Row(children: [
                          PhlioAvatar(
                              name: '${author['display_name'] ?? ''}',
                              imageUrl: author['avatar_url'] as String?,
                              size: 30,
                              showMomentRing: false),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text('${author['username'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PhlioTypography.bodyStrong.copyWith(
                                    color: Colors.white, shadows: const [Shadow(color: Colors.black54, blurRadius: 8)])),
                          ),
                          if (created != null) ...[
                            const SizedBox(width: 6),
                            Text(timeago.format(created, locale: 'en_short'),
                                style: const TextStyle(
                                    color: Colors.white70, shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
                          ],
                        ]),
                      ),
                    if (caption.isNotEmpty)
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 48,
                        child: Text(caption,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                shadows: [Shadow(color: Colors.black87, blurRadius: 10)])),
                      ),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(20)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.visibility_off_outlined, color: Colors.white, size: 14),
                          SizedBox(width: 6),
                          Text("Preview · they won't see you",
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _MenuCard(width: width, children: [
              if (item != null)
                _MenuRow(
                    icon: Icons.play_circle_outline_rounded,
                    label: 'Watch moment',
                    onTap: () => Navigator.pop(context, 'watch')),
              if (widget.showProfile)
                _MenuRow(
                    icon: Icons.account_circle_outlined, label: 'View profile', onTap: () => Navigator.pop(context, 'profile')),
              _MenuRow(icon: Icons.notifications_off_outlined, label: 'Mute', onTap: () => Navigator.pop(context, 'mute')),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.children, this.width});
  final List<Widget> children;
  final double? width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: PhlioColors.surfaceElevated, borderRadius: BorderRadius.circular(18)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: PhlioColors.border),
            children[i],
          ],
        ]),
      );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, required this.onTap, this.danger = false, this.trailing});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colour = danger ? PhlioColors.danger : PhlioColors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(children: [
          Expanded(child: Text(label, style: PhlioTypography.bodyStrong.copyWith(color: colour))),
          if (trailing != null) ...[trailing!, const SizedBox(width: 10)],
          Icon(icon, color: colour, size: 22),
        ]),
      ),
    );
  }
}

// -- super heart -----------------------------------------------------------------------------

/// A big heart that pops, with small hearts floating up around it. Lives
/// for [duration], then calls [onDone].
class SuperHeartBurst extends StatefulWidget {
  const SuperHeartBurst({this.onDone, this.duration = const Duration(milliseconds: 1600), super.key});
  final VoidCallback? onDone;
  final Duration duration;
  @override
  State<SuperHeartBurst> createState() => _SuperHeartBurstState();
}

class _SuperHeartBurstState extends State<SuperHeartBurst> with SingleTickerProviderStateMixin {
  late final AnimationController t = AnimationController(vsync: this, duration: widget.duration)
    ..forward().whenComplete(() => widget.onDone?.call());
  final _rng = math.Random();
  late final hearts = [
    for (var i = 0; i < 22; i++)
      (
        x: _rng.nextDouble() * 2 - 1, // -1..1 of the width
        delay: _rng.nextDouble() * .35,
        size: 18 + _rng.nextDouble() * 26,
        sway: (_rng.nextDouble() - .5) * 60,
        colour: const [_heart, PhlioColors.brandPink, PhlioColors.brandViolet, PhlioColors.brandPeach][i % 4],
      )
  ];

  @override
  void dispose() {
    t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: t,
          builder: (context, _) => LayoutBuilder(builder: (context, box) {
            final v = t.value;
            final pop = Curves.elasticOut.transform((v / .45).clamp(0.0, 1.0));
            final fade = v < .75 ? 1.0 : (1 - (v - .75) / .25);
            return Stack(clipBehavior: Clip.none, children: [
              for (final h in hearts)
                () {
                  final p = ((v - h.delay) / (1 - h.delay)).clamp(0.0, 1.0);
                  if (p <= 0) return const SizedBox.shrink();
                  final y = box.maxHeight * (.78 - .7 * Curves.easeOutCubic.transform(p));
                  final x = box.maxWidth / 2 + h.x * box.maxWidth * .38 + math.sin(p * math.pi * 2) * h.sway / 2;
                  return Positioned(
                    left: x - h.size / 2,
                    top: y,
                    child: Opacity(
                      opacity: (1 - p).clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: h.sway / 200 * p,
                        child: Icon(Icons.favorite_rounded, color: h.colour, size: h.size * (.6 + .4 * p)),
                      ),
                    ),
                  );
                }(),
              Center(
                child: Opacity(
                  opacity: fade.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: .3 + 1.0 * pop,
                    child: const Icon(Icons.favorite_rounded,
                        color: _heart, size: 120, shadows: [Shadow(color: Color(0x66000000), blurRadius: 18)]),
                  ),
                ),
              ),
            ]);
          }),
        ),
      );
}

// -- duration ---------------------------------------------------------------------------------

/// 12 / 24 / 48 hours. [from] is when the moment was shared (shows when
/// each choice would end); null for a new moment.
Future<int?> showMomentDurationPicker(BuildContext context, {int current = 24, DateTime? from}) =>
    showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      backgroundColor: PhlioColors.surface,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
              child: Text('Moment length', style: PhlioTypography.title.copyWith(color: PhlioColors.textPrimary)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
              child: Text('How long your moment stays up before it ends.',
                  style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted)),
            ),
            for (final h in momentDurations)
              () {
                final ends = (from ?? DateTime.now()).toLocal().add(Duration(hours: h));
                final past = from != null && ends.isBefore(DateTime.now());
                final on = h == current;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: on ? PhlioColors.brandViolet.withValues(alpha: .16) : PhlioColors.surfaceElevated,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: on ? PhlioColors.brandViolet : Colors.transparent, width: 1.4)),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      enabled: !past,
                      onTap: () => Navigator.pop(sheet, h),
                      leading: Icon(Icons.timelapse_rounded, color: on ? PhlioColors.brandViolet : PhlioColors.textSecondary),
                      title: Text('$h hours${h == 24 ? ' · default' : ''}',
                          style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textPrimary)),
                      subtitle: Text(past ? 'Already past' : 'Ends ${_dayTime(ends)}',
                          style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
                      trailing: on ? const Icon(Icons.check_circle_rounded, color: PhlioColors.brandViolet) : null,
                    ),
                  ),
                );
              }(),
          ]),
        ),
      ),
    );

/// Changes a live moment's length. Returns the updated moment, or null.
Future<Map?> changeMomentDuration(BuildContext context, Map item) async {
  final current = (item['duration_hours'] as num?)?.toInt() ?? 24;
  final from = DateTime.tryParse('${item['created_at'] ?? ''}');
  final hours = await showMomentDurationPicker(context, current: current, from: from);
  if (hours == null || hours == current || !context.mounted) return null;
  try {
    final res = await getIt<ApiClient>().dio.put('/social/moments/${_mid(item)}/duration', data: {'hours': hours});
    if (context.mounted) _say(context, 'Your moment now lasts $hours hours');
    return res.data as Map;
  } catch (e) {
    if (context.mounted) _say(context, _problem(e, 'Could not change the length. Try again.'));
    return null;
  }
}

/// Spotlight: front of followers' rails, once every 7 days.
Future<bool> spotlightMoment(BuildContext context, Map item) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    useRootNavigator: true,
    backgroundColor: PhlioColors.surface,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: PhlioColors.brandPeach.withValues(alpha: .16), shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome_rounded, color: PhlioColors.brandPeach, size: 32),
          ),
          const SizedBox(height: 14),
          Text('Spotlight this moment?',
              style: PhlioTypography.title.copyWith(color: PhlioColors.textPrimary), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
              "It moves to the front of your followers' moment rail while it's live. You can spotlight one moment every 7 days.",
              textAlign: TextAlign.center,
              style: PhlioTypography.body.copyWith(color: PhlioColors.textSecondary)),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: PhlioColors.brandViolet,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () => Navigator.pop(sheet, true),
              child: const Text('Spotlight', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          TextButton(onPressed: () => Navigator.pop(sheet, false), child: const Text('Not now')),
        ]),
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    final res = await getIt<ApiClient>().dio.post('/social/moments/${_mid(item)}/spotlight');
    final next = DateTime.tryParse('${(res.data as Map)['next_spotlight_at'] ?? ''}')?.toLocal();
    if (context.mounted) {
      _say(context, next == null ? 'Spotlight is on' : 'Spotlight is on. Next one ${_dayTime(next)}.');
    }
    return true;
  } catch (e) {
    if (context.mounted) _say(context, _problem(e, 'Could not spotlight. Try again.'));
    return false;
  }
}

// -- settings (default length, viewer alerts) ------------------------------------------------

/// The default length for new moments (24 when unset or offline).
Future<int> momentDefaultHours() async {
  try {
    final data = (await getIt<ApiClient>().dio.get('/social/moments/settings/me')).data as Map;
    final h = (data['default_hours'] as num?)?.toInt() ?? 24;
    return momentDurations.contains(h) ? h : 24;
  } catch (_) {
    return 24;
  }
}

Future<void> showMomentSettings(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (_) => const _MomentSettings(),
    );

class _MomentSettings extends StatefulWidget {
  const _MomentSettings();
  @override
  State<_MomentSettings> createState() => _MomentSettingsState();
}

class _MomentSettingsState extends State<_MomentSettings> {
  Map? data;
  bool failed = false, saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await getIt<ApiClient>().dio.get('/social/moments/settings/me');
      if (mounted) setState(() => data = res.data as Map);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  List<Map> get people => (data?['notify_viewers'] as List? ?? const []).cast<Map>();

  Future<void> _save(Map<String, dynamic> body) async {
    setState(() => saving = true);
    try {
      final res = await getIt<ApiClient>().dio.put('/social/moments/settings/me', data: body);
      if (mounted) setState(() => data = res.data as Map);
    } catch (e) {
      if (mounted) _say(context, _problem(e, 'Could not save. Try again.'));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _add() async {
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (_) => _PeoplePicker(selected: {for (final p in people) '${p['username']}'}),
    );
    if (picked != null) await _save({'notify_viewers': picked});
  }

  @override
  Widget build(BuildContext context) {
    final hours = (data?['default_hours'] as num?)?.toInt() ?? 24;
    final next = DateTime.tryParse('${data?['next_spotlight_at'] ?? ''}')?.toLocal();
    final canSpotlight = next == null || next.isBefore(DateTime.now());
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: data == null
          ? Center(
              child: failed
                  ? TextButton(
                      onPressed: () {
                        setState(() => failed = false);
                        _load();
                      },
                      child: const Text('Could not load settings. Retry'))
                  : const CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              Row(children: [
                Expanded(
                    child: Text('Moment settings',
                        style: PhlioTypography.headline.copyWith(fontSize: 22, color: PhlioColors.textPrimary))),
                if (saving) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              const SizedBox(height: 18),
              _Section('Default length', 'New moments stay up this long. You can change it for each moment.'),
              const SizedBox(height: 10),
              Row(children: [
                for (final h in momentDurations) ...[
                  Expanded(
                    child: _Segment(
                      label: '${h}h',
                      on: h == hours,
                      onTap: () => _save({'default_hours': h}),
                    ),
                  ),
                  if (h != momentDurations.last) const SizedBox(width: 8),
                ],
              ]),
              const SizedBox(height: 26),
              _Section('Viewer alerts', 'Get a notification when these people view your moments.'),
              const SizedBox(height: 8),
              for (final p in people)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PhlioAvatar(
                      name: '${p['display_name'] ?? ''}',
                      imageUrl: p['avatar_url'] as String?,
                      size: 40,
                      showMomentRing: false),
                  title: Text('${p['display_name'] ?? p['username']}',
                      style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textPrimary)),
                  subtitle: Text('@${p['username']}', style: const TextStyle(color: PhlioColors.textMuted)),
                  trailing: IconButton(
                    tooltip: 'Stop alerts',
                    icon: const Icon(Icons.notifications_off_outlined, color: PhlioColors.textSecondary),
                    onPressed: () => _save({
                      'notify_viewers': [
                        for (final o in people)
                          if (o['username'] != p['username']) '${o['username']}'
                      ]
                    }),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(people.isEmpty ? 'Choose people' : 'Edit people'),
                ),
              ),
              const SizedBox(height: 18),
              _Section('Spotlight', 'Put one live moment at the front of the rail, once every 7 days.'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: PhlioColors.surfaceElevated, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Icon(Icons.auto_awesome_rounded, color: canSpotlight ? PhlioColors.brandPeach : PhlioColors.textMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(canSpotlight ? 'Available now. Open your moment, tap •••, then Spotlight.' : 'Next spotlight ${_dayTime(next!)}',
                        style: PhlioTypography.body.copyWith(color: PhlioColors.textSecondary)),
                  ),
                ]),
              ),
              const SizedBox(height: 22),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_stories_outlined, color: PhlioColors.brandViolet),
                title: Text("What's new", style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textPrimary)),
                subtitle: const Text('A quick tour of the latest features', style: TextStyle(color: PhlioColors.textMuted)),
                trailing: const Icon(Icons.chevron_right_rounded, color: PhlioColors.textMuted),
                onTap: () => showMomentTour(context),
              ),
            ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.body);
  final String title, body;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textPrimary, fontSize: 16)),
        const SizedBox(height: 2),
        Text(body, style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
      ]);
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: on ? PhlioColors.brandViolet : PhlioColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Center(
                child: Text(label,
                    style: PhlioTypography.bodyStrong.copyWith(color: on ? Colors.white : PhlioColors.textSecondary))),
          ),
        ),
      );
}

/// Pick people (from your chats and connections); returns usernames.
class _PeoplePicker extends StatefulWidget {
  const _PeoplePicker({required this.selected});
  final Set<String> selected;
  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  late final Set<String> chosen = {...widget.selected};
  String search = '';
  late final Future<List<Map>> people = getIt<ApiClient>().dio.get('/sharing/destinations').then((r) => [
        for (final p in ((r.data as Map)['people'] as List? ?? const [])) Map.from(p as Map),
      ]);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(children: [
          Text('Viewer alerts', style: PhlioTypography.title.copyWith(color: PhlioColors.textPrimary)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              onChanged: (v) => setState(() => search = v.trim().toLowerCase()),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: PhlioColors.surfaceElevated,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map>>(
              future: people,
              builder: (_, s) {
                if (s.hasError) return const Center(child: Text('Could not load people.'));
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                final list = s.data!
                    .where((p) => '${p['username']} ${p['display_name']}'.toLowerCase().contains(search))
                    .toList();
                if (list.isEmpty) return const Center(child: Text('No one found.'));
                return ListView(children: [
                  for (final p in list)
                    CheckboxListTile(
                      value: chosen.contains('${p['username']}'),
                      onChanged: (v) => setState(() =>
                          v == true ? chosen.add('${p['username']}') : chosen.remove('${p['username']}')),
                      secondary: PhlioAvatar(
                          name: '${p['display_name'] ?? ''}',
                          imageUrl: p['avatar_url'] as String?,
                          size: 40,
                          showMomentRing: false),
                      title: Text('${p['display_name'] ?? p['username']}'),
                      subtitle: Text('@${p['username']}'),
                    ),
                ]);
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, chosen.toList()),
                  child: Text(chosen.isEmpty ? 'Turn off alerts' : 'Done · ${chosen.length}'),
                ),
              ),
            ),
          ),
        ]),
      );
}

// -- profile peek (comment avatars) ----------------------------------------------------------

/// [person] needs `username` (or `id`). If they have a live moment, the
/// moment preview opens; otherwise a profile card (`display_name` and
/// `avatar_url` show at once while the rest loads).
Future<void> showProfilePeek(BuildContext context, Map person) async {
  HapticFeedback.mediumImpact();
  final router = GoRouter.maybeOf(context);
  final username = '${person['username'] ?? person['id'] ?? ''}'.replaceFirst('@', '');
  if (username.isEmpty) return;
  // Someone with a live moment: preview the moment (not marked as seen).
  try {
    final data = (await getIt<ApiClient>().dio.get('/social/moments/user/${Uri.encodeComponent(username)}')).data;
    if (data is Map && (data['items'] as List? ?? const []).isNotEmpty) {
      if (context.mounted) await showMomentPeek(context, username, data: data);
      return;
    }
  } catch (_) {}
  if (!context.mounted) return;
  final go = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: .7),
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (_, a, __, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child)),
    pageBuilder: (dialog, _, __) => Center(
      child: Material(
        type: MaterialType.transparency,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 300,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.circular(24)),
            child: FutureBuilder(
              future: getIt<ApiClient>().dio.get('/users/${Uri.encodeComponent(username)}'),
              builder: (_, s) {
                final full = s.data?.data is Map ? s.data!.data as Map : const {};
                final name = '${full['full_name'] ?? full['display_name'] ?? person['display_name'] ?? username}';
                final avatar = (full['avatar_url'] ?? person['avatar_url']) as String?;
                final bio = '${full['bio'] ?? ''}'.trim();
                String count(String k) => '${full[k] ?? full['${k}_count'] ?? '–'}';
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  PhlioAvatar(name: name, imageUrl: avatar, size: 86, showMomentRing: false),
                  const SizedBox(height: 12),
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhlioTypography.title.copyWith(color: PhlioColors.textPrimary)),
                  Text('@$username', style: PhlioTypography.body.copyWith(color: PhlioColors.textMuted)),
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(bio,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: PhlioTypography.body.copyWith(color: PhlioColors.textSecondary)),
                  ],
                  if (full.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      _Stat(count('posts'), 'Posts'),
                      _Stat(count('followers'), 'Followers'),
                      _Stat(count('following'), 'Following'),
                    ]),
                  ],
                ]);
              },
            ),
          ),
          const SizedBox(height: 12),
          _MenuCard(width: 300, children: [
            _MenuRow(icon: Icons.account_circle_outlined, label: 'View profile', onTap: () => Navigator.pop(dialog, true)),
          ]),
        ]),
      ),
    ),
  );
  if (go == true) router?.push('/creator/${Uri.encodeComponent(username)}');
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value, label;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textPrimary)),
        Text(label, style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
      ]);
}

// -- chat preview ------------------------------------------------------------------------------

/// Long-press a chat. Shows the latest messages without marking them read
/// and returns `open`, `pin`, `delete`, `mute` or `mute_calls` (or null).
Future<String?> showChatPreview(BuildContext context,
    {required Map conversation,
    required String? meId,
    required Future<List<Map<String, dynamic>>> messages,
    Widget Function(Map<String, dynamic> message, bool mine)? messageBuilder}) {
  HapticFeedback.mediumImpact();
  final peer = conversation['peer'] as Map;
  final pinned = conversation['pinned'] == true;
  final muted = conversation['muted'] == true;
  final mutedCalls = conversation['muted_calls'] == true;
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close preview',
    barrierColor: Colors.black.withValues(alpha: .72),
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (_, a, __, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child)),
    pageBuilder: (dialog, _, __) {
      final width = math.min(MediaQuery.sizeOf(dialog).width - 40, 380.0);
      return SafeArea(
        child: Center(
          child: Material(
            type: MaterialType.transparency,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: () => Navigator.pop(dialog, 'open'),
                child: Container(
                  width: width,
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(dialog).height * .56),
                  decoration: BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.circular(22)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Row(children: [
                        PhlioAvatar(
                            name: '${peer['full_name'] ?? ''}',
                            imageUrl: peer['avatar_url'] as String?,
                            size: 38,
                            showMomentRing: false),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${peer['full_name'] ?? peer['username']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textPrimary)),
                            Text('@${peer['username'] ?? ''}',
                                style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
                          ]),
                        ),
                      ]),
                    ),
                    const Divider(height: 1, color: PhlioColors.border),
                    Flexible(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: messages,
                        builder: (_, s) {
                          if (s.hasError) {
                            return const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('Could not load messages.', style: TextStyle(color: PhlioColors.textMuted)));
                          }
                          if (!s.hasData) {
                            return const Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator());
                          }
                          final list = [...s.data!]
                            ..sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
                          // The latest messages, newest at the bottom (where the chat
                          // opens); scroll up for earlier ones.
                          final last = list.length > 30 ? list.sublist(list.length - 30) : list;
                          if (last.isEmpty) {
                            return const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('No messages yet.', style: TextStyle(color: PhlioColors.textMuted)));
                          }
                          final latest = DateTime.tryParse('${last.last['created_at'] ?? ''}');
                          Widget bubble(Map<String, dynamic> m) {
                            final mine = _sentByMe(m, meId);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: width * .78),
                                  child: messageBuilder?.call(m, mine) ?? _PreviewBubble(m, mine: mine),
                                ),
                              ),
                            );
                          }
                          // Scrolls; taps on a message open the chat instead of
                          // the card (AbsorbPointer keeps the scroll working).
                          return ListView(
                              shrinkWrap: true,
                              reverse: true,
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              children: [
                                if (latest != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                        'Last message · ${timeago.format(latest)}',
                                        textAlign: _sentByMe(last.last, meId) ? TextAlign.right : TextAlign.left,
                                        style: const TextStyle(color: PhlioColors.textMuted, fontSize: 11.5)),
                                  ),
                                for (final m in last.reversed) AbsorbPointer(child: bubble(m)),
                              ],
                          );
                        },
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: const BoxDecoration(
                          color: PhlioColors.surfaceElevated,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(22))),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.mark_chat_read_outlined, size: 14, color: PhlioColors.textMuted),
                        SizedBox(width: 6),
                        Text("Previewing · they won't see it as read",
                            style: TextStyle(color: PhlioColors.textMuted, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              _MenuCard(width: width, children: [
                _MenuRow(
                    icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    label: pinned ? 'Unpin' : 'Pin',
                    onTap: () => Navigator.pop(dialog, 'pin')),
                _MenuRow(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    danger: true,
                    onTap: () => Navigator.pop(dialog, 'delete')),
                _MenuRow(
                    icon: muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                    label: muted ? 'Unmute messages' : 'Mute messages',
                    onTap: () => Navigator.pop(dialog, 'mute')),
                _MenuRow(
                    icon: mutedCalls ? Icons.call_outlined : Icons.phone_disabled_outlined,
                    label: mutedCalls ? 'Unmute calls' : 'Mute calls',
                    onTap: () => Navigator.pop(dialog, 'mute_calls')),
              ]),
            ]),
          ),
        ),
      );
    },
  );
}

/// One message in the chat preview, drawn like the chat: shared posts,
/// clips, videos, profiles, moments and places are cards (never links),
/// payments the payment card, attachments a labelled chip.
class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble(this.m, {required this.mine});
  final Map m;
  final bool mine;

  static String _attachment(List files) {
    final kinds = {for (final a in files) '${(a as Map)['kind'] ?? 'file'}'};
    if (kinds.length == 1) {
      return switch (kinds.first) {
        'image' => files.length > 1 ? '📷 ${files.length} photos' : '📷 Photo',
        'video' => '🎬 Video',
        'audio' || 'voice' => '🎤 Voice message',
        'gif' => 'GIF',
        'sticker' => 'Sticker',
        _ => '📎 Attachment',
      };
    }
    return '📎 ${files.length} attachments';
  }

  @override
  Widget build(BuildContext context) {
    final text = '${m['text'] ?? ''}'.trim();
    final files = (m['attachments'] as List?) ?? const [];
    final style = TextStyle(color: mine ? Colors.white : PhlioColors.textPrimary, fontSize: 14);
    final payment = parsePaymentMessage(text);
    final Widget body;
    var bare = false; // cards bring their own surface
    if (payment != null) {
      body = PaymentMessageCard(payment: payment, mine: mine);
      bare = true;
    } else if (text.contains('phlio://')) {
      body = SharedContentText(text, mine: mine, style: style);
      bare = true;
    } else if (text.isNotEmpty) {
      body = Text(text.length > 220 ? '${text.substring(0, 220)}…' : text, style: style);
    } else {
      body = Text(files.isEmpty ? 'Message' : _attachment(files), style: style);
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: const BoxConstraints(maxWidth: 270),
        padding: bare ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: bare
            ? null
            : BoxDecoration(
                color: mine ? PhlioColors.brandViolet : PhlioColors.surfaceElevated,
                borderRadius: BorderRadius.circular(18),
              ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            body,
            if (text.isNotEmpty && files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_attachment(files),
                    style: style.copyWith(fontSize: 12.5, color: mine ? Colors.white70 : PhlioColors.textMuted)),
              ),
          ],
        ),
      ),
    );
  }
}

bool _sentByMe(Map m, String? meId) => m['sender_id'] == meId;

/// Saves a chat preference (`pinned`, `muted`, `muted_calls`).
Future<bool> saveChatPref(BuildContext context, String peerId, Map<String, bool> body) async {
  try {
    await getIt<ApiClient>().dio.put('/messaging/peers/${Uri.encodeComponent(peerId)}/prefs', data: body);
    return true;
  } catch (e) {
    if (context.mounted) _say(context, _problem(e, 'Could not update this chat. Try again.'));
    return false;
  }
}

/// "Delete chat" for you (the other person keeps their copy).
Future<bool> deleteChatForMe(BuildContext context, Map peer) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Delete chat?'),
      content: Text("This removes the conversation with ${peer['full_name'] ?? peer['username']} for you. "
          "They'll still see it."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete', style: TextStyle(color: PhlioColors.danger))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await getIt<ApiClient>().dio.delete('/messaging/peers/${Uri.encodeComponent('${peer['id']}')}/conversation');
    return true;
  } catch (e) {
    if (context.mounted) _say(context, _problem(e, 'Could not delete. Try again.'));
    return false;
  }
}

// -- post quick menu (profile) ---------------------------------------------------------------

/// Long-press a post on a profile: returns `pin`, `like`, `comment`,
/// `share`, `edit`, `delete`, `more` (with [more]) or null. [mine] shows
/// the pin, edit and delete rows ([pinnable] false hides pin, e.g. videos).
Future<String?> showPostQuickMenu(BuildContext context,
    {required bool mine,
    required bool pinned,
    required bool liked,
    Widget? preview,
    bool more = false,
    bool pinnable = true,
    bool reactions = true,
    String editLabel = 'Edit caption'}) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: .72),
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (_, a, __, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child)),
    pageBuilder: (dialog, _, __) {
      final width = math.min(MediaQuery.sizeOf(dialog).width - 48, 360.0);
      return SafeArea(
        child: Center(
          child: Material(
            type: MaterialType.transparency,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (preview != null)
                Container(
                  width: width,
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(dialog).height * .45),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: PhlioColors.surface, borderRadius: BorderRadius.circular(22)),
                  child: SingleChildScrollView(child: IgnorePointer(child: preview)),
                ),
              const SizedBox(height: 12),
              _MenuCard(width: width, children: [
                if (mine && pinnable)
                  _MenuRow(
                      icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                      label: pinned ? 'Unpin from main grid' : 'Pin to your main grid',
                      onTap: () => Navigator.pop(dialog, 'pin')),
                if (reactions) ...[
                  _MenuRow(
                      icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      label: liked ? 'Unlike' : 'Like',
                      onTap: () => Navigator.pop(dialog, 'like')),
                  _MenuRow(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Comment',
                      onTap: () => Navigator.pop(dialog, 'comment')),
                ],
                _MenuRow(icon: Icons.send_outlined, label: 'Share', onTap: () => Navigator.pop(dialog, 'share')),
                if (mine)
                  _MenuRow(icon: Icons.edit_outlined, label: editLabel, onTap: () => Navigator.pop(dialog, 'edit')),
                if (mine)
                  _MenuRow(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      danger: true,
                      onTap: () => Navigator.pop(dialog, 'delete')),
                if (more)
                  _MenuRow(
                      icon: Icons.more_horiz_rounded, label: 'More options', onTap: () => Navigator.pop(dialog, 'more')),
              ]),
            ]),
          ),
        ),
      );
    },
  );
}

/// Pins or unpins a post on your profile (up to 6). True when it worked.
Future<bool> setPostPinned(BuildContext context, String postId, bool pinned) async {
  try {
    await getIt<ApiClient>().dio.put('/social/posts/${Uri.encodeComponent(postId)}/pin', data: {'pinned': pinned});
    if (context.mounted) _say(context, pinned ? 'Pinned to your profile' : 'Unpinned');
    return true;
  } catch (e) {
    var message = _problem(e, 'Could not update the pin. Try again.');
    // FastAPI's bare "Not Found" means the route itself is missing: the
    // server is running code from before pinning existed.
    if (message == 'Not Found') {
      message = 'Pinning needs the latest Phlio server. Restart the backend (or redeploy) and try again.';
    }
    if (context.mounted) _say(context, message);
    return false;
  }
}
