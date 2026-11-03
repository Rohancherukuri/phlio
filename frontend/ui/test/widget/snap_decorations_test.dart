import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/profile/presentation/widgets/snap_decorations.dart';
import 'package:phlio/shared/moments/stickers/sticker_model.dart';

void main() {
  testWidgets('Captions tray fits narrow screens and includes all snap tools', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SnapCaptionsSheet())));
    for (final text in ['Captions', 'Aa Text', 'Now Playing', 'Location', 'GIF', 'Stickers']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('Snap caption can be moved and removed', (tester) async {
    final layers = [MomentSticker(StickerType.word, {'word': 'Hello', 'style': 'text'})];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (context, update) =>
      SizedBox(width: 320, height: 320, child: SnapDecorationCanvas(
        layers: layers, onChanged: () => update(() {}), child: const ColoredBox(color: Colors.blue),
      )),
    ))));
    await tester.drag(find.text('Hello'), const Offset(40, 30));
    await tester.pump();
    expect(layers.first.x, greaterThan(.5));
    await tester.tap(find.text('Hello'));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove decoration'));
    await tester.pump();
    expect(layers, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
