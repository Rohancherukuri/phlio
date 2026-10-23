import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:phlio/features/profile/presentation/widgets/memories_screen.dart';
import 'social_chat_modes_test.dart' show TestAuth;
void main() {
 testWidgets('Memories empty state fits a small phone and offers capture', (tester) async {
  await tester.binding.setSurfaceSize(const Size(320, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(overrides: [
    authControllerProvider.overrideWith(TestAuth.new),
    memoriesProvider.overrideWith((ref) async => []),
  ], child: const MaterialApp(home: MemoriesScreen(openCamera: false))));
  await tester.pumpAndSettle();
  expect(find.text('Memories'), findsOneWidget);
  await tester.scrollUntilVisible(find.text('Take a snap'), 200);
  expect(find.text('Take a snap'), findsOneWidget);
  expect(find.text('No snaps yet. Capture your first memory.'), findsOneWidget);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
 });
}

