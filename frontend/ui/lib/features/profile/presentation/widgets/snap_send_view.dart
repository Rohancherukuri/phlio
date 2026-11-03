// Snap "Send to…" — what you see right after taking a snap (Locket-style,
// in Phlio colours).
//
//   ┌ Send to…                         ⤓ ┐   save to your gallery
//   │ ╭──────────────────────────────╮    │
//   │ │   your photo / video          │    │   filter + decorations, drag them
//   │ │       ( Add a message )       │    │   swipe the pill: message · music ·
//   │ ╰──────────────────────────────╯    │   location · time · image · GIF · sticker
//   │            ● ● ● ● ● ● ●            │
//   │    ✕          (  ➤  )         Aa✨  │   discard · send · captions sheet
//   │ (All) (★Close) (Lists…) (+New) (Alex)… │   who gets it (Phlio gradient ring)
//   └─────────────────────────────────────┘
//
// "All" sends to your friends. Close friends and your own lists (made with
// "New list", kept on the server: /social/snap-lists) send to their members;
// long-press a list to edit or delete it. Picking people sends only to them.
// Everyone picked must follow you, as for close friends.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/widgets/foxy_stickers.dart';
import '../../../../shared/giphy/giphy_picker.dart';
import '../../../../shared/media/phlio_look_data.dart';
import '../../../../shared/media/phlio_look_view.dart';
import '../../../../shared/moments/stickers/sticker_model.dart';
import '../../../../shared/moments/stickers/sticker_tray.dart' show askText, pickMomentSong;
import 'snap_audience.dart';
import 'snap_decorations.dart';

/// The swipeable pill under the photo: one quick add per page.
const _pills = <(String, IconData?, String)>[
  ('message', null, 'Add a message'),
  ('music', Icons.music_note_rounded, 'Add Music'),
  ('location', Icons.location_on_rounded, 'Add Location'),
  ('clock', Icons.schedule_rounded, 'Add Time'),
  ('image', Icons.add_photo_alternate_rounded, 'Add Image'),
  ('gif', Icons.gif_box_rounded, 'Add GIF'),
  ('stickers', Icons.emoji_emotions_rounded, 'Add Sticker'),
];

/// Uploads a picked image for an image decoration; returns its /media URL.
Future<String> uploadSnapImage(String path) async {
  final res = await getIt<ApiClient>().dio.post('/social/composer/upload',
      data: FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: path.split(Platform.pathSeparator).last)}));
  return '${(res.data as Map)['url']}';
}

/// Picks a gallery image and returns it as a snap decoration.
Future<MomentSticker?> pickSnapImage(BuildContext context) async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1080, imageQuality: 88);
  if (picked == null) return null;
  final url = await uploadSnapImage(picked.path);
  return MomentSticker(StickerType.photo, {'url': url, 'shape': 'rounded'}, scale: .8);
}

class SnapSendView extends StatefulWidget {
  const SnapSendView({
    required this.file,
    required this.video,
    required this.filter,
    required this.decorations,
    required this.caption,
    required this.audience,
    required this.busy,
    required this.media,
    required this.onChanged,
    required this.onAudience,
    required this.onDiscard,
    required this.onSend,
    super.key,
  });

  final XFile file;
  final bool video;
  final String filter;
  final List<MomentSticker> decorations;
  final TextEditingController caption;
  final SnapAudience audience;
  final bool busy;

  /// The photo / video preview (filter applied).
  final Widget media;
  final VoidCallback onChanged, onDiscard, onSend;
  final ValueChanged<SnapAudience> onAudience;

  @override
  State<SnapSendView> createState() => _SnapSendViewState();
}

class _SnapSendViewState extends State<SnapSendView> {
  final _pill = PageController();
  final _canvas = GlobalKey();
  int _page = 0;
  bool _working = false;
  /// Your lists (Close friends first) and which one is selected.
  List<Map> _lists = const [];
  String? _list;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  Future<void> _loadLists() async {
    try {
      final res = await getIt<ApiClient>().dio.get('/social/snap-lists');
      if (mounted) setState(() => _lists = [for (final l in res.data as List) l as Map]);
    } catch (_) {}
  }

  late final Future<List<Map>> _followers = getIt<ApiClient>()
      .dio
      .get('/social/connections')
      .then((r) => [for (final p in ((r.data as Map)['followers'] as List? ?? const [])) p as Map])
      .catchError((_) => <Map>[]);

