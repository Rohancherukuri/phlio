import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../app/config/app_config.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/widgets/foxy_stickers.dart';
import '../../../../shared/giphy/giphy_picker.dart';
import '../../../../shared/moments/stickers/sticker_model.dart';
import '../../../../shared/moments/stickers/sticker_tray.dart';
import '../../../../shared/moments/stickers/sticker_views.dart';
import 'snap_send_view.dart' show pickSnapImage;

/// Captions tray is intentionally limited to decorations supported by snaps.
Future<MomentSticker?> pickSnapDecoration(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context, isScrollControlled: true, useSafeArea: true,
    backgroundColor: PhlioColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (_) => const SnapCaptionsSheet(),
  );
  if (!context.mounted || choice == null) return null;
  if (choice == 'music') {
    final song = await pickMomentSong(context);
    return song == null ? null : MomentSticker(StickerType.music, song);
  }
  if (choice == 'image') return pickSnapImage(context);
  if (choice == 'gif') {
    final gif = await showGiphyPicker(context);
    return gif == null ? null : MomentSticker(StickerType.gif, {'url': gif.url, 'title': gif.title});
  }
  if (choice == 'stickers') {
    final sticker = await showFoxyStickerSheet(context);
    return sticker == null ? null : MomentSticker(StickerType.foxy, {'sticker': sticker});
  }
  if (choice == 'location') {
    final text = await askText(context, 'Location', 'Add a place name');
    return text == null ? null : MomentSticker(StickerType.location, {'text': text});
  }
  if (choice == 'clock') {
    return MomentSticker(StickerType.clock, {'time': TimeOfDay.now().format(context)});
  }
  final decorative = {'party': '🪩 Party Time!', 'ootd': '🕶️ OOTD', 'miss': '🥰 Miss you'};
  final text = decorative[choice] ?? await askText(context, 'Caption', 'Write something…');
  if (text == null || text.trim().isEmpty) return null;
  return MomentSticker(StickerType.word, {'word': text, 'style': choice});
}

class SnapCaptionsSheet extends StatelessWidget {
  const SnapCaptionsSheet({super.key});
  @override
  Widget build(BuildContext context) {
    Widget chip(String id, String label, {IconData? icon, bool accent = false}) => Semantics(
      button: true,
      child: InkWell(onTap: () => Navigator.pop(context, id), borderRadius: BorderRadius.circular(32),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(32),
            color: accent ? null : PhlioColors.roomsInput,
            gradient: accent ? const LinearGradient(colors: [PhlioColors.brandViolet, PhlioColors.brandPink, PhlioColors.brandPeach]) : null),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 26, color: Colors.white), const SizedBox(width: 8)],
            Flexible(child: Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white))),
          ])),
      ));
    return SafeArea(top: false, child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 20),
        const Center(child: Text('Captions', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold))),
        const SizedBox(height: 24),
        const Text('General', style: TextStyle(fontSize: 18, color: Colors.white60)),
        const SizedBox(height: 14),
        Wrap(spacing: 12, runSpacing: 12, children: [
          chip('text', 'Aa Text'), chip('gradient', 'Colour text', accent: true),
          chip('music', 'Now Playing', icon: Icons.music_note_rounded),
          chip('location', 'Location', icon: Icons.location_on_rounded),
          chip('image', 'Image', icon: Icons.add_photo_alternate_outlined),
          chip('gif', 'GIF', icon: Icons.gif_box_outlined),
          chip('stickers', 'Stickers', icon: Icons.emoji_emotions_outlined),
          chip('clock', TimeOfDay.now().format(context), icon: Icons.schedule),
        ]),
        const SizedBox(height: 24),
        const Text('Decorative', style: TextStyle(fontSize: 18, color: Colors.white60)),
        const SizedBox(height: 14),
        Wrap(spacing: 12, runSpacing: 12, children: [
          chip('party', '🪩 Party Time!', accent: true), chip('ootd', '🕶️ OOTD'),
          chip('miss', '🥰 Miss you', accent: true),
        ]),
      ]),
    ));
  }
}

