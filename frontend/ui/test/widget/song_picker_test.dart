import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/app/theme/app_theme.dart';
import 'package:phlio/shared/music/song_picker.dart';

void main() {
  testWidgets('Music sheet searches, saves and selects the actual track', (tester) async {
    final dio = Dio();
    final requests = <RequestOptions>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(request);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data:
        request.path.endsWith('/status') ? {'connected':true,'configured':true} :
        request.path.endsWith('/saved') ? {} : {'items':[
          {'id':'aaaaaaaaaaaaaaaaaaaaaa','title':'A song with a long title that must fit',
            'artist':'Artist one, Artist two','duration_ms':181000,'saved':false,
            'url':'https://open.spotify.com/track/aaaaaaaaaaaaaaaaaaaaaa'}
        ], 'has_more':false}));
    }));
    await tester.binding.setSurfaceSize(const Size(360,800));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    Map? chosen;
    await tester.pumpWidget(ProviderScope(overrides:[musicApiProvider.overrideWithValue(dio)],
      child:MaterialApp(theme:AppTheme.dark,home:Builder(builder:(context)=>Scaffold(body:TextButton(
        onPressed:()async{chosen=await showSongPicker(context);},child:const Text('Choose')))))));
    await tester.tap(find.text('Choose'));await tester.pumpAndSettle();
    expect(find.text('For you'), findsOneWidget);
    expect(find.textContaining('3:01'), findsOneWidget);
    await tester.enterText(find.byType(TextField),'Artist');
    await tester.pump(const Duration(milliseconds:400));await tester.pumpAndSettle();
    expect(requests.last.queryParameters['q'],'Artist');
    await tester.tap(find.byTooltip('Save song'));await tester.pumpAndSettle();
    expect(find.byTooltip('Unsave song'), findsOneWidget);
    await tester.tap(find.text('A song with a long title that must fit'));await tester.pumpAndSettle();
    expect(chosen?['id'],'aaaaaaaaaaaaaaaaaaaaaa');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Disconnected users get connection UI, not fabricated tracks', (tester) async {
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler)=>handler.resolve(
      Response(requestOptions:request,statusCode:200,data:{'connected':false,'configured':true}))));
    await tester.binding.setSurfaceSize(const Size(320,700));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(overrides:[musicApiProvider.overrideWithValue(dio)],child:
      MaterialApp(theme:AppTheme.dark,home:const Scaffold(body:SongPicker()))));
    await tester.pumpAndSettle();
    expect(find.text('Connect Spotify'),findsOneWidget);
    expect(find.byType(ListTile),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
