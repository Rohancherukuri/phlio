// Notes above the DM inbox, like Instagram Notes.
//
// A note is a short thought (60 characters) with, optionally, a song from
// Phlio Stream, a GIF from GIPHY and a place. It sits in a bubble over your
// avatar for 24 hours; people who follow you (or only people you follow back)
// see it at the top of their chats, can like it and reply in DMs.
//
// Backend: /api/v1/social/notes (backend/app/api/v1/status_notes.py).

import 'package:audioplayers/audioplayers.dart';
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
import '../../../../shared/music/stream_song_picker.dart';
import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../../profile/presentation/controllers/avatar_controller.dart';
import '../../data/datasources/messaging_api.dart';

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

/// The short line a bubble shows: text, else the song, place or "GIF".
String _bubbleLine(Map note) {
  final text = '${note['text'] ?? ''}'.trim();
  if (text.isNotEmpty) return text;
  final music = note['music'] as Map?;
  if (music != null) return '${music['title']}';
  final place = note['location'] as Map?;
  if (place != null) return '${place['name']}';
  return note['gif'] != null ? 'GIF' : '';
}

/// A speech bubble (with the song / place / GIF line Instagram shows).
class NoteBubble extends StatelessWidget {
  const NoteBubble({super.key, this.note, this.placeholder, this.maxWidth = 104});

  /// The note; null shows [placeholder] (your "Note..." prompt).
  final Map? note;
  final String? placeholder;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final n = note;
    final music = n?['music'] as Map?;
    final place = n?['location'] as Map?;
    final gif = n?['gif'] as Map?;
    final line = n == null ? (placeholder ?? '') : _bubbleLine(n);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: PhlioColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (music != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.graphic_eq_rounded, size: 13, color: PhlioColors.brandPink),
              const SizedBox(width: 3),
              Flexible(
                child: Text('${music['title']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
            ]),
          if (music != null && '${music['artist'] ?? ''}'.isNotEmpty)
            Text('${music['artist']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: PhlioColors.textMuted)),
          if (gif != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(imageUrl: '${gif['url']}', height: 34, fit: BoxFit.cover),
              ),
            ),
          if (place != null && (n?['text'] ?? '').toString().trim().isEmpty && music == null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.place_rounded, size: 12, color: PhlioColors.brandViolet),
              Flexible(
                child: Text(line,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
              ),
            ])
          else if (line.isNotEmpty && (music == null || '${n?['text'] ?? ''}'.trim().isNotEmpty) && line != 'GIF')
            Text(line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: n == null ? PhlioColors.textMuted : PhlioColors.textPrimary, height: 1.15)),
        ]),
      ),
    );
  }
}

/// The notes strip for the top of the inbox: your note, then others' notes,
/// then [trailing] (recent contacts without notes).
class NotesStrip extends ConsumerWidget {
  const NotesStrip({super.key, this.trailing = const []});

  /// Extra tiles after the notes (e.g. recent chats).
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    final data = ref.watch(statusNotesProvider).valueOrNull;
    final mine = data?.$1;
    final items = data?.$2 ?? const <Map>[];
    Widget tile({required Widget avatar, required String caption, Widget? bubble, required VoidCallback onTap,
        Widget? captionIcon}) {
      return SizedBox(
        width: 104,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Column(children: [
            SizedBox(
              height: 128,
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                Positioned(top: 38, child: avatar),
                if (bubble != null) Positioned(top: 0, child: bubble),
              ]),
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (captionIcon != null) captionIcon,
              Flexible(
                child: Text(caption,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              ),
            ]),
          ]),
        ),
      );
    }

    return SizedBox(
      height: 160,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          tile(
            avatar: MeAvatar(name: me?.username ?? 'You', size: 76),
            bubble: NoteBubble(note: mine, placeholder: 'Note...'),
            caption: 'Your note',
            captionIcon: mine?['location'] != null
                ? const Icon(Icons.place_rounded, size: 12, color: PhlioColors.brandViolet)
                : null,
            onTap: () => mine == null ? openNoteComposer(context) : showNoteSheet(context, mine, own: true),
          ),
          for (final note in items)
            tile(
              avatar: PhlioAvatar(
                  name: '${(note['author'] as Map)['display_name'] ?? ''}',
                  imageUrl: (note['author'] as Map)['avatar_url'] as String?,
                  size: 76),
              bubble: NoteBubble(note: note),
              caption: '${(note['author'] as Map)['display_name'] ?? (note['author'] as Map)['username']}',
              onTap: () => showNoteSheet(context, note),
            ),
          // Line plain contacts up with the avatars under the bubbles.
          for (final t in trailing) Padding(padding: const EdgeInsets.only(top: 34), child: t),
        ],
      ),
    );
  }
}

