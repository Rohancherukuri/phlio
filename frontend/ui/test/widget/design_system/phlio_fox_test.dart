// Design-system widget tests for the Foxy mascot widgets.

import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/design_system/widgets/foxy_puppet.dart';
import 'package:phlio/design_system/widgets/phlio_fox.dart';

void main() {
  test('PhlioFoxPose assets point at real pose art paths', () {
    expect(PhlioFoxPose.happy.assetPath, 'assets/images/foxy/foxy_happy.png');
    expect(PhlioFoxPose.explorer.assetPath, 'assets/images/foxy/foxy_explorer.png');
    expect(PhlioFoxPose.journey.assetPath, 'assets/images/foxy/foxy_journey.png');
  });

  // Loops are no longer GIFs: they play live on the rigged Foxy puppet,
  // so each loop maps to a puppet act.
  test('PhlioFoxLoop loops play on the rigged puppet', () {
    expect(PhlioFoxLoop.wave.act, FoxyAct.wave);
    expect(PhlioFoxLoop.think.act, FoxyAct.think);
    expect(PhlioFoxLoop.sleep.act, FoxyAct.sleep);
    expect(PhlioFoxLoop.celebrate.act, FoxyAct.cheer);
    expect(PhlioFoxLoop.explore.act, FoxyAct.ready);
    expect(PhlioFoxLoop.moods.act, FoxyAct.love);
  });

  test('sticker catalog is non-empty with unique ids', () {
    final ids = PhlioStickers.catalog.map((s) => s.id).toSet();
    expect(ids, isNotEmpty);
    expect(ids.length, PhlioStickers.catalog.length);
    expect(PhlioStickers.assetFor('happy'), 'assets/stickers/sticker_foxy_happy.png');
  });
}
