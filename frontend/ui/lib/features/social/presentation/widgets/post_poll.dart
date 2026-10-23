import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/config/app_config.dart';
import '../../../../design_system/colors.dart';
import '../../../../shared/music/song_picker.dart';

final postPollProvider = FutureProvider.autoDispose.family<Map?, String>(
    (ref, id) async =>
        (await ref.watch(musicApiProvider).get('/social/posts/$id/poll')).data
            as Map?);

class PostPoll extends ConsumerStatefulWidget {
  const PostPoll({super.key, required this.id});
  final String id;
  @override
  ConsumerState<PostPoll> createState() => _PostPollState();
}

class _PostPollState extends ConsumerState<PostPoll> {
  bool voting = false;
  @override
  Widget build(BuildContext context) {
    final poll = ref.watch(postPollProvider(widget.id)).valueOrNull;
    if (poll == null) return const SizedBox.shrink();
    final choices = poll['choices'] as List;
    final total = poll['total'] as int;
    final results = poll['selected'] != null || poll['closed'] == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < choices.length; i++)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
                onPressed: voting || poll['closed'] == true
                    ? null
                    : () async {
                        setState(() => voting = true);
                        try {
                          await ref.read(musicApiProvider).put(
                              '/social/posts/${widget.id}/poll/vote',
                              data: {'choice': i});
                          ref.invalidate(postPollProvider(widget.id));
                        } catch (_) {
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Could not record your vote. Please try again.')));
                        } finally {
                          if (mounted) setState(() => voting = false);
                        }
                      },
                child: Row(children: [
                  if (choices[i]['image_url'] != null)
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Image.network(
                            AppConfig.mediaUrl(
                                choices[i]['image_url'] as String),
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.image_not_supported_outlined))),
                  Expanded(child: Text('${choices[i]['text']}')),
                  if (poll['selected'] == i)
                    const Icon(Icons.check_circle_outline,
                        color: PhlioColors.brandOrange),
                  if (results)
                    Text(
                        ' ${total == 0 ? 0 : ((poll['counts'][i] as int) * 100 / total).round()}%')
                ]))),
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
              '$total votes · ${poll['closed'] == true ? 'Poll ended' : 'Ends ${DateTime.parse(poll['expires_at'] as String).toLocal()}'}',
              style:
                  const TextStyle(fontSize: 12, color: PhlioColors.textMuted)))
    ]);
  }
}