  @override
  void dispose() {
    _pill.dispose();
    super.dispose();
  }

  void _say(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  void _add(MomentSticker? s) {
    if (s == null || !mounted) return;
    if (widget.decorations.length >= 20) return _say('You can add up to 20 decorations.');
    if (s.type == StickerType.music) widget.decorations.removeWhere((d) => d.type == StickerType.music);
    widget.decorations.add(s);
    widget.onChanged();
  }

  /// The pill's action for [id].
  Future<void> _quick(String id) async {
    if (widget.busy || _working) return;
    HapticFeedback.selectionClick();
    setState(() => _working = true);
    try {
      switch (id) {
        case 'message':
          final text = await askText(context, 'Add a message', 'Say something…', initial: widget.caption.text, allowEmpty: true);
          if (text != null) {
            widget.caption.text = text.trim();
            widget.onChanged();
          }
        case 'music':
          final song = await pickMomentSong(context);
          if (song != null) _add(MomentSticker(StickerType.music, song, y: .2));
        case 'location':
          final text = await askText(context, 'Location', 'Add a place name');
          if (text != null && text.trim().isNotEmpty) _add(MomentSticker(StickerType.location, {'text': text.trim()}));
        case 'clock':
          _add(MomentSticker(StickerType.clock, {'time': TimeOfDay.now().format(context)}, y: .3));
        case 'image':
          _add(await pickSnapImage(context));
        case 'gif':
          final gif = await showGiphyPicker(context);
          if (gif != null) _add(MomentSticker(StickerType.gif, {'url': gif.url, 'title': gif.title}));
        case 'stickers':
          final sticker = await showFoxyStickerSheet(context);
          if (sticker != null) _add(MomentSticker(StickerType.foxy, {'sticker': sticker}));
      }
    } catch (_) {
      _say('Couldn\'t add that. Try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Aa✨: the full captions sheet (text styles, music, location, image,
  /// GIF, stickers, time, decorative captions).
  Future<void> _captions() async {
    if (widget.busy || _working) return;
    setState(() => _working = true);
    try {
      _add(await pickSnapDecoration(context));
    } catch (_) {
      _say('Couldn\'t add that. Try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// ⤓ Saves the snap: photos as you see them (filter + decorations),
  /// videos as recorded.
  Future<void> _save() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) return _say('Allow photo access to save.');
      final title = 'phlio_snap_${DateTime.now().millisecondsSinceEpoch}';
      if (widget.video) {
        await PhotoManager.editor.saveVideo(File(widget.file.path), title: title);
      } else {
        final boundary = _canvas.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final file = File('${(await getTemporaryDirectory()).path}/$title.png');
        await file.writeAsBytes(png!.buffer.asUint8List());
        await PhotoManager.editor.saveImageWithPath(file.path, title: title);
      }
      HapticFeedback.lightImpact();
      _say('Saved to your gallery');
    } catch (_) {
      _say('Could not save to your gallery.');
    }
  }

  // -- recipients -------------------------------------------------------------------

  bool get _all => widget.audience.mode != 'close_friends';

  /// Sends to a list's members (an empty list opens it for editing).
  Future<void> _pickList(Map list) async {
    final ids = [for (final id in list['member_ids'] as List? ?? const []) '$id'];
    if (ids.isEmpty) return _editList(list);
    HapticFeedback.selectionClick();
    setState(() => _list = '${list['id']}');
    widget.onAudience(SnapAudience(mode: 'close_friends', recipients: ids));
  }

  /// Create (list == null), or edit a list's name and members.
  Future<void> _editList([Map? list]) async {
    final followers = await _followers;
    if (!mounted) return;
    final saved = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PhlioColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _ListEditor(list: list, followers: followers),
    );
    if (saved == null || !mounted) return;
    await _loadLists();
    if (saved['deleted'] == true) {
      if (_list == '${list?['id']}') {
        setState(() => _list = null);
        widget.onAudience(const SnapAudience());
      }
      return;
    }
    final fresh = _lists.where((l) => l['id'] == saved['id']).firstOrNull ?? saved;
    if ((fresh['member_ids'] as List? ?? const []).isNotEmpty) await _pickList(fresh);
  }

  void _toggle(String id) {
    _list = null;
    final picked = {...widget.audience.recipients};
    picked.contains(id) ? picked.remove(id) : picked.add(id);
    widget.onAudience(picked.isEmpty
        ? const SnapAudience()
        : SnapAudience(mode: 'close_friends', recipients: picked.toList()));
  }

  Widget _person({required String label, required bool on, required Widget avatar, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: widget.busy ? null : onTap,
        child: SizedBox(
          width: 78,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 62,
              height: 62,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: on ? PhlioColors.brandGradient : null,
                color: on ? null : Colors.white12,
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                child: ClipOval(child: avatar),
              ),
            ),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: on ? PhlioColors.brandPeach : Colors.white60, fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
        ),
      );

  Widget _recipients() => SizedBox(
        height: 96,
        child: FutureBuilder<List<Map>>(
          future: _followers,
          builder: (_, snap) {
            final people = snap.data ?? const <Map>[];
            return ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _person(
                  label: 'All',
                  on: _all,
                  avatar: const ColoredBox(
                      color: Color(0xFF3A3A3C), child: Center(child: Icon(Icons.people_alt_rounded, color: Colors.white))),
                  onTap: () {
                    setState(() => _list = null);
                    widget.onAudience(const SnapAudience());
                  },
                ),
                // Close friends and your lists, then "New list".
                for (final l in _lists)
                  GestureDetector(
                    onLongPress: widget.busy ? null : () => _editList(l),
                    child: _person(
                      label: '${l['name']}',
                      on: _list == '${l['id']}',
                      avatar: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: l['close'] == true
                              ? const LinearGradient(colors: [Color(0xFF2FBF71), Color(0xFF68D7CD)])
                              : const LinearGradient(colors: [Color(0xFF3A3A3C), Color(0xFF2A2A2E)]),
                        ),
                        child: Center(
                          child: l['close'] == true
                              ? const Icon(Icons.star_rounded, color: Colors.white, size: 30)
                              : Text(
                                  '${(l['member_ids'] as List? ?? const []).length}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                                ),
                        ),
                      ),
                      onTap: () => _pickList(l),
                    ),
                  ),
                _person(
                  label: 'New list',
                  on: false,
                  avatar: const ColoredBox(
                      color: Color(0xFF2A2A2E), child: Center(child: Icon(Icons.add_rounded, color: Colors.white, size: 30))),
                  onTap: () => _editList(),
                ),
                for (final p in people)
                  _person(
                    label: '${p['display_name'] ?? p['username'] ?? ''}'.split(' ').first,
                    on: _list == null && widget.audience.recipients.contains('${p['id']}'),
                    avatar: _avatar(p),
                    onTap: () => _toggle('${p['id']}'),
                  ),
              ],
            );
          },
        ),
      );

  Widget _avatar(Map p) {
    final url = p['avatar_url'] as String?;
    final name = '${p['display_name'] ?? p['username'] ?? '?'}';
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
    return ColoredBox(
      color: const Color(0xFF3A3A3C),
      child: url == null || url.isEmpty
          ? Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)))
          : Image.network(AppConfig.mediaUrl(url), fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(child: Text(initials, style: const TextStyle(color: Colors.white)))),
    );
  }

  // -- layout ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final message = widget.caption.text.trim();
    return SafeArea(
      child: Column(children: [
        // Send to…  ⤓
        SizedBox(
          height: 56,
          child: Row(children: [
            const SizedBox(width: 56),
            const Expanded(
              child: Text('Send to…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            IconButton(
              tooltip: 'Save to gallery',
              onPressed: widget.busy ? null : _save,
              icon: const Icon(Icons.download_rounded, color: Colors.white70, size: 28),
            ),
            const SizedBox(width: 4),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (_, box) {
            final side = box.maxWidth < box.maxHeight - 60 ? box.maxWidth : box.maxHeight - 60;
            return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(
                width: side,
                height: side,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(side * .14),
                  child: Stack(fit: StackFit.expand, children: [
                    RepaintBoundary(
                      key: _canvas,
                      child: ColoredBox(
                        color: const Color(0xFF1C1C1E),
                        child: SnapDecorationCanvas(layers: widget.decorations, onChanged: widget.onChanged, child: widget.media),
                      ),
                    ),
                    // The swipeable pill: message, music, location, time, image, GIF, sticker.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: side * .07,
                      height: 52,
                      child: PageView.builder(
                        controller: _pill,
                        itemCount: _pills.length,
                        onPageChanged: (i) {
                          HapticFeedback.selectionClick();
                          setState(() => _page = i);
                        },
                        itemBuilder: (_, i) {
                          final (id, icon, label) = _pills[i];
                          final text = id == 'message' && message.isNotEmpty ? message : label;
                          return Center(
                            child: GestureDetector(
                              onTap: () => _quick(id),
                              child: Container(
                                constraints: BoxConstraints(maxWidth: side * .86),
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .55),
                                  borderRadius: BorderRadius.circular(26),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  if (icon != null) ...[
                                    ShaderMask(
                                      shaderCallback: (r) => PhlioColors.brandGradient.createShader(r),
                                      child: Icon(icon, color: Colors.white, size: 24),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: Text(text,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
                                  ),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (_working) const Center(child: CircularProgressIndicator()),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              // Page dots (the last ones shrink, like the reference).
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < _pills.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: i >= _pills.length - 2 && i != _page ? (i == _pills.length - 1 ? 5 : 7) : 9,
                    height: i >= _pills.length - 2 && i != _page ? (i == _pills.length - 1 ? 5 : 7) : 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page ? Colors.white : Colors.white30,
                    ),
                  ),
              ]),
            ]);
          }),
        ),
        const SizedBox(height: 22),
        // ✕   ➤   Aa✨
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          IconButton(
            tooltip: 'Discard',
            iconSize: 40,
            onPressed: widget.busy ? null : widget.onDiscard,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          PhlioSendButton(busy: widget.busy, onTap: widget.onSend),
          IconButton(
            tooltip: 'Captions',
            onPressed: widget.busy ? null : _captions,
            icon: const _CaptionsIcon(),
          ),
        ]),
        const SizedBox(height: 22),
        _recipients(),
        const SizedBox(height: 8),
      ]),
    );
  }
}

/// "Aa" in a rounded outline with a sparkle (the captions button).
class _CaptionsIcon extends StatelessWidget {
  const _CaptionsIcon();
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 52,
        height: 46,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: 44,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Aa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
            ),
          ),
          const Positioned(right: 0, top: 0, child: Icon(Icons.auto_awesome, color: Colors.white, size: 18)),
        ]),
      );
}

