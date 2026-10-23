import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/shared/content/moment_viewer.dart';
import 'package:phlio/shared/content/content_surface.dart';
import 'package:phlio/features/authentication/domain/entities/user_entity.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
class _Auth extends AuthController { @override Future<UserEntity?> build() async => null; }
void main() {
 testWidgets('Moment viewer only shows chosen author and excludes expired stories', (tester) async {
  Map story(String id,String author,String title,int hours)=>{'id':id,'author':{'id':author,'display_name':author},'expires_at':DateTime.now().add(Duration(hours:hours)).toIso8601String(),'content':{'title':title}};
  await tester.pumpWidget(ProviderScope(overrides:[
   authControllerProvider.overrideWith(_Auth.new),
   sharedStoriesProvider.overrideWith((ref) async=>[story('1','maya','Morning walk',1),story('2','sam','Other story',1),story('3','maya','Expired story',-1)]),
  ],child:const MaterialApp(home:MomentViewer(authorId:'maya'))));
  await tester.pumpAndSettle();
  expect(find.text('Morning walk'),findsOneWidget);
  expect(find.text('Other story'),findsNothing);
  expect(find.text('Expired story'),findsNothing);
  expect(find.text('1 / 1'),findsOneWidget);
  expect(tester.takeException(),isNull);
 });
}
