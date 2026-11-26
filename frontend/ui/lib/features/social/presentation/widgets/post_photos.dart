// A post's photos the way a feed shows them: full card width, rounded, at the
// photo's own shape clamped to Instagram's range (4:5 portrait … 1.91:1
// landscape), cropped to fill. Several photos become a swipeable carousel
// with a "2/5" counter and dots; the first photo sets the frame.

import 'package:flutter/material.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/network/media_cache.dart';
import '../../../../design_system/colors.dart';

class PostPhotos extends StatefulWidget {
  const PostPhotos({required this.urls, this.radius = 16, this.onTap, super.key});
  final List<String> urls;
  final double radius;
  final VoidCallback? onTap;

  /// Instagram's limits: 4:5 portrait to 1.91:1 landscape.
  static const minRatio = 4 / 5, maxRatio = 1.91;

  @override
  State<PostPhotos> createState() => _PostPhotosState();
}

class _PostPhotosState extends State<PostPhotos> {
  double? _ratio;
  int _page = 0;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  ImageProvider _provider(String url) => (phlioNetworkImage(AppConfig.mediaUrl(url))).image;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void didUpdateWidget(PostPhotos old) {
    super.didUpdateWidget(old);
    if (old.urls.isEmpty || widget.urls.isEmpty || old.urls.first != widget.urls.first) _measure();
  }

  /// Reads the first photo's size to pick the frame's shape.
  void _measure() {
    _stopListening();
    if (widget.urls.isEmpty) return;
    final stream = _provider(widget.urls.first).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      final w = info.image.width.toDouble(), h = info.image.height.toDouble();
      if (h > 0 && mounted) {
        setState(() => _ratio = (w / h).clamp(PostPhotos.minRatio, PostPhotos.maxRatio));
      }
      _stopListening();
    }, onError: (_, __) {
      if (mounted) setState(() => _ratio = 1);
      _stopListening();
    });
    _stream = stream..addListener(listener);
    _listener = listener;
  }

  void _stopListening() {
    if (_stream != null && _listener != null) _stream!.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  Widget _photo(String url) => phlioNetworkImage(
        AppConfig.mediaUrl(url),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: PhlioColors.surfaceElevated,
          child: Center(child: Icon(Icons.broken_image_outlined, color: PhlioColors.textMuted)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.isEmpty) return const SizedBox.shrink();
    final many = urls.length > 1;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: AspectRatio(
          // Square while the first photo's size is still loading.
          aspectRatio: _ratio ?? 1,
          child: ColoredBox(
            color: PhlioColors.surfaceElevated,
            child: GestureDetector(
              onTap: widget.onTap,
              child: !many
                  ? _photo(urls.first)
                  : Stack(fit: StackFit.expand, children: [
                      PageView.builder(
                        itemCount: urls.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (_, i) => _photo(urls[i]),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(20)),
                          child: Text('${_page + 1}/${urls.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 10,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          for (var i = 0; i < urls.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.symmetric(horizontal: 2.5),
                              width: i == _page ? 7 : 6,
                              height: i == _page ? 7 : 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == _page ? Colors.white : Colors.white.withValues(alpha: .5),
                              ),
                            ),
                        ]),
                      ),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}
