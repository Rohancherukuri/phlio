import 'package:phlio/features/social/presentation/widgets/social_explore_posts_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/social/presentation/controllers/video_library.dart';
import 'package:phlio/features/social/presentation/widgets/social_explore_videos_view.dart';

void main() {
  testWidgets('Explore category tabs have finite widths and can switch',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
      body: SocialExplorePostsView(
          posts: const [], query: '', onRefresh: () async {}),
    ))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('For you')).width.isFinite, isTrue);
    await tester.tap(find.text('Trending'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('No posts to explore yet.'), findsOneWidget);
  });

  testWidgets('Title search excludes unrelated videos and clips',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          explorePostsProvider.overrideWith((ref) async => []),
          socialVideoCatalogProvider.overrideWith((ref) async => [
                const PlayableVideo(
                    id: 'v1',
                    title: 'Ocean diving',
                    creator: 'alex',
                    url: '',
                    kind: 'video'),
                const PlayableVideo(
                    id: 'c1',
                    title: 'Mountain walk',
                    creator: 'sam',
                    url: '',
                    kind: 'clip'),
              ]),
        ],
        child: const MaterialApp(
            home: Scaffold(body: SocialExploreVideosView()))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Mountain');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Videos'));
    await tester.pumpAndSettle();
    expect(find.text('No videos match your search.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ocean');
    await tester.tap(find.text('Posts'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Clips'));
    await tester.pumpAndSettle();
    expect(find.text('No clips match your search.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Search persists between content tabs and clears',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          explorePostsProvider.overrideWith((ref) async => []),
          socialVideoCatalogProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
            home: Scaffold(body: SocialExploreVideosView()))));
    await tester.pumpAndSettle();
    expect(find.text('Posts'), findsOneWidget);
    expect(find.text('Your story'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Ocean');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Videos'));
    await tester.pumpAndSettle();
    expect(find.text('No videos match your search.'), findsOneWidget);
    expect(find.text('Ocean'), findsOneWidget);
    await tester.tap(find.text('Clips'));
    await tester.pumpAndSettle();
    expect(find.text('No clips match your search.'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('No clips yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
