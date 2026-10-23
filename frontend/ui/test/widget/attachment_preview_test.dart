import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/features/rooms/domain/entities/room_message_entity.dart';
import 'package:phlio/features/rooms/presentation/widgets/attachment_preview.dart';

void main() {
  test('large-file threshold and file kinds are classified correctly', () {
    expect(AttachmentPreviewPolicy.canPreview(1024 * 1024 * 1024), isFalse);
    expect(AttachmentPreviewPolicy.canPreview(17 * 1024), isTrue);
    expect(attachmentKindForName('photo.PNG'), 'image');
    expect(attachmentKindForName('movie.mp4'), 'video');
    expect(attachmentKindForName('voice.m4a'), 'audio');
    expect(attachmentKindForName('resume.docx'), 'document');
  });

  test('Office and text files produce readable document samples', () async {
    final dir = Directory.systemTemp.createTempSync('phlio_preview_test_');
    addTearDown(() => dir.delete(recursive: true));
    final archive = Archive()
      ..addFile(ArchiveFile.string('word/document.xml',
          '<w:document xmlns:w="urn:word"><w:p><w:t>Resume document preview</w:t></w:p></w:document>'));
    final doc = File('${dir.path}/resume.docx');
    await doc.writeAsBytes(ZipEncoder().encode(archive));
    expect(await documentSample(doc.path, 'resume.docx'),
        contains('Resume document preview'));
    final text = File('${dir.path}/notes.txt');
    await text.writeAsString('Readable notes');
    expect(await documentSample(text.path, 'notes.txt'), 'Readable notes');
  });

  testWidgets('document thumbnail opens a readable full-screen preview',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('phlio_document_test_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/notes.txt');
    file.writeAsStringSync('The contents of my document');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
      width: 240,
      child: AttachmentPreview(
          compact: true,
          attachment: MessageAttachmentEntity(
            id: 'notes',
            kind: 'document',
            name: 'notes.txt',
            size: 27,
            localPath: file.path,
          )),
    )))));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AttachmentPreview));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('The contents of my document'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large attachments never load bytes or initialize media',
      (tester) async {
    var loaded = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 280,
      child: AttachmentPreview(
          attachment: const MessageAttachmentEntity(
            id: 'huge',
            kind: 'video',
            name: 'large-video.mp4',
            size: 2 * 1024 * 1024 * 1024,
          ),
          loadPrivateFile: () async {
            loaded = true;
            return 'not-a-file';
          }),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Large file · preview disabled'), findsOneWidget);
    expect(find.text('2.0 GB'), findsOneWidget);
    expect(loaded, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'staged image shows a thumbnail without loading the whole file into state',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('phlio_image_test_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/image.png');
    file.writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 180,
      child: AttachmentPreview(
          compact: true,
          attachment: MessageAttachmentEntity(
            id: 'image',
            kind: 'image',
            name: 'image.png',
            size: 68,
            localPath: file.path,
          )),
    ))));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });
}
