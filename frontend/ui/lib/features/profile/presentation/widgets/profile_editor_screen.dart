// Edit profile: name, bio, profile song and the profile's look
// (background colour, wallpaper, animated effects), with a live preview
// and Foxy reacting to every change.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/foxy_puppet.dart';
import '../../../../shared/appearance/appearance.dart';
import '../../../../shared/appearance/appearance_editor.dart';
import '../../../../shared/content/content_surface.dart' show catalogProvider;
import '../../../../shared/music/stream_song_picker.dart';
import '../../../authentication/domain/entities/user_entity.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../controllers/avatar_controller.dart';

/// Opens the editor. [songTitle] is the current profile song;
/// [onPickSong] runs the profile's song picker and returns the new title.
Future<void> openProfileEditor(
  BuildContext context, {
  required String songTitle,
  required Future<String?> Function(String source) onPickSong,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) =>
          ProfileEditorScreen(songTitle: songTitle, onPickSong: onPickSong),
      transitionsBuilder: (_, animation, __, child) {
        final curve =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                .animate(curve),
            child: child,
          ),
        );
      },
    ),
  );
}

class ProfileEditorScreen extends ConsumerStatefulWidget {
  const ProfileEditorScreen(
      {required this.songTitle, required this.onPickSong, super.key});

  final String songTitle;
  final Future<String?> Function(String source) onPickSong;

  @override
  ConsumerState<ProfileEditorScreen> createState() =>
      _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends ConsumerState<ProfileEditorScreen> {
  late final UserEntity _user = ref.read(authControllerProvider).valueOrNull!;
  late final _name = TextEditingController(text: _user.fullName);
  late final _bio = TextEditingController(text: _user.bio);
  late String _song = widget.songTitle;
  Appearance _look = Appearance.plain;
  Appearance _saved = Appearance.plain;
  bool _loaded = false, _saving = false;

  // Foxy's reaction: an act, settling back to idle after a moment.
  FoxyAct _act = FoxyAct.wave;
  bool _talking = false;
  int _hop = 0;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    ref.read(myAppearanceProvider.future).then((a) {
      if (!mounted) return;
      setState(() {
        _look = _saved = a;
        _loaded = true;
      });
    });
    _bio.addListener(() => _react('type'));
    _name.addListener(() => _react('type'));
    _react('hello');
  }

