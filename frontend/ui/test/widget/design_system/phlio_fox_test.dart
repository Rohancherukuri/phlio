// Design-system widget tests for the Foxy mascot widgets.

import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/design_system/widgets/phlio_fox.dart';

void main() {
  test('PhlioFoxPose assets point at real pose art paths', () {
    expect(PhlioFoxPose.happy.assetPath, 'assets/images/foxy/foxy_happy.png');
    expect(PhlioFoxPose.explorer.assetPath, 'assets/images/foxy/foxy_explorer.png');
    expect(PhlioFoxPose.journey.assetPath, 'assets/images/foxy/foxy_journey.png');
  });

  test('PhlioFoxLoop assets point at looping GIF paths', () {
    expect(PhlioFoxLoop.wave.assetPath, 'assets/animations/foxy_wave.gif');
    expect(PhlioFoxLoop.moods.assetPath, 'assets/animations/foxy_moods.gif');
  });

  test('sticker catalog is non-empty with unique ids', () {
    final ids = PhlioStickers.catalog.map((s) => s.id).toSet();
    expect(ids, isNotEmpty);
    expect(ids.length, PhlioStickers.catalog.length);
    expect(PhlioStickers.assetFor('happy'), 'assets/stickers/sticker_foxy_happy.png');
  });
}
