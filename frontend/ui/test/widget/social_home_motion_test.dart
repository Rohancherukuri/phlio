import 'dart:io';
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
    {bool reduced = false}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        feedControllerProvider.overrideWith(_Feed.new)
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
        ...kStoryUsers.map((user) => user.avatarAsset),
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
        expect(reveal(tester), 1);
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
        expect(reveal(tester), 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'The same avatar follows the finger and reverses without a cross-fade',
      (tester) async {
    await app(tester, 390, 1);
    final avatar = find.byKey(const ValueKey('social-story-avatar-1'));
    final originalElement = tester.element(avatar);
    final start = tester.getRect(avatar);
    final gesture = await tester.startGesture(tester.getCenter(feedList()));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -35));
    await tester.pump();
    final middle = tester.getRect(avatar);
    expect(middle.width, lessThan(start.width));
    expect(middle.width, greaterThan(22));
    expect(middle.left, greaterThan(start.left));
    expect(tester.element(avatar), same(originalElement));
    expect(find.byType(StoriesHeaderStack), findsNothing);
    expect(find.byType(StoriesStrip), findsNothing);
    if (capture) await shot(tester, 'morph-middle');
    await gesture.moveBy(const Offset(0, 15));
    await tester.pump();
    final reverse = tester.getRect(avatar);
    expect(reverse.width, greaterThan(middle.width));
    expect(reverse.left, lessThan(middle.left));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Story rail scrolls and compact stack can reopen it',
      (tester) async {
    await app(tester, 390, 1);
    final avatar = find.byKey(const ValueKey('social-story-avatar-2'));
    final start = tester.getTopLeft(avatar).dx;
    await tester.drag(avatar, const Offset(-90, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(avatar).dx, lessThan(start));
    await tester.drag(feedList(), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(reveal(tester), 0);
    await tester.tap(find.bySemanticsLabel('Expand stories'));
    await tester.pumpAndSettle();
    expect(reveal(tester), 1);
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
