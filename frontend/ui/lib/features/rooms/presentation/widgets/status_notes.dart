// Notes above the DM inbox, like Instagram Notes.
//
// A note is a short thought (60 characters) with, optionally, a song from
// Phlio Stream, a GIF from GIPHY, a place, a bubble colour and an animated
// effect (Bubble Editor). It sits in a bubble on your avatar for 24 hours;
// your followers (or only people you follow back) see it at the top of
// their chats, can like it and reply in DMs.
//
// Widgets: NoteBubble / NoteTile (note_bubble.dart), BubbleEditorScreen
// (note_bubble_editor.dart). Backend: /api/v1/social/notes.

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart' show DioException;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../design_system/colors.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../shared/giphy/giphy_picker.dart';
import '../../../../shared/location/location_service.dart';
import '../../../../shared/location/places_api.dart';
import '../../../../shared/location/device_places.dart';
import '../../../../shared/location/google_places.dart';
import '../../../../shared/location/server_places.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../profile/presentation/controllers/avatar_controller.dart';
import '../../data/datasources/messaging_api.dart';
import 'note_bubble.dart';
import 'note_bubble_editor.dart';
import 'note_music_picker.dart';
import 'note_place_picker.dart';
import 'package:phlio/core/network/media_cache.dart';

/// `(mine, items)` from the server; refreshed when the inbox refreshes.
final statusNotesProvider = FutureProvider.autoDispose<(Map?, List<Map>)>((ref) async {
  ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
  final res = await getIt<ApiClient>().dio.get<dynamic>('/social/notes');
  final body = Map<String, dynamic>.from(res.data as Map);
  return (
    body['mine'] as Map?,
    [for (final n in (body['items'] as List? ?? const [])) Map<String, dynamic>.from(n as Map)],
  );
});

String _bubbleLine(Map note) {
  final text = '${note['text'] ?? ''}'.trim();
  if (text.isNotEmpty) return text;
  final music = note['music'] as Map?;
  if (music != null) return '${music['title']}';
  final place = note['location'] as Map?;
  if (place != null) return '${place['name']}';
  return note['gif'] != null ? 'GIF' : '';
}

/// "📍 KPHB Colony" or, for your own note without a place, "Location off".
Widget _placeLine(Map? note, {required bool own}) {
  final place = note?['location'] as Map?;
  if (place == null && !own) return const SizedBox.shrink();
  final off = place == null;
  return Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
    Icon(off ? Icons.location_off_rounded : Icons.location_on_rounded,
        size: 12, color: off ? const Color(0xFFFF4D67) : const Color(0xFF3897F0)),
    const SizedBox(width: 2),
    Flexible(
      child: Text(off ? 'Location off' : '${place['name']}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: PhlioColors.textPrimary)),
    ),
  ]);
}

/// The notes row for the top of the inbox: your note, others' notes, then
/// [trailing] (recent chats without notes).
class NotesStrip extends ConsumerWidget {
  const NotesStrip({super.key, this.trailing = const []});

  final List<Widget> trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    final data = ref.watch(statusNotesProvider).valueOrNull;
    final mine = data?.$1;
    final items = data?.$2 ?? const <Map>[];
    return SizedBox(
      height: 176,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          NoteTile(
            avatar: MeAvatar(name: me?.username ?? 'You', size: NoteTile.avatarSize),
            note: mine,
            placeholder: 'Note...',
            caption: 'Your note',
            subcaption: _placeLine(mine, own: true),
            onTap: () => mine == null ? openNoteComposer(context) : showNoteSheet(context, mine, own: true),
          ),
          for (final note in items)
            NoteTile(
              avatar: PhlioAvatar(
                name: '${(note['author'] as Map)['display_name'] ?? ''}',
                imageUrl: (note['author'] as Map)['avatar_url'] as String?,
                size: NoteTile.avatarSize,
              ),
              note: note,
              caption: '${(note['author'] as Map)['display_name'] ?? (note['author'] as Map)['username']}',
              subcaption: _placeLine(note, own: false),
              onTap: () => showNoteSheet(context, note),
            ),
          // Plain contacts line up with the avatars under the bubbles.
          for (final t in trailing) Padding(padding: const EdgeInsets.only(top: 51), child: t),
        ],
      ),
    );
  }
}

