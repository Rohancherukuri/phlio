import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/pay/presentation/screens/payment_status_view.dart';
void main() {
  testWidgets('Payment animations reflect supplied status and fit narrow screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320,640));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    Future<void> show(String status) => tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: PaymentStatusView(status: status,amount:12345,preview:true)))));
    await show('processing');
    await tester.pump(const Duration(seconds:2));
    expect(find.text('Checking payment'),findsOneWidget);
    expect(find.text('Payment successful'),findsNothing);
    await show('success');
    await tester.pumpAndSettle();
    expect(find.text('Payment successful'),findsOneWidget);
    await show('failed');
    await tester.pumpAndSettle();
    expect(find.text('Payment failed'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
