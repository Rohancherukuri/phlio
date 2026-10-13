import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/core/di/service_locator.dart';
import 'package:phlio/core/network/api_client.dart';
import 'package:phlio/shared/content/social_comments_sheet.dart';
import 'content_surface_test.dart' show FakeApi;

void main() {
  testWidgets('Composer stays at screen bottom above nested navigation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
        overrides: [socialCommentsProvider.overrideWith((ref, id) async => [])],
        child: MaterialApp(
            home: Scaffold(
                bottomNavigationBar: const SizedBox(height: 80),
                body: Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute(
                        builder: (context) => Scaffold(
                            body: Center(
                                child: TextButton(
                                    onPressed: () =>
                                        showSocialComments(context, 'demo'),
                                    child: const Text('Open comments'))))))))));
    await tester.tap(find.text('Open comments'));
    await tester.pumpAndSettle();
    final composer =
        tester.getRect(find.byKey(const ValueKey('comment-composer')));
    expect(composer.bottom, closeTo(844, 1));
    expect(tester.getRect(find.byTooltip('Attach image')).bottom,
        greaterThan(800));
    expect(find.byTooltip('Attach GIF'), findsOneWidget);
    expect(find.byTooltip('Stickers'), findsOneWidget);
    await tester.tap(find.byTooltip('Insert ❤️'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '❤️');
    expect(find.byTooltip('Post comment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('Rich comments fit keyboard at scale $scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = FakeApi();
      bool posted = false;
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.method == 'POST') {
          posted = true;
          h.resolve(Response(requestOptions: o, data: {}, statusCode: 201));
        } else
          h.resolve(Response(
              requestOptions: o,
              data: [
                {'username': 'neha', 'id': 'neha'}
              ],
              statusCode: 200));
      }));
      getIt.registerSingleton<ApiClient>(api);
      addTearDown(() => getIt.reset());
      await tester.pumpWidget(ProviderScope(
          overrides: [
            socialCommentsProvider.overrideWith((ref, id) async => [])
          ],
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      viewInsets: const EdgeInsets.only(bottom: 220)),
                  child: child!),
              home: const Scaffold(
                  resizeToAvoidBottomInset: false,
                  body: SocialCommentsSheet(contentId: 'demo')))));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Hello @ne');
      await tester.pumpAndSettle();
      expect(find.text('@neha'), findsOneWidget);
      await tester.tap(find.text('@neha'));
      await tester.pumpAndSettle();
      expect(find.text('Hello @neha '), findsOneWidget);
      await tester.tap(find.byTooltip('Post comment'));
      await tester.pumpAndSettle();
      expect(posted, isTrue);
    });
  }
}
