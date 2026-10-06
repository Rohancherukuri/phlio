import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:phlio/app/theme/app_theme.dart';
import 'package:phlio/core/result/result.dart';
import 'package:phlio/features/rooms/data/datasources/messaging_api.dart';
import 'package:phlio/features/rooms/domain/entities/room_entity.dart';
import 'package:phlio/features/rooms/domain/repositories/rooms_repository.dart';
import 'package:phlio/features/rooms/presentation/controllers/rooms_controller.dart';
import 'package:phlio/features/rooms/presentation/screens/rooms_explore_screen.dart';
import 'package:phlio/features/rooms/presentation/widgets/rooms_hub_panels.dart';

class _Api extends Mock implements MessagingApi {}

class _Repository extends Mock implements RoomsRepository {}

void main() {
  final room = RoomEntity(
      id: 'tech',
      name: 'Tech Hangout',
      slug: 'tech',
      description: 'Talk about your latest projects.',
      category: RoomCategory.techAndAi,
      icon: 'T',
      isPrivate: false,
      memberCount: 12,
      createdAt: DateTime(2026));
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
        'Search filters request matching content at $width with large text',
        (tester) async {
      final api = _Api();
      when(() => api.search(any(), any())).thenAnswer((_) async => []);
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
          overrides: [messagingApiProvider.overrideWithValue(api)],
          child: MaterialApp(
              theme: AppTheme.dark,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(2),
                      viewInsets: const EdgeInsets.only(bottom: 280)),
                  child: child!),
              home: const Scaffold(
                  resizeToAvoidBottomInset: false, body: RoomsSearchPanel()))));
      await tester.pumpAndSettle();
      verify(() => api.search('', 'recent')).called(1);
      await tester.enterText(find.byType(TextField), 'report');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      verify(() => api.search('report', 'recent')).called(1);
      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();
      verify(() => api.search('report', 'people')).called(1);
      expect(tester.takeException(), isNull);
    });
    testWidgets('Explore joins rooms and shows communities at $width',
        (tester) async {
      final repository = _Repository();
      bool joined = false;
      when(() => repository.joinRoom('tech')).thenAnswer((_) async {
        joined = true;
        return Result.success(room);
      });
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
          overrides: [
            roomsRepositoryProvider.overrideWithValue(repository),
            roomsDirectoryProvider.overrideWith((ref) async => [room]),
            myRoomsProvider.overrideWith((ref) async => joined ? [room] : [])
          ],
          child: MaterialApp(
              theme: AppTheme.dark,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!),
              home: const RoomsExploreScreen())));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Join'), 200,
          scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      verify(() => repository.joinRoom('tech')).called(1);
      expect(find.text('Open room'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Communities'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Communities'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tech & AI'));
      await tester.pumpAndSettle();
      expect(find.text('Tech Hangout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Add Friends sends request and incoming request can be accepted',
      (tester) async {
    final api = _Api();
    var accepted = false;
    when(() => api.friends()).thenAnswer((_) async => [
          {
            'peer': {
              'id': 'neha',
              'username': 'neha',
              'full_name': 'Neha Sharma'
            },
            'status': accepted ? 'accepted' : 'pending',
            'incoming': true
          }
        ]);
    when(() => api.addFriend('arjun')).thenAnswer((_) async {});
    when(() => api.friendAction('neha', 'accept')).thenAnswer((_) async {
      accepted = true;
    });
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
        overrides: [messagingApiProvider.overrideWithValue(api)],
        child: MaterialApp(
            theme: AppTheme.dark,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: const Scaffold(body: RoomsFriendsPanel()))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'arjun');
    await tester.tap(find.text('Send friend request'));
    await tester.pumpAndSettle();
    verify(() => api.addFriend('arjun')).called(1);
    await tester.scrollUntilVisible(find.text('Accept'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    verify(() => api.friendAction('neha', 'accept')).called(1);
    expect(find.text('Friends'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
