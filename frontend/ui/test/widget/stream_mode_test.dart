import 'package:phlio/features/profile/presentation/widgets/memories_screen.dart';
import 'package:phlio/features/activity/presentation/controllers/activity_controller.dart';
import 'package:phlio/features/activity/domain/entities/activity_entity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/shared/content/content_surface.dart';
import 'package:phlio/shared/content/stream_screen.dart';

class EmptyActivity extends ActivityFeedController {
 @override Future<List<ActivityItemEntity>> build() async => [];
}

void main() {
  testWidgets('Mode toggle separates audio and video search content', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      memoriesProvider.overrideWith((ref) async => []),
      activityFeedProvider.overrideWith(EmptyActivity.new),
      engagementProvider.overrideWith((ref, path) async => {'count': 0, 'avatars': [], 'people': []}),
      catalogProvider('stream').overrideWith((ref) async => [
        {'ref': '1', 'title': 'Ocean movie', 'kind': 'movie'},
        {'ref': '2', 'title': 'Ocean song', 'kind': 'song'},
        {'ref': '3', 'title': 'Ocean podcast', 'kind': 'podcast'},
      ]),
    ], child: const MaterialApp(home: StreamScreen(explore: true))));
    await tester.pumpAndSettle();
    expect(find.text('Ocean movie'), findsOneWidget);
    expect(find.byTooltip('Like content'), findsWidgets);
    expect(find.text('Ocean song'), findsNothing);
    await tester.enterText(find.byType(TextField), 'movie');
    await tester.tap(find.byTooltip('Switch to music and podcasts'));
    await tester.pumpAndSettle();
    expect(find.text('Ocean movie'), findsNothing);
    expect(find.text('Ocean song'), findsOneWidget);
    expect(find.text('Ocean podcast'), findsOneWidget);
    expect(find.text('Songs, artists and podcasts'), findsOneWidget);
    expect(find.text('Movies'), findsNothing);
    await tester.tap(find.byTooltip('Switch to movies and shows'));
    await tester.pumpAndSettle();
    expect(find.text('Ocean movie'), findsOneWidget);
    expect(find.text('Ocean song'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
