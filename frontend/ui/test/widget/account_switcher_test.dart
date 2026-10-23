import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:phlio/app/shell/account_switcher.dart';
import 'package:phlio/core/di/service_locator.dart';
import 'package:phlio/core/storage/token_storage.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'social_chat_modes_test.dart' show TestAuth;

void main(){
  for(final fail in [false,true]){
    testWidgets('Account switch ${fail?'failure preserves original':'validates and activates saved session'}',(tester)async{
      FlutterSecureStorage.setMockInitialValues({});
      final storage=TokenStorage();
      await storage.saveTokens(const AuthTokens(accessToken:'other-access',refreshToken:'other-refresh'));
      await storage.rememberAccount(id:'other',username:'other_user');
      await storage.saveTokens(const AuthTokens(accessToken:'original-access',refreshToken:'original-refresh'));
      getIt.registerSingleton<TokenStorage>(storage);addTearDown(()=>getIt.reset());
      final api=Dio();api.interceptors.add(InterceptorsWrapper(onRequest:(options,handler){
        expect(options.headers['Authorization'],'Bearer other-access');
        if(fail){handler.reject(DioException(requestOptions:options,type:DioExceptionType.connectionError));return;}
        handler.resolve(Response(requestOptions:options,statusCode:200,data:{'id':'other','username':'other_user','full_name':'Other User','email':'other@example.com','created_at':'2026-01-01T00:00:00Z'}));
      }));
      final container=ProviderContainer(overrides:[authControllerProvider.overrideWith(TestAuth.new),accountSessionApiProvider.overrideWithValue(api)]);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      final router=GoRouter(initialLocation:'/profile',routes:[GoRoute(path:'/profile',builder:(context,state)=>Scaffold(body:TextButton(onPressed:()=>showAccountSwitcher(context),child:const Text('Choose account'))))]);
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container:container,child:MaterialApp.router(routerConfig:router)));
      await tester.tap(find.text('Choose account'));await tester.pumpAndSettle();
      expect(find.text('Add Phlio account'),findsOneWidget);
      await tester.tap(find.text('other_user'));await tester.pumpAndSettle();
      expect(await storage.accessToken,fail?'original-access':'other-access');
      expect(container.read(authControllerProvider).valueOrNull?.id,fail?'me':'other');
      if(fail)expect(find.textContaining('Could not switch accounts'),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  }
}
