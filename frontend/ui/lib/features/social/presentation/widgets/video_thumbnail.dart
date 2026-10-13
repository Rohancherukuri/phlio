import 'package:flutter/material.dart';
import '../../../../app/config/app_config.dart';

/// A frame from the video's API metadata. Failed loads never masquerade as
/// generic cover art, and can be retried without restarting the application.
class VideoThumbnail extends StatefulWidget {
  const VideoThumbnail({required this.url, this.fit = BoxFit.cover, super.key});
  final String? url;
  final BoxFit fit;
  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  int retry = 0;
  @override
  Widget build(BuildContext context) {
    if (widget.url == null || widget.url!.isEmpty) {
      return const Center(child: Text('Preview unavailable'));
    }
    final source = Uri.parse(AppConfig.mediaUrl(widget.url!));
    final url = retry == 0
        ? source.toString()
        : source.replace(queryParameters: {
            ...source.queryParameters,
            'retry': '$retry',
          }).toString();
    return Image.network(
      url,
      key: ValueKey(url),
      fit: widget.fit,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : const Center(
              child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))),
      errorBuilder: (_, __, ___) => Center(
          child: TextButton.icon(
        onPressed: () => setState(() => retry++),
        icon: const Icon(Icons.refresh),
        label: const Text('Reload preview'),
      )),
    );
  }
}
