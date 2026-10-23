import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:phlio/features/profile/presentation/widgets/profile_connections.dart';
import 'social_chat_modes_test.dart' show TestAuth;
void main() {
  testWidgets('Connections searches usernames and switches tabs', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      authControllerProvider.overrideWith(TestAuth.new),
      profileConnectionsProvider.overrideWith((ref) async => {
        'followers': [{'id':'a','username':'maya.test','display_name':'Maya'}],
        'following': [{'id':'b','username':'kabir.test','display_name':'Kabir'}],
      }),
    ], child: const MaterialApp(home: ProfileConnectionsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('maya.test'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '@MAYA');
    await tester.pumpAndSettle();
    expect(find.text('maya.test'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No matching usernames'), findsWidgets);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('1 following'));
    await tester.pumpAndSettle();
    expect(find.text('kabir.test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
