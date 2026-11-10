// The Phlio tour — shown once, right after sign-up (and from Settings →
// "Take the tour"). Foxy, live and fully rigged, walks a new person through
// the buttons that matter: switching platforms, the create button, posts &
// clips, moments, snaps, experiences, Spaces, payments, discovering people
// and Foxy AI.
//
// Every page pairs Foxy (a different act per page; he hops between pages
// and leans with your swipe) with a small animated replica of the real UI,
// so the person sees exactly which button to look for.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/platform/phlio_platform.dart';
import '../../../design_system/colors.dart';
import '../../../design_system/typography.dart';
import '../../../design_system/widgets/foxy_puppet.dart';
import '../../../shared/pay/phlio_currency.dart';
import '../../../shared/social/discover_people.dart' show EarthGridIcon;
import '../../authentication/presentation/controllers/auth_controller.dart';
import 'widgets/onboarding_kit.dart';

/// Remembers (per account, on this device) that the tour was seen.
abstract final class PhlioTour {
  static Future<File?> _file(String userId) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final safe = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      return File('${dir.path}${Platform.pathSeparator}tour_seen_$safe');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> seen(String userId) async =>
      (await _file(userId))?.existsSync() ?? true;

  static Future<void> markSeen(String userId) async {
    try {
      final f = await _file(userId);
      if (f != null) await f.writeAsString(DateTime.now().toIso8601String());
    } catch (_) {}
  }
}

typedef _Demo = Widget Function(double t, PhlioCurrency currency);

class _Page {
  const _Page({
    required this.title,
    required this.line,
    required this.body,
    required this.act,
    required this.accent,
    required this.demo,
  });

  final String title;

  /// What Foxy says in his bubble.
  final String line;
  final String body;
  final FoxyAct act;
  final Color accent;
  final _Demo demo;
}

