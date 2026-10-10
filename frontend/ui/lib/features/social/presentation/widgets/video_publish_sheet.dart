import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/video_library.dart';

Future<void> showVideoPublisher(BuildContext context, {required String kind}) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _VideoPublisher(kind: kind));

class _VideoPublisher extends ConsumerStatefulWidget {
  const _VideoPublisher({required this.kind});
  final String kind;
  @override
  ConsumerState<_VideoPublisher> createState() => _VideoPublisherState();
}

class _VideoPublisherState extends ConsumerState<_VideoPublisher> {
  final title = TextEditingController();
  String? path, fileName, error;
  bool busy = false;
  double progress = 0;
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final result = await FilePicker.pickFiles(type: FileType.video);
    if (!mounted || result == null) return;
    final file = result.files.single;
    if (file.size > 2 * 1024 * 1024 * 1024) {
      setState(() => error = 'Choose a video smaller than 2 GB.');
      return;
    }
    setState(() {
      path = file.path;
      fileName = file.name;
      title.text = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      error = null;
    });
  }

  Future<void> publish() async {
    if (path == null || title.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(socialVideoApiProvider).upload(path!, title.text.trim(),
          kind: widget.kind, onProgress: (sent, total) {
        if (mounted) setState(() => progress = total > 0 ? sent / total : 0);
      });
      ref.invalidate(socialVideoCatalogProvider);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(
            content:
                Text('${widget.kind == 'clip' ? 'Clip' : 'Video'} published')));
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      String? message;
      if (data is Map) {
        message = data['detail'] as String?;
        if (data['error'] is Map) message = data['error']['message'] as String?;
      }
      if (mounted)
        setState(() => error = message ?? 'Upload failed. Please try again.');
    } catch (_) {
      if (mounted) setState(() => error = 'Upload failed. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Text(widget.kind == 'clip' ? 'New clip' : 'New video',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(widget.kind == 'clip'
                    ? '15 seconds–2 minutes'
                    : '1–5 minutes'),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                    onPressed: busy ? null : pick,
                    icon: const Icon(Icons.video_file_outlined),
                    label: Text(fileName ?? 'Choose a video',
                        maxLines: 2, overflow: TextOverflow.ellipsis)),
                const SizedBox(height: 12),
                TextField(
                    controller: title,
                    enabled: !busy,
                    maxLength: 160,
                    decoration: const InputDecoration(labelText: 'Title')),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.redAccent)),
                if (busy) LinearProgressIndicator(value: progress),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: busy || path == null ? null : publish,
                    child: Text(busy ? 'Uploading…' : 'Publish')),
              ]))));
}
