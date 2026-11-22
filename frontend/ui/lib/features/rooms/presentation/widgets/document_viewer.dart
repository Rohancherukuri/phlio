// Documents in chats, Discord-style: a file card with the type's colour and
// icon, the name and size, and an inline preview underneath (the first PDF
// page, or the start of a text / code / Word / Excel / PowerPoint file).
// Tap it and the document opens full screen in [DocumentViewerScreen]:
//
//   PDF        every page, pinch-zoom, "Page 3 of 12"
//   text/code  the whole file in monospace with line numbers
//   Word       paragraphs
//   Excel      the first sheet as a scrollable table
//   PowerPoint each slide's text, slide by slide
//
// Other formats (zip, apk…) show the card only, with Open externally.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart';

import '../../../../design_system/colors.dart';

const _textExt = {'txt', 'md', 'csv', 'log', 'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'env', 'rtf'};
const _codeExt = {
  'dart', 'py', 'js', 'ts', 'tsx', 'jsx', 'java', 'kt', 'swift', 'c', 'h', 'cpp', 'cc', 'cs', 'go', 'rs', 'rb',
  'php', 'html', 'css', 'scss', 'sh', 'ps1', 'bat', 'sql', 'gradle', 'kts', 'lua', 'r'
};

String docExt(String name) => name.contains('.') ? name.split('.').last.toLowerCase() : '';

/// Label, colour and icon for a file type.
({String label, Color color, IconData icon}) docType(String name) {
  final ext = docExt(name);
  return switch (ext) {
    'pdf' => (label: 'PDF', color: const Color(0xFFE5484D), icon: Icons.picture_as_pdf_rounded),
    'doc' || 'docx' || 'odt' || 'rtf' => (label: 'Word', color: const Color(0xFF4C8DFF), icon: Icons.description_rounded),
    'xls' || 'xlsx' || 'csv' || 'ods' => (label: 'Sheet', color: const Color(0xFF30A46C), icon: Icons.table_chart_rounded),
    'ppt' || 'pptx' || 'odp' => (label: 'Slides', color: const Color(0xFFF76B15), icon: Icons.slideshow_rounded),
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => (label: 'Archive', color: const Color(0xFFFFB224), icon: Icons.folder_zip_rounded),
    'apk' || 'exe' || 'msi' || 'dmg' => (label: 'App', color: const Color(0xFF8E8C99), icon: Icons.apps_rounded),
    _ when _codeExt.contains(ext) => (label: ext.toUpperCase(), color: const Color(0xFF8D78FF), icon: Icons.code_rounded),
    _ when _textExt.contains(ext) => (label: ext.toUpperCase(), color: const Color(0xFF9BA1AE), icon: Icons.article_rounded),
    _ => (label: ext.isEmpty ? 'File' : ext.toUpperCase(), color: const Color(0xFF9BA1AE), icon: Icons.insert_drive_file_rounded),
  };
}

/// Whether Phlio can show this file itself.
bool docViewable(String name) {
  final ext = docExt(name);
  return ext == 'pdf' || _textExt.contains(ext) || _codeExt.contains(ext) || {'docx', 'xlsx', 'pptx'}.contains(ext);
}

bool docIsCode(String name) => _codeExt.contains(docExt(name)) || {'json', 'xml', 'yaml', 'yml', 'toml', 'ini'}.contains(docExt(name));

/// What the viewer shows for non-PDF files.
sealed class DocContent {}

class DocText extends DocContent {
  DocText(this.text, {this.truncated = false});
  final String text;
  final bool truncated;
}

class DocTable extends DocContent {
  DocTable(this.rows);
  final List<List<String>> rows;
}

class DocSlides extends DocContent {
  DocSlides(this.slides);
  final List<String> slides;
}

Future<DocContent> readDocument(String path, String name) => compute(_read, (path, name));

DocContent _read((String, String) input) {
  final (path, name) = input;
  final ext = docExt(name);
  final file = File(path);
  if (_textExt.contains(ext) || _codeExt.contains(ext)) {
    const cap = 2 * 1024 * 1024;
    final raf = file.openSync();
    try {
      final bytes = raf.readSync(cap);
      return DocText(utf8.decode(bytes, allowMalformed: true), truncated: file.lengthSync() > cap);
    } finally {
      raf.closeSync();
    }
  }
  if (file.lengthSync() > 64 * 1024 * 1024) return DocText('This file is too big to show here.');
  final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
  ArchiveFile? entry(String n) => archive.files.where((f) => f.name == n).firstOrNull;
  String xmlOf(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);

  if (ext == 'docx') {
    final doc = entry('word/document.xml');
    if (doc == null) return DocText('');
    final xml = XmlDocument.parse(xmlOf(doc));
    final paragraphs = [
      for (final p in xml.descendants.whereType<XmlElement>().where((e) => e.name.local == 'p'))
        p.descendants.whereType<XmlElement>().where((e) => e.name.local == 't').map((e) => e.innerText).join(),
    ];
    return DocText(paragraphs.join('\n'));
  }
  if (ext == 'xlsx') {
    final shared = <String>[];
    final strings = entry('xl/sharedStrings.xml');
    if (strings != null) {
      for (final si in XmlDocument.parse(xmlOf(strings)).descendants.whereType<XmlElement>().where((e) => e.name.local == 'si')) {
        shared.add(si.descendants.whereType<XmlElement>().where((e) => e.name.local == 't').map((e) => e.innerText).join());
      }
    }
    final sheet = entry('xl/worksheets/sheet1.xml');
    if (sheet == null) return DocTable(const []);
    final rows = <List<String>>[];
    for (final row in XmlDocument.parse(xmlOf(sheet)).descendants.whereType<XmlElement>().where((e) => e.name.local == 'row')) {
      final cells = <String>[];
      for (final c in row.childElements.where((e) => e.name.local == 'c')) {
        // Column letters → index, so empty cells keep their place.
        final ref = c.getAttribute('r') ?? '';
        final letters = ref.replaceAll(RegExp(r'[0-9]'), '');
        var col = 0;
        for (final ch in letters.codeUnits) {
          col = col * 26 + (ch - 64);
        }
        while (cells.length < col - 1) {
          cells.add('');
        }
        final v = c.childElements.where((e) => e.name.local == 'v').firstOrNull?.innerText ??
            c.descendants.whereType<XmlElement>().where((e) => e.name.local == 't').map((e) => e.innerText).join();
        cells.add(c.getAttribute('t') == 's' ? (shared.elementAtOrNull(int.tryParse(v) ?? -1) ?? v) : v);
      }
      rows.add(cells);
      if (rows.length >= 500) break;
    }
    return DocTable(rows);
  }
  if (ext == 'pptx') {
    final slides = archive.files.where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name)).toList()
      ..sort((a, b) => int.parse(RegExp(r'\d+').firstMatch(a.name.split('/').last)!.group(0)!)
          .compareTo(int.parse(RegExp(r'\d+').firstMatch(b.name.split('/').last)!.group(0)!)));
    return DocSlides([
      for (final s in slides)
        [
          for (final p in XmlDocument.parse(xmlOf(s)).descendants.whereType<XmlElement>().where((e) => e.name.local == 'p'))
            p.descendants.whereType<XmlElement>().where((e) => e.name.local == 't').map((e) => e.innerText).join(),
        ].where((line) => line.trim().isNotEmpty).join('\n'),
    ]);
  }
  return DocText('');
}

