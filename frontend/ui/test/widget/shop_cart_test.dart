import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/shop/presentation/controllers/cart_controller.dart';
import 'package:phlio/features/shop/presentation/screens/cart_sheet.dart';
import 'package:phlio/design_system/widgets/phlio_bottom_nav.dart';

class TestCart extends CartController {
  int quantity = 2;
  Map<String, dynamic> value() => {
    'items': quantity == 0 ? [] : [{'quantity': quantity, 'product': {
      'id': 'retailer-product', 'seller_id': 'retailer', 'title': 'Real product with a long name',
      'description': '', 'category': 'fashion', 'price_minor_units': 2499, 'currency': 'USD',
      'image_urls': <String>[], 'created_at': '2026-10-13T00:00:00Z',
    }}], 'totals': quantity == 0 ? {} : {'USD': 2499*quantity}, 'count': quantity,
  };
  @override
  Future<Map<String, dynamic>> build() async => value();
  @override
  Future<void> setQuantity(String id, int amount) async {
    quantity = amount; state = AsyncData(value());
  }
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('Cart changes quantity and removes items at scale $scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(overrides: [cartProvider.overrideWith(TestCart.new)],
        child: MaterialApp(builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: const Scaffold(body: CartSheet()))));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Increase quantity')); await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove item')); await tester.pumpAndSettle();
      expect(find.text('Your cart is empty'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Cart navigation action has an accessible label and count', (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(bottomNavigationBar: PhlioBottomNav(
      currentIndex: 0, onTap: (_) {}, createLabel: 'Cart', createCount: 3,
      createIcon: Icons.shopping_cart_outlined, onCreateTap: () => opened = true))));
    await tester.tap(find.byTooltip('Cart')); await tester.pump();
    expect(opened, isTrue); expect(find.text('3'), findsOneWidget);
  });
}
