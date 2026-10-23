import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:phlio/app/theme/app_theme.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:phlio/features/authentication/domain/entities/user_entity.dart';
import 'package:phlio/features/rooms/presentation/controllers/messaging_controller.dart';
import 'package:phlio/core/result/result.dart';
import 'package:phlio/features/rooms/domain/entities/room_entity.dart';
import 'package:phlio/features/rooms/domain/entities/room_message_entity.dart';
import 'package:phlio/features/rooms/domain/repositories/rooms_repository.dart';
import 'package:phlio/features/rooms/presentation/controllers/rooms_controller.dart';
import 'package:phlio/features/rooms/presentation/screens/rooms_screen.dart';
import 'package:phlio/features/rooms/presentation/widgets/chat_composer.dart';
import 'package:phlio/shared/models/paginated_response.dart';

class _Repository extends Mock implements RoomsRepository {}

class _SignedOut extends AuthController {
  @override
  Future<UserEntity?> build() async => null;
}

const _capture = bool.fromEnvironment('CAPTURE_ROOMS');
final _captureKey = GlobalKey();
Future<void> _screenshot(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary =
      _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/rooms-previews').createSync(recursive: true);
    File('build/rooms-previews/$name.png')
        .writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.record/messages'),
            (call) async => null);
    if (_capture) {
      final fonts = FontLoader('Manrope');
      for (final weight in ['regular', '500', '600', '700', '800']) {
        fonts.addFont(
            rootBundle.load('assets/fonts/manrope-v20-latin-$weight.ttf'));
      }
      await fonts.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final display = FontLoader('Quicksand');
      for (final weight in ['regular', '500', '600', '700']) {
        display.addFont(
            rootBundle.load('assets/fonts/quicksand-v37-latin-$weight.ttf'));
      }
      await display.load();
    }
  });
  final room = RoomEntity(
    id: 'local',
    name: 'Hitech City Locals',
    slug: 'hitech-city',
    description: 'Meetups, courts, and recommendations around Hitech City.',
    category: RoomCategory.localNearby,
    icon: '📍',
    isPrivate: false,
    memberCount: 158,
    createdAt: DateTime(2026),
  );

  for (final width in [320.0, 390.0, 600.0, 720.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Rooms fits $width at text scale $scale with keyboard',
          (tester) async {
        final repository = _Repository();
        when(() => repository.myRooms())
            .thenAnswer((_) async => Result.success([room]));
        when(() => repository.getMessages('local')).thenAnswer(
          (_) async => const Result.success(
            PaginatedResponse<RoomMessageEntity>(
              items: [],
              nextCursor: null,
              hasMore: false,
            ),
          ),
        );
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(ProviderScope(
          overrides: [
            roomsRepositoryProvider.overrideWithValue(repository),
            authControllerProvider.overrideWith(_SignedOut.new),
            dmConversationsProvider.overrideWith((ref) async => [
                  {
                    'peer': {
                      'id': 'arjun',
                      'full_name': 'Arjun Kumar',
                      'username': 'arjun'
                    },
                    'last_message': {
                      'text': 'Badminton this weekend?',
                      'created_at': '2026-10-05T10:00:00Z'
                    }
                  },
                  {
                    'peer': {
                      'id': 'neha',
                      'full_name': 'Neha Sharma',
                      'username': 'neha'
                    },
                    'last_message': {
                      'text': 'Just finished my new setup!',
                      'created_at': '2026-10-05T09:00:00Z'
                    }
                  },
                ]),
            discoverRoomsProvider.overrideWith((ref) async => [room]),
          ],
          child: RepaintBoundary(
              key: _captureKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.dark,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    viewInsets: EdgeInsets.only(bottom: _capture ? 0 : 280),
                  ),
                  child: child!,
                ),
                home: const RoomsScreen(),
              )),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        if (_capture && width == 390 && scale == 1)
          await _screenshot(tester, 'rooms-home');
        expect(find.byTooltip('Create room'), findsNothing);
        expect(find.byTooltip('Profile'), findsNothing);
        expect(find.text('My Rooms'), findsNothing);
        await tester.tap(find.byTooltip('Hitech City Locals'));
        await tester.pumpAndSettle();
        if (_capture && width == 390 && scale == 1)
          await _screenshot(tester, 'rooms-chat');
        expect(find.byType(ChatComposer), findsOneWidget);
        expect(tester.getSize(find.byType(ChatComposer)).width, width);
        expect(find.text('My Rooms'), findsNothing);
        if (width < 720) {
          await tester.tap(find.byTooltip('Browse rooms'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (_capture && width == 390 && scale == 1)
            await _screenshot(tester, 'rooms-drawer');
          await tester.tap(find.byTooltip('Hitech City Locals'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('rooms-scrim')), findsNothing);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
