import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/authentication/domain/entities/user_entity.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:phlio/features/rooms/data/datasources/messaging_api.dart';
import 'package:phlio/features/rooms/presentation/controllers/messaging_controller.dart';
import 'package:phlio/features/rooms/presentation/widgets/chat_composer.dart';
import 'package:phlio/features/rooms/presentation/widgets/chat_policy.dart';
import 'package:phlio/features/rooms/presentation/widgets/dm_thread.dart';
import 'package:phlio/features/rooms/presentation/widgets/message_media_editor.dart';
import 'package:phlio/features/rooms/presentation/widgets/message_sticker_canvas.dart';
import 'package:phlio/features/social/presentation/widgets/creator_chat.dart';

class TestAuth extends AuthController {
  @override
  Future<UserEntity?> build() async => UserEntity(
        id: 'me',
        username: 'arjun',
        fullName: 'Arjun',
        email: '',
        bio: '',
        interests: const [],
        isVerified: false,
        createdAt: DateTime(2026),
      );
}

class ChatApi extends MessagingApi {
  ChatApi() : super(Dio());
  String? reaction;
  List<Map<String, dynamic>>? saved;
  @override
  Future<void> react(
    String peer,
    String messageId,
    String kind,
    String value,
  ) async {
    reaction = value;
  }

  @override
  Future<void> setOverlays(
    String peer,
    String id,
    List<Map<String, dynamic>> overlays,
  ) async {
    saved = overlays;
  }
}

void main() {
  test('DM media kinds and limits are checked at their boundaries', () {
    expect(dmMediaError('image.gif', dmImageLimit), isNull);
    expect(dmMediaError('image.png', dmImageLimit + 1), contains('8 MB'));
    expect(dmMediaError('clip.mp4', dmMediaLimit), isNull);
    expect(dmMediaError('note.m4a', dmMediaLimit + 1), contains('25 MB'));
    for (final name in ['document.pdf', 'archive.zip', 'notes.txt']) {
      expect(dmMediaError(name, 50), contains('Rooms'));
    }
  });
  for (final mode in ChatAudience.values) {
    testWidgets('Attachment menu enforces $mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showAttachmentTypeMenu(context, audience: mode),
                child: const Text('Attach'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Attach'));
      await tester.pumpAndSettle();
      expect(find.text('Sticker'), findsOneWidget);
      expect(find.text('GIF'), findsOneWidget);
      expect(
        find.text('Document'),
        mode == ChatAudience.rooms ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Image'),
        mode == ChatAudience.publicChat ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Public chat uses its own history and has no microphone',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creatorChatProvider('neha').overrideWith(
            (ref) => Stream.value([
              {
                'id': 'public',
                'username': 'arjun',
                'text': 'Public chat message',
                'attachments': [],
              }
            ]),
          ),
          dmHistoryProvider('neha').overrideWith(
            (ref) => throw StateError('Must not read private DMs'),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CreatorChat(username: 'neha')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Public chat message', findRichText: true),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 390.0, 800.0]) {
    testWidgets('DM reactions and sticker editing at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = ChatApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(TestAuth.new),
            messagingApiProvider.overrideWithValue(api),
            dmPeerProvider('neha').overrideWith(
                (ref) async => {'id': 'neha', 'full_name': 'Neha'}),
            dmHistoryProvider('neha').overrideWith(
              (ref) => Stream.value([
                {
                  'id': 'sent',
                  'sender_id': 'me',
                  'text': 'Decorate this message',
                  'attachments': [],
                  'created_at': '2026-10-01T00:00:00Z',
                  'overlays': [],
                }
              ]),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: DmThread(username: 'neha')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      await tester.longPress(find.text('Decorate this message'));
      await tester.pumpAndSettle();
      expect(find.text('Add or edit stickers'), findsOneWidget);
      await tester.tap(find.byTooltip('React ❤️'));
      await tester.pumpAndSettle();
      expect(api.reaction, '❤️');
      await tester.longPress(find.text('Decorate this message'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add or edit stickers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add sticker'));
      await tester.pumpAndSettle();
      expect(find.text('GIFs'), findsNothing);
      await tester.tap(find.text('Foxy'));
      await tester.pumpAndSettle();
      final sticker = find.descendant(
        of: find.byType(MessageStickerCanvas).last,
        matching: find.byType(Image),
      );
      final editable = tester
          .widget<MessageStickerCanvas>(find.byType(MessageStickerCanvas).last);
      expect(editable.onChanged, isNotNull);
      final drag = await tester.startGesture(tester.getCenter(sticker));
      await drag.moveBy(const Offset(25, 0));
      await tester.pump();
      await drag.moveBy(const Offset(50, 0));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.saved!.single['value'], 'sticker_foxy_happy');
      expect(api.saved!.single['x'], greaterThan(.5));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Image editor exports the cropped and filtered image',
      (tester) async {
    final source =
        File('assets/images/placeholders/social/thumb_gaming_1.png').absolute;
    StagedAttachment? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await Navigator.push<StagedAttachment>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MessageMediaEditor(
                      attachment: StagedAttachment(
                        kind: 'image',
                        name: 'photo.png',
                        path: source.path,
                        size: source.lengthSync(),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pump();
    for (var i = 0; i < 8 && find.text('Square crop').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Square crop'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Square crop'));
    await tester.tap(find.text('Black & white'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pump();
    for (var i = 0; i < 12 && saved == null; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.path, isNot(source.path));
    await tester.runAsync(() async {
      final codec = await ui
          .instantiateImageCodec(await File(saved!.path!).readAsBytes());
      final frame = await codec.getNextFrame();
      expect(frame.image.width, frame.image.height);
      final rgba = (await frame.image.toByteData())!.buffer.asUint8List();
      final center = ((frame.image.height ~/ 2) * frame.image.width +
              frame.image.width ~/ 2) *
          4;
      expect((rgba[center] - rgba[center + 1]).abs(), lessThanOrEqualTo(1));
      expect((rgba[center + 1] - rgba[center + 2]).abs(), lessThanOrEqualTo(1));
      frame.image.dispose();
      codec.dispose();
      await File(saved!.path!).delete();
    });
    expect(tester.takeException(), isNull);
  });
}
