import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/authentication/domain/entities/user_entity.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:phlio/features/social/presentation/widgets/post_composer.dart';

class _Auth extends AuthController {
  @override
  Future<UserEntity?> build() async => null;
}

void main() {
  testWidgets('Composer has fixed tools and enables Post after typing',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
        overrides: [authControllerProvider.overrideWith(_Auth.new)],
        child: const MaterialApp(home: PostComposer())));
    await tester.pumpAndSettle();
    expect(find.text('Drafts'), findsOneWidget);
    final decoration =
        tester.widget<TextField>(find.byType(TextField)).decoration!;
    expect(decoration.filled, false);
    expect(decoration.hintText, isNotEmpty);
    final toolbarIcons = [
      'Photos',
      'Camera',
      'Create Space',
      'GIF',
      'Add poll',
      'Location tagging is not available',
      'Add music',
      'Add another post'
    ];
    final centers = [
      for (final label in toolbarIcons) tester.getCenter(find.byTooltip(label))
    ];
    for (var i = 1; i < centers.length; i++) {
      expect(centers[i].dy, centers[0].dy);
      expect(centers[i].dx - centers[i - 1].dx, closeTo(43, 1));
    }

    expect(find.text('Everyone can reply'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), 'A new moment');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    expect(find.byTooltip('Add music'), findsOneWidget);
    final plus = find.byTooltip('Add another post');
    expect(tester.getCenter(plus).dx, greaterThan(300));
    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(find.text('A new moment'), findsOneWidget);
    expect(find.text('Post all'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await tester.enterText(find.byType(TextField), 'Second post');
    await tester.tap(find.text('A new moment'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'A new moment');
    expect(find.text('Second post'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Add poll'));
    await tester.tap(find.byTooltip('Add poll'));
    await tester.pumpAndSettle();
    expect(find.text('Choice 1'), findsOneWidget);
    expect(find.text('Choice 2'), findsOneWidget);
    expect(find.text('Poll length'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Add choice'));
    await tester.tap(find.byTooltip('Add choice'));
    await tester.pumpAndSettle();
    expect(find.text('Choice 3'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Remove poll'));
    await tester.tap(find.byTooltip('Remove poll'));
    await tester.pumpAndSettle();
    expect(find.text('Choice 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
