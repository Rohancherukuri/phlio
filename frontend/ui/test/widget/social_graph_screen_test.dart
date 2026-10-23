import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/social/presentation/screens/social_graph_screen.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('Graph privacy and private Notes fit mobile at scale $scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(overrides: [
        graphActivityProvider.overrideWith((ref) async => []),
        graphNotesProvider.overrideWith((ref) async => [{'text': 'Private note from a friend'}]),
        graphPoliciesProvider.overrideWith((ref) async => []),
      ], child: MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!), home: const SocialGraphScreen())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes')); await tester.pumpAndSettle();
      expect(find.text('Private note from a friend'), findsOneWidget);
      await tester.tap(find.text('Privacy')); await tester.pumpAndSettle();
      final scroll = find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text('Only me'), 100, scrollable: scroll);
      expect(find.text('Only me'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('No access'), 100, scrollable: scroll);
      expect(find.text('No access'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
