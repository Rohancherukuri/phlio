import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:phlio/features/profile/presentation/widgets/invite_friends.dart';
import 'social_chat_modes_test.dart' show TestAuth;
void main() {
 testWidgets('Profile QR contains the signed-in profile link and fits a small phone', (tester) async {
  await tester.binding.setSurfaceSize(const Size(320,640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(overrides: [authControllerProvider.overrideWith(TestAuth.new)], child: const MaterialApp(home: ProfileInviteQrScreen())));
  await tester.pumpAndSettle();
  expect(find.text('@arjun'), findsOneWidget);
  expect(profileInviteLink('arjun'), 'phlio://app/creator/arjun');
  await tester.scrollUntilVisible(find.text('Share invite'),100);
  expect(tester.takeException(), isNull);
 });
}