class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key});

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen>
    with SingleTickerProviderStateMixin {
  final _pager = PageController();
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))
        ..repeat();
  int _index = 0;
  double _drag = 0; // page offset from the current page, -1..1
  int _hop = 0;
  int _confetti = 0;
  bool _talking = false;

  late final List<_Page> _pagesList = _buildPages();

  @override
  void initState() {
    super.initState();
    _pager.addListener(() {
      final p = _pager.page ?? 0;
      setState(() => _drag = (p - _index).clamp(-1.0, 1.0));
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    _loop.dispose();
    super.dispose();
  }

  List<_Page> _buildPages() {
    final name = ref.read(authControllerProvider).valueOrNull?.fullName.split(' ').first;
    return [
      _Page(
        title: 'Welcome to Phlio',
        line: 'Hey${name == null ? '' : ' $name'}! I\'m Foxy. Let me show you around — it\'ll take a minute.',
        body: 'One account, eight platforms: Social, Pay, Rooms, Book, Shop, Stream, News and me, your AI.',
        act: FoxyAct.hooray,
        accent: PhlioColors.brandViolet,
        demo: (t, _) => _WelcomeDemo(t: t),
      ),
      _Page(
        title: 'Switch platforms',
        line: 'Tap the grid at the bottom-right to hop between platforms.',
        body: 'The app tray (⊞) switches Phlio. Home and Explore change to that platform — Profile stays yours.',
        act: FoxyAct.wave,
        accent: PhlioColors.domainSocial,
        demo: (t, _) => _PlatformsDemo(t: t),
      ),
      _Page(
        title: 'The create button',
        line: 'The big + in the middle makes things. It changes with the platform!',
        body: 'Create in Social, Scan & Pay in Pay, Cart in Shop, New room in Rooms, playlists in Stream and News.',
        act: FoxyAct.clap,
        accent: PhlioColors.brandOrange,
        demo: (t, _) => _CreateDemo(t: t),
      ),
      _Page(
        title: 'Posts, videos & clips',
        line: 'Share a post, or film a clip — swipe up to keep watching.',
        body: '+ → New post, New video (1–5 min) or New clip (15 s–2 min). Double-tap to like, tap 💬 to comment, ↗ to share.',
        act: FoxyAct.love,
        accent: PhlioColors.domainStream,
        demo: (t, _) => _PostsDemo(t: t),
      ),
      _Page(
        title: 'Moments',
        line: 'Moments disappear after 24 hours. Glowing ring = something new!',
        body: 'Tap a glowing ring at the top of Social to watch. + → New moment to post yours, with templates, music and stickers.',
        act: FoxyAct.happy,
        accent: PhlioColors.domainNews,
        demo: (t, _) => _MomentsDemo(t: t),
      ),
      _Page(
        title: 'Snaps',
        line: 'Tap for a photo, hold for a video. Watch the glow run round!',
        body: '+ → New snap. Send to everyone, your Close friends, or a list you make yourself.',
        act: FoxyAct.cheer,
        accent: PhlioColors.domainPay,
        demo: (t, _) => _SnapDemo(t: t),
      ),
      _Page(
        title: 'Experiences',
        line: 'Weekly photo dumps with your best friends — my favourite.',
        body: '+ → New experience. Everyone adds their photos through the week; it all comes together as one story.',
        act: FoxyAct.love,
        accent: PhlioColors.brandPink,
        demo: (t, _) => _ExperiencesDemo(t: t),
      ),
      _Page(
        title: 'Spaces',
        line: 'Spaces are live audio rooms. Jump in and talk!',
        body: 'Find the Spaces row in Social — tap a live one to listen, or start your own and invite friends to speak.',
        act: FoxyAct.talk,
        accent: PhlioColors.brandPurple,
        demo: (t, _) => _SpacesDemo(t: t),
      ),
      _Page(
        title: 'Payments',
        line: 'Pay anyone in a chat with one tap — in your own currency.',
        body: 'In Pay, the middle button is Scan & Pay. In any DM, tap the currency button to send money; see everything in Transaction history.',
        act: FoxyAct.phone,
        accent: PhlioColors.domainPay,
        demo: (t, c) => _PayDemo(t: t, currency: c),
      ),
      _Page(
        title: 'Discover people',
        line: 'Tap the globe to find people you might know.',
        body: 'On your profile it sits next to Share profile; on other people\'s, next to Message. Follow back in a tap.',
        act: FoxyAct.think,
        accent: PhlioColors.domainRooms,
        demo: (t, _) => _DiscoverDemo(t: t),
      ),
      _Page(
        title: 'Ask me anything',
        line: 'And I\'m always here — plan, book, shop and pay just by asking.',
        body: 'Open Agent from the tray. Attach photos or PDFs with +, and find past chats in the chats panel.',
        act: FoxyAct.happy,
        accent: PhlioColors.brandOrange,
        demo: (t, c) => _AgentDemo(t: t, currency: c),
      ),
      _Page(
        title: 'You\'re all set!',
        line: 'That\'s the tour! Tap me anytime I show up — I love a hop.',
        body: 'You can replay this tour from Settings → Take the tour.',
        act: FoxyAct.hooray,
        accent: PhlioColors.brandViolet,
        demo: (t, _) => _FinishDemo(t: t),
      ),
    ];
  }

  void _onPage(int i) {
    HapticFeedback.selectionClick();
    setState(() {
      _index = i;
      _drag = 0;
      _hop++;
      if (i == _pagesList.length - 1) _confetti++;
    });
  }

  Future<void> _done() async {
    final id = ref.read(authControllerProvider).valueOrNull?.id;
    if (id != null) await PhlioTour.markSeen(id);
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _next() {
    if (_index == _pagesList.length - 1) {
      _done();
      return;
    }
    _pager.nextPage(duration: const Duration(milliseconds: 520), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final page = _pagesList[_index];
    final last = _index == _pagesList.length - 1;
    final currency = ref.watch(userCurrencyProvider);
    final n = _pagesList.length;

    return Scaffold(
      body: OnboardingBackdrop(
        child: Stack(children: [
          // A soft wash of the page's colour behind everything.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.35),
                    radius: 1.1,
                    colors: [page.accent.withValues(alpha: 0.18), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
                child: Row(children: [
                  Expanded(child: OnboardingProgress(value: (_index + 1) / n)),
                  const SizedBox(width: 8),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: last ? 0 : 1,
                    child: TextButton(
                      onPressed: last ? null : _done,
                      child: Text('Skip',
                          style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textSecondary)),
                    ),
                  ),
                ]),
              ),
              // Foxy + what he's saying.
              SizedBox(
                height: 168,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Transform.translate(
                    offset: Offset(-24 * _drag, 0),
                    child: Transform.rotate(
                      angle: -0.05 * _drag,
                      child: FoxyPuppet(
                        act: page.act,
                        size: 148,
                        talking: _talking,
                        lean: (-_drag * 1.6).clamp(-1.0, 1.0),
                        hopSignal: _hop,
                        entrance: true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 18, bottom: 20),
                      child: FoxyBubble(
                        key: ValueKey(_index),
                        text: page.line,
                        // Long lines must fit the bubble at any text size.
                        style: PhlioTypography.title.copyWith(
                            fontSize: page.line.length > 44 ? 15.5 : 17.5,
                            height: 1.28),
                        onTyping: (v) {
                          if (mounted && v != _talking) setState(() => _talking = v);
                        },
                      ),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pager,
                  itemCount: n,
                  onPageChanged: _onPage,
                  itemBuilder: (context, i) {
                    final p = _pagesList[i];
                    return AnimatedBuilder(
                      animation: _pager,
                      builder: (context, child) {
                        final offset = _pager.hasClients && _pager.position.haveDimensions
                            ? (_pager.page ?? 0) - i
                            : (i - _index).toDouble();
                        final f = offset.abs().clamp(0.0, 1.0);
                        return Opacity(
                          opacity: (1 - 0.55 * f).clamp(0.0, 1.0),
                          child: Transform.scale(scale: 1 - 0.08 * f, child: child),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: Column(children: [
                          Expanded(
                            child: _DemoCard(
                              accent: p.accent,
                              child: i == _index
                                  ? AnimatedBuilder(
                                      animation: _loop,
                                      builder: (_, __) => p.demo(_loop.value, currency),
                                    )
                                  : p.demo(0.35, currency),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(p.title, textAlign: TextAlign.center, style: PhlioTypography.headline),
                          const SizedBox(height: 8),
                          Text(p.body,
                              textAlign: TextAlign.center,
                              style: PhlioTypography.body.copyWith(color: PhlioColors.textSecondary, height: 1.4)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Row(children: [
                  // Page dots.
                  Expanded(
                    child: Wrap(spacing: 5, runSpacing: 5, children: [
                      for (var i = 0; i < n; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOut,
                          width: i == _index ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _index ? page.accent : PhlioColors.textMuted.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ]),
                  ),
                  _GlowButton(
                    label: last ? 'Start exploring' : 'Next',
                    icon: last ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                    onTap: _next,
                  ),
                ]),
              ),
            ]),
          ),
          Positioned.fill(child: IgnorePointer(child: ConfettiBurst(trigger: _confetti))),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pieces

class _GlowButton extends StatelessWidget {
  const _GlowButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: PhlioColors.brandGradient,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(color: PhlioColors.brandViolet.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: PhlioTypography.bodyStrong.copyWith(color: PhlioColors.textOnBrand, fontSize: 16)),
              const SizedBox(width: 8),
              Icon(icon, size: 20, color: PhlioColors.textOnBrand),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.06), accent.withValues(alpha: 0.25)],
        ),
      ),
      padding: const EdgeInsets.all(1.2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: ColoredBox(
          color: const Color(0xFF12161F),
          child: LayoutBuilder(
            builder: (context, box) => FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(width: 320, height: math.max(240, 320 * box.maxHeight / math.max(1, box.maxWidth)).clamp(240, 420).toDouble(), child: child),
            ),
          ),
        ),
      ),
    );
  }
}

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
double _ease(double x) => Curves.easeOutCubic.transform(x.clamp(0.0, 1.0));
double _pop(double x) => Curves.easeOutBack.transform(x.clamp(0.0, 1.0));

/// A finger-tap marker: a dot with an expanding ring.
class _Tap extends StatelessWidget {
  const _Tap({required this.t});

  final double t; // 0..1 through the tap

  @override
  Widget build(BuildContext context) {
    if (t <= 0 || t >= 1) return const SizedBox(width: 44, height: 44);
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: 16 + 28 * t,
          height: 16 + 28 * t,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: (1 - t) * 0.8), width: 2),
          ),
        ),
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.85 * (1 - t * 0.5))),
        ),
      ]),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.seed, this.size = 36, this.ring});

  final int seed;
  final double size;
  final Gradient? ring;

  static const _pairs = [
    [Color(0xFF8D78FF), Color(0xFFE795D7)],
    [Color(0xFF72A7FF), Color(0xFF6FD6B5)],
    [Color(0xFFFFB58F), Color(0xFFE795D7)],
    [Color(0xFF6FD6B5), Color(0xFF72A7FF)],
    [Color(0xFFFFD27A), Color(0xFFFF8A80)],
  ];
  static const _letters = 'AKNRSMJT';

  @override
  Widget build(BuildContext context) {
    final c = _pairs[seed % _pairs.length];
    final face = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: c)),
      child: Text(_letters[seed % _letters.length],
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.4)),
    );
    if (ring == null) return face;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: ring),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF12161F)),
        child: face,
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({this.center = Icons.add_rounded, this.centerPulse = 0, this.trayPulse = 0, this.trayIcon = Icons.apps_rounded});

  final IconData center;
  final double centerPulse;
  final double trayPulse;
  final IconData trayIcon;

  @override
  Widget build(BuildContext context) {
    Widget icon(IconData i, {double pulse = 0, bool big = false}) => SizedBox(
          width: 52,
          height: 46,
          child: Center(
            child: Transform.scale(
              scale: 1 + 0.18 * pulse,
              child: big
                  ? Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        gradient: PhlioColors.brandGradient,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(i, color: PhlioColors.textOnBrand, size: 22),
                    )
                  : Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(shape: BoxShape.circle),
                      child: Icon(i, color: pulse > 0.05 ? Colors.white : PhlioColors.textSecondary, size: 24),
                    ),
            ),
          ),
        );
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF0C1018),
        border: Border(top: BorderSide(color: Color(0xFF242C3A))),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        icon(Icons.home_rounded),
        icon(Icons.search_rounded),
        icon(center, pulse: centerPulse, big: true),
        icon(Icons.person_outline_rounded),
        icon(trayIcon, pulse: trayPulse),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Demos (each 320 wide; `t` loops 0→1 every 3.6 s)

