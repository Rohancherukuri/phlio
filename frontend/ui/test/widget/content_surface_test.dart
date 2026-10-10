import 'package:phlio/features/social/presentation/widgets/social_videos_view.dart';
import 'package:phlio/features/social/presentation/controllers/video_library.dart';
import 'package:phlio/features/social/presentation/widgets/social_clips_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/core/di/service_locator.dart';
import 'package:phlio/core/network/api_client.dart';
import 'package:phlio/shared/content/content_surface.dart';

class FakeApi implements ApiClient {
  @override
  final dio = Dio();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('First video request omits an empty pagination cursor', () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.queryParameters.containsKey('before'), isFalse);
      handler.resolve(Response(requestOptions: options, data: <dynamic>[]));
    }));
    expect(await SocialVideoApi(dio).videos(), isEmpty);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('Three avatars, more count and share menu fit at scale $scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = FakeApi();
      api.dio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
                  Response(requestOptions: options, statusCode: 200, data: {
                'people': [
                  {'id': 'a', 'display_name': 'Aanya'},
                  {'id': 'b', 'display_name': 'Aarav'}
                ],
                'groups': [],
                'rooms': []
              }))));
      getIt.registerSingleton<ApiClient>(api);
      addTearDown(() => getIt.reset());
      await tester.pumpWidget(ProviderScope(
          overrides: [
            engagementProvider.overrideWith((ref, path) async => {
                  'count': 8,
                  'avatars': [
                    for (final id in ['a', 'b', 'c'])
                      {'id': id, 'display_name': id}
                  ],
                  'people': [],
                  'liked_by_me': false
                })
          ],
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      viewInsets: const EdgeInsets.only(bottom: 220)),
                  child: child!),
              home: const Scaffold(
                  body: SingleChildScrollView(
                      child: ContentSurface(
                          platform: 'social',
                          contentId: 'sample',
                          child: SizedBox(
                              height: 80, child: Text('Demo post'))))))));
      await tester.pumpAndSettle();
      expect(find.text('5 more liked'), findsOneWidget);
      await tester.longPress(find.text('Demo post'));
      await tester.pumpAndSettle();
      expect(find.text('Share content'), findsOneWidget);
      expect(find.text('Rooms'), findsNWidgets(2));
      await tester.ensureVisible(find.text('New group'));
      await tester.tap(find.text('New group'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Compact product engagement remains readable at large text',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          engagementProvider.overrideWith((ref, path) async => {
                'count': 8,
                'avatars': [
                  for (final id in ['a', 'b', 'c'])
                    {'id': id, 'display_name': id}
                ],
                'people': [],
                'liked_by_me': false,
              })
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!),
            home: const Scaffold(
                body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                        width: 140,
                        child: EngagementRow(path: 'shop/demo')))))));
    await tester.pumpAndSettle();
    expect(find.text('5 more liked'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Videos and Clips tabs separate their backend media',
      (tester) async {
    const videos = [
      PlayableVideo(
          id: 'long',
          title: 'Long video only',
          creator: '',
          url: '/long.mp4',
          durationSeconds: 60),
      PlayableVideo(
          id: 'short',
          title: 'Short clip only',
          creator: '',
          url: '/short.mp4',
          kind: 'clip',
          durationSeconds: 15)
    ];
    Widget app(Widget child) => ProviderScope(overrides: [
          socialVideoCatalogProvider.overrideWith((ref) async => videos),
          followedCreatorsProvider.overrideWithValue({}),
          engagementProvider.overrideWith(
              (ref, path) async => {'count': 0, 'avatars': [], 'people': []})
        ], child: MaterialApp(home: Scaffold(body: child)));
    await tester.pumpWidget(app(const SocialVideosView()));
    await tester.pumpAndSettle();
    expect(find.text('Long video only'), findsOneWidget);
    expect(find.text('Short clip only'), findsNothing);
    expect(find.byTooltip('Upload a video'), findsNothing);
    await tester.pumpWidget(app(const SocialClipsView()));
    await tester.pumpAndSettle();
    expect(find.text('Short clip only'), findsOneWidget);
    expect(find.text('Long video only'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Mutuals display the count and overlapping circles',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          mutualsProvider.overrideWith((ref, target) async => {
                'count': 5,
                'avatars': [
                  for (final id in ['a', 'b', 'c'])
                    {'id': id, 'display_name': id}
                ]
              })
        ],
        child: const MaterialApp(
            home: Scaffold(body: MutualAvatars(target: 'creator')))));
    await tester.pumpAndSettle();
    expect(find.text('5 mutual friends'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Malformed shared URI remains readable', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SharedContentText('phlio://content/social/%invalid'))));
    expect(tester.takeException(), isNull);
    expect(find.text('phlio://content/social/%invalid'), findsOneWidget);
  });
}
