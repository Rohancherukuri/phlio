import 'package:phlio/core/di/service_locator.dart';
import 'package:phlio/core/network/api_client.dart';
import 'content_surface_test.dart' show FakeApi;
import 'package:go_router/go_router.dart';
import 'package:phlio/app/app.dart';
import 'package:phlio/app/router/app_router.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:phlio/features/authentication/domain/entities/user_entity.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:phlio/features/social/presentation/widgets/creator_follow_button.dart';
import 'package:video_player/video_player.dart';
import 'package:phlio/features/social/presentation/controllers/video_library.dart';
import 'package:phlio/features/social/presentation/controllers/video_playback_controller.dart';

class TestAuth extends AuthController {
  @override
  Future<UserEntity?> build() async => null;
}

class TestVideoApi extends SocialVideoApi {
  TestVideoApi() : super(Dio());
  final subscriptions = <String>{};
  @override
  Future<Set<String>> following() async => {...subscriptions};
  @override
  Future<void> follow(String creator, bool enabled) async {
    if (enabled) {
      subscriptions.add(creator);
    } else {
      subscriptions.remove(creator);
    }
  }
}

class MockPlayer extends Mock implements VideoPlayerController {}

const video =
    PlayableVideo(id: 'one', title: 'A video', creator: '', url: '/one.mp4');
MockPlayer player() {
  final p = MockPlayer();
  when(() => p.value).thenReturn(const VideoPlayerValue(
      duration: Duration(minutes: 2),
      isInitialized: true,
      position: Duration(seconds: 30),
      size: Size(1920, 1080)));
  when(() => p.initialize()).thenAnswer((_) async {});
  when(() => p.setPlaybackSpeed(any())).thenAnswer((_) async {});
  when(() => p.setVolume(any())).thenAnswer((_) async {});
  when(() => p.setLooping(any())).thenAnswer((_) async {});
  when(() => p.play()).thenAnswer((_) async {});
  when(() => p.pause()).thenAnswer((_) async {});
  when(() => p.dispose()).thenAnswer((_) async {});
  when(() => p.seekTo(any())).thenAnswer((_) async {});
  return p;
}

void main() {
  setUpAll(() => registerFallbackValue(Duration.zero));
  testWidgets('Switching modes retains session, position and speed',
      (tester) async {
    final p = player();
    final c = VideoPlaybackController(factory: (_) => p);
    await c.open(video);
    await c.setSpeed(1.5);
    c.setMode(SocialPlayerMode.fullscreen);
    c.setMode(SocialPlayerMode.floating);
    await c.open(video);
    expect(c.player, same(p));
    expect(c.player!.value.position, const Duration(seconds: 30));
    expect(c.speed, 1.5);
    verify(() => p.initialize()).called(1);
    await c.seek(const Duration(seconds: -10));
    verify(() => p.seekTo(Duration.zero)).called(1);
    c.close();
    expect(c.mode, SocialPlayerMode.hidden);
    verify(() => p.dispose()).called(1);
    c.dispose();
  });
  testWidgets('Closing during initialization does not start playback',
      (tester) async {
    final p = player();
    final initialized = Completer<void>();
    when(() => p.initialize()).thenAnswer((_) => initialized.future);
    final c = VideoPlaybackController(factory: (_) => p);
    final opening = c.open(video);
    c.close();
    initialized.complete();
    await opening;
    verifyNever(() => p.play());
    expect(c.mode, SocialPlayerMode.hidden);
    c.dispose();
  });
  testWidgets('Follow action persists and both buttons stay synchronized',
      (tester) async {
    final api = TestVideoApi();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(TestAuth.new),
          socialVideoApiProvider.overrideWithValue(api)
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: Column(children: [
          CreatorFollowButton(creator: 'neha'),
          CreatorFollowButton(creator: 'neha')
        ])))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Follow').first);
    await tester.pumpAndSettle();
    expect(api.subscriptions, {'neha'});
    expect(find.text('Following'), findsNWidgets(2));
    await tester.tap(find.text('Following').last);
    await tester.pumpAndSettle();
    expect(api.subscriptions, isEmpty);
    expect(find.text('Follow'), findsNWidgets(2));
  });
  testWidgets('Holding the global player opens the share sheet above playback',
      (tester) async {
    final api = FakeApi();
    api.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'people': [], 'groups': [], 'rooms': []}))));
    getIt.registerSingleton<ApiClient>(api);
    addTearDown(() => getIt.reset());
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('Home')))
    ]);
    addTearDown(router.dispose);
    final c = VideoPlaybackController();
    c.video = video;
    c.error = 'Demo picture';
    c.setMode(SocialPlayerMode.expanded);
    await tester.pumpWidget(ProviderScope(overrides: [
      videoPlaybackProvider.overrideWith((ref) => c),
      routerProvider.overrideWithValue(router),
      authControllerProvider.overrideWith(TestAuth.new)
    ], child: const PhlioApp()));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Demo picture'));
    await tester.pumpAndSettle();
    expect(find.text('Share content'), findsOneWidget);
    expect(c.mode, SocialPlayerMode.hidden);
    expect(tester.takeException(), isNull);
    router.routerDelegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(c.mode, SocialPlayerMode.floating);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1280, 800)
  ]) {
    testWidgets('Player layout and floating controls at $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = VideoPlaybackController();
      c.video = video;
      c.error = 'Could not play this video.';
      c.setMode(SocialPlayerMode.expanded);
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('Underlying page')))
      ]);
      addTearDown(router.dispose);
      // Exercise the global player in MaterialApp.router.builder, outside routes.
      await tester.pumpWidget(ProviderScope(overrides: [
        videoPlaybackProvider.overrideWith((ref) => c),
        routerProvider.overrideWithValue(router),
        authControllerProvider.overrideWith(TestAuth.new),
      ], child: const PhlioApp()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Playback settings'));
      await tester.pump();
      expect(find.text('Playback speed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Fullscreen'));
      await tester.pump();
      expect(c.mode, SocialPlayerMode.fullscreen);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Exit fullscreen'));
      await tester.pump();
      await tester.longPress(find.byTooltip('Minimize player'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Minimize player'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byTooltip('Floating player'));
      await tester.pump();
      expect(c.mode, SocialPlayerMode.floating);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Expand player'));
      await tester.pump();
      expect(c.mode, SocialPlayerMode.expanded);
      await tester.tap(find.byTooltip('Close player'));
      await tester.pump();
      expect(find.byTooltip('Playback settings'), findsNothing);
    });
  }
}
