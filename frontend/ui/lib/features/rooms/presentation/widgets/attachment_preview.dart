import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_player/video_player.dart';
import 'package:xml/xml.dart';

import '../../../../app/config/app_config.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/widgets/foxy_pack.dart';
import '../../domain/entities/room_message_entity.dart';

/// Preview budgets keep multi-GB uploads out of decoders and memory.
abstract final class AttachmentPreviewPolicy {
  static const largeFileBytes = 1024 * 1024 * 1024;
  static const autoLoadBytes = 20 * 1024 * 1024;
  static const documentReadBytes = 16 * 1024 * 1024;
  static bool canPreview(int bytes) => bytes < largeFileBytes;
  static bool canAutoLoad(int bytes) => bytes > 0 && bytes <= autoLoadBytes;
}

String attachmentSize(int bytes) {
  if (bytes <= 0) return 'File';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < AttachmentPreviewPolicy.largeFileBytes)
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / AttachmentPreviewPolicy.largeFileBytes).toStringAsFixed(1)} GB';
}

String attachmentKindForName(String name) {
  final extension = name.split('.').last.toLowerCase();
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(extension))
    return 'image';
  if (['mp4', 'mov', 'mkv', 'webm', 'avi'].contains(extension)) return 'video';
  if (['mp3', 'wav', 'ogg', 'm4a', 'flac'].contains(extension)) return 'audio';
  return 'document';
}

/// Extracts a bounded text sample off the UI thread, without unpacking files to disk.
Future<String> documentSample(String path, String name) =>
    compute(_readSample, (path, name));

String _readSample((String, String) input) {
  final file = File(input.$1);
  if (file.lengthSync() > AttachmentPreviewPolicy.documentReadBytes) return '';
  return _extractSample((file.readAsBytesSync(), input.$2));
}

String _extractSample((List<int>, String) input) {
  final (bytes, name) = input;
  final ext = name.split('.').last.toLowerCase();
  if (['txt', 'md', 'json', 'csv', 'xml', 'yaml', 'log'].contains(ext)) {
    return utf8.decode(bytes.take(12000).toList(), allowMalformed: true);
  }
  if (!['docx', 'xlsx', 'pptx'].contains(ext)) return '';
  final archive = ZipDecoder().decodeBytes(bytes);
  final samples = <String>[];
  var total = 0;
  for (final entry in archive) {
    final selected = entry.name == 'word/document.xml' ||
        entry.name == 'xl/sharedStrings.xml' ||
        entry.name == 'xl/worksheets/sheet1.xml' ||
        entry.name == 'ppt/slides/slide1.xml';
    if (!selected || entry.size > 4 * 1024 * 1024 || total > 12000) continue;
    final document =
        XmlDocument.parse(utf8.decode(entry.content, allowMalformed: true));
    final values = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 't' || e.name.local == 'v')
        .map((e) => e.innerText)
        .take(200);
    final text = values.join(' ');
    total += text.length;
    samples.add(text);
  }
  return samples
      .join('\n')
      .substring(0, samples.join('\n').length.clamp(0, 12000));
}

class AttachmentPreview extends StatefulWidget {
  const AttachmentPreview(
      {required this.attachment,
      this.compact = false,
      this.loadPrivateFile,
      super.key});
  final MessageAttachmentEntity attachment;
  final bool compact;
  final Future<String> Function()? loadPrivateFile;
  @override
  State<AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends State<AttachmentPreview> {
  String? _path;
  bool _loading = false;
  bool _unavailable = false;
  Future<String>? _sample;
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _path = widget.attachment.localPath;
    final a = widget.attachment;
    if (!AttachmentPreviewPolicy.canPreview(a.size)) return;
    if (_path != null) {
      _prepareDocument();
      if (a.kind == 'video') unawaited(_prepareVideo());
    } else if (widget.loadPrivateFile != null &&
        AttachmentPreviewPolicy.canAutoLoad(a.size) &&
        a.kind != 'video' &&
        a.kind != 'audio') {
      unawaited(_load());
    } else if (a.kind == 'document' &&
        AttachmentPreviewPolicy.canAutoLoad(a.size)) {
      unawaited(_load());
    }
  }

  void _prepareDocument() {
    if (_path != null &&
        widget.attachment.kind == 'document' &&
        !widget.attachment.name.toLowerCase().endsWith('.pdf')) {
      _sample = documentSample(_path!, widget.attachment.name);
    }
  }

