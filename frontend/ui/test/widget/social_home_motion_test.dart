import 'package:phlio/shared/content/content_surface.dart';
import 'dart:io';
import 'package:phlio/features/social/presentation/controllers/video_library.dart';
import 'package:phlio/features/profile/presentation/widgets/profile_posts.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/app/theme/app_theme.dart';
import 'package:phlio/features/authentication/domain/entities/user_entity.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:phlio/features/social/domain/entities/post_entity.dart';
import 'package:phlio/features/social/presentation/controllers/feed_controller.dart';
import 'package:phlio/features/social/presentation/screens/social_home_screen.dart';
import 'package:phlio/features/social/presentation/widgets/social_feed_view.dart';
import 'package:phlio/features/social/presentation/widgets/social_videos_view.dart';
import 'package:phlio/features/social/presentation/widgets/stories_bar.dart';

class _Auth extends AuthController {
  @override
  Future<UserEntity?> build() async => null;
}

class _Feed extends FeedController {
  @override
  Future<FeedState> build() async => FeedState(posts: [
        for (var i = 0; i < 12; i++)
          PostEntity(
              id: '$i',
              authorId: ['Arjun Kumar', 'Neha Sharma', 'Kiara Patel'][i % 3],
              text:
                  'Small moments, great conversations. What are you creating this week?',
              media: const [],
              tags: const ['creativity'],
              likeCount: 24,
              commentCount: 6,
              createdAt: DateTime.now().subtract(Duration(minutes: 5 + i)),
              likedByMe: false)
      ], nextCursor: null, hasMore: false);
}

const capture = bool.fromEnvironment('CAPTURE_SOCIAL');
final captureKey = GlobalKey();
Future<void> shot(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary =
      captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/social-previews').createSync(recursive: true);
    File('build/social-previews/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> app(WidgetTester tester, double width, double scale,
    {bool reduced = false, List stories = const []}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        sharedStoriesProvider.overrideWith((ref) async => stories),
        feedControllerProvider.overrideWith(_Feed.new),
        socialVideoCatalogProvider.overrideWith((ref) async => []),
        creatorFollowingProvider.overrideWith((ref) async => {}),
        publicProfileProvider
            .overrideWith((ref, id) async => {'full_name': id}),
        storyUsersProvider.overrideWith((ref) => [
              for (var i = 0; i < 8; i++) (name: 'Creator $i', avatarAsset: '')
            ]),
      ],
      child: RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
              theme: AppTheme.dark,
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      disableAnimations: reduced),
                  child: child!),
              home: const SocialHomeScreen()))));
  await tester.pumpAndSettle();
  if (capture) {
    await tester.runAsync(() async {
      for (final path in {
        ...kSocialVideos.map((video) => video.thumbAsset),
        ...kSocialVideos.map((video) => video.avatarAsset)
      }) {
        await precacheImage(AssetImage(path), captureKey.currentContext!);
      }
    });
    await tester.pumpAndSettle();
  }
}

Finder feedList() => find
    .descendant(
        of: find.byType(SocialFeedView), matching: find.byType(ListView))
    .first;
double reveal(WidgetTester tester) =>
    1 -
    tester
        .widget<MorphingStoriesHeader>(find.byType(MorphingStoriesHeader))
        .progress;
