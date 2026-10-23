import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/social/presentation/controllers/video_library.dart';
void main() {
 test('Preferences hide selected clips and promote similar titles and creators', () {
  final items = [
   const PlayableVideo(id:'1',title:'Cooking pasta',creator:'a',url:'',kind:'clip'),
   const PlayableVideo(id:'2',title:'Mountain hiking',creator:'b',url:'',kind:'clip'),
   const PlayableVideo(id:'3',title:'Mountain lake',creator:'c',url:'',kind:'clip'),
  ];
  final ranked = rankClips(items, [
   {'clip_id':'2','preference':'interested','title':'Mountain hiking','creator':'b'},
   {'clip_id':'1','preference':'not_interested'},
  ]);
  expect(ranked.map((v)=>v.id), ['2','3']);
 });
}