  Future<void> _load() async {
    if (_loading || !AttachmentPreviewPolicy.canPreview(widget.attachment.size))
      return;
    setState(() {
      _loading = true;
      _unavailable = false;
    });
    try {
      if (widget.loadPrivateFile != null) {
        _path = await widget.loadPrivateFile!();
      } else if (widget.attachment.url.isNotEmpty) {
        final dir = await Directory.systemTemp.createTemp('phlio_preview_');
        _path = '${dir.path}/preview';
        await Dio().download(AppConfig.mediaUrl(widget.attachment.url), _path!);
      }
      if (!mounted) return;
      _prepareDocument();
    } catch (_) {
      if (mounted) _unavailable = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _prepareVideo() async {
    if (_video != null ||
        !AttachmentPreviewPolicy.canPreview(widget.attachment.size)) return;
    if (_path == null && widget.loadPrivateFile != null) await _load();
    if (!mounted || _unavailable) return;
    final controller = _path != null
        ? VideoPlayerController.file(File(_path!))
        : VideoPlayerController.networkUrl(
            Uri.parse(AppConfig.mediaUrl(widget.attachment.url)));
    _video = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      controller.addListener(_videoChanged);
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
    }
  }

  void _videoChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _playAudio() async {
    try {
      if (_audio == null) {
        if (_path == null && widget.loadPrivateFile != null) await _load();
        if (!mounted || _unavailable) return;
        _audio = AudioPlayer();
        _subscriptions.add(_audio!.onDurationChanged.listen((v) {
          if (mounted) setState(() => _duration = v);
        }));
        _subscriptions.add(_audio!.onPositionChanged.listen((v) {
          if (mounted) setState(() => _position = v);
        }));
        _subscriptions.add(_audio!.onPlayerStateChanged.listen((v) {
          if (mounted) setState(() => _playing = v == PlayerState.playing);
        }));
      }
      if (_playing) {
        await _audio!.pause();
      } else {
        final source = _path == null
            ? UrlSource(AppConfig.mediaUrl(widget.attachment.url))
            : DeviceFileSource(_path!);
        await _audio!.play(source);
      }
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _video?.removeListener(_videoChanged);
    unawaited(_video?.dispose() ?? Future<void>.value());
    unawaited(_audio?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  String _time(Duration time) =>
      '${time.inMinutes}:${(time.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _body() {
    final a = widget.attachment;
    if (!AttachmentPreviewPolicy.canPreview(a.size))
      return _placeholder(
          Icons.insert_drive_file_outlined, 'Large file · preview disabled');
    if (_unavailable)
      return _placeholder(Icons.broken_image_outlined, 'Preview unavailable');
    if (_loading)
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (a.isSticker) {
      final item = FoxyPack.resolve(a.value);
      return Image.asset(
          item?.assetPath ?? 'assets/stickers/sticker_foxy_happy.png',
          fit: BoxFit.contain);
    }
    if (a.isImage || (a.kind == 'gif' && a.url.isNotEmpty)) {
      if (_path != null)
        return Image.file(File(_path!),
            fit: BoxFit.cover,
            cacheWidth: widget.compact ? 320 : 800,
            errorBuilder: (_, __, ___) => _placeholder(
                Icons.image_not_supported_outlined, 'Preview unavailable'));
      if (widget.loadPrivateFile != null) return _loadButton();
      return Image.network(AppConfig.mediaUrl(a.url),
          fit: BoxFit.cover,
          cacheWidth: 800,
          errorBuilder: (_, __, ___) => _placeholder(
              Icons.image_not_supported_outlined, 'Preview unavailable'));
    }
    if (a.kind == 'video') {
      final video = _video;
      if (video == null || !video.value.isInitialized)
        return Center(
            child: IconButton.filledTonal(
                tooltip: 'Preview video',
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () async {
                  await _prepareVideo();
                  if (mounted && _video?.value.isInitialized == true)
                    await _video!.play();
                }));
      return Stack(alignment: Alignment.center, children: [
        Center(
            child: AspectRatio(
                aspectRatio: video.value.aspectRatio,
                child: VideoPlayer(video))),
        IconButton.filledTonal(
            tooltip: video.value.isPlaying ? 'Pause video' : 'Play video',
            onPressed: () =>
                video.value.isPlaying ? video.pause() : video.play(),
            icon: Icon(video.value.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded)),
        if (!widget.compact)
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(video, allowScrubbing: true)),
      ]);
    }
    if (a.kind == 'audio')
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          IconButton.filledTonal(
              tooltip: _playing ? 'Pause audio' : 'Play audio',
              onPressed: _playAudio,
              icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded)),
          const SizedBox(width: 8),
          Expanded(
              child: Column(children: [
            const Icon(Icons.graphic_eq_rounded,
                color: PhlioColors.domainRooms, size: 32),
            Text('${_time(_position)} / ${_time(_duration)}',
                style: const TextStyle(fontSize: 11)),
          ])),
        ]),
        if (!widget.compact && _duration.inMilliseconds > 0)
          Slider(
              value: _position.inMilliseconds
                  .clamp(0, _duration.inMilliseconds)
                  .toDouble(),
              max: _duration.inMilliseconds.toDouble(),
              onChanged: (v) =>
                  _audio?.seek(Duration(milliseconds: v.toInt()))),
      ]);
    if (a.kind == 'document') {
      if (_path == null) return _loadButton();
      if (a.name.toLowerCase().endsWith('.pdf'))
        return PdfDocumentViewBuilder.file(_path!,
            errorBuilder: (_, __, ___) => _placeholder(
                Icons.picture_as_pdf_outlined, 'PDF preview unavailable'),
            builder: (context, document) => document == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : PdfPageView(document: document, pageNumber: 1));
      if (_sample != null)
        return FutureBuilder<String>(
            future: _sample,
            builder: (context, snapshot) {
              if (snapshot.hasError || snapshot.data?.isEmpty == true)
                return _placeholder(Icons.description_outlined, 'Document');
              return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(snapshot.data ?? 'Loading preview…',
                      maxLines: widget.compact ? 3 : 8,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: PhlioColors.textSecondary)));
            });
    }
    return _placeholder(Icons.insert_drive_file_outlined, 'File');
  }

  Future<void> _openPreview() async {
    final a = widget.attachment;
    if (!AttachmentPreviewPolicy.canPreview(a.size)) return;
    if (_path == null &&
        (widget.loadPrivateFile != null || a.kind == 'document')) await _load();
    if (!mounted || _unavailable) return;
    Widget content;
    if (a.kind == 'document' &&
        _path != null &&
        a.name.toLowerCase().endsWith('.pdf')) {
      content = PdfViewer.file(_path!);
    } else if (a.kind == 'document' && _sample != null) {
      content = FutureBuilder<String>(
          future: _sample,
          builder: (context, snapshot) => SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                snapshot.data?.isNotEmpty == true
                    ? snapshot.data!
                    : snapshot.hasError
                        ? 'Could not read this document.'
                        : snapshot.hasData
                            ? 'This file format does not have an in-app text preview.'
                            : 'Loading document…',
              )));
    } else if (a.isImage) {
      content = InteractiveViewer(
          maxScale: 5,
          child: Center(
              child: _path != null
                  ? Image.file(File(_path!), fit: BoxFit.contain)
                  : Image.network(AppConfig.mediaUrl(a.url),
                      fit: BoxFit.contain)));
    } else {
      content = Center(child: Text('No readable preview for ${a.name}.'));
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
              backgroundColor: PhlioColors.roomsChat,
              appBar: AppBar(
                  title: Text(a.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
              body: SafeArea(child: content),
            )));
  }

  Widget _placeholder(IconData icon, String label) => Center(
      child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: widget.compact ? 24 : 32,
                color: PhlioColors.textSecondary),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
          ])));
  Widget _loadButton() => Center(
      child: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Load preview')));

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
            color: PhlioColors.roomsInput,
            borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                  onTap: widget.attachment.kind == 'document' ||
                          widget.attachment.isImage
                      ? _openPreview
                      : null,
                  child: SizedBox(
                      height: widget.compact
                          ? 74
                          : widget.attachment.kind == 'audio'
                              ? 120
                              : 190,
                      child: _body())),
              if (!widget.compact)
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.attachment.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(attachmentSize(widget.attachment.size),
                            style: const TextStyle(
                                fontSize: 11,
                                color: PhlioColors.textSecondary)),
                      ],
                    )),
            ]),
      );
}