class SnapDecorationCanvas extends StatefulWidget {
  const SnapDecorationCanvas({super.key, required this.child, required this.layers, this.onChanged});
  final Widget child;
  final List<MomentSticker> layers;
  final VoidCallback? onChanged;
  @override
  State<SnapDecorationCanvas> createState() => _SnapDecorationCanvasState();
}

class _SnapDecorationCanvasState extends State<SnapDecorationCanvas> {
  String? selected;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final active = widget.layers.where((s) => s.id == selected).firstOrNull;
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      for (final layer in widget.layers)
        Align(alignment: Alignment(layer.x * 2 - 1, layer.y * 2 - 1),
          child: GestureDetector(
            onTap: widget.onChanged == null ? null : () => setState(() => selected = layer.id),
            onPanUpdate: widget.onChanged == null ? null : (event) {
              layer.x = (layer.x + event.delta.dx / box.maxWidth).clamp(.05, .95);
              layer.y = (layer.y + event.delta.dy / box.maxHeight).clamp(.05, .95);
              widget.onChanged!();
            },
            child: Transform.rotate(angle: layer.rotation,
              child: Transform.scale(scale: layer.scale * box.maxWidth / 360,
                child: Container(constraints: const BoxConstraints(maxWidth: 220),
                  decoration: selected == layer.id && widget.onChanged != null ? BoxDecoration(border: Border.all(color: PhlioColors.brandPeach), borderRadius: BorderRadius.circular(20)) : null,
                  child: _Decoration(layer: layer, playable: widget.onChanged == null),
                ))),
          )),
      if (active != null && widget.onChanged != null)
        Positioned(bottom: 4, left: 8, right: 8, child: Material(color: Colors.black87, borderRadius: BorderRadius.circular(24),
          child: Row(children: [
            IconButton(tooltip: 'Remove decoration', icon: const Icon(Icons.delete_outline), onPressed: () {
              widget.layers.remove(active); setState(() => selected = null); widget.onChanged!();
            }),
            Expanded(child: Slider(value: active.scale.clamp(.5, 1.5), min: .5, max: 1.5,
              onChanged: (v) { active.scale = v; widget.onChanged!(); })),
            IconButton(tooltip: 'Done positioning', icon: const Icon(Icons.check), onPressed: () => setState(() => selected = null)),
          ]))),
    ]);
  });
}

class _Decoration extends StatelessWidget {
  const _Decoration({required this.layer, required this.playable});
  final MomentSticker layer;
  final bool playable;
  @override
  Widget build(BuildContext context) {
    if (layer.type == StickerType.word) {
      final accent = ['gradient', 'party', 'miss'].contains(layer.data['style']);
      return Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: accent ? null : Colors.black87, borderRadius: BorderRadius.circular(26),
          gradient: accent ? const LinearGradient(colors: [PhlioColors.brandViolet, PhlioColors.brandPink, PhlioColors.brandPeach]) : null),
        child: Text('${layer.data['word']}', textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)));
    }
    final view = MomentStickerView(layer);
    return layer.type == StickerType.music && playable ? _SnapMusic(key: ValueKey(layer.id), layer: layer, child: view) : view;
  }
}

class _SnapMusic extends StatefulWidget {
  const _SnapMusic({super.key, required this.layer, required this.child});
  final MomentSticker layer;
  final Widget child;
  @override
  State<_SnapMusic> createState() => _SnapMusicState();
}
class _SnapMusicState extends State<_SnapMusic> with WidgetsBindingObserver {
  final player = AudioPlayer();
  bool playing = false, busy = false;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) { player.pause(); if (mounted) setState(() => playing = false); }
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); player.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => InkWell(onTap: busy ? null : () async {
    setState(() => busy = true);
    try {
      if (playing) { await player.pause(); } else { await player.play(UrlSource(AppConfig.mediaUrl('${widget.layer.data['url']}'))); }
      if (mounted) setState(() => playing = !playing);
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This song is unavailable. Try again later.')));
    } finally { if (mounted) setState(() => busy = false); }
  }, child: Column(mainAxisSize: MainAxisSize.min, children: [widget.child,
    Text(busy ? 'Loading…' : playing ? 'Tap to pause' : 'Tap to play', style: const TextStyle(color: Colors.white, fontSize: 11)),
  ]));
}
