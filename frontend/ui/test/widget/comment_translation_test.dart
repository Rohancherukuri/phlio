import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/core/di/service_locator.dart';
import 'package:phlio/core/network/api_client.dart';
import 'package:phlio/shared/content/social_comments_sheet.dart';
import 'content_surface_test.dart' show FakeApi;
void main() {
 testWidgets('Translation displays English inline and toggles without another request', (tester) async {
  final api=FakeApi();var calls=0;
  api.dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h){calls++;expect(o.path, '/social/content/item/comments/comment/translate');expect(o.queryParameters['platform'],'shop');h.resolve(Response(requestOptions:o,data:{'text':'Hello','target_language':'en'}));}));
  getIt.registerSingleton<ApiClient>(api);addTearDown(()=>getIt.reset());
  await tester.pumpWidget(ProviderScope(overrides:[socialCommentsProvider.overrideWith((ref,id) async=>[{'id':'comment','text':'Bonjour','created_at':'2026-10-23','author':{'id':'friend','username':'friend','display_name':'Friend'}}])],child:const MaterialApp(home:Scaffold(body:SocialCommentsSheet(contentId:'shop/item')))));
  await tester.pumpAndSettle();await tester.tap(find.text('See translation'));await tester.pumpAndSettle();
  expect(find.text('Hello'),findsOneWidget);expect(find.text('See original'),findsOneWidget);
  await tester.tap(find.text('See original'));await tester.pumpAndSettle();expect(find.text('Hello'),findsNothing);
  await tester.tap(find.text('See translation'));await tester.pumpAndSettle();expect(calls,1);expect(tester.takeException(),isNull);
 });
}