class _WelcomeDemo extends StatelessWidget {
  const _WelcomeDemo({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final platforms = PhlioPlatform.values;
    return LayoutBuilder(builder: (context, box) {
      final c = Offset(box.maxWidth / 2, box.maxHeight / 2);
      final r = math.min(box.maxWidth, box.maxHeight) * 0.36;
      return Stack(children: [
        Positioned(
          left: c.dx - r - 8,
          top: c.dy - r - 8,
          child: Container(
            width: 2 * r + 16,
            height: 2 * r + 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
        ),
        for (var i = 0; i < platforms.length; i++)
          () {
            final a = 2 * math.pi * (i / platforms.length + t * 0.25) - math.pi / 2;
            final p = platforms[i];
            final glow = 0.5 + 0.5 * math.sin(2 * math.pi * (t * 2 + i / platforms.length));
            return Positioned(
              left: c.dx + r * math.cos(a) - 22,
              top: c.dy + r * math.sin(a) - 22,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.color.withValues(alpha: 0.16),
                  border: Border.all(color: p.color.withValues(alpha: 0.5 + 0.4 * glow)),
                ),
                child: Icon(p.activeIcon, color: p.color, size: 22),
              ),
            );
          }(),
        Positioned(
          left: c.dx - 40,
          top: c.dy - 46,
          child: Transform.scale(
            scale: 1 + 0.04 * math.sin(2 * math.pi * t),
            child: Image.asset('assets/images/logo/logo_mark.png',
                width: 80, height: 92, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox()),
          ),
        ),
      ]);
    });
  }
}