/// Opens the note composer (pre-filled with [existing] when editing).
Future<void> openNoteComposer(BuildContext context, {Map? existing}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      builder: (_) => NoteComposerScreen(existing: existing),
      fullscreenDialog: true,
    ));

/// A note up close: bubble (with its effect), song preview, place, like, reply.
Future<void> showNoteSheet(BuildContext context, Map note, {bool own = false}) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (_) => _NoteSheet(note: note, own: own),
    );

class _NoteSheet extends ConsumerStatefulWidget {
  const _NoteSheet({required this.note, required this.own});
  final Map note;
  final bool own;

  @override
  ConsumerState<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends ConsumerState<_NoteSheet> {
  final _player = AudioPlayer();
  final _reply = TextEditingController();
  late bool liked = widget.note['liked_by_me'] == true;
  bool playing = false, sending = false;

  double get _clipStart => ((widget.note['music'] as Map?)?['clip_start'] as num?)?.toDouble() ?? 0;
  double get _clipLength => ((widget.note['music'] as Map?)?['clip_length'] as num?)?.toDouble() ?? 30;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => playing = false);
    });
    // Play only the chosen clip, on a loop.
    _player.onPositionChanged.listen((p) {
      if (playing && p.inMilliseconds / 1000 >= _clipStart + _clipLength) {
        _player.seek(Duration(milliseconds: (_clipStart * 1000).round()));
      }
    });
    // Like Instagram, a note's song starts playing when you open it.
    if (widget.note['music'] != null && !_spotify) _togglePlay();
  }

  @override
  void dispose() {
    _player.dispose();
    _reply.dispose();
    super.dispose();
  }

  bool get _spotify => (widget.note['music'] as Map?)?['source'] == 'spotify';

  Future<void> _togglePlay() async {
    final music = widget.note['music'] as Map?;
    if (music == null) return;
    if (_spotify) {
      // Spotify audio stays in Spotify: open the track there.
      await launchUrl(Uri.parse('${music['url']}'), mode: LaunchMode.externalApplication);
      return;
    }
    try {
      if (playing) {
        await _player.pause();
      } else {
        await _player.play(UrlSource(AppConfig.mediaUrl('${music['url']}')),
            position: Duration(milliseconds: (_clipStart * 1000).round()));
      }
      if (mounted) setState(() => playing = !playing);
    } catch (_) {}
  }

  String get _author => '${(widget.note['author'] as Map)['id']}';

  Future<void> _like() async {
    HapticFeedback.selectionClick();
    setState(() => liked = !liked);
    try {
      final dio = getIt<ApiClient>().dio;
      liked
          ? await dio.put<dynamic>('/social/notes/$_author/like')
          : await dio.delete<dynamic>('/social/notes/$_author/like');
    } catch (_) {
      if (mounted) setState(() => liked = !liked);
    }
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await ref.read(messagingApiProvider).send(_author, 'Replied to your note “${_bubbleLine(widget.note)}”\n$text');
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply sent')));
    } catch (_) {
      if (mounted) {
        setState(() => sending = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send. Try again.')));
      }
    }
  }

  Future<void> _delete() async {
    try {
      await getIt<ApiClient>().dio.delete<dynamic>('/social/notes/mine');
      ref.invalidate(statusNotesProvider);
      if (mounted) Navigator.pop(context);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final author = note['author'] as Map;
    final music = note['music'] as Map?;
    final place = note['location'] as Map?;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 190,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
            Positioned(
              top: 96,
              child: PhlioAvatar(
                  name: '${author['display_name'] ?? ''}', imageUrl: author['avatar_url'] as String?, size: 90),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 110,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: NoteBubble(note: note, large: true, loopEffect: true),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(widget.own ? 'Your note' : '${author['display_name'] ?? author['username']}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        if (music != null)
          Card(
            margin: const EdgeInsets.only(top: 14),
            child: ListTile(
              leading: music['image_url'] != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(cacheManager: PhlioMediaCache.images, 
                          imageUrl: AppConfig.mediaUrl('${music['image_url']}'), width: 44, height: 44, fit: BoxFit.cover))
                  : const Icon(Icons.music_note_rounded),
              title: Text('${music['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${music['artist'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: _spotify
                  ? TextButton.icon(
                      onPressed: _togglePlay,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16, color: kSpotifyGreen),
                      label: const Text('Spotify', style: TextStyle(color: kSpotifyGreen)),
                    )
                  : IconButton(
                      tooltip: playing ? 'Pause' : 'Play',
                      icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, size: 34),
                      onPressed: _togglePlay,
                    ),
            ),
          ),
        if (place != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on_rounded, color: Color(0xFF3897F0)),
            title: Text('${place['name']}'),
            subtitle: '${place['address'] ?? ''}'.isEmpty ? null : Text('${place['address']}'),
            trailing: place['lat'] == null ? null : const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: place['lat'] == null
                ? null
                : () => launchUrl(Uri.parse('https://maps.google.com/?q=${place['lat']},${place['lng']}'),
                    mode: LaunchMode.externalApplication),
          ),
        const SizedBox(height: 16),
        if (widget.own)
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete note'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  openNoteComposer(context, existing: note);
                },
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Leave a new note'),
              ),
            ),
          ])
        else
          Row(children: [
            IconButton(
              tooltip: liked ? 'Unlike' : 'Like',
              onPressed: _like,
              icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: liked ? const Color(0xFFFF3B5C) : null),
            ),
            Expanded(
              child: TextField(
                controller: _reply,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendReply(),
                decoration: InputDecoration(
                  hintText: 'Reply to ${author['display_name'] ?? 'note'}…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  isDense: true,
                ),
              ),
            ),
            IconButton(tooltip: 'Send', onPressed: sending ? null : _sendReply, icon: const Icon(Icons.send_rounded)),
          ]),
      ]),
    );
  }
}

