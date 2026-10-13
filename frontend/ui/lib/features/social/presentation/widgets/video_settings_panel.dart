import 'package:flutter/material.dart';
import '../controllers/video_playback_controller.dart';

class VideoSettingsPanel extends StatelessWidget {
  const VideoSettingsPanel(
      {required this.controller,
      required this.onClose,
      required this.onLock,
      required this.audioOnly,
      required this.onAudioOnly,
      super.key});
  final VideoPlaybackController controller;
  final VoidCallback onClose, onLock;
  final bool audioOnly;
  final ValueChanged<bool> onAudioOnly;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Stack(children: [
      Positioned.fill(
          child: GestureDetector(
              onTap: onClose, child: const ColoredBox(color: Colors.black54))),
      Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: 640,
                maxHeight: MediaQuery.sizeOf(context).height * .78),
            child: Material(
                color: const Color(0xFF182231),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        const SizedBox(width: 20),
                        const Expanded(
                            child: Text('Video settings',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700))),
                        IconButton(
                            tooltip: 'Close settings',
                            onPressed: onClose,
                            icon: const Icon(Icons.close))
                      ]),
                      ListTile(
                          leading: const Icon(Icons.tune),
                          title: const Text('Quality'),
                          subtitle:
                              Text(c.loading ? 'Switching…' : c.qualityLabel)),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(spacing: 8, children: [
                            ChoiceChip(
                                label: const Text('Auto / original'),
                                selected: c.qualityLabel == 'Auto',
                                onSelected: c.loading
                                    ? null
                                    : (_) => c.setQuality(null)),
                            for (final source
                                in c.video?.sources ?? <Map<String, dynamic>>[])
                              ChoiceChip(
                                  label: Text(source['label'] as String),
                                  selected: c.qualityLabel == source['label'],
                                  onSelected: c.loading
                                      ? null
                                      : (_) => c.setQuality(source)),
                          ])),
                      const ListTile(
                          leading: Icon(Icons.speed),
                          title: Text('Playback speed')),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(spacing: 8, children: [
                            for (final speed in [
                              .25,
                              .5,
                              .75,
                              1.0,
                              1.25,
                              1.5,
                              1.75,
                              2.0
                            ])
                              ChoiceChip(
                                  label: Text('${speed}x'),
                                  selected: c.speed == speed,
                                  onSelected: (_) => c.setSpeed(speed)),
                          ])),
                      const ListTile(
                          leading: Icon(Icons.closed_caption_off_outlined),
                          title: Text('Captions'),
                          subtitle:
                              Text('No caption track provided for this video')),
                      const ListTile(
                          leading: Icon(Icons.audiotrack),
                          title: Text('Audio track'),
                          subtitle: Text('Original audio')),
                      ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: const Text('Lock controls'),
                          onTap: onLock),
                      SwitchListTile(
                          secondary: const Icon(Icons.headphones),
                          title: const Text('Audio only'),
                          subtitle:
                              const Text('Listen while this screen stays open'),
                          value: audioOnly,
                          onChanged: onAudioOnly),
                      SwitchListTile(
                          title: const Text('Loop video'),
                          value: c.loop,
                          onChanged: c.setLoop),
                      SwitchListTile(
                          title: const Text('Fill screen'),
                          value: c.fill,
                          onChanged: c.setFill),
                      Row(children: [
                        const Padding(
                            padding: EdgeInsets.all(16),
                            child: Icon(Icons.volume_up)),
                        Expanded(
                            child:
                                Slider(value: c.volume, onChanged: c.setVolume))
                      ]),
                      if (c.notice != null)
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(c.notice!)),
                    ])))),
          )),
    ]);
  }
}