class _PlatformsDemo extends StatelessWidget {
  const _PlatformsDemo({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final platforms = PhlioPlatform.values;
    final open = _ease(_seg(t, 0.12, 0.3)) * (1 - _ease(_seg(t, 0.9, 1)));
    final pick = (_seg(t, 0.32, 0.86) * platforms.length).floor().clamp(0, platforms.length - 1);
    final current = platforms[pick];
    final trayTap = _seg(t, 0.0, 0.16);
    return Column(children: [
      // The "home" re-skins to the chosen platform.
      Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [current.color.withValues(alpha: 0.28), Colors.transparent],
            ),
          ),
          child: Stack(children: [
            Positioned(
              left: 16,
              top: 14,
              child: Row(children: [
                Icon(current.activeIcon, color: current.color, size: 22),
                const SizedBox(width: 8),
                Text('Phlio ${current.label}', style: PhlioTypography.title.copyWith(color: Colors.white)),
              ]),
            ),
            // The tray sheet.
            Positioned(
              left: 12,
              right: 12,
              bottom: 8 - 30 * (1 - open),
              child: Opacity(
                opacity: (open).clamp(0.0, 1.0),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2230),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18)],
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    runSpacing: 8,
                    children: [
                      for (final p in platforms)
                        SizedBox(
                          width: 66,
                          child: Column(children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: p == current ? p.color : p.color.withValues(alpha: 0.14),
                              ),
                              child: Icon(p.activeIcon, size: 20, color: p == current ? Colors.white : p.color),
                            ),
                            const SizedBox(height: 3),
                            Text(p.label,
                                style: PhlioTypography.caption.copyWith(
                                    fontSize: 10, color: p == current ? Colors.white : PhlioColors.textSecondary)),
                          ]),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
      Stack(clipBehavior: Clip.none, children: [
        _NavBar(trayPulse: trayTap > 0 && trayTap < 1 ? 1 - trayTap : 0.3 + 0.3 * math.sin(2 * math.pi * t * 2), trayIcon: open > 0.5 ? current.activeIcon : Icons.apps_rounded),
        Positioned(right: 12, top: 4, child: IgnorePointer(child: _Tap(t: trayTap))),
      ]),
    ]);
  }
}

class _CreateDemo extends StatelessWidget {
  const _CreateDemo({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.edit_rounded, 'New post', PhlioColors.domainSocial),
      (Icons.videocam_rounded, 'New video', PhlioColors.domainStream),
      (Icons.content_cut_rounded, 'New clip', PhlioColors.brandOrange),
      (Icons.photo_library_rounded, 'New moment', PhlioColors.domainNews),
      (Icons.auto_stories_rounded, 'New experience', PhlioColors.brandPink),
      (Icons.photo_camera_rounded, 'New snap', PhlioColors.domainPay),
    ];
    final tap = _seg(t, 0.02, 0.18);
    final sheet = _ease(_seg(t, 0.14, 0.32)) * (1 - _ease(_seg(t, 0.92, 1)));
    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Opacity(
            opacity: (sheet).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 40 * (1 - sheet)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2230),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < items.length; i++)
                    () {
                      final a = _pop(_seg(t, 0.22 + i * 0.05, 0.42 + i * 0.05));
                      final (icon, label, color) = items[i];
                      return Opacity(
                        opacity: a.clamp(0.0, 1.0),

                        child: Transform.translate(
                          offset: Offset(30 * (1 - a), 0),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: Row(children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(9)),
                                child: Icon(icon, size: 16, color: color),
                              ),
                              const SizedBox(width: 10),
                              Text(label, style: PhlioTypography.bodyStrong.copyWith(fontSize: 13)),
                            ]),
                          ),
                        ),
                      );
                    }(),
                ]),
              ),
            ),
          ),
        ),
      ),
      Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        _NavBar(centerPulse: tap > 0 && tap < 1 ? 1 - tap : 0.25 + 0.25 * math.sin(2 * math.pi * t * 2)),
        Positioned(top: 4, child: IgnorePointer(child: _Tap(t: tap))),
      ]),
    ]);
  }
}