/// Write a note — Instagram's layout: the bubble you type into sits on your
/// photo, a palette button opens the Bubble Editor, and song / place / GIF
/// buttons sit underneath.
class NoteComposerScreen extends ConsumerStatefulWidget {
  const NoteComposerScreen({super.key, this.existing});

  /// Your current note, to start from when leaving a new one.
  final Map? existing;

  @override
  ConsumerState<NoteComposerScreen> createState() => _NoteComposerScreenState();
}

class _NoteComposerScreenState extends ConsumerState<NoteComposerScreen> {
  late final _text = TextEditingController(text: '${widget.existing?['text'] ?? ''}');
  late Map<String, dynamic>? music = _copy(widget.existing?['music']);
  late Map<String, dynamic>? gif = _copy(widget.existing?['gif']);
  late Map<String, dynamic>? place = _copy(widget.existing?['location']);
  late String? color = widget.existing?['color'] as String?;
  late String? effect = widget.existing?['effect'] as String?;
  late String audience = '${widget.existing?['audience'] ?? 'followers'}';
  bool busy = false, locating = false;

  static Map<String, dynamic>? _copy(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _ready => _text.text.trim().isNotEmpty || music != null || gif != null;

  Map<String, dynamic> get _draft => {
        'text': _text.text,
        if (music != null) 'music': music,
        if (gif != null) 'gif': gif,
        'color': color,
        'effect': effect,
      };

  Widget _avatar(double size) {
    final me = ref.read(authControllerProvider).valueOrNull;
    return MeAvatar(name: me?.username ?? 'You', size: size);
  }

  Future<void> _pickSong() async {
    final song = await pickNoteMusic(context);
    if (song != null && mounted) setState(() => music = song);
  }

  Future<void> _pickGif() async {
    final item = await showGiphyPicker(context);
    if (item == null || !mounted) return;
    if (item.isFoxy || item.url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a GIF from the GIPHY tab.')));
      return;
    }
    setState(() => gif = {'url': item.url, 'title': item.title});
  }

  /// Like Instagram: one tap adds where you are now; tap the place to choose
  /// a different one nearby.
  Future<void> _addHere() async {
    setState(() => locating = true);
    try {
      final pos = await currentPosition();
      // The neighbourhood name people use ("KPHB Colony"), in English,
      // not whatever building or road happens to be under the GPS fix.
      final nearby = await googleNearby(pos.latitude, pos.longitude);
      final google = (nearby != null && nearby.areas.isNotEmpty ? nearby.areas : null) ??
          await deviceAreas(pos.latitude, pos.longitude) ??
          await serverAreas(pos.latitude, pos.longitude);
      final here = (google != null && google.isNotEmpty ? google.first : null) ??
          await areaName(pos.latitude, pos.longitude) ??
          await reverseGeocode(pos.latitude, pos.longitude);
      if (here != null && mounted) _setPlace(here);
    } on LocationProblem catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not find your location.')));
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> _choosePlace() async {
    final chosen = await pickNotePlace(context, selected: place?['name'] as String?);
    if (chosen != null && mounted) _setPlace(chosen);
  }

  void _setPlace(Place p) => setState(() => place = {
        'name': p.name.length > 80 ? p.name.substring(0, 80) : p.name,
        'address': p.address.length > 160 ? p.address.substring(0, 160) : p.address,
        'lat': p.lat,
        'lng': p.lng,
      });

  Future<void> _openEditor() async {
    final style = await openBubbleEditor(context, note: _draft, avatar: _avatar(120), text: _text);
    if (!mounted) return;
    // Text typed in the editor is already in _text; refresh Share either way.
    setState(() {
      if (style != null) {
        color = style.color;
        effect = style.effect;
      }
    });
  }

  Future<void> _chooseAudience() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Share with', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final (id, title, sub, icon) in const [
            ('followers', 'Followers', 'Everyone who follows you', Icons.people_alt_rounded),
            ('mutuals', 'Friends', 'Followers you follow back', Icons.handshake_rounded),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(sub),
              trailing: audience == id ? const Icon(Icons.check_circle_rounded, color: Color(0xFF4F5BD5)) : null,
              onTap: () => Navigator.pop(sheet, id),
            ),
        ]),
      ),
    );
    if (picked != null && mounted) setState(() => audience = picked);
  }

  Future<void> _share() async {
    if (!_ready || busy) return;
    setState(() => busy = true);
    try {
      // A song from the phone goes up first, then the note.
      if (needsUpload(music)) {
        try {
          music = await uploadNoteSong(music!);
        } catch (message) {
          if (mounted) {
            setState(() => busy = false);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message')));
          }
          return;
        }
      }
      await getIt<ApiClient>().dio.post<dynamic>('/social/notes', data: {
        'text': _text.text.trim(),
        'audience': audience,
        if (music != null)
          'music': {
            'title': music!['title'],
            'artist': music!['artist'] ?? '',
            'url': music!['url'],
            if (music!['image_url'] != null) 'image_url': music!['image_url'],
            if (music!['ref'] != null) 'ref': music!['ref'],
            'source': music!['source'] ?? 'stream',
            if (music!['clip_start'] != null) 'clip_start': music!['clip_start'],
            if (music!['clip_length'] != null) 'clip_length': music!['clip_length'],
            if (music!['explicit'] == true) 'explicit': true,
          },
        if (gif != null) 'gif': {'url': gif!['url'], 'title': gif!['title'] ?? 'GIF'},
        if (place != null) 'location': place,
        if (color != null) 'color': color,
        if (effect != null) 'effect': effect,
      });
      ref.invalidate(statusNotesProvider);
      if (mounted) Navigator.pop(context);
    } on DioException catch (e) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.response?.statusCode == 404
                ? 'Your Phlio server doesn\'t have Notes yet — deploy the latest backend, then share again.'
                : 'Could not share your note. Try again.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not share your note.')));
      }
    }
  }

  /// The small rounded buttons under the avatar. Tapping a filled one
  /// offers Change / Remove.
  Widget _attach(IconData icon, Color tint, bool on, VoidCallback pick, VoidCallback clear, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            if (!on) {
              pick();
              return;
            }
            final action = await showModalBottomSheet<String>(
              context: context,
              backgroundColor: PhlioColors.surface,
              builder: (sheet) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(leading: Icon(icon), title: Text('Change $label'), onTap: () => Navigator.pop(sheet, 'change')),
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF4D67)),
                    title: Text('Remove $label', style: const TextStyle(color: Color(0xFFFF4D67))),
                    onTap: () => Navigator.pop(sheet, 'remove'),
                  ),
                ]),
              ),
            );
            if (action == 'change') pick();
            if (action == 'remove') clear();
          },
          child: Ink(
            width: 56,
            height: 44,
            decoration: BoxDecoration(
              color: on ? tint.withValues(alpha: 0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? tint : const Color(0xFF3A3F4B), width: 1.2),
            ),
            child: Icon(icon, color: tint, size: 22),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authControllerProvider);
    const avatarSize = 140.0;
    return Scaffold(
      backgroundColor: PhlioColors.background,
      appBar: AppBar(
        backgroundColor: PhlioColors.background,
        leading: IconButton(
            tooltip: 'Close', icon: const Icon(Icons.close_rounded, size: 30), onPressed: () => Navigator.pop(context)),
      ),
      body: SafeArea(
        child: Column(children: [
          // Everything above the bottom bar scrolls as one block, centred
          // when there's room, so nothing overlaps when the keyboard opens.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(height: 12),
                    // Bubble resting on the photo, like Instagram.
                    SizedBox(
                      width: 300,
                      height: 132 + avatarSize,
                      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                        Positioned(top: 132, child: _avatar(avatarSize)),
                        Positioned(
                          top: 132 + avatarSize - 38,
                          left: 150 + avatarSize * 0.5 * 0.7 - 8,
                          child: Material(
                            color: kNoteBubbleColor,
                            shape: const CircleBorder(side: BorderSide(color: PhlioColors.background, width: 3)),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _openEditor,
                              child: const Padding(
                                padding: EdgeInsets.all(7),
                                child: Icon(Icons.palette_outlined, size: 20, color: Color(0xFFFF2E7E)),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height: 150,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: NoteTextBubble(
                              controller: _text,
                              note: _draft,
                              autofocus: widget.existing == null,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _attach(Icons.music_note_rounded, const Color(0xFFFF2E7E), music != null, _pickSong,
                          () => setState(() => music = null), 'song'),
                      _attach(Icons.location_on_outlined, const Color(0xFF9B6BFF), place != null, _addHere,
                          () => setState(() => place = null), 'location'),
                      _attach(Icons.gif_box_outlined, const Color(0xFF2FCB6A), gif != null, _pickGif,
                          () => setState(() => gif = null), 'GIF'),
                    ]),
                    const SizedBox(height: 16),
                    if (locating)
                      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Finding where you are…', style: TextStyle(color: PhlioColors.textMuted)),
                      ])
                    else if (place != null)
                      // "📍 KPHB Colony ×" — tap the name to pick another place.
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.location_on_rounded, color: Color(0xFF3897F0), size: 20),
                        const SizedBox(width: 4),
                        Flexible(
                          child: InkWell(
                            onTap: _choosePlace,
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Flexible(
                                child: Text('${place!['name']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                              ),
                              const Icon(Icons.expand_more_rounded, size: 20, color: PhlioColors.textMuted),
                            ]),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove location',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 20, color: PhlioColors.textMuted),
                          onPressed: () => setState(() => place = null),
                        ),
                      ]),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
                      child: Text(
                        place != null
                            ? 'Your note will be visible at this location and at the top of Inbox for 24 hours.'
                            : 'Your note will be visible at the top of Inbox for 24 hours.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: PhlioColors.textMuted, fontSize: 13),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 16, 12),
            child: Row(children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: PhlioColors.textPrimary),
                onPressed: _chooseAudience,
                icon: const Icon(Icons.people_alt_rounded, size: 20),
                label: Text(audience == 'followers' ? 'Share with followers  ›' : 'Share with friends  ›',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _ready && !busy ? _share : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F5BD5),
                  disabledBackgroundColor: const Color(0xFF1C2350),
                  disabledForegroundColor: Colors.white38,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                ),
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Share', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