void main() {
  setUpAll(() async {
    if (capture) {
      for (final family in ['Manrope', 'Quicksand']) {
        final fonts = FontLoader(family);
        final base = family == 'Manrope' ? 'manrope-v20' : 'quicksand-v37';
        for (final weight in ['regular', '500', '600', '700'])
          fonts
              .addFont(rootBundle.load('assets/fonts/$base-latin-$weight.ttf'));
        await fonts.load();
      }
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    }
  });
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Social fold and tabs align at $width scale $scale',
          (tester) async {
        await app(tester, width, scale);
        final tabs = find.byKey(const ValueKey('social-tabs'));
        final left = tester.getTopLeft(tabs).dx;
        expect(reveal(tester), 0);
        await tester.drag(feedList(), const Offset(0, 180));
        await tester.pumpAndSettle();
        expect(reveal(tester), 1);
        if (capture && width == 390 && scale == 1)
          await shot(tester, 'expanded');
        await tester.drag(feedList(), const Offset(0, -220));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(reveal(tester), lessThan(1));
        if (capture && width == 390 && scale == 1)
          await shot(tester, 'folding');
        await tester.pumpAndSettle();
        expect(reveal(tester), 0);
        expect(tester.getTopLeft(tabs).dx, left);
        expect(tester.takeException(), isNull);
        if (capture && width == 390 && scale == 1)
          await shot(tester, 'collapsed');
        await tester.ensureVisible(find.text('Videos'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Videos'));
        await tester.pumpAndSettle();
        expect(reveal(tester), 0);
        expect(find.byType(SocialVideosView), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (capture && width == 390 && scale == 1) await shot(tester, 'videos');
        await tester.ensureVisible(find.text('Posts'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Posts'));
        await tester.pumpAndSettle();
        expect(reveal(tester), 0);
        final scroll = tester.state<ScrollableState>(find
            .descendant(of: feedList(), matching: find.byType(Scrollable))
            .first);
        expect(scroll.position.pixels, greaterThan(48));
        scroll.position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(reveal(tester), 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('Only active moment authors populate the expanded row',
      (tester) async {
    await app(tester, 390, 1, stories: [
      {
        'author': {
          'id': 'moment-author',
          'display_name': 'Maya',
          'avatar_url': null
        }
      },
      {
        'author': {
          'id': 'moment-author',
          'display_name': 'Maya',
          'avatar_url': null
        }
      },
    ]);
    await tester.drag(feedList(), const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(find.text('Maya'), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-moment-0')), findsNothing);
    expect(find.byKey(const ValueKey('empty-moment-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('No moments renders grey slots on all three tabs',
      (tester) async {
    await app(tester, 390, 1);
    for (final tab in ['Posts', 'Videos', 'Clips']) {
      await tester.ensureVisible(find.text(tab));
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('empty-moment-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('Each tab reveals moments only on leading-edge overscroll',
      (tester) async {
    await app(tester, 390, 1);
    for (var index = 0; index < 3; index++) {
      await tester
          .ensureVisible(find.text(['Posts', 'Videos', 'Clips'][index]));
      await tester.tap(find.text(['Posts', 'Videos', 'Clips'][index]));
      await tester.pumpAndSettle();
      expect(reveal(tester), 0);
      final listener = find
          .descendant(
            of: find.byKey(ValueKey('social-tab-$index')),
            matching: find.byType(NotificationListener<ScrollNotification>),
          )
          .first;
      final callback = tester
          .widget<NotificationListener<ScrollNotification>>(listener)
          .onNotification!;
      final metrics = FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 1200,
          pixels: 0,
          viewportDimension: 600,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1);
      callback(OverscrollNotification(
          metrics: metrics,
          context: tester.element(listener),
          overscroll: -90,
          dragDetails: DragUpdateDetails(
              globalPosition: Offset.zero, delta: const Offset(0, 90))));
      callback(ScrollEndNotification(
          metrics: metrics, context: tester.element(listener)));
      await tester.pumpAndSettle();
      expect(reveal(tester), 1);
      callback(ScrollUpdateNotification(
          metrics: metrics,
          context: tester.element(listener),
          scrollDelta: 120,
          dragDetails: DragUpdateDetails(
              globalPosition: Offset.zero, delta: const Offset(0, -120))));
      callback(ScrollEndNotification(
          metrics: metrics, context: tester.element(listener)));
      await tester.pumpAndSettle();
      expect(reveal(tester), 0);
    }
  });
  testWidgets('Scrolling back within later content does not reveal moments',
      (tester) async {
    await app(tester, 390, 1);
    await tester.drag(feedList(), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.drag(feedList(), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(reveal(tester), 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Reduced motion changes header immediately', (tester) async {
    await app(tester, 390, 1, reduced: true);
    await tester.drag(feedList(), const Offset(0, -180));
    await tester.pump();
    expect(reveal(tester), 0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
