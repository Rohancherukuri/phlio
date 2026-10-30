import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/shared/content/stream_title_details.dart';

void main() {
  testWidgets('Details show cast, episodes and honest external viewing availability', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: StreamTitleDetails(item: {
        'provider': 'tvmaze', 'genres': ['Drama'], 'rating': 8.5, 'publisher': 'TVmaze',
        'cast': [{'name': 'Actor', 'role': 'Lead'}],
        'episodes': [{'season': 1, 'number': 1, 'title': 'Pilot', 'description': 'A story'}],
        'watch_links': [{'name': 'Official website', 'url': 'https://example.org'}],
      }),
    ))));
    expect(find.text('Rating: 8.5 / 10 · TVmaze'), findsOneWidget);
    expect(find.text('Official website'), findsOneWidget);
    expect(find.textContaining('regional availability'), findsOneWidget);
    await tester.tap(find.text('Cast'));
    await tester.pumpAndSettle();
    expect(find.text('Actor'), findsOneWidget);
    await tester.tap(find.text('Episodes (1)'));
    await tester.pumpAndSettle();
    expect(find.text('S1 · E1  Pilot'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
