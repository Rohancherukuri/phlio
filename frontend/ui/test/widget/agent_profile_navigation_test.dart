import 'package:flutter/material.dart';
import 'package:phlio/features/social/presentation/screens/creator_profile_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:phlio/app/theme/app_theme.dart';
import 'package:phlio/core/result/result.dart';
import 'package:phlio/design_system/widgets/phlio_card.dart';
import 'package:phlio/features/phlio_agent/domain/entities/agent_message_entity.dart';
import 'package:phlio/features/phlio_agent/presentation/controllers/agent_controller.dart';
import 'package:phlio/features/phlio_agent/presentation/screens/agent_screen.dart';
import 'package:phlio/features/profile/presentation/widgets/profile_posts.dart';
import 'package:phlio/features/social/domain/entities/post_entity.dart';
import 'package:phlio/features/social/presentation/controllers/video_library.dart';
import 'package:phlio/features/social/presentation/controllers/video_playback_controller.dart';

class _Agent extends AgentController {
  String? sent;
  @override
  Future<List<AgentMessageEntity>> build() async => [];
  @override
  Future<Result<void>> sendMessage(String text) async {
    sent = text;
    return const Result.success(null);
  }
}

class _Playback extends VideoPlaybackController {
  PlayableVideo? opened;
  @override
  Future<void> open(PlayableVideo source) async {
    opened = source;
  }
}

PostEntity post(String id, List<MediaAttachmentEntity> media) => PostEntity(
    id: id,
    authorId: 'usr_real',
    text: '$id content',
    media: media,
    tags: const [],
    likeCount: 0,
    commentCount: 0,
    createdAt: DateTime(2026),
    likedByMe: false);

void main() {
  for (final scenario in [
    (360.0, 570.0, 1.0, 0.0),
    (320.0, 600.0, 2.0, 220.0),
    (800.0, 360.0, 1.0, 100.0)
  ]) {
    testWidgets('Agent welcome scrolls and prompts work at $scenario',
        (tester) async {
      final agent = _Agent();
      await tester.binding.setSurfaceSize(Size(scenario.$1, scenario.$2));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
          overrides: [agentControllerProvider.overrideWith(() => agent)],
          child: MaterialApp(
              theme: AppTheme.dark,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scenario.$3),
                      viewInsets: EdgeInsets.only(bottom: scenario.$4)),
                  child: child!),
              home: const AgentScreen())));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      final prompt = find.text('Suggest a budget-friendly evening out');
      await tester.ensureVisible(prompt);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(prompt);
      await tester.pump();
      expect(agent.sent, 'Suggest a budget-friendly evening out');
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(TextField)).bottom,
          lessThanOrEqualTo(scenario.$2 - scenario.$4));
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'Creator profile uses real identity and Posts tab menu at scale $scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(initialLocation: '/creator/usr_actual', routes: [
        GoRoute(
            path: '/creator/:id',
            builder: (_, state) =>
                CreatorProfileScreen(username: state.pathParameters['id']!)),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            publicProfileProvider('usr_actual').overrideWith((ref) async => {
                  'id': 'usr_actual',
                  'username': 'real',
                  'full_name': 'Real Person',
                  'bio': 'My actual profile',
                  'avatar_url': null,
                  'interests': <String>[],
                  'is_verified': false,
                }),
            profilePostsProvider('real')
                .overrideWith((ref) async => [post('article', [])]),
          ],
          child: MaterialApp.router(
              theme: AppTheme.dark,
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!))));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Real Person'), findsOneWidget);
      expect(find.text('@real'), findsOneWidget);
      final scroll = find
          .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(find.byType(ProfilePostsMenu), 200,
          scrollable: scroll);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Posts'));
      await tester.pumpAndSettle();
      expect(find.text('Articles'), findsOneWidget);
      expect(find.text('Videos'), findsOneWidget);
      expect(find.text('Pics'), findsOneWidget);
      await tester.tap(find.text('Pics'));
      await tester.pumpAndSettle();
      expect(find.text('No pics yet'), findsOneWidget);
      expect(find.text('article content'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Avatar opens its account, while its conversation row opens DM',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
              body: ListTile(
                  leading: const PhlioAvatar(
                      name: 'Display Name', profileId: 'usr_actual'),
                  title: const Text('Conversation'),
                  onTap: () => context.push('/dm')))),
      GoRoute(
          path: '/creator/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Profile ${state.pathParameters['id']}'))),
      GoRoute(
          path: '/dm',
          builder: (_, __) => const Scaffold(body: Text('Private messages'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.byType(PhlioAvatar));
    await tester.pumpAndSettle();
    expect(find.text('Profile usr_actual'), findsOneWidget);
    expect(find.text('Private messages'), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conversation'));
    await tester.pumpAndSettle();
    expect(find.text('Private messages'), findsOneWidget);
  });

  testWidgets(
      'Posts dropdown filters articles, images, videos and creator uploads',
      (tester) async {
    final playback = _Playback();
    var type = ProfilePostType.articles;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          profilePostsProvider('real').overrideWith((ref) async => [
                post('article', []),
                post('picture', const [
                  MediaAttachmentEntity(
                      url: 'https://example.test/photo.jpg',
                      kind: MediaKind.image)
                ]),
                post('video', const [
                  MediaAttachmentEntity(
                      url: 'https://example.test/clip.mp4',
                      kind: MediaKind.video)
                ]),
              ]),
          socialVideoCatalogProvider.overrideWith((ref) async => const [
                PlayableVideo(
                    id: 'upload',
                    title: 'My upload',
                    creator: 'real',
                    url: '/mine.mp4'),
                PlayableVideo(
                    id: 'other',
                    title: 'Other creator upload',
                    creator: 'other',
                    url: '/other.mp4'),
              ]),
          videoPlaybackProvider.overrideWith((ref) => playback),
        ],
        child: MaterialApp(
            theme: AppTheme.dark,
            home: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                        body: Column(children: [
                      ProfilePostsMenu(
                          selected: type,
                          onSelected: (value) => setState(() => type = value)),
                      Expanded(child: ProfilePosts(author: 'real', type: type))
                    ]))))));
    await tester.pumpAndSettle();
    expect(find.text('article content'), findsOneWidget);
    expect(find.text('picture content'), findsNothing);
    await tester.tap(find.text('Posts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pics'));
    await tester.pumpAndSettle();
    expect(find.text('picture content'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('article content'), findsNothing);
    await tester.tap(find.text('Posts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Videos'));
    await tester.pumpAndSettle();
    expect(find.text('video content'), findsOneWidget);
    expect(find.text('My upload'), findsOneWidget);
    expect(find.text('Other creator upload'), findsNothing);
    expect(find.text('picture content'), findsNothing);
    await tester.tap(find.text('Play video'));
    expect(playback.opened?.url, 'https://example.test/clip.mp4');
    expect(tester.takeException(), isNull);
  });
}
