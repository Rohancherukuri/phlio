import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/social/presentation/controllers/video_library.dart';
import 'package:phlio/features/social/presentation/widgets/social_videos_view.dart';

void main() {
  testWidgets('Plain StatefulElement survives reassembly and catalog retry',
      (tester) async {
    var requests = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialVideoCatalogProvider.overrideWith((ref) async {
            if (++requests == 1) throw Exception('Offline');
            return <PlayableVideo>[];
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SafeArea(child: SocialVideosView())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // This is the element type that existed before the Riverpod migration.
    final element = tester.element(find.byType(SocialVideosView));
    expect(element.runtimeType, StatefulElement);
    expect(find.text('Could not load videos.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Exercise hot-reload reassembly on the retained element, without a VM reload.
    // ignore: invalid_use_of_protected_member
    element.reassemble();
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(SocialVideosView)), same(element));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No videos yet.'), findsOneWidget);
    expect(requests, 2);
    expect(tester.takeException(), isNull);
  });
}
