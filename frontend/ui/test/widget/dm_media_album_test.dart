import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/rooms/presentation/widgets/dm_media_album.dart';

void main() {
  for (final count in [1, 2, 3, 4, 7]) {
    testWidgets('Album keeps $count attachments accessible on narrow screens', (tester) async {
      final heights = <double?>[];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: SizedBox(width: 240, child: DmMediaAlbum(
          attachments: List.generate(count, (i) => {'id': '$i', 'kind': i.isEven ? 'image' : 'video'}),
          tileBuilder: (data, height) {
            heights.add(height);
            return SizedBox(height: height ?? 260, child: Text('Media ${data['id']}'));
          },
        )),
      ))));
      await tester.pumpAndSettle();
      for (var i = 0; i < count; i++) {
        expect(find.text('Media $i'), findsOneWidget);
      }
      if (count > 1) expect(heights.whereType<double>().every((h) => h == 118.5), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
