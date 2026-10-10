import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/shared/content/news_screen.dart';
import 'package:phlio/shared/content/content_surface.dart';

void main() {
  for (final explore in [false, true]) {
    testWidgets('News layout fits narrow screen, explore=$explore',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final article = {
        'ref': 'rss_test',
        'title':
            'A publisher headline with enough text to wrap across several lines',
        'publisher': 'Publisher',
        'category': 'Science',
        'published_at': '2026-10-09T10:00:00Z',
        'source_url': 'https://example.com/story'
      };
      await tester.pumpWidget(ProviderScope(
          overrides: [
            newsFeedProvider.overrideWith((ref, filter) async => {
                  'items': [article],
                  'headlines': [article],
                  'categories': ['Top International', 'For You', 'Science'],
                  'topics': [
                    {'name': 'Science', 'count': 1}
                  ],
                  'notice': null
                }),
            engagementProvider.overrideWith(
                (ref, path) async => {'count': 0, 'avatars': [], 'people': []}),
          ],
          child:
              MaterialApp(home: Scaffold(body: NewsScreen(explore: explore)))));
      await tester.pumpAndSettle();
      expect(find.text(explore ? 'Discover' : 'Phlio News'), findsOneWidget);
      expect(find.text(explore ? 'Suggested topics' : 'Headlines'),
          findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
