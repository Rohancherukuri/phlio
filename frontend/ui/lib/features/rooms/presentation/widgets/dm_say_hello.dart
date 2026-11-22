// The empty chat: what you see in a DM with someone you haven't talked to
// yet (Discord's "say hi" with its waving mascot, Instagram's sticker row).
//
//   * Their photo, name and @handle, "View profile", and "This is the very
//     beginning of your conversation with …".
//   * Foxy, live (the rigged [FoxyPuppet]): he waves, cheers, sends love and
//     claps in turn; tap him and he hops.
//   * "Say hello by sending a sticker": a row of animated Foxy Moves
//     stickers. One tap sends it — Foxy celebrates — and the chat begins.
//     ✕ hides the row.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/foxy_pack.dart';
import '../../../../design_system/widgets/foxy_puppet.dart';
import '../../../../design_system/widgets/foxy_stickers.dart';
import '../../../../design_system/widgets/phlio_card.dart';

/// Stickers offered to start a chat, friendliest first.
const _hello = ['move_hi', 'move_wag', 'move_yay', 'move_love', 'move_thumbs_up', 'move_cheers', 'move_giggle', 'move_wink', 'move_coffee'];

class DmSayHello extends StatefulWidget {
  const DmSayHello({
    required this.username,
    required this.name,
    required this.onSticker,
    this.handle,
    this.avatarUrl,
    this.compact = false,
    super.key,
  });

  final String username, name;
  final String? handle, avatarUrl;
  final bool compact;

  /// Sends the sticker (id, label).
  final Future<void> Function(String id, String label) onSticker;

  @override
  State<DmSayHello> createState() => _DmSayHelloState();
}

class _DmSayHelloState extends State<DmSayHello> {
  static const _acts = [FoxyAct.wave, FoxyAct.cheer, FoxyAct.love, FoxyAct.clap, FoxyAct.happy];
  Timer? _cycle;
  int _act = 0, _hop = 0;
  bool _tray = true;
  String? _sending;
  FoxyAct? _override;

  @override
  void initState() {
    super.initState();
    _cycle = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (mounted && _override == null) setState(() => _act = (_act + 1) % _acts.length);
    });
  }

  @override
  void dispose() {
    _cycle?.cancel();
    super.dispose();
  }

  Future<void> _send(String id) async {
    if (_sending != null) return;
    final label = FoxyPack.resolve(id)?.label ?? 'Foxy sticker';
    HapticFeedback.mediumImpact();
    setState(() {
      _sending = id;
      _override = FoxyAct.hooray;
      _hop++;
    });
    try {
      await widget.onSticker(id, label);
    } catch (_) {
      if (mounted) {
        setState(() => _override = FoxyAct.oops);
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('Could not send the sticker. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _sending = null);
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _override = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final scheme = Theme.of(context).colorScheme;
    final act = _override ?? _acts[_act];
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          // IntrinsicHeight lets the Spacer push the sticker row to the
          // bottom on tall screens while short ones still scroll.
          child: IntrinsicHeight(
            child: Column(children: [
            SizedBox(height: compact ? 12 : 24),
            PhlioAvatar(
              profileId: widget.username,
              name: widget.name,
              imageUrl: widget.avatarUrl,
              size: compact ? 72 : 96,
              showMomentRing: false,
            ),
            const SizedBox(height: 12),
            Text(widget.name,
                textAlign: TextAlign.center, style: PhlioTypography.bodyStrong.copyWith(fontSize: compact ? 20 : 24)),
            const SizedBox(height: 2),
            Text(widget.handle ?? widget.username, textAlign: TextAlign.center, style: PhlioTypography.body),
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: () => context.push('/creator/${Uri.encodeComponent(widget.username)}'),
              child: const Text('View profile'),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'This is the very beginning of your conversation with ${widget.name}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurface.withValues(alpha: .6), height: 1.35),
              ),
            ),
            SizedBox(height: compact ? 4 : 12),
            // Foxy, on a soft glow, doing his rounds.
            SizedBox(
              height: compact ? 150 : 210,
              child: Stack(alignment: Alignment.center, children: [
                Container(
                  width: compact ? 120 : 170,
                  height: compact ? 120 : 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      const Color(0xFFFFB58F).withValues(alpha: .28),
                      const Color(0xFFFFB58F).withValues(alpha: 0),
                    ]),
                  ),
                ),
                FoxyPuppet(
                  act: act,
                  size: compact ? 140 : 196,
                  hopSignal: _hop,
                  poseBlend: const Duration(milliseconds: 320),
                ),
              ]),
            ),
            const Spacer(),
            AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              child: !_tray
                  ? const SizedBox(width: double.infinity)
                  : Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: scheme.onSurface.withValues(alpha: .1))),
                      ),
                      padding: const EdgeInsets.only(top: 12, bottom: 10),
                      child: Column(children: [
                        Row(children: [
                          const SizedBox(width: 48),
                          Expanded(
                            child: Text('Say hello by sending a sticker',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: scheme.onSurface.withValues(alpha: .75), fontSize: 14.5)),
                          ),
                          IconButton(
                            tooltip: 'Hide',
                            onPressed: () => setState(() => _tray = false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ]),
                        SizedBox(
                          height: compact ? 84 : 104,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _hello.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 6),
                            itemBuilder: (_, i) => _HelloSticker(
                              id: _hello[i],
                              size: compact ? 76 : 96,
                              index: i,
                              busy: _sending == _hello[i],
                              onTap: () => _send(_hello[i]),
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
    );
  }
}

/// A sticker that pops in (staggered) and squishes when pressed.
class _HelloSticker extends StatefulWidget {
  const _HelloSticker({required this.id, required this.size, required this.index, required this.busy, required this.onTap});
  final String id;
  final double size;
  final int index;
  final bool busy;
  final VoidCallback onTap;
  @override
  State<_HelloSticker> createState() => _HelloStickerState();
}

class _HelloStickerState extends State<_HelloSticker> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 420 + widget.index * 70),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Transform.translate(
          offset: Offset(0, 24 * (1 - t)),
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        ),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? .86 : (widget.busy ? 1.12 : 1),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: widget.busy ? .6 : 1,
              duration: const Duration(milliseconds: 160),
              child: FoxyStickerView(id: widget.id, size: widget.size),
            ),
          ),
        ),
      );
}
