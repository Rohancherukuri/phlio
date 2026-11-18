// Bubble Editor (from the palette button on your avatar in the note
// composer): pick a bubble colour — five pages of swatches — and an
// animated effect (Congrats confetti, sparkles, hearts, fireworks, glow,
// snow, fizz) drawn by a fragment shader. Apply returns the style; Clear
// goes back to the plain bubble.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/colors.dart';
import 'note_bubble.dart';

/// `(color hex or null, effect id or null)`.
typedef NoteStyle = ({String? color, String? effect});

/// [text] is the composer's controller, so you can keep typing here and
/// the words carry back.
Future<NoteStyle?> openBubbleEditor(
  BuildContext context, {
  required Map note,
  required Widget avatar,
  required TextEditingController text,
}) =>
    Navigator.of(context).push<NoteStyle>(
      MaterialPageRoute(builder: (_) => BubbleEditorScreen(note: note, avatar: avatar, text: text)),
    );

class BubbleEditorScreen extends StatefulWidget {
  const BubbleEditorScreen({required this.note, required this.avatar, required this.text, super.key});

  /// The note as it is now (text, music, gif, color, effect).
  final Map note;
  final Widget avatar;
  final TextEditingController text;

  @override
  State<BubbleEditorScreen> createState() => _BubbleEditorScreenState();
}

class _BubbleEditorScreenState extends State<BubbleEditorScreen> {
  late String? color = widget.note['color'] as String?;
  late String? effect = widget.note['effect'] as String?;
  late final _pages = PageController(initialPage: _initialPage());
  int page = 0;

  int _initialPage() {
    final c = parseNoteColor(color);
    for (var i = 0; i < kNoteColorPages.length; i++) {
      if (c != null && kNoteColorPages[i].contains(c)) return page = i;
    }
    return 0;
  }

  bool get _changed => color != widget.note['color'] || effect != widget.note['effect'];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _pickEffect() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Effects', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _EffectTile(
                  label: 'None',
                  icon: Icons.block_rounded,
                  selected: effect == null,
                  onTap: () => Navigator.pop(sheet, ''),
                ),
                for (final (id, label, icon) in kNoteEffects)
                  _EffectTile(
                    label: label,
                    icon: icon,
                    effect: id,
                    selected: effect == id,
                    onTap: () => Navigator.pop(sheet, id),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
    if (picked != null && mounted) {
      HapticFeedback.selectionClick();
      setState(() => effect = picked.isEmpty ? null : picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = {...widget.note, 'color': color, 'effect': effect};
    return Scaffold(
      backgroundColor: PhlioColors.background,
      appBar: AppBar(
        backgroundColor: PhlioColors.background,
        centerTitle: true,
        title: const Text('Bubble Editor', style: TextStyle(fontWeight: FontWeight.w700)),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        // Tap outside the bubble to put the keyboard away and see the colours.
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: SizedBox(
                width: 300,
                height: 320,
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                  Positioned(top: 150, child: Opacity(opacity: 0.55, child: widget.avatar)),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 168,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Stack(clipBehavior: Clip.none, children: [
                        NoteTextBubble(controller: widget.text, note: preview),
                        // Effects button on the bubble's top-left corner.
                        Positioned(
                          left: -18,
                          top: -18,
                          child: Material(
                            color: kNoteBubbleColor,
                            shape: const CircleBorder(),
                            elevation: 4,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _pickEffect,
                              child: Padding(
                                padding: const EdgeInsets.all(9),
                                child: ShaderMask(
                                  shaderCallback: (r) => const LinearGradient(
                                    colors: [Color(0xFFFF2E7E), Color(0xFFFF8A3D)],
                                  ).createShader(r),
                                  child: const Icon(Icons.add_reaction_outlined, color: Colors.white, size: 24),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          SizedBox(
            height: 64,
            child: PageView.builder(
              controller: _pages,
              itemCount: kNoteColorPages.length,
              onPageChanged: (i) => setState(() => page = i),
              itemBuilder: (_, i) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final c in kNoteColorPages[i])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => color = noteColorHex(c));
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 50,
                        height: 50,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: const Color(0xFF3A3F4B),
                          border: Border.all(
                            color: color == noteColorHex(c) ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < kNoteColorPages.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == page ? PhlioColors.textMuted : const Color(0xFF3A3F4B),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 4),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _changed ? () => Navigator.pop<NoteStyle>(context, (color: color, effect: effect)) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F5BD5),
                  disabledBackgroundColor: const Color(0xFF1C2350),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Apply', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          TextButton(
            onPressed: color == null && effect == null
                ? null
                : () => Navigator.pop<NoteStyle>(context, (color: null, effect: null)),
            child: const Text('Clear', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
        ]),
        ),
      ),
    );
  }
}

class _EffectTile extends StatelessWidget {
  const _EffectTile({required this.label, required this.icon, required this.selected, required this.onTap, this.effect});
  final String label;
  final IconData icon;
  final String? effect;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, color: Colors.white, size: 26);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFF1C212B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? PhlioColors.brandViolet : Colors.transparent, width: 2),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // A live, looping mini preview of the effect.
          SizedBox(
            height: 34,
            child: Center(
              child: effect == null
                  ? iconWidget
                  : NoteEffectLayer(effect: effect!, pad: 14, child: iconWidget),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11.5)),
        ]),
      ),
    );
  }
}
