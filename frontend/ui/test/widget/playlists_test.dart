import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/shared/content/content_surface.dart';
import 'package:phlio/shared/content/playlists_screen.dart';

void main() {
  for (final platform in ['news', 'stream']) {
    testWidgets('$platform playlist shows only eligible bookmarks', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320,700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Map<String,dynamic> item(String id,String p) => {'object_id':id,'platform':p,'ref':id,'title':id};
      await tester.pumpWidget(ProviderScope(overrides:[
        playlistItemsProvider.overrideWith((ref,id) async => [item('Already added',platform)]),
        contentLibraryProvider.overrideWith((ref,verb) async => [item('Already added',platform),item('Add this',platform),item('Other platform',platform=='news'?'stream':'news')]),
      ],child:MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(2)),child:child!),
        home:PlaylistScreen(playlist:{'id':'playlist:test','name':'Weekend','platform':platform}))));
      await tester.pumpAndSettle();
      expect(find.text('Already added'),findsOneWidget);
      expect(find.text('Add this'),findsOneWidget);
      expect(find.text('Other platform'),findsNothing);
      expect(find.byTooltip('Add to playlist'),findsOneWidget);
      expect(find.byTooltip('Remove from playlist'),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  }
}