/// Opens the note composer.
Future<void> openNoteComposer(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(builder: (_) => const NoteComposerScreen(), fullscreenDialog: true));

/// A note up close: song preview, GIF, place, like and reply.
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

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => playing = false);
    });
    // Like Instagram, a note's song starts playing when you open it.
    if (widget.note['music'] != null) _togglePlay();
  }

  @override
  void dispose() {
    _player.dispose();
    _reply.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final music = widget.note['music'] as Map?;
    if (music == null) return;
    if (playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(AppConfig.mediaUrl('${music['url']}')));
    }
    if (mounted) setState(() => playing = !playing);
  }

  String get _author => '${(widget.note['author'] as Map)['id']}';

  Future<void> _like() async {
    HapticFeedback.selectionClick();
    setState(() => liked = !liked);
    try {
      final dio = getIt<ApiClient>().dio;
      liked ? await dio.put<dynamic>('/social/notes/$_author/like') : await dio.delete<dynamic>('/social/notes/$_author/like');
    } catch (_) {
      if (mounted) setState(() => liked = !liked);
    }
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      final line = _bubbleLine(widget.note);
      await ref.read(messagingApiProvider).send(_author, 'Replied to your note “$line”\n$text');
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
    final gif = note['gif'] as Map?;
    final text = '${note['text'] ?? ''}'.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        PhlioAvatar(name: '${author['display_name'] ?? ''}', imageUrl: author['avatar_url'] as String?, size: 64),
        const SizedBox(height: 6),
        Text(widget.own ? 'Your note' : '${author['display_name'] ?? author['username']}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        if (text.isNotEmpty)
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        if (gif != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(imageUrl: '${gif['url']}', height: 140, fit: BoxFit.cover)),
          ),
        if (music != null)
          Card(
            margin: const EdgeInsets.only(top: 14),
            child: ListTile(
              leading: music['image_url'] != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                          imageUrl: AppConfig.mediaUrl('${music['image_url']}'), width: 44, height: 44, fit: BoxFit.cover))
                  : const Icon(Icons.music_note_rounded),
              title: Text('${music['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${music['artist'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: playing ? 'Pause' : 'Play',
                icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, size: 34),
                onPressed: _togglePlay,
              ),
            ),
          ),
        if (place != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_rounded, color: PhlioColors.brandViolet),
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
                  openNoteComposer(context);
                },
                icon: const Icon(Icons.edit_rounded),
                label: const Text('New note'),
              ),
            ),
          ])
        else
          Row(children: [
            IconButton(
              tooltip: liked ? 'Unlike' : 'Like',
              onPressed: _like,
              icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: liked ? PhlioColors.brandPink : null),
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

/// Write a note (Instagram's layout: your avatar with a bubble, and song,
/// place and GIF buttons underneath).
class NoteComposerScreen extends ConsumerStatefulWidget {
  const NoteComposerScreen({super.key});

  @override
  ConsumerState<NoteComposerScreen> createState() => _NoteComposerScreenState();
}

class _NoteComposerScreenState extends ConsumerState<NoteComposerScreen> {
  final _text = TextEditingController();
  Map<String, dynamic>? music, gif, place;
  String audience = 'followers';
  bool busy = false, locating = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _ready => _text.text.trim().isNotEmpty || music != null || gif != null || place != null;

  Future<void> _pickSong() async {
    final song = await showStreamSongPicker(context);
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

  Future<void> _pickPlace() async {
    setState(() => locating = true);
    try {
      final pos = await currentPosition();
      final nearby = await nearbyPlaces(pos.latitude, pos.longitude, radius: 400, limit: 12);
      final here = await reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;
      final chosen = await showModalBottomSheet<Place>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            const ListTile(title: Text('Add a place', style: TextStyle(fontWeight: FontWeight.w800))),
            if (here != null)
              ListTile(
                leading: const Icon(Icons.my_location_rounded),
                title: Text(here.name),
                subtitle: Text(here.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(sheet, here),
              ),
            for (final p in nearby)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(p.name),
                subtitle: Text(p.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(sheet, p),
              ),
          ]),
        ),
      );
      if (chosen != null && mounted) {
        setState(() => place = {
              'name': chosen.name.length > 80 ? chosen.name.substring(0, 80) : chosen.name,
              'address': chosen.address.length > 160 ? chosen.address.substring(0, 160) : chosen.address,
              'lat': chosen.lat,
              'lng': chosen.lng,
            });
      }
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

  Future<void> _share() async {
    if (!_ready || busy) return;
    setState(() => busy = true);
    try {
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
          },
        if (gif != null) 'gif': gif,
        if (place != null) 'location': place,
      });
      ref.invalidate(statusNotesProvider);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not share your note.')));
      }
    }
  }

  Widget _chip(IconData icon, Color color, String label, bool on, VoidCallback onTap, VoidCallback onClear) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: on
          ? InputChip(
              avatar: Icon(icon, size: 16, color: color),
              label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              onPressed: onTap,
              onDeleted: onClear,
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              child: Icon(icon, color: color),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authControllerProvider).valueOrNull;
    return Scaffold(
      backgroundColor: PhlioColors.background,
      appBar: AppBar(
        backgroundColor: PhlioColors.background,
        leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ),
      body: SafeArea(
        child: Column(children: [
          const Spacer(),
          // The bubble you type into, above your photo.
          Container(
            constraints: const BoxConstraints(maxWidth: 260),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: PhlioColors.surfaceElevated, borderRadius: BorderRadius.circular(22)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (music != null) NoteBubble(note: {'music': music}, maxWidth: 220),
              TextField(
                controller: _text,
                autofocus: true,
                maxLength: 60,
                maxLines: 3,
                minLines: 1,
                textAlign: TextAlign.center,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(
                    hintText: "Today's vibe...", border: InputBorder.none, counterText: '', isDense: true),
              ),
              if (gif != null)
                ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(imageUrl: '${gif!['url']}', height: 70, fit: BoxFit.cover)),
            ]),
          ),
          const SizedBox(height: 8),
          MeAvatar(name: me?.username ?? 'You', size: 96),
          const SizedBox(height: 18),
          Wrap(alignment: WrapAlignment.center, runSpacing: 8, children: [
            _chip(Icons.music_note_rounded, PhlioColors.brandPink, '${music?['title'] ?? ''}', music != null, _pickSong,
                () => setState(() => music = null)),
            _chip(Icons.place_outlined, PhlioColors.brandViolet,
                locating ? 'Finding…' : '${place?['name'] ?? ''}', place != null || locating, _pickPlace,
                () => setState(() => place = null)),
            _chip(Icons.gif_box_outlined, const Color(0xFF39D98A), '${gif?['title'] ?? 'GIF'}', gif != null, _pickGif,
                () => setState(() => gif = null)),
          ]),
          const Spacer(flex: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: PhlioColors.textPrimary),
                  onPressed: () => setState(() => audience = audience == 'followers' ? 'mutuals' : 'followers'),
                  icon: const Icon(Icons.people_alt_rounded, size: 20),
                  label: Text(audience == 'followers' ? 'Share with followers  ›' : 'Followers you follow back  ›',
                      overflow: TextOverflow.ellipsis),
                ),
              ),
              FilledButton(
                onPressed: _ready && !busy ? _share : null,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14)),
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Share'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
