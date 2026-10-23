import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:phlio/features/profile/presentation/controllers/avatar_controller.dart';
import 'package:phlio/shared/content/content_surface.dart';
import 'social_chat_modes_test.dart' show TestAuth;
void main() {
 testWidgets('Compact likes show follower avatars rather than unrelated likers', (tester) async {
  final follower = {'id':'follower','display_name':'Maya'};
  final stranger = {'id':'stranger','display_name':'Other'};
  await tester.pumpWidget(ProviderScope(overrides: [
   authControllerProvider.overrideWith(TestAuth.new),
   engagementProvider.overrideWith((ref,path) async => {'count':2,'avatars':[stranger],'follower_avatars':[follower],'people':[follower,stranger]}),
  ], child: const MaterialApp(home: Scaffold(body: SizedBox(width:145, child: EngagementRow(path:'stream/track',compact:true))))));
  await tester.pumpAndSettle();
  final previews = tester.widgetList<ContentAuthorAvatar>(find.byType(ContentAuthorAvatar)).map((w)=>w.author);
  expect(previews, ['follower']);
  expect(find.byTooltip('Like content'), findsOneWidget);
  expect(tester.takeException(), isNull);
 });
}
