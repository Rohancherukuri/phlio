import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/rooms/presentation/widgets/rooms_layout.dart';

void main() {
  Future<void> mount(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return RoomsLayout(
            sidebarWidth: sidebarWidth,
            onSidebarWidthChanged: (width) =>
                setState(() => sidebarWidth = width),
            sidebarBuilder: (close) => Column(children: [
              TextButton(onPressed: close, child: const Text('Select room')),
            ]),
            chatBuilder: (open) => Column(children: [
              if (open != null)
                IconButton(
                  tooltip: 'Browse rooms',
                  onPressed: open,
                  icon: const Icon(Icons.menu),
                ),
              const Expanded(child: Center(child: Text('Conversation'))),
              const TextField(key: ValueKey('composer')),
            ]),
          );
        }),
      ),
    ));
  }

  setUp(() => sidebarWidth = 260);

  for (final width in [320.0, 390.0, 600.0]) {
    testWidgets('mobile composer fills $width and panel selection closes it',
        (tester) async {
      await mount(tester, width);
      expect(
          tester.getSize(find.byKey(const ValueKey('composer'))).width, width);
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await tester.tap(find.byTooltip('Browse rooms'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rooms-scrim')), findsOneWidget);
      await tester.tap(find.text('Select room'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rooms-scrim')), findsNothing);
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('edge swipe opens, swipe and outside tap close', (tester) async {
    await mount(tester, 390);
    await tester.dragFrom(const Offset(8, 300), const Offset(270, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rooms-scrim')), findsOneWidget);
    await tester.dragFrom(const Offset(250, 300), const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rooms-scrim')), findsNothing);
    await tester.tap(find.byTooltip('Browse rooms'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(360, 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rooms-scrim')), findsNothing);
  });

  testWidgets('desktop resizing preserves room for chat', (tester) async {
    await mount(tester, 1000);
    expect(find.byTooltip('Browse rooms'), findsNothing);
    expect(find.text('Select room'), findsOneWidget);
    final composer = find.byKey(const ValueKey('composer'));
    expect(tester.getSize(composer).width, 706);
    await tester.drag(
        find.byKey(const ValueKey('rooms-divider')), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(composer).width, 626);
    await tester.binding.setSurfaceSize(const Size(720, 700));
    await tester.pumpAndSettle();
    expect(tester.getSize(composer).width, greaterThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back closes the room panel before leaving the conversation',
      (tester) async {
    await mount(tester, 390);
    await tester.tap(find.byTooltip('Browse rooms'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rooms-scrim')), findsNothing);
    expect(find.text('Conversation'), findsOneWidget);
  });
}

double sidebarWidth = 260;
