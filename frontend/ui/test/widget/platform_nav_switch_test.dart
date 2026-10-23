import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/design_system/widgets/phlio_bottom_nav.dart';

void main() {
  testWidgets('Platform replaces Tray without moving other navigation icons', (tester) async {
    var opens = 0;
    Widget app({bool selected = false}) => MaterialApp(home: Scaffold(
      bottomNavigationBar: PhlioBottomNav(currentIndex: 0, onTap: (_) {},
        onTrayTap: () => opens++,
        trayIcon: selected ? Icons.storefront : Icons.grid_view_outlined,
        trayLabel: selected ? 'Shop' : 'Tray')));
    await tester.pumpWidget(app());
    final positions = [for (final label in ['Home','Explore','Profile']) tester.getCenter(find.text(label))];
    await tester.tap(find.text('Tray'));
    expect(opens, 1);
    await tester.pumpWidget(app(selected: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Shop'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Tray'), findsNothing);
    expect([for (final label in ['Home','Explore','Profile']) tester.getCenter(find.text(label))], positions);
    await tester.tap(find.text('Shop'));
    expect(opens, 2);
    expect(tester.takeException(), isNull);
  });
}
