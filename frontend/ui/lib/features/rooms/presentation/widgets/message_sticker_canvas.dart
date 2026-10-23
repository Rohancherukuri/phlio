import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../../../design_system/widgets/foxy_pack.dart';

/// Normalized positions keep message decorations aligned on every screen.
class MessageStickerCanvas extends StatelessWidget {
  const MessageStickerCanvas({
    required this.child,
    required this.overlays,
    this.onChanged,
    super.key,
  });
  final Widget child;
  final List<Map<String, dynamic>> overlays;
  final ValueChanged<List<Map<String, dynamic>>>? onChanged;
  @override
  Widget build(BuildContext context) => Stack(
        children: [
          child,
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, bounds) => Stack(
                children: [
                  for (var i = 0; i < overlays.length; i++) _sticker(i, bounds),
                ],
              ),
            ),
          ),
        ],
      );
  Widget _sticker(int index, BoxConstraints bounds) {
    final sticker = overlays[index];
    final item = FoxyPack.resolve(sticker['value'] as String);
    if (item == null) return const SizedBox.shrink();
    final size = (56 * ((sticker['scale'] as num?)?.toDouble() ?? 1))
        .clamp(20.0, bounds.maxWidth.clamp(20.0, 112.0))
        .toDouble();
    final dx = (bounds.maxWidth - size).clamp(0.0, double.infinity);
    final dy = (bounds.maxHeight - size).clamp(0.0, double.infinity);
    return Positioned(
      left: dx * (sticker['x'] as num).toDouble(),
      top: dy * (sticker['y'] as num).toDouble(),
      width: size,
      height: size,
      child: IgnorePointer(
        ignoring: onChanged == null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanUpdate: (d) {
            final copy =
                overlays.map((v) => Map<String, dynamic>.from(v)).toList();
            copy[index]['x'] =
                ((sticker['x'] as num) + d.delta.dx / (dx > 0 ? dx : 1))
                    .clamp(0.0, 1.0);
            copy[index]['y'] =
                ((sticker['y'] as num) + d.delta.dy / (dy > 0 ? dy : 1))
                    .clamp(0.0, 1.0);
            onChanged?.call(copy);
          },
          onDoubleTap: () {
            final copy =
                overlays.map((v) => Map<String, dynamic>.from(v)).toList();
            copy[index]['scale'] =
                (sticker['scale'] as num? ?? 1) >= 1.5 ? 0.75 : 1.5;
            onChanged?.call(copy);
          },
          onLongPress: () => onChanged?.call([...overlays]..removeAt(index)),
          child: Image.asset(item.assetPath, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

Future<List<Map<String, dynamic>>?> editMessageStickers(
  BuildContext context, {
  required Widget child,
  required List<Map<String, dynamic>> initial,
}) =>
    showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StickerSheet(content: child, initial: initial),
    );

class _StickerSheet extends StatefulWidget {
  const _StickerSheet({required this.content, required this.initial});
  final Widget content;
  final List<Map<String, dynamic>> initial;
  @override
  State<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<_StickerSheet> {
  late List<Map<String, dynamic>> items =
      widget.initial.map((v) => Map<String, dynamic>.from(v)).toList();
  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .85,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Expanded(child: Text('Decorate your message')),
                    TextButton(
                      onPressed: () => Navigator.pop(context, items),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Drag to move • Double-tap to resize • Hold a sticker to remove',
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: MessageStickerCanvas(
                    overlays: items,
                    onChanged: (v) => setState(() => items = v),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 150,
                        minWidth: double.infinity,
                      ),
                      child: widget.content,
                    ),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: items.length >= 12
                    ? null
                    : () async {
                        final item = await showFoxyPicker(
                          context,
                          initialTab: FoxyReactionKind.sticker,
                          includeGifs: false,
                          title: 'Add sticker',
                        );
                        if (mounted &&
                            item != null &&
                            item.kind != FoxyReactionKind.gif) {
                          setState(
                            () => items.add({
                              'value': item.id,
                              'x': .5,
                              'y': .5,
                              'scale': 1.0,
                            }),
                          );
                        }
                      },
                icon: const Icon(Icons.add_reaction_outlined),
                label: const Text('Add sticker'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
}