  @override
  void dispose() {
    _settle?.cancel();
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _loaded &&
      (_look != _saved ||
          _bio.text.trim() != _user.bio ||
          _name.text.trim() != _user.fullName);

  void _react(String what) {
    final act = switch (what) {
      'hello' => FoxyAct.wave,
      'type' => FoxyAct.talk,
      'color' => FoxyAct.love,
      'wallpaper' => FoxyAct.happy,
      'effect' => FoxyAct.cheer,
      'theme' => FoxyAct.hooray,
      'song' => FoxyAct.chill,
      'saved' => FoxyAct.hooray,
      'oops' => FoxyAct.oops,
      _ => FoxyAct.idle,
    };
    _settle?.cancel();
    setState(() {
      if (act != _act) _hop++;
      _act = act;
      _talking = what == 'type';
    });
    _settle = Timer(Duration(milliseconds: what == 'type' ? 900 : 2200), () {
      if (mounted) {
        setState(() {
          _act = FoxyAct.idle;
          _talking = false;
        });
      }
    });
  }

  Future<void> _pickSong() async {
    final source = await showSongSourceSheet(context);
    if (source == null || !mounted) return;
    final title = await widget.onPickSong(source);
    if (title != null && mounted) {
      setState(() => _song = title);
      _react('song');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final api = ref.read(appearanceApiProvider);
    try {
      final bio = _bio.text.trim();
      final name = _name.text.trim();
      if (bio != _user.bio || (name.isNotEmpty && name != _user.fullName)) {
        final json = await api.saveProfileText(
            bio: bio, fullName: name.isEmpty ? null : name);
        ref.read(authControllerProvider.notifier).activateAccount(UserEntity(
              id: _user.id,
              username: _user.username,
              fullName: json['full_name'] as String? ?? _user.fullName,
              email: _user.email,
              bio: json['bio'] as String? ?? bio,
              interests: _user.interests,
              isVerified: _user.isVerified,
              createdAt: _user.createdAt,
              avatarUrl: _user.avatarUrl,
              dateOfBirth: _user.dateOfBirth,
              phoneNumber: _user.phoneNumber,
              country: _user.country,
            ));
      }
      var synced = true;
      if (_look != _saved) {
        // Saved on this device first, so the profile shows it right away.
        synced = await saveLook(myLookKey(_user.id), _look, api.saveMine);
        _saved = _look;
        ref.invalidate(myAppearanceProvider);
        ref.invalidate(userAppearanceProvider(_user.username));
      }
      if (!synced && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Saved on this phone. It syncs to your account once the Phlio server is updated.')));
      }
      HapticFeedback.mediumImpact();
      _react('saved');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _react('oops');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save your profile. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits to the profile will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep editing')),
          TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Discard')),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // Keep the Phlio Stream catalog warm so its picker opens with songs.
    ref.listen(catalogProvider('stream'), (_, __) {});
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _look = _saved; // nothing dirty any more
          _bio.text = _user.bio;
          _name.text = _user.fullName;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: PhlioColors.background,
        appBar: AppBar(
          title: const Text('Edit profile'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: AnimatedOpacity(
                opacity: _dirty || _saving ? 1 : 0.45,
                duration: const Duration(milliseconds: 200),
                child: _SaveButton(
                    saving: _saving, onTap: _dirty ? _save : null),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            _preview(),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Name', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bio,
              maxLength: 150,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: 'Bio', hintText: 'Tell people about you'),
            ),
            const SizedBox(height: 4),
            _songTile(),
            const SizedBox(height: 22),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              AppearanceEditor(
                value: _look,
                onChanged: (a) => setState(() => _look = a),
                onInteract: _react,
                onPickPhoto: () => pickAndUploadWallpaper(
                    context, ref.read(appearanceApiProvider)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    final name = _name.text.trim().isEmpty ? _user.fullName : _name.text.trim();
    final bio = _bio.text.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 236,
        child: AppearanceBackdrop(
          appearance: _look,
          fallback: PhlioColors.surface,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 120, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MeAvatar(name: name, size: 62),
                    const SizedBox(height: 10),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PhlioTypography.headline),
                    Text('@${_user.username}',
                        style: PhlioTypography.caption
                            .copyWith(color: PhlioColors.textSecondary)),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Text(
                        bio.isEmpty ? 'Your bio shows here' : bio,
                        key: ValueKey(bio),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: PhlioTypography.body.copyWith(
                            color: bio.isEmpty
                                ? PhlioColors.textMuted
                                : PhlioColors.textPrimary),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.music_note_rounded,
                            size: 14, color: PhlioColors.brandOrange),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(_song,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PhlioTypography.caption
                                  .copyWith(color: Colors.white)),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: -6,
                bottom: -8,
                child: FoxyPuppet(
                  act: _act,
                  size: 150,
                  talking: _talking,
                  hopSignal: _hop,
                  entrance: true,
                  tapToHop: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _songTile() {
    return Material(
      color: PhlioColors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _pickSong,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                  gradient: PhlioColors.sunsetGradient, shape: BoxShape.circle),
              child: const Icon(Icons.music_note_rounded,
                  size: 18, color: PhlioColors.textOnBrand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Profile song', style: PhlioTypography.caption),
                  Text(_song,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhlioTypography.bodyStrong),
                ],
              ),
            ),
            Text('Change',
                style: PhlioTypography.label
                    .copyWith(color: PhlioColors.brandOrange)),
          ]),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saving, required this.onTap});
  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: saving ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: PhlioColors.sunsetGradient,
          borderRadius: BorderRadius.circular(999),
        ),
        child: saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: PhlioColors.textOnBrand))
            : Text('Save',
                style: PhlioTypography.bodyStrong
                    .copyWith(color: PhlioColors.textOnBrand)),
      ),
    );
  }
}