// -- full view ------------------------------------------------------------------------------------------

class DocumentViewerScreen extends StatefulWidget {
  const DocumentViewerScreen({required this.path, required this.name, this.sizeLabel = '', super.key});
  final String path, name, sizeLabel;
  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  late final bool _pdf = docExt(widget.name) == 'pdf';
  late final Future<DocContent>? _content = _pdf ? null : readDocument(widget.path, widget.name);
  final _pdfController = PdfViewerController();
  int _page = 1, _pages = 0;

  @override
  Widget build(BuildContext context) {
    final type = docType(widget.name);
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D12),
        leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        titleSpacing: 0,
        title: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: type.color.withValues(alpha: .18), borderRadius: BorderRadius.circular(8)),
            child: Icon(type.icon, color: type.color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Text(
                [type.label, if (widget.sizeLabel.isNotEmpty) widget.sizeLabel, if (_pdf && _pages > 0) 'Page $_page of $_pages']
                    .join(' · '),
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
            ]),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: 'Share / open with…',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(widget.path, name: widget.name)])),
          ),
        ],
      ),
      body: _pdf
          ? PdfViewer.file(
              widget.path,
              controller: _pdfController,
              params: PdfViewerParams(
                backgroundColor: const Color(0xFF0B0D12),
                onViewerReady: (document, controller) => setState(() => _pages = document.pages.length),
                onPageChanged: (page) {
                  if (page != null) setState(() => _page = page);
                },
              ),
            )
          : FutureBuilder<DocContent>(
              future: _content,
              builder: (context, snap) {
                if (snap.hasError) return const Center(child: Text('Could not read this document.'));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                return switch (snap.data!) {
                  DocText(:final text, :final truncated) => text.trim().isEmpty
                      ? const Center(child: Text('This document has no text to show.'))
                      : _TextView(text: text, code: docIsCode(widget.name), truncated: truncated),
                  DocTable(:final rows) => _TableView(rows: rows),
                  DocSlides(:final slides) => ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: slides.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (_, i) => AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1E27),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Slide ${i + 1}', style: const TextStyle(color: Color(0xFFF76B15), fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                child: SelectableText(slides[i].isEmpty ? '(no text)' : slides[i],
                                    style: const TextStyle(fontSize: 15, height: 1.4)),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                };
              },
            ),
    );
  }
}

