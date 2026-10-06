import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/colors.dart';
import '../widgets/stories_bar.dart';
import '../widgets/social_clips_view.dart';
import '../widgets/social_feed_view.dart';
import '../widgets/social_videos_view.dart';

/// Scroll-linked avatar geometry, matching the continuous collapse in the reference.
class SocialHomeScreen extends ConsumerStatefulWidget {
  const SocialHomeScreen({super.key});
  @override
  ConsumerState<SocialHomeScreen> createState() => _SocialHomeScreenState();
}

class _SocialHomeScreenState extends ConsumerState<SocialHomeScreen>
    with TickerProviderStateMixin {
  // Backed by nullable fields instead of `late final`: a hot reload can
  // re-run build() on a State instance created before these fields existed
  // (uninitialized late-final storage) and crash with LateInitializationError
  // — the lazy getters rebuild the controller instead.
  TabController? _tabsInst;
  AnimationController? _foldInst;
  TabController get _tabs => _tabsInst ??= TabController(
      length: 3,
      vsync: this,
      animationDuration: const Duration(milliseconds: 260));
  AnimationController get _fold => _foldInst ??= AnimationController(
      vsync: this, duration: const Duration(milliseconds: 280));
  final _foldTargets = [0.0, 0.0, 0.0];
  bool _collapsed = false;
  bool _reduceMotion = false;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_tabChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _fold.value = _collapsed ? 1 : 0;
  }

  void _tabChanged() {
    if (_selected == _tabs.index) return;
    _selected = _tabs.index;
    _settle(_foldTargets[_selected]);
  }

  void _settle(double target) {
    _foldTargets[_selected] = target;
    _collapsed = target >= .5;
    if (_reduceMotion) {
      _fold.value = _collapsed ? 1 : 0;
    } else {
      _fold.animateTo(target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic);
    }
  }

  bool _scroll(int tab, ScrollNotification event) {
    if (event.metrics.axis != Axis.vertical) return false;
    if (event is ScrollUpdateNotification) {
      final delta = event.scrollDelta ?? 0;
      if (tab == _tabs.index && delta != 0) {
        _fold.stop();
        final target = event.metrics.pixels <= 0
            ? 0.0
            : (_foldTargets[tab] + delta / 110).clamp(0.0, 1.0);
        _foldTargets[tab] = target;
        _collapsed = target >= .5;
        _fold.value = _reduceMotion ? (_collapsed ? 1 : 0) : target;
      }
    } else if (event is ScrollEndNotification && tab == _tabs.index) {
      _settle(_foldTargets[tab] >= .5 ? 1 : 0);
    }
    return false;
  }

  @override
  void dispose() {
    _tabsInst?.removeListener(_tabChanged);
    _tabsInst?.dispose();
    _foldInst?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          bottom: false,
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: Column(children: [
                    AnimatedBuilder(
                        animation: _fold,
                        builder: (context, _) => _header(context, _fold.value)),
                    Expanded(
                        child: TabBarView(controller: _tabs, children: [
                      for (final (index, child) in const [
                        SocialFeedView(),
                        SocialVideosView(),
                        SocialClipsView()
                      ].indexed)
                        _SocialTab(
                            key: ValueKey('social-tab-$index'),
                            child: NotificationListener<ScrollNotification>(
                                onNotification: (event) =>
                                    _scroll(index, event),
                                child: child)),
                    ])),
                  ])))));

  Widget _header(BuildContext context, double progress) =>
      LayoutBuilder(builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
        final stackOnOwnLine = largeText && constraints.maxWidth < 480;
        return DecoratedBox(
            decoration: BoxDecoration(
                color: PhlioColors.background,
                border: Border(
                    bottom: BorderSide(
                        color: PhlioColors.borderSubtle
                            .withValues(alpha: .3 + progress * .7))),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .12 * progress),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]),
            child: MorphingStoriesHeader(
              progress: progress,
              compactBelow: stackOnOwnLine,
              onExpand: () => _settle(0),
              toolbar: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  child: Row(children: [
                    Expanded(
                        child: TabBar(
                            key: const ValueKey('social-tabs'),
                            controller: _tabs,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            dividerHeight: 0,
                            labelPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            labelColor: PhlioColors.textPrimary,
                            unselectedLabelColor: PhlioColors.textMuted,
                            labelStyle: const TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 16,
                                height: 1.25,
                                fontWeight: FontWeight.w700),
                            unselectedLabelStyle: const TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 16,
                                height: 1.25,
                                fontWeight: FontWeight.w700),
                            indicatorSize: TabBarIndicatorSize.label,
                            indicator: const UnderlineTabIndicator(
                                borderSide: BorderSide(
                                    width: 3, color: PhlioColors.brandOrange),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(3))),
                            onTap: (index) {
                              if (_reduceMotion)
                                _tabs.animateTo(index, duration: Duration.zero);
                            },
                            tabs: const [
                          Tab(text: 'Posts'),
                          Tab(text: 'Videos'),
                          Tab(text: 'Clips')
                        ])),
                    if (!stackOnOwnLine) const SizedBox(width: 62, height: 48),
                    IconButton(
                        tooltip: 'Activity',
                        onPressed: () => context.push('/activity'),
                        icon:
                            const Icon(Icons.notifications_outlined, size: 22)),
                  ])),
            ));
      });
}

/// Keep the feed position and clip state when switching tabs.
class _SocialTab extends StatefulWidget {
  const _SocialTab({required this.child, super.key});
  final Widget child;
  @override
  State<_SocialTab> createState() => _SocialTabState();
}

class _SocialTabState extends State<_SocialTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
