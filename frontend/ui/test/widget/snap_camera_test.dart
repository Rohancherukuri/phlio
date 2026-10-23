import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/profile/presentation/widgets/snap_camera_screen.dart';
class NoCamera extends CameraPlatform {
 @override Future<List<CameraDescription>> availableCameras() async => [];
}
void main() {
 testWidgets('Snap camera gracefully handles unavailable hardware on a small screen', (tester) async {
  final original = CameraPlatform.instance;
  CameraPlatform.instance = NoCamera();
  addTearDown(() => CameraPlatform.instance = original);
  await tester.binding.setSurfaceSize(const Size(320, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: SnapCameraScreen()));
  await tester.pumpAndSettle();
  expect(find.text('New snap'), findsOneWidget);
  expect(find.text('Retry camera'), findsOneWidget);
  expect(find.byTooltip('Flip camera'), findsOneWidget);
  expect(find.byTooltip('Enable flash'), findsOneWidget);
  expect(find.byTooltip('Your memories'), findsOneWidget);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
 });
}