/// The snap with its filter, for [SnapSendView.media].
Widget snapMediaPreview({required String path, required bool video, required String filter, required Widget videoPlayer}) {
  if (video) return videoPlayer;
  final (look, effect) = splitMomentFilter(filter);
  return PhlioLook(look: look, effect: effect, child: Image.file(File(path), fit: BoxFit.cover));
}


/// The Phlio send button: a sunset-gradient orb with a soft glow and a
/// white paper plane; it dips when pressed and spins a ring while sending.
class PhlioSendButton extends StatefulWidget {
  const PhlioSendButton({required this.busy, required this.onTap, this.size = 96, super.key});
  final bool busy;
  final VoidCallback onTap;
  final double size;
  @override
  State<PhlioSendButton> createState() => _PhlioSendButtonState();
}

class _PhlioSendButtonState extends State<PhlioSendButton> with SingleTickerProviderStateMixin {
  bool _down = false;
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(PhlioSendButton old) {
    super.didUpdateWidget(old);
    widget.busy ? _spin.repeat() : _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Semantics(
      button: true,
      label: 'Send snap',
      child: GestureDetector(
        onTapDown: widget.busy ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.busy
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onTap();
              },
        child: AnimatedScale(
          scale: _down ? .9 : 1,
          duration: const Duration(milliseconds: 120),
          child: SizedBox(
            width: s,
            height: s,
            child: Stack(alignment: Alignment.center, children: [
              // Glow
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: PhlioColors.brandGradient,
                  boxShadow: [
                    BoxShadow(color: PhlioColors.brandPink.withValues(alpha: .45), blurRadius: 26, spreadRadius: 1),
                    BoxShadow(color: PhlioColors.brandViolet.withValues(alpha: .35), blurRadius: 40, offset: const Offset(-6, 6)),
                  ],
                ),
              ),
              // Inner sheen
              Container(
                width: s * .86,
                height: s * .86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-.4, -.5),
                    colors: [Colors.white.withValues(alpha: .28), Colors.transparent],
                  ),
                ),
              ),
              if (widget.busy)
                RotationTransition(
                  turns: _spin,
                  child: SizedBox(
                    width: s * .62,
                    height: s * .62,
                    child: const CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                  ),
                )
              else
                CustomPaint(size: Size.square(s * .44), painter: _PlanePainter()),
            ]),
          ),
        ),
      ),
    );
  }
}

