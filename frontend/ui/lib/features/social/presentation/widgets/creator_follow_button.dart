import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../controllers/video_library.dart';

class CreatorFollowButton extends ConsumerStatefulWidget {
  const CreatorFollowButton({required this.creator, super.key});
  final String creator;
  @override
  ConsumerState<CreatorFollowButton> createState() =>
      _CreatorFollowButtonState();
}

class _CreatorFollowButtonState extends ConsumerState<CreatorFollowButton> {
  bool _busy = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final own = ref.watch(authControllerProvider).valueOrNull?.username;
    if (widget.creator.isEmpty || own == widget.creator) {
      return const SizedBox.shrink();
    }
    final following = ref.watch(creatorFollowingProvider);
    final enabled = following.valueOrNull?.contains(widget.creator) ?? false;
    return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.tonal(
              onPressed: _busy || following.isLoading
                  ? null
                  : () async {
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      try {
                        if (following.hasError) {
                          ref.invalidate(creatorFollowingProvider);
                          return;
                        }
                        await ref
                            .read(socialVideoApiProvider)
                            .follow(widget.creator, !enabled);
                        if (mounted) ref.invalidate(creatorFollowingProvider);
                      } catch (_) {
                        if (mounted) {
                          setState(
                              () => _error = 'Could not update. Try again.');
                        }
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: Text(
                _busy
                    ? 'Saving…'
                    : following.hasError
                        ? 'Retry follow'
                        : enabled
                            ? 'Following'
                            : 'Follow',
              ),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(fontSize: 11)),
          ],
        ));
  }
}
