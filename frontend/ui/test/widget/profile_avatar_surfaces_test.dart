import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:phlio/features/profile/presentation/controllers/avatar_controller.dart';
import 'package:phlio/features/social/presentation/widgets/stories_bar.dart';
import 'package:phlio/shared/content/social_comments_sheet.dart';
import 'package:phlio/shared/content/content_surface.dart';
import 'social_chat_modes_test.dart' show TestAuth;

class TestAvatar extends AvatarController {
  @override
  AvatarState build() => const AvatarState();
}

void main() {
  testWidgets('Own like uses current profile avatar in stack and liker list', (tester) async {
    final person = {'id':'me','display_name':'Arjun','avatar_url':'https://example.com/stale.jpg'};
    await tester.pumpWidget(ProviderScope(overrides:[
      authControllerProvider.overrideWith(TestAuth.new),
      avatarProvider.overrideWith(TestAvatar.new),
      engagementProvider.overrideWith((ref, path) async => {
        'avatars':[person], 'people':[person], 'count':1, 'liked_by_me':true,
      }),
    ],child:const MaterialApp(home:Scaffold(body:EngagementRow(path:'social/post')))));
    await tester.pumpAndSettle();
    expect(find.byType(MeAvatar), findsOneWidget);
    await tester.tap(find.text('1 liked'));
    await tester.pumpAndSettle();
    expect(find.byType(MeAvatar), findsNWidgets(2));
    expect(tester.takeException(),isNull);
  });
  for (final embedded in [false, true]) {
    testWidgets('Post/video comments open shared GIF and sticker tabs (embedded: $embedded)', (tester) async {
      await tester.pumpWidget(ProviderScope(overrides: [
        authControllerProvider.overrideWith(TestAuth.new),
        avatarProvider.overrideWith(TestAvatar.new),
        socialCommentsProvider.overrideWith((ref, id) async => []),
      ], child: MaterialApp(home: Scaffold(body: SocialCommentsSheet(contentId: 'test', embedded: embedded)))));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('GIFs and stickers'));
      await tester.pumpAndSettle();
      expect(find.text('GIFs'), findsOneWidget);
      expect(find.text('Stickers'), findsOneWidget);
      expect(find.byTooltip('Trending'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Stories and own comments use the shared profile avatar',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      authControllerProvider.overrideWith(TestAuth.new),
      avatarProvider.overrideWith(TestAvatar.new),
      storyUsersProvider.overrideWith((ref) => [])
    ], child: const MaterialApp(home: Scaffold(body: StoriesStrip()))));
    await tester.pumpAndSettle();
    expect(find.byType(MeAvatar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(TestAuth.new),
          avatarProvider.overrideWith(TestAvatar.new),
          socialCommentsProvider.overrideWith((ref, id) async => [
                {
                  'id': 'comment',
                  'text': 'My real comment',
                  'created_at': '2026-10-14T00:00:00Z',
                  'author': {
                    'id': 'me',
                    'username': 'placeholder',
                    'display_name': 'Placeholder',
                    'avatar_url': null
                  }
                },
              ])
        ],
        child: const MaterialApp(
            home: Scaffold(body: SocialCommentsSheet(contentId: 'post')))));
    await tester.pumpAndSettle();
    expect(find.byType(MeAvatar), findsNWidgets(2));
    expect(find.text('arjun'), findsOneWidget);
    expect(find.text('placeholder'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
