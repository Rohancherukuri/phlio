// Widget test for `PhlioPrimaryButton` — the one button every form/CTA in
// the app uses (see design_system/widgets/phlio_button.dart). Covers the
// three states that matter: normal tap, loading (tap disabled), and
// disabled (`onPressed: null`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/design_system/widgets/phlio_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('renders its label', (tester) async {
    await tester.pumpWidget(wrap(PhlioPrimaryButton(label: 'Continue', onPressed: () {})));
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('calls onPressed when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(PhlioPrimaryButton(label: 'Continue', onPressed: () => tapped = true)),
    );

    await tester.tap(find.byType(PhlioPrimaryButton));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('does not call onPressed while isLoading is true', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(
        PhlioPrimaryButton(label: 'Continue', isLoading: true, onPressed: () => tapped = true),
      ),
    );

    // The label is replaced by a spinner while loading.
    expect(find.text('Continue'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byType(PhlioPrimaryButton));
    await tester.pump();

    expect(tapped, isFalse);
  });

  testWidgets('renders as visibly disabled when onPressed is null', (tester) async {
    await tester.pumpWidget(wrap(const PhlioPrimaryButton(label: 'Continue', onPressed: null)));

    // `Opacity` is the outermost wrapper used to visually dim a disabled
    // button — see PhlioPrimaryButton.build.
    final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
    expect(opacity.opacity, lessThan(1.0));
  });
}
