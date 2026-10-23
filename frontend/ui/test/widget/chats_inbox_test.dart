import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:phlio/features/rooms/presentation/controllers/messaging_controller.dart';
import 'package:phlio/features/rooms/presentation/screens/chats_inbox_screen.dart';
import 'package:phlio/app/shell/settings_screen.dart';
import 'social_chat_modes_test.dart' show TestAuth;

void main(){
  for(final scale in [1.0,2.0]){
    testWidgets('Inbox search and folders at text scale $scale',(tester)async{
      await tester.binding.setSurfaceSize(const Size(320,700));
      addTearDown(()=>tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(overrides:[authControllerProvider.overrideWith(TestAuth.new),dmConversationsProvider.overrideWith((ref)async=>[
        {'peer':{'id':'a','username':'neha','full_name':'Neha'},'folder':'primary','unread_count':1,'last_message':{'text':'Design plans'}},
        {'peer':{'id':'b','username':'sam','full_name':'Sam'},'folder':'general','unread_count':0,'last_message':{'text':'Weekend trip'}},
      ])],child:MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:child!),home:const ChatsInboxScreen())));
      await tester.pumpAndSettle();
      expect(find.text('Design plans'),findsOneWidget);
      expect(find.text('Weekend trip'),findsNothing);
      await tester.enterText(find.byType(TextField),'not found');await tester.pumpAndSettle();
      expect(find.text('No matching conversations'),findsOneWidget);
      await tester.enterText(find.byType(TextField),'');
      await tester.ensureVisible(find.text('General'));await tester.tap(find.text('General'));await tester.pumpAndSettle();
      expect(find.text('Weekend trip'),findsOneWidget);
      expect(find.text('Design plans'),findsNothing);
      expect(tester.takeException(),isNull);
    });
  }
  testWidgets('Settings search exposes real destinations and logout',(tester)async{
    await tester.pumpWidget(ProviderScope(overrides:[authControllerProvider.overrideWith(TestAuth.new)],child:const MaterialApp(home:SettingsScreen())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'log out');await tester.pumpAndSettle();
    expect(find.text('Log out'),findsOneWidget);
    await tester.enterText(find.byType(TextField),'privacy');await tester.pumpAndSettle();
    expect(find.text('Activity privacy'),findsOneWidget);
    expect(find.text('Log out'),findsNothing);
  });
}