class _PostsDemo extends StatelessWidget {
  const _PostsDemo({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final like = _seg(t, 0.18, 0.4);
    final liked = t > 0.24;
    final swipe = _ease(_seg(t, 0.5, 0.75));
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        // Post card.
        Expanded(
          flex: 6,
          child: Container(
            decoration: BoxDecoration(color: const Color(0xFF1B2230), borderRadius: BorderRadius.circular(18)),
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const _Avatar(seed: 1, size: 24),
                const SizedBox(width: 6),
                Text('kiara', style: PhlioTypography.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: Stack(alignment: Alignment.center, children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFFB58F), Color(0xFF8D78FF)]),
                    ),
                  ),
                  if (like > 0 && like < 1)
                    Transform.scale(
                      scale: _pop(like * 2) * (1 + 0.2 * like),
                      child: Opacity(
                        opacity: (1 - like).clamp(0.0, 1.0),

                        child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 54),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Transform.scale(
                  scale: liked ? 1 + 0.3 * (1 - _seg(t, 0.24, 0.36)) : 1,
                  child: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      size: 20, color: liked ? const Color(0xFFFF6B8B) : Colors.white),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 10),
                const Icon(Icons.send_rounded, size: 18, color: Colors.white),
              ]),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        // Clip: swipe up to the next one.
        Expanded(
          flex: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: LayoutBuilder(builder: (context, box) {
              Widget clip(List<Color> c, String label) => Container(
                    width: box.maxWidth,
                    height: box.maxHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: c),
                    ),
                    child: Stack(children: [
                      const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 36)),
                      Positioned(
                        left: 8,
                        bottom: 10,
                        child: Text(label, style: PhlioTypography.caption.copyWith(color: Colors.white, fontSize: 11)),
                      ),
                    ]),
                  );
              final y = -box.maxHeight * swipe;
              return Stack(children: [
                Positioned(top: y, child: clip(const [Color(0xFF2B5876), Color(0xFF4E4376)], '#clip')),
                Positioned(top: y + box.maxHeight, child: clip(const [Color(0xFF6FD6B5), Color(0xFF2B5876)], '#next')),
                Positioned(
                  right: 8,
                  bottom: 18 + 26 * (1 - swipe) * _seg(t, 0.4, 0.5),
                  child: Opacity(
                    opacity: ((1 - swipe) * (t > 0.38 ? 1 : 0)).clamp(0.0, 1.0),
                    child: const Icon(Icons.swipe_up_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ]);
            }),
          ),
        ),
      ]),
    );
  }
}

