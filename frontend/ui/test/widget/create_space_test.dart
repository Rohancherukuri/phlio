import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/shared/realtime/create_space_screen.dart';
import 'package:phlio/app/theme/app_theme.dart';
void main(){
  testWidgets('Space title enables start and topics can be selected',(tester)async{
    await tester.binding.setSurfaceSize(const Size(360,740));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(child:MaterialApp(theme:AppTheme.dark,home:const CreateSpaceScreen())));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
    await tester.enterText(find.byType(TextField),'Music tonight');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNotNull);
    await tester.tap(find.text('Add Topics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Music'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Music'),findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged,isNull);
    expect(tester.takeException(),isNull);
  });
}