/// An outlined paper plane, pointing up-right.
class _PlanePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .09
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final body = Path()
      ..moveTo(w * .92, h * .08) // nose
      ..lineTo(w * .06, h * .44) // left wing tip
      ..lineTo(w * .44, h * .56) // fold
      ..lineTo(w * .56, h * .94) // tail
      ..close();
    canvas.drawPath(body, paint);
    canvas.drawLine(Offset(w * .44, h * .56), Offset(w * .92, h * .08), paint);
  }

  @override
  bool shouldRepaint(_PlanePainter old) => false;
}

/// Create or edit a snap list: name and members (people who follow you).
class _ListEditor extends StatefulWidget {
  const _ListEditor({required this.list, required this.followers});
  final Map? list;
  final List<Map> followers;
  @override
  State<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<_ListEditor> {
  late final _name = TextEditingController(text: widget.list?['name'] as String? ?? '');
  late final Set<String> _members = {for (final id in widget.list?['member_ids'] as List? ?? const []) '$id'};
  String _search = '';
  bool _busy = false;

  bool get _close => widget.list?['close'] == true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (!_close && name.isEmpty) return _say('Give your list a name.');
    setState(() => _busy = true);
    try {
      final dio = getIt<ApiClient>().dio;
      final body = {if (!_close) 'name': name, 'members': _members.toList()};
      final res = widget.list == null
          ? await dio.post('/social/snap-lists', data: body)
          : await dio.put('/social/snap-lists/${widget.list!['id']}', data: body);
      if (mounted) Navigator.pop(context, res.data as Map);
    } catch (_) {
      _say('Couldn\'t save the list. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await getIt<ApiClient>().dio.delete('/social/snap-lists/${widget.list!['id']}');
      if (mounted) Navigator.pop(context, {'deleted': true});
    } catch (_) {
      _say('Couldn\'t delete the list.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String t) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t)));

  @override
  Widget build(BuildContext context) {
    final people = widget.followers
        .where((p) => '${p['username']} ${p['display_name']}'.toLowerCase().contains(_search))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
              child: Container(
                  width: 40, height: 5, decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text(
                _close ? 'Close friends' : widget.list == null ? 'New list' : 'Edit list',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
            if (widget.list != null)
              TextButton(
                onPressed: _busy ? null : _delete,
                child: Text(_close ? 'Clear' : 'Delete', style: const TextStyle(color: PhlioColors.danger)),
              ),
          ]),
          if (!_close) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              maxLength: 40,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: 'List name (e.g. Roomies)', counterText: ''),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search people who follow you'),
          ),
          const SizedBox(height: 6),
          Text('${_members.length} selected', style: const TextStyle(color: Colors.white54)),
          Expanded(
            child: people.isEmpty
                ? const Center(
                    child: Text('Only people who follow you can be in a list.',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)))
                : ListView(children: [
                    for (final p in people)
                      CheckboxListTile(
                        value: _members.contains('${p['id']}'),
                        activeColor: PhlioColors.brandPink,
                        onChanged: (v) => setState(() => v == true ? _members.add('${p['id']}') : _members.remove('${p['id']}')),
                        title: Text('${p['display_name'] ?? p['username']}', style: const TextStyle(color: Colors.white)),
                        subtitle: Text('@${p['username']}', style: const TextStyle(color: Colors.white54)),
                        secondary: CircleAvatar(
                          backgroundColor: const Color(0xFF3A3A3C),
                          backgroundImage: (p['avatar_url'] as String?)?.isNotEmpty == true
                              ? NetworkImage(AppConfig.mediaUrl(p['avatar_url'] as String))
                              : null,
                        ),
                      ),
                  ]),
          ),
          DecoratedBox(
            decoration: BoxDecoration(gradient: PhlioColors.brandGradient, borderRadius: BorderRadius.circular(28)),
            child: TextButton(
              onPressed: _busy ? null : _save,
              style: TextButton.styleFrom(foregroundColor: PhlioColors.textOnBrand, padding: const EdgeInsets.all(16)),
              child: Text(_busy ? 'Saving…' : 'Save', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          ),
        ]),
      ),
    );
  }
}
