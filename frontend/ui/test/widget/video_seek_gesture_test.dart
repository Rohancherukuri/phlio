import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/social/presentation/widgets/video_seek_gesture.dart';

void main() {
  testWidgets('Double taps seek on sides but not centre; disabled ignores taps', (tester) async {
    final seeks = <Duration>[];
    Future<void> mount(bool enabled) => tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SizedBox(width: 360, height: 220, child: VideoSeekGesture(
        enabled: enabled, onSeek: seeks.add, child: const ColoredBox(color: Colors.black))),
    )));
    Future<void> doubleTap(Offset point) async {
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(point);
      await tester.pump();
    }
    await mount(true);
    await doubleTap(const Offset(60, 110));
    expect(seeks, [const Duration(seconds: -10)]);
    expect(find.text('10 seconds'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('10 seconds'), findsNothing);
    await doubleTap(const Offset(300, 110));
    expect(seeks.last, const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 700));
    await doubleTap(const Offset(180, 110));
    expect(seeks.length, 2);
    await mount(false);
    await doubleTap(const Offset(60, 110));
    expect(seeks.length, 2);
    expect(tester.takeException(), isNull);
  });
}