class _MomentsDemo extends StatelessWidget {
  const _MomentsDemo({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final ring = SweepGradient(
      transform: GradientRotation(2 * math.pi * t),
      colors: const [Color(0xFF8D78FF), Color(0xFFE795D7), Color(0xFFFFB58F), Color(0xFF8D78FF)],
    );
    final open = _ease(_seg(t, 0.22, 0.4));
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Column(children: [
            Stack(clipBehavior: Clip.none, children: [
              const _Avatar(seed: 0, size: 44),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: PhlioColors.brandBlue, border: Border.all(color: const Color(0xFF12161F), width: 2)),
                  child: const Icon(Icons.add_rounded, size: 12, color: Colors.white),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text('You', style: PhlioTypography.caption.copyWith(fontSize: 10)),
          ]),
          for (var i = 1; i < 4; i++)
            Column(children: [
              Transform.scale(
                scale: i == 1 ? 1 + 0.1 * (1 - _seg(t, 0.1, 0.22)) * (t > 0.1 ? 1 : 0) : 1,
                child: _Avatar(seed: i, size: 40, ring: ring),
              ),
              const SizedBox(height: 4),
              Text(['', 'asha', 'neha', 'arjun'][i], style: PhlioTypography.caption.copyWith(fontSize: 10)),
            ]),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Opacity(
            opacity: (open).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.85 + 0.15 * open,
              alignment: const Alignment(-0.45, -1),
              child: Container(
                width: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF72A7FF), Color(0xFF8D78FF), Color(0xFFE795D7)]),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  Row(children: [
                    for (var s = 0; s < 3; s++)
                      Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: _seg(t, 0.4 + s * 0.18, 0.58 + s * 0.18),
                            child: Container(
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                            ),
                          ),
                        ),
                      ),
                  ]),
                  const Spacer(),
                  Text('🌅 sunset run', style: PhlioTypography.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('24h', style: PhlioTypography.caption.copyWith(color: Colors.white70, fontSize: 10)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _SnapDemo extends StatelessWidget {
  const _SnapDemo({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final flash = _seg(t, 0.08, 0.22);
    final hold = _seg(t, 0.38, 0.9);
    final recording = t > 0.38 && t < 0.92;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Expanded(
          child: Stack(children: [
            // Photo slot with the travelling gradient streak while holding.
            Positioned.fill(
              child: CustomPaint(
                painter: _StreakBorderPainter(progress: recording ? hold : 0, radius: 20),
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF243B55), Color(0xFF141E30)],
                    ),
                  ),
                  child: Center(
                    child: Icon(Icons.landscape_rounded, size: 56, color: Colors.white.withValues(alpha: 0.25)),
                  ),
                ),
              ),
            ),
            if (flash > 0 && flash < 1)
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.white.withValues(alpha: 0.7 * (1 - flash)),
                  ),
                ),
              ),
            if (recording)
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFFFF4D5E), shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text('0:0${(hold * 9).floor()}', style: PhlioTypography.caption.copyWith(color: Colors.white, fontSize: 11)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Tap · photo', style: PhlioTypography.caption.copyWith(color: t < 0.35 ? Colors.white : PhlioColors.textMuted)),
          const SizedBox(width: 16),
          Transform.scale(
            scale: recording ? 1.12 : (flash > 0 && flash < 1 ? 0.9 : 1),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              padding: const EdgeInsets.all(4),
              child: Container(
                decoration: BoxDecoration(
                  shape: recording ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: recording ? BorderRadius.circular(8) : null,
                  color: recording ? const Color(0xFFFF4D5E) : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text('Hold · video', style: PhlioTypography.caption.copyWith(color: recording ? Colors.white : PhlioColors.textMuted)),
        ]),
      ]),
    );
  }
}

class _StreakBorderPainter extends CustomPainter {
  _StreakBorderPainter({required this.progress, required this.radius});

  final double progress;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(1.5);
    final path = Path()..addRRect(rrect);
    final metric = path.computeMetrics().first;
    final len = metric.length;
    // A comet streak running round, leaving the border lit behind it.
    final lit = metric.extractPath(0, len * progress);
    canvas.drawPath(
      lit,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = const SweepGradient(colors: [
          Color(0xFF8D78FF),
          Color(0xFFE795D7),
          Color(0xFFFFB58F),
          Color(0xFF8D78FF),
        ]).createShader(Offset.zero & size),
    );
    final head = metric.getTangentForOffset(len * progress)?.position;
    if (head != null) {
      canvas.drawCircle(head, 6, Paint()..color = Colors.white.withValues(alpha: 0.9)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
  }

  @override
  bool shouldRepaint(_StreakBorderPainter old) => old.progress != progress;
}

class _ExperiencesDemo extends StatelessWidget {
  const _ExperiencesDemo({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    const tiles = [
      [Color(0xFFFFB58F), Color(0xFFE795D7)],
      [Color(0xFF72A7FF), Color(0xFF8D78FF)],
      [Color(0xFF6FD6B5), Color(0xFF72A7FF)],
      [Color(0xFFFFD27A), Color(0xFFFF8A80)],
      [Color(0xFF8D78FF), Color(0xFFE795D7)],
      [Color(0xFF2B5876), Color(0xFF6FD6B5)],
    ];
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Row(children: [
          Text('This week', style: PhlioTypography.bodyStrong),
          const Spacer(),
          SizedBox(
            width: 70,
            height: 24,
            child: Stack(children: [
              for (var i = 0; i < 4; i++) Positioned(left: i * 14.0, child: _Avatar(seed: i, size: 24)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: GridView.count(
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (var i = 0; i < tiles.length; i++)
                () {
                  final f = _ease(_seg(t, 0.06 + i * 0.08, 0.26 + i * 0.08)) * (1 - _ease(_seg(t, 0.92, 1)));
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.002)
                      ..rotateY((1 - f) * math.pi / 2),
                    child: Opacity(
                      opacity: (f).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: tiles[i]),
                        ),
                        alignment: Alignment.bottomLeft,
                        padding: const EdgeInsets.all(5),
                        child: _Avatar(seed: i, size: 18),
                      ),
                    ),
                  );
                }(),
            ],
          ),
        ),
      ]),
    );
  }
}

