import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/core/di/service_locator.dart';
import 'package:phlio/core/network/api_client.dart';
import 'package:phlio/features/profile/presentation/widgets/snap_audience.dart';
class FakeApi implements ApiClient {
 @override final Dio dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (o,h) => h.resolve(Response(requestOptions:o, data: {'followers': [{'id':'p','username':'maya','display_name':'Maya'}]}))));
 @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main() {
 testWidgets('Close Friends requires selecting a follower and returns their ID', (tester) async {
  getIt.registerSingleton<ApiClient>(FakeApi());
  addTearDown(() => getIt.unregister<ApiClient>());
  await tester.binding.setSurfaceSize(const Size(360,740));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SnapAudience? result;
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () async { result = await pickSnapAudience(c, const SnapAudience()); }, child: const Text('Open'))))));
  await tester.tap(find.text('Open')); await tester.pumpAndSettle();
  await tester.tap(find.text('Close Friends')); await tester.pumpAndSettle();
  expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  await tester.tap(find.text('Maya')); await tester.pumpAndSettle();
  await tester.tap(find.text('Done')); await tester.pumpAndSettle();
  expect(result?.mode, 'close_friends'); expect(result?.recipients, ['p']);
  expect(tester.takeException(), isNull);
 });
}
