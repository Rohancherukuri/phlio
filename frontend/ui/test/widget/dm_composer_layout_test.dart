import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/rooms/presentation/widgets/chat_composer.dart';
import 'package:phlio/features/rooms/presentation/widgets/chat_policy.dart';

void main() {
  testWidgets('Compact DM controls send text and open shared GIPHY picker',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String sent = '';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatComposer(
                    hint: 'Message',
                    compact: true,
                    audience: ChatAudience.directMessage,
                    onSendText: (value) => sent = value,
                    onSendFiles: (_, __) async {},
                    onSendVoice: (_, __) async {})))));
    expect(find.byTooltip('Camera'), findsOneWidget);
    expect(find.byTooltip('Photos'), findsOneWidget);
    expect(find.byTooltip('Voice message'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(sent, 'Hello');
    await tester.tap(find.byTooltip('GIFs and stickers'));
    await tester.pumpAndSettle();
    expect(find.text('GIFs'), findsOneWidget);
    expect(find.text('Stickers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
