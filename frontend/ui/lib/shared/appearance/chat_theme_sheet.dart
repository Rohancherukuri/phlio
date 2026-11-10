// DM chat theme: background colour, wallpaper and effects for one
// conversation. Shared by both people in the chat (either can change it).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../design_system/widgets/foxy_puppet.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import 'appearance.dart';
import 'appearance_editor.dart';

Future<void> showChatThemeSheet(BuildContext context, String username) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: PhlioColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _ChatThemeSheet(username: username),
  );
}

class _ChatThemeSheet extends ConsumerStatefulWidget {
  const _ChatThemeSheet({required this.username});
  final String username;

  @override
  ConsumerState<_ChatThemeSheet> createState() => _ChatThemeSheetState();
}

class _ChatThemeSheetState extends ConsumerState<_ChatThemeSheet> {
  Appearance? _look;
  Appearance? _saved;
  bool _saving = false;
  FoxyAct _act = FoxyAct.wave;
  int _hop = 0;

  @override
  void initState() {
    super.initState();
    ref.read(chatAppearanceProvider(widget.username).future).then((a) {
      if (mounted) setState(() => _look = _saved = a);
    });
  }

  void _react(String what) => setState(() {
        _hop++;
        _act = switch (what) {
          'color' => FoxyAct.love,
          'wallpaper' => FoxyAct.happy,
          'effect' => FoxyAct.cheer,
          'theme' => FoxyAct.hooray,
          'saved' => FoxyAct.hooray,
          _ => FoxyAct.idle,
        };
      });

  Future<void> _save() async {
    final look = _look;
    if (look == null || _saving) return;
    setState(() => _saving = true);
    try {
      final me = ref.read(authControllerProvider).valueOrNull?.id ?? '';
      final api = ref.read(appearanceApiProvider);
      final synced = await saveLook(chatLookKey(me, widget.username), look,
          (a) => api.saveChat(widget.username, a));
      _saved = look;
      ref.invalidate(chatAppearanceProvider(widget.username));
      if (!synced && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Theme saved on this phone. The other person sees it once the Phlio server is updated.')));
      }
      HapticFeedback.mediumImpact();
      _react('saved');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _act = FoxyAct.oops);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not change the chat theme. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = _look;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.86,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: PhlioColors.border,
                  borderRadius: BorderRadius.circular(4)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Chat theme', style: PhlioTypography.title),
                      Text('You and @${widget.username} both see it',
                          style: PhlioTypography.caption),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: look == null || look == _saved || _saving
                      ? null
                      : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ]),
            ),
            Expanded(
              child: look == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: SizedBox(
                            height: 190,
                            child: AppearanceBackdrop(
                              appearance: look,
                              decorate: false,
                              fallback: PhlioColors.roomsChat,
                              child: Stack(children: [
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _bubble('Hey! 👋', mine: false),
                                      _bubble('Loving this new theme ✨',
                                          mine: true),
                                      _bubble('Same, it looks so good',
                                          mine: false),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  right: 4,
                                  bottom: -6,
                                  child: FoxyPuppet(
                                      act: _act,
                                      size: 104,
                                      hopSignal: _hop,
                                      entrance: true),
                                ),
                              ]),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        AppearanceEditor(
                          value: look,
                          onChanged: (a) => setState(() => _look = a),
                          onInteract: _react,
                          onPickPhoto: () => pickAndUploadWallpaper(
                              context, ref.read(appearanceApiProvider)),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(String text, {required bool mine}) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: 8, right: mine ? 90 : 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: mine ? PhlioColors.sunsetGradient : null,
          color: mine ? null : PhlioColors.surfaceElevated.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(text,
            style: PhlioTypography.body.copyWith(
                color: mine ? PhlioColors.textOnBrand : PhlioColors.textPrimary)),
      ),
    );
  }
}