class _TextView extends StatelessWidget {
  const _TextView({required this.text, required this.code, required this.truncated});
  final String text;
  final bool code, truncated;
  @override
  Widget build(BuildContext context) {
    if (!code) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: SelectableText(text + (truncated ? '\n\n… (showing the first 2 MB)' : ''),
            style: const TextStyle(fontSize: 15.5, height: 1.55)),
      );
    }
    final lines = text.split('\n');
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5);
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 40),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text([for (var i = 1; i <= lines.length; i++) '$i'].join('\n'),
                  textAlign: TextAlign.right, style: mono.copyWith(color: Colors.white30)),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: SelectableText(text, style: mono.copyWith(color: const Color(0xFFE3E5EA))),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TableView extends StatelessWidget {
  const _TableView({required this.rows});
  final List<List<String>> rows;
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Center(child: Text('This sheet is empty.'));
    final cols = rows.fold<int>(0, (a, r) => r.length > a ? r.length : a);
    return InteractiveViewer(
      constrained: false,
      minScale: .5,
      maxScale: 3,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: Colors.white12),
          children: [
            for (final (i, r) in rows.indexed)
              TableRow(
                decoration: BoxDecoration(color: i == 0 ? const Color(0xFF1C2A22) : null),
                children: [
                  for (var c = 0; c < cols; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(c < r.length ? r[c] : '',
                            style: TextStyle(fontSize: 13, fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w400)),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Discord's file card: type tile, blue name, size, and an open button.
class DocFileHeader extends StatelessWidget {
  const DocFileHeader({required this.name, required this.sizeLabel, this.onOpen, super.key});
  final String name, sizeLabel;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) {
    final type = docType(name);
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
        child: Row(children: [
          Container(
            width: 40,
            height: 48,
            decoration: BoxDecoration(color: type.color.withValues(alpha: .16), borderRadius: BorderRadius.circular(8)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(type.icon, color: type.color, size: 22),
              Text(type.label.length > 5 ? type.label.substring(0, 4) : type.label,
                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: type.color)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF6FB3FF), fontWeight: FontWeight.w600, height: 1.25)),
              const SizedBox(height: 2),
              Text(sizeLabel, style: const TextStyle(fontSize: 11.5, color: PhlioColors.textSecondary)),
            ]),
          ),
          if (onOpen != null)
            IconButton(
              tooltip: 'Open',
              icon: const Icon(Icons.open_in_full_rounded, size: 20, color: PhlioColors.textSecondary),
              onPressed: () {
                HapticFeedback.selectionClick();
                onOpen!();
              },
            ),
        ]),
      ),
    );
  }
}