class _SpacesDemo extends StatelessWidget {
  const _SpacesDemo({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final speaker = (t * 5).floor() % 5;
    final local = (t * 5) % 1;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFFFF4D5E), borderRadius: BorderRadius.circular(8)),
            child: Text('LIVE', style: PhlioTypography.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('Sunday design jam 🎨', style: PhlioTypography.bodyStrong, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.headphones_rounded, size: 16, color: PhlioColors.textSecondary),
          const SizedBox(width: 3),
          Text('128', style: PhlioTypography.caption),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.center,
            runAlignment: WrapAlignment.center,
            spacing: 22,
            runSpacing: 14,
            children: [
              for (var i = 0; i < 5; i++)
                SizedBox(
                  width: 62,
                  child: Column(children: [
                    SizedBox(
                      width: 62,
                      height: 62,
                      child: Stack(alignment: Alignment.center, children: [
                        if (i == speaker)
                          for (final k in [0.0, 0.5])
                            Container(
                              width: 46 + 16 * ((local + k) % 1),
                              height: 46 + 16 * ((local + k) % 1),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: PhlioColors.brandPurple.withValues(alpha: 0.8 * (1 - (local + k) % 1)), width: 2.5),
                              ),
                            ),
                        _Avatar(seed: i, size: 46),
                      ]),
                    ),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(i == speaker ? Icons.mic_rounded : Icons.mic_off_rounded,
                          size: 12, color: i == speaker ? PhlioColors.brandPurple : PhlioColors.textMuted),
                      Text(['host', 'ravi', 'meera', 'sam', 'ali'][i], style: PhlioTypography.caption.copyWith(fontSize: 10)),
                    ]),
                  ]),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(gradient: PhlioColors.brandGradient, borderRadius: BorderRadius.circular(999)),
          child: Text('✋ Request to speak', style: PhlioTypography.caption.copyWith(color: PhlioColors.textOnBrand, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

class _PayDemo extends StatelessWidget {
  const _PayDemo({required this.t, required this.currency});

  final double t;
  final PhlioCurrency currency;

  @override
  Widget build(BuildContext context) {
    final scan = 0.5 - 0.5 * math.cos(2 * math.pi * t * 2);
    final tap = _seg(t, 0.45, 0.6);
    final sent = _pop(_seg(t, 0.62, 0.78)) * (1 - _ease(_seg(t, 0.94, 1)));
    final amount = currency.format(currency.quickAmounts[1] * 100);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        // Scan & Pay.
        Expanded(
          child: Row(children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: const Color(0xFF1B2230)),
              child: Stack(children: [
                Center(child: Icon(Icons.qr_code_2_rounded, size: 72, color: Colors.white.withValues(alpha: 0.85))),
                Positioned(
                  left: 10,
                  right: 10,
                  top: 10 + 80 * scan,
                  child: Container(
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: PhlioColors.domainPay,
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Scan & Pay', style: PhlioTypography.bodyStrong),
                const SizedBox(height: 4),
                Text('The middle button in Phlio Pay scans any Phlio QR.',
                    style: PhlioTypography.caption.copyWith(fontSize: 11, color: PhlioColors.textSecondary)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        // DM: money button → sent.
        Opacity(
          opacity: (sent).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - sent)),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFF7B5CFF), borderRadius: BorderRadius.circular(16)),
                child: Text('💸 Sent $amount via Phlio Pay',
                    style: PhlioTypography.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
        Container(
          height: 44,
          padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
          decoration: BoxDecoration(color: const Color(0xFF262626), borderRadius: BorderRadius.circular(999)),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: Color(0xFF7B5CFF), shape: BoxShape.circle),
              child: const Icon(Icons.photo_camera_rounded, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('Message…', style: PhlioTypography.body.copyWith(color: const Color(0xFF8E8E93)))),
            const Icon(Icons.mic_none_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Stack(alignment: Alignment.center, children: [
              Transform.scale(
                scale: 1 + 0.25 * (tap > 0 && tap < 1 ? 1 - tap : 0) + 0.08 * math.sin(2 * math.pi * t * 3),
                child: CurrencyGlyph(currency: currency, size: 22),
              ),
              IgnorePointer(child: _Tap(t: tap)),
            ]),
            const SizedBox(width: 6),
          ]),
        ),
      ]),
    );
  }
}

class _DiscoverDemo extends StatelessWidget {
  const _DiscoverDemo({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final tap = _seg(t, 0.06, 0.2);
    final globeSpin = t * 2 * math.pi;
    Widget button(String label) => Expanded(
          child: Container(
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFF1B2230), borderRadius: BorderRadius.circular(9)),
            child: Text(label, style: PhlioTypography.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Row(children: [
          const _Avatar(seed: 2, size: 46),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('You', style: PhlioTypography.bodyStrong),
            Text('12 posts · 180 followers', style: PhlioTypography.caption.copyWith(fontSize: 10)),
          ]),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          button('Edit profile'),
          const SizedBox(width: 6),
          button('Share profile'),
          const SizedBox(width: 6),
          Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            Transform.scale(
              scale: 1 + 0.2 * (tap > 0 && tap < 1 ? 1 - tap : 0),
              child: Container(
                width: 34,
                height: 30,
                decoration: BoxDecoration(
                  color: PhlioColors.domainRooms.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: PhlioColors.domainRooms.withValues(alpha: 0.7)),
                ),
                child: Center(
                  child: Transform.rotate(angle: 0.15 * math.sin(globeSpin), child: const EarthGridIcon(size: 18, color: Colors.white)),
                ),
              ),
            ),
            IgnorePointer(child: _Tap(t: tap)),
          ]),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Row(children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: () {
                  final f = _pop(_seg(t, 0.18 + i * 0.1, 0.42 + i * 0.1)) * (1 - _ease(_seg(t, 0.93, 1)));
                  final following = i == 0 && t > 0.62;
                  return Opacity(
                    opacity: f.clamp(0.0, 1.0),

                    child: Transform.translate(
                      offset: Offset(40 * (1 - f), 0),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFF1B2230), borderRadius: BorderRadius.circular(14)),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          _Avatar(seed: i + 3, size: 38),
                          const SizedBox(height: 4),
                          Text(['meera', 'sam', 'ali'][i], style: PhlioTypography.caption.copyWith(color: Colors.white, fontSize: 11)),
                          Text(['3 mutuals', 'Follows you', 'Popular'][i], style: PhlioTypography.caption.copyWith(fontSize: 9)),
                          const SizedBox(height: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: following ? const Color(0xFF2A3242) : PhlioColors.brandBlue,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(following ? 'Following' : 'Follow',
                                style: PhlioTypography.caption.copyWith(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      ),
                    ),
                  );
                }(),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _AgentDemo extends StatelessWidget {
  const _AgentDemo({required this.t, required this.currency});

  final double t;
  final PhlioCurrency currency;

  @override
  Widget build(BuildContext context) {
    final ask = _pop(_seg(t, 0.04, 0.18));
    final typing = t > 0.2 && t < 0.42;
    final reply = _ease(_seg(t, 0.42, 0.6));
    final budget = currency.format(currency.quickAmounts.last * 200);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerRight,
          child: Opacity(
            opacity: ask.clamp(0.0, 1.0),

            child: Transform.scale(
              scale: 0.8 + 0.2 * ask,
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(gradient: PhlioColors.brandGradient, borderRadius: BorderRadius.circular(16)),
                child: Text('Plan Saturday for 3 under $budget',
                    style: PhlioTypography.caption.copyWith(color: PhlioColors.textOnBrand, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (typing)
          Row(children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.3 + 0.6 * (0.5 + 0.5 * math.sin(2 * math.pi * (t * 6 - i / 3)))),
                ),
              ),
          ]),
        Opacity(
          opacity: (reply).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - reply)),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF1B2230), borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Here\'s a plan within budget:', style: PhlioTypography.caption.copyWith(color: Colors.white)),
                const SizedBox(height: 6),
                for (final (i, (icon, label)) in const [
                  (Icons.sports_tennis_rounded, 'Badminton court · 10 am'),
                  (Icons.restaurant_rounded, 'Lunch at Green Leaf'),
                  (Icons.movie_rounded, 'Evening movie · 3 seats'),
                ].indexed)
                  Opacity(
                    opacity: (_seg(t, 0.55 + i * 0.07, 0.65 + i * 0.07)).clamp(0.0, 1.0),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        Icon(icon, size: 15, color: PhlioColors.brandOrange),
                        const SizedBox(width: 6),
                        Text(label, style: PhlioTypography.caption.copyWith(fontSize: 11, color: PhlioColors.textSecondary)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        const Spacer(),
        Container(
          height: 40,
          decoration: BoxDecoration(color: const Color(0xFF182231), borderRadius: BorderRadius.circular(999)),
          child: Row(children: [
            const SizedBox(width: 6),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF303A4A))),
              child: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Text('Ask Foxy anything...', style: PhlioTypography.caption.copyWith(color: PhlioColors.textMuted)),
          ]),
        ),
      ]),
    );
  }
}

class _FinishDemo extends StatelessWidget {
  const _FinishDemo({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(shape: BoxShape.circle),
          child: Image.asset('assets/images/logo/logo_mark.png',
              height: 84, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox(height: 84)),
        ),
        const SizedBox(height: 10),
        Image.asset('assets/images/logo/logo_wordmark.png',
            height: 26, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Text('Phlio', style: PhlioTypography.headline)),
        const SizedBox(height: 8),
        Text('PEOPLE. PLACES. POSSIBILITIES.',
            style: PhlioTypography.caption.copyWith(letterSpacing: 2.4, fontSize: 10, color: PhlioColors.textMuted)),
      ]),
    );
  }
}
