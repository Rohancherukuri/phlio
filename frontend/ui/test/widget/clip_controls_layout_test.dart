import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/authentication/domain/entities/user_entity.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:phlio/features/social/presentation/controllers/video_library.dart';
import 'package:phlio/features/social/presentation/widgets/social_clips_view.dart';
import 'package:phlio/shared/content/content_surface.dart';
import 'package:phlio/shared/content/social_comments_sheet.dart';
import 'package:phlio/shared/music/song_picker.dart';
class _Auth extends AuthController {
 @override Future<UserEntity?> build() async => null;
}
void main() {
 testWidgets('Clip controls fit short viewport and mute never overlaps likes', (tester) async {
  await tester.binding.setSurfaceSize(const Size(360, 500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(overrides: [
    authControllerProvider.overrideWith(_Auth.new),
    friendsLikedClipsProvider.overrideWith((ref) async => {}),
    socialVideoCatalogProvider.overrideWith((ref) async => [const PlayableVideo(id:'clip',title:'Test clip',creator:'creator',url:'',kind:'clip')]),
    creatorFollowingProvider.overrideWith((ref) async => {}),
    engagementProvider.overrideWith((ref,id) async => {}),
    socialCommentsProvider.overrideWith((ref,id) async => []),
    contentSongProvider.overrideWith((ref,id) async => null),
  ], child: const MaterialApp(home: Scaffold(body: TickerMode(enabled:false, child: SocialClipsView())))));
  await tester.pumpAndSettle();
  final mute = tester.getRect(find.byTooltip('Mute'));
  final like = tester.getRect(find.byIcon(Icons.favorite_border));
  expect(mute.overlaps(like), isFalse);
  expect(like.top, greaterThanOrEqualTo(0));
  expect(like.bottom, lessThanOrEqualTo(500));
  expect(find.text('Clips'), findsOneWidget);
  await tester.tap(find.byTooltip('Clips feed'));
  await tester.pumpAndSettle();
  expect(find.text('Following'), findsOneWidget);
  expect(find.byIcon(Icons.people_outline_rounded), findsOneWidget);
  Navigator.of(tester.element(find.text('Following'))).pop();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byIcon(Icons.notes));
  await tester.tap(find.byIcon(Icons.notes));
  await tester.pumpAndSettle();
  expect(find.text('About this clip'), findsOneWidget);
  expect(find.text('Ask Foxy AI...'), findsOneWidget);
  await tester.scrollUntilVisible(find.text('Playback'), 100, scrollable: find.byType(Scrollable).last);
  await tester.tap(find.text('Playback'));
  await tester.pumpAndSettle();
  expect(find.text('Auto scroll'), findsOneWidget);
  Navigator.of(tester.element(find.text('Auto scroll'))).pop();
  await tester.pumpAndSettle();
  await tester.longPressAt(const Offset(160,250));
  await tester.pumpAndSettle();
  expect(find.text('View fullscreen'),findsOneWidget);
  expect(find.text('Auto scroll'),findsOneWidget);
  expect(find.text('Closed captions'),findsOneWidget);
  await tester.tap(find.byType(Switch));
  await tester.pumpAndSettle();
  expect(tester.widget<Switch>(find.byType(Switch)).value,isTrue);
  expect(tester.takeException(), isNull);
 });
}
