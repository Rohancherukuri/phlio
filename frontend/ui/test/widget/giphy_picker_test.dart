import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/shared/giphy/giphy_picker.dart';
void main() {
  testWidgets('GIPHY has only GIF and sticker tabs and explains missing configuration', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GiphyPicker())));
    await tester.pumpAndSettle();
    expect(find.text('GIFs'), findsOneWidget);
    expect(find.text('Stickers'), findsOneWidget);
    expect(find.text('GIPHY is not configured yet.'), findsOneWidget);
    await tester.tap(find.text('Stickers'));
    await tester.pumpAndSettle();
    expect(find.text('Search GIPHY stickers'), findsOneWidget);
    expect(find.text('Powered by GIPHY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
