part of 'experience_screen.dart';

// Sharing and viewing Experiences.
//
//   Composer  your photos / videos as polaroids. Tap ✎ on a card for the
//             full editor (crop, adjust, filters, effects, trim, speed…).
//             Add collaborators from your friends — or just @mention them
//             in the caption — and the place: read from the photos' GPS
//             when they have it, or picked from places around you.
//   Viewer    whoever posted each card, the collaborators, where it was
//             taken (pill → map of the dump's places), reactions and a
//             reply. Collaborators can add their own photos to the dump.

// -- share --------------------------------------------------------------------------------

/// Picks up to 10 photos / videos and opens the Experience composer.
/// With [group], they're added to that (collaborative) Experience.
Future<void> shareExperience(BuildContext context, WidgetRef ref, {String? group}) async {
  final picked = await ImagePicker().pickMultipleMedia(limit: 10, imageQuality: 92, maxWidth: 2160);
  if (picked.isEmpty || !context.mounted) return;
  final shared = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ExperienceComposer(files: picked.take(10).toList(), group: group)));
  if (shared == true) ref.invalidate(memoriesProvider);
}

bool _isVideoPath(String path) =>
    const ['.mp4', '.mov', '.m4v', '.webm', '.3gp'].any((e) => path.toLowerCase().endsWith(e));

/// One picked photo / video and what you did to it.
class _ExpItem {
  _ExpItem(this.file) : video = _isVideoPath(file.path);
  final XFile file;
  final bool video;
  MediaEdit? edit;
  PhotoExif? exif;

  /// Where this one was taken (from its GPS), when known.
  Place? place;

  String get path => edit?.path ?? file.path;
  FilterSpec get spec => edit?.spec ?? FilterSpec();
}

Map<String, dynamic> _placeJson(Place p, String source) => {...p.toJson(), 'source': source};

class ExperienceComposer extends ConsumerStatefulWidget {
  const ExperienceComposer({required this.files, this.group, super.key});
  final List<XFile> files;

  /// Adding to someone's Experience as a collaborator.
  final String? group;
  @override
  ConsumerState<ExperienceComposer> createState() => _ExperienceComposerState();
}

class _ExperienceComposerState extends ConsumerState<ExperienceComposer> {
  late final List<_ExpItem> _items = [for (final f in widget.files) _ExpItem(f)];
  final _caption = MentionTextEditingController();
  final _pager = PageController(viewportFraction: .82);
  SnapAudience _audience = const SnapAudience();
  int _page = 0;
  int _sent = 0;
  bool _busy = false;

  /// Friends you're making this with (`{id, username, full_name, avatar_url}`).
  final List<Map> _team = [];
  List<Map>? _friends;

  /// The dump's place (picked, or from the photos' GPS).
  Place? _place;
  String _placeSource = 'picked';
  bool _locating = false;

  /// "@ne…" being typed in the caption.
  String? _mention;

  bool get _joining => widget.group != null;

  @override
  void initState() {
    super.initState();
    _caption.addListener(_watchMention);
    _readPhotoPlaces();
  }

  @override
  void dispose() {
    _caption.dispose();
    _pager.dispose();
    super.dispose();
  }

  // -- places from the photos -------------------------------------------------------------

  Future<void> _readPhotoPlaces() async {
    setState(() => _locating = true);
    final named = <String, Place?>{};
    for (final item in _items.where((i) => !i.video)) {
      final exif = await readPhotoExif(item.file.path);
      item.exif = exif;
      if (!exif.hasLocation) continue;
      // One lookup per spot (~100 m), so a dump from one café asks once.
      final key = '${exif.lat!.toStringAsFixed(3)},${exif.lng!.toStringAsFixed(3)}';
      if (!named.containsKey(key) && named.length < 5) named[key] = await reverseGeocode(exif.lat!, exif.lng!);
      final near = named[key];
      item.place = Place(
          lat: exif.lat!, lng: exif.lng!, name: near?.name ?? 'Pinned spot', address: near?.address ?? '', kind: near?.kind);
    }
    if (!mounted) return;
    final first = _items.map((i) => i.place).whereType<Place>().firstOrNull;
    setState(() {
      _locating = false;
      if (_place == null && first != null) {
        _place = first;
        _placeSource = 'photo';
      }
    });
  }

  Future<void> _pickPlace() async {
    final p = await pickNotePlace(context, selected: _place?.name);
    if (p != null && mounted) {
      setState(() {
        _place = p;
        _placeSource = 'picked';
      });
    }
  }

  // -- collaborators and @mentions ---------------------------------------------------------

  Future<List<Map>> _loadFriends() async {
    if (_friends != null) return _friends!;
    try {
      final rows = await ref.read(messagingApiProvider).friends();
      _friends = [for (final r in rows) if (r['peer'] is Map) Map.from(r['peer'] as Map)];
    } catch (_) {
      _friends = [];
    }
    return _friends!;
  }

  void _watchMention() {
    final text = _caption.text;
    final at = _caption.selection.baseOffset;
    final before = at < 0 || at > text.length ? text : text.substring(0, at);
    final m = RegExp(r'(?:^|\s)@([A-Za-z0-9_.]{0,30})$').firstMatch(before);
    final next = m?.group(1);
    if (next != _mention) {
      setState(() => _mention = next);
      if (next != null) {
        _loadFriends().then((_) {
          if (mounted) setState(() {});
        });
      }
    }
  }

  void _useMention(Map person) {
    final text = _caption.text;
    final at = _caption.selection.baseOffset < 0 ? text.length : _caption.selection.baseOffset;
    final start = text.substring(0, at).lastIndexOf('@');
    final insert = '@${person['username']} ';
    final next = text.replaceRange(start, at, insert);
    _caption.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + insert.length));
    _addTeam(person);
  }

  void _addTeam(Map person) {
    if (_team.any((p) => p['id'] == person['id'])) return;
    setState(() => _team.add(person));
  }

  Future<void> _editTeam() async {
    final friends = await _loadFriends();
    if (!mounted) return;
    final picked = await pickExperienceCollaborators(context, friends: friends, selected: _team);
    if (picked != null && mounted) {
      setState(() => _team
        ..clear()
        ..addAll(picked));
    }
  }

  // -- edit -----------------------------------------------------------------------------------

  Future<void> _edit(int i) async {
    final item = _items[i];
    final result = await openMediaEditor(context, original: item.file.path, isVideo: item.video, initial: item.edit);
    if (result != null && mounted) setState(() => item.edit = result);
  }

  // -- share ----------------------------------------------------------------------------------

  Future<void> _share() async {
    if (_busy || _items.isEmpty) return;
    setState(() {
      _busy = true;
      _sent = 0;
    });
    final group = widget.group ?? 'exp_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    try {
      for (final item in _items) {
        final path = item.path;
        final spec = item.spec;
        final place = item.place ?? _place;
        final edits = item.video ? item.edit?.videoEdits() : null;
        await getIt<ApiClient>().dio.post(
              '/social/memories',
              data: FormData.fromMap({
                // The caption goes with the first item of the dump.
                'caption': item == _items.first ? _caption.text.trim() : '',
                'audience': _audience.mode,
                'recipients': jsonEncode(_audience.recipients),
                'kind': 'experience',
                'group': group,
                if (!_joining) 'collaborators': jsonEncode([for (final p in _team) p['username']]),
                if (!spec.isEmpty) 'filter_spec': jsonEncode(spec.toJson()),
                if (edits != null) 'edits': jsonEncode(edits),
                if (place != null) 'location': jsonEncode(_placeJson(place, item.place != null ? 'photo' : _placeSource)),
                'file': await MultipartFile.fromFile(path,
                    filename: path.split(Platform.pathSeparator).last,
                    contentType: item.video
                        ? DioMediaType('video', 'mp4')
                        : path.toLowerCase().endsWith('.png')
                            ? DioMediaType('image', 'png')
                            : DioMediaType('image', 'jpeg')),
              }),
              options: Options(sendTimeout: const Duration(minutes: 3), receiveTimeout: const Duration(minutes: 4)),
            );
        if (mounted) setState(() => _sent++);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(SnackBar(
          content: Text(_joining
              ? 'Added to the Experience'
              : _team.isEmpty
                  ? 'Experience shared with ${_audience.label} for 7 days'
                  : 'Experience shared with ${_team.length} collaborator${_team.length == 1 ? '' : 's'} and ${_audience.label}')));
    } on DioException catch (e) {
      final detail = e.response?.data is Map ? (e.response!.data as Map)['detail'] : null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(detail is String
                ? detail
                : 'Shared $_sent of ${_items.length}. Check your connection and try again.')));
        // Keep only what didn't go up, so a retry doesn't post twice.
        setState(() => _items.removeRange(0, _sent));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Shared $_sent of ${_items.length}. Try again.')));
        setState(() => _items.removeRange(0, _sent));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -- UI -------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final week = experienceWeek();
    final suggestions = _mention == null
        ? const <Map>[]
        : [
            for (final f in _friends ?? const <Map>[])
              if ('${f['username']}'.toLowerCase().startsWith(_mention!.toLowerCase()) ||
                  '${f['full_name'] ?? ''}'.toLowerCase().contains(_mention!.toLowerCase()))
                f
          ].take(8).toList();
    return Scaffold(
      backgroundColor: PhlioColors.background,
      appBar: AppBar(
        backgroundColor: PhlioColors.background,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Column(children: [
          Text(_joining ? 'Add to Experience' : 'Your Experience', style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(_weekLabel(week),
              style: const TextStyle(color: Colors.white54, fontSize: 11.5, letterSpacing: 1.6, fontFamily: 'monospace')),
        ]),
      ),
      body: SafeArea(
        child: Column(children: [
          if (!_joining)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
              child: _CollaboratorBanner(team: _team, onTap: _busy ? null : _editTeam),
            ),
          Expanded(
            child: PageView.builder(
              controller: _pager,
              itemCount: _items.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => AnimatedBuilder(
                animation: _pager,
                builder: (_, child) {
                  final page = _pager.hasClients && _pager.position.haveDimensions ? _pager.page ?? 0 : 0.0;
                  final d = (page - i).clamp(-1.0, 1.0);
                  return Transform.rotate(angle: d * -.08, child: Transform.scale(scale: 1 - d.abs() * .08, child: child));
                },
                child: _card(i),
              ),
            ),
          ),
          Text('${math.min(_page + 1, _items.length)} / ${_items.length}', style: const TextStyle(color: Colors.white54)),
          if (suggestions.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                children: [
                  for (final f in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: PhlioAvatar(
                            name: '${f['full_name'] ?? f['username']}',
                            imageUrl: f['avatar_url'] as String?,
                            size: 24,
                            showMomentRing: false),
                        label: Text('@${f['username']}'),
                        onPressed: () => _useMention(f),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: TextField(
              controller: _caption,
              enabled: !_busy,
              maxLength: 500,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _joining ? 'Say something about it…' : 'Say something about your week… @mention friends',
                counterText: '',
              ),
            ),
          ),
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              children: [
                ActionChip(
                  avatar: const Icon(Icons.people_alt_outlined, size: 18),
                  label: Text(_audience.label),
                  onPressed: _busy
                      ? null
                      : () async {
                          final v = await pickSnapAudience(context, _audience);
                          if (mounted && v != null) setState(() => _audience = v);
                        },
                ),
                const SizedBox(width: 8),
                if (_place == null)
                  ActionChip(
                    avatar: _locating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_location_alt_outlined, size: 18),
                    label: const Text('Add location'),
                    onPressed: _busy ? null : _pickPlace,
                  )
                else
                  InputChip(
                    avatar: Icon(_placeSource == 'photo' ? Icons.photo_camera_outlined : Icons.location_on_rounded,
                        size: 18, color: PhlioColors.brandPeach),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: Text(_place!.name, overflow: TextOverflow.ellipsis),
                    ),
                    onPressed: _busy ? null : _pickPlace,
                    onDeleted: _busy ? null : () => setState(() => _place = null),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _busy ? null : _share,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const ExperienceMark(size: 20),
                label: Text(_busy ? 'Sharing $_sent/${_items.length}…' : (_joining ? 'Add to Experience' : 'Share Experience'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _card(int i) {
    final item = _items[i];
    final place = item.place;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Stack(children: [
        Positioned.fill(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F1EC),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: ClipRect(
              child: StoryFxLayer(
                fx: item.spec.fx,
                amount: item.spec.fxAmount,
                adjust: item.spec.adjust,
                stamp: item.exif?.takenAt,
                child: PhlioLook(
                  look: item.spec.look,
                  strength: item.spec.strength,
                  child: _LocalMedia(
                    key: ValueKey(item.path),
                    path: item.path,
                    video: item.video,
                    playing: i == _page,
                    edit: item.edit,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          top: 14,
          child: _CardButton(
            tooltip: 'Edit',
            icon: Icons.edit_rounded,
            active: item.edit != null,
            onTap: _busy ? null : () => _edit(i),
          ),
        ),
        Positioned(
          right: 14,
          top: 14,
          child: _CardButton(
            tooltip: 'Remove',
            icon: Icons.close_rounded,
            onTap: _busy
                ? null
                : () {
                    setState(() => _items.removeAt(i));
                    if (_items.isEmpty) Navigator.pop(context);
                  },
          ),
        ),
        if (place != null)
          Positioned(left: 16, bottom: 18, right: 16, child: Align(alignment: Alignment.centerLeft, child: _PlacePill(name: place.name))),
      ]),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({required this.tooltip, required this.icon, this.onTap, this.active = false});
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  @override
  Widget build(BuildContext context) => Material(
        color: active ? PhlioColors.brandPeach : Colors.black54,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          icon: Icon(icon, color: active ? Colors.black : Colors.white, size: 18),
        ),
      );
}

class _PlacePill extends StatelessWidget {
  const _PlacePill({required this.name, this.onTap});
  final String name;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: .62), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.location_on_rounded, color: PhlioColors.brandPeach, size: 16),
            const SizedBox(width: 4),
            Flexible(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ]),
        ),
      );
}

/// "you can now add collaborators": faces + label, Corner style.
class _CollaboratorBanner extends StatelessWidget {
  const _CollaboratorBanner({required this.team, this.onTap});
  final List<Map> team;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              gradient: team.isEmpty ? PhlioColors.brandGradient : null,
              color: team.isEmpty ? null : PhlioColors.surface,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(children: [
              _FaceStack(people: team, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  team.isEmpty
                      ? 'Add collaborators — make it together'
                      : 'With ${team.take(2).map((p) => '@${p['username']}').join(', ')}${team.length > 2 ? ' +${team.length - 2}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: team.isEmpty ? PhlioColors.textOnBrand : Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              Icon(team.isEmpty ? Icons.person_add_alt_1_rounded : Icons.edit_rounded,
                  color: team.isEmpty ? PhlioColors.textOnBrand : Colors.white70, size: 20),
              const SizedBox(width: 6),
            ]),
          ),
        ),
      );
}

class _FaceStack extends StatelessWidget {
  const _FaceStack({required this.people, this.size = 28});
  final List<Map> people;
  final double size;
  @override
  Widget build(BuildContext context) {
    final shown = people.take(3).toList();
    if (shown.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.white24,
        child: Icon(Icons.group_add_rounded, size: size * .55, color: Colors.white),
      );
    }
    return SizedBox(
      width: size + (shown.length - 1) * size * .62,
      height: size,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(
            left: i * size * .62,
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: PhlioColors.background, width: 1.5)),
              child: PhlioAvatar(
                  name: '${shown[i]['full_name'] ?? shown[i]['display_name'] ?? shown[i]['username']}',
                  imageUrl: shown[i]['avatar_url'] as String?,
                  size: size - 3,
                  showMomentRing: false),
            ),
          ),
      ]),
    );
  }
}

/// Multi-select of your friends; returns the new list (null when cancelled).
Future<List<Map>?> pickExperienceCollaborators(BuildContext context,
        {required List<Map> friends, required List<Map> selected}) =>
    showModalBottomSheet<List<Map>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PhlioColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CollaboratorPicker(friends: friends, selected: selected),
    );

class _CollaboratorPicker extends StatefulWidget {
  const _CollaboratorPicker({required this.friends, required this.selected});
  final List<Map> friends, selected;
  @override
  State<_CollaboratorPicker> createState() => _CollaboratorPickerState();
}

class _CollaboratorPickerState extends State<_CollaboratorPicker> {
  late final Set<String> picked = {for (final p in widget.selected) '${p['id']}'};
  String query = '';

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    final shown = [
      for (final f in widget.friends)
        if (q.isEmpty ||
            '${f['username']}'.toLowerCase().contains(q) ||
            '${f['full_name'] ?? f['display_name'] ?? ''}'.toLowerCase().contains(q))
          f
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
          child: Row(children: [
            const Expanded(
              child: Text('Collaborators', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, [
                for (final f in widget.friends)
                  if (picked.contains('${f['id']}')) f
              ]),
              child: Text(picked.isEmpty ? 'Done' : 'Done · ${picked.length}'),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Collaborators see this Experience and can add their own photos to it. Only friends can collaborate.',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (v) => setState(() => query = v.trim()),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search friends',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: widget.friends.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text('Add friends first — collaborators come from your friends list.',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
                  ),
                )
              : ListView(children: [
                  for (final f in shown)
                    CheckboxListTile(
                      value: picked.contains('${f['id']}'),
                      onChanged: (v) => setState(() => v == true ? picked.add('${f['id']}') : picked.remove('${f['id']}')),
                      secondary: PhlioAvatar(
                          name: '${f['full_name'] ?? f['display_name'] ?? f['username']}',
                          imageUrl: f['avatar_url'] as String?,
                          size: 42,
                          showMomentRing: false),
                      title: Text('${f['full_name'] ?? f['display_name'] ?? f['username']}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      subtitle: Text('@${f['username']}', style: const TextStyle(color: Colors.white54)),
                    ),
                ]),
        ),
      ]),
    );
  }
}

/// A picked (or edited) photo, or a looping, muted video previewed with
/// its trim and speed.
class _LocalMedia extends StatefulWidget {
  const _LocalMedia({required this.path, required this.video, required this.playing, this.edit, super.key});
  final String path;
  final bool video;
  final bool playing;
  final MediaEdit? edit;
  @override
  State<_LocalMedia> createState() => _LocalMediaState();
}

class _LocalMediaState extends State<_LocalMedia> {
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    if (widget.video) {
      final c = VideoPlayerController.file(File(widget.path));
      _video = c;
      c.initialize().then((_) async {
        await c.setLooping(true);
        await c.setVolume(0);
        await c.setPlaybackSpeed(widget.edit?.speed ?? 1);
        final start = widget.edit?.trimStart;
        if (start != null) await c.seekTo(start);
        c.addListener(_trim);
        if (widget.playing) await c.play();
        if (mounted) setState(() {});
      });
    }
  }

  void _trim() {
    final c = _video;
    final e = widget.edit;
    if (c == null || e == null) return;
    final end = e.trimEnd;
    if (end != null && c.value.position > end) c.seekTo(e.trimStart ?? Duration.zero);
  }

  @override
  void didUpdateWidget(_LocalMedia old) {
    super.didUpdateWidget(old);
    final c = _video;
    if (c != null && c.value.isInitialized) {
      if (old.playing != widget.playing) widget.playing ? c.play() : c.pause();
      if (old.edit != widget.edit) c.setPlaybackSpeed(widget.edit?.speed ?? 1);
    }
  }

  @override
  void dispose() {
    _video?.removeListener(_trim);
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _video;
    if (c == null) return Image.file(File(widget.path), fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    if (!c.value.isInitialized) return const Center(child: CircularProgressIndicator());
    final e = widget.edit;
    Widget player = SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c));
    if (e != null && (e.quarterTurns % 4 != 0 || e.flip)) {
      player = Transform.flip(flipX: e.flip, child: RotatedBox(quarterTurns: e.quarterTurns % 4, child: player));
    }
    return SizedBox.expand(child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: player));
  }
}

// -- viewer --------------------------------------------------------------------------------

class ExperienceViewer extends ConsumerStatefulWidget {
  const ExperienceViewer({required this.items, super.key});
  final List<Map> items;
  @override
  ConsumerState<ExperienceViewer> createState() => _ExperienceViewerState();
}

class _ExperienceViewerState extends ConsumerState<ExperienceViewer> {
  final _pager = PageController();
  final _reply = TextEditingController();
  int _page = 0;
  String? _burst;
  late List<Map> _team = _collaborators();

  @override
  void initState() {
    super.initState();
    _seen(0);
  }

  @override
  void dispose() {
    _pager.dispose();
    _reply.dispose();
    super.dispose();
  }

  /// Everyone in the dump: its owner's collaborators (profiles).
  List<Map> _collaborators() {
    final seen = <String>{};
    final out = <Map>[];
    for (final m in widget.items) {
      for (final p in (m['collaborators'] as List? ?? const []).whereType<Map>()) {
        if (seen.add('${p['id']}')) out.add(p);
      }
      final a = m['author'] as Map?;
      if (a != null && m != widget.items.first && seen.add('${a['id']}')) out.add(a);
    }
    final owner = (widget.items.first['author'] as Map?)?['id'];
    return [for (final p in out) if (p['id'] != owner) p];
  }

  String? get _group => widget.items.first['group'] as String?;

  Future<void> _seen(int i) async {
    final item = widget.items[i];
    if (item['unread'] != true) return;
    try {
      await getIt<ApiClient>().dio.put('/social/memories/${item['id']}/seen');
    } catch (_) {}
  }

  Future<void> _react(String emoji) async {
    final item = widget.items[_page];
    try {
      await getIt<ApiClient>().dio.put('/social/memories/${item['id']}/reaction', data: {'emoji': emoji});
      HapticFeedback.lightImpact();
      setState(() => _burst = emoji);
      ref.invalidate(memoriesProvider);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) setState(() => _burst = null);
    } catch (_) {
      _say('Could not send reaction. Try again.');
    }
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    final author = widget.items[_page]['author'] as Map? ?? const {};
    if (text.isEmpty || author['username'] == null) return;
    try {
      await ref.read(messagingApiProvider).send('${author['username']}', 'Reply to your Experience: $text');
      _reply.clear();
      _say('Reply sent in messages.');
    } catch (_) {
      _say('Could not send reply. Try again.');
    }
  }

  void _say(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _showTeam({required bool owner}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: PhlioColors.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Made together', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          for (final p in [widget.items.first['author'] as Map? ?? const {}, ..._team])
            ListTile(
              leading: PhlioAvatar(
                  name: '${p['display_name'] ?? p['full_name'] ?? p['username']}',
                  imageUrl: p['avatar_url'] as String?,
                  size: 40,
                  showMomentRing: false),
              title: Text('${p['display_name'] ?? p['full_name'] ?? p['username']}', style: const TextStyle(color: Colors.white)),
              subtitle: Text(p == widget.items.first['author'] ? 'Started it' : '@${p['username']}',
                  style: const TextStyle(color: Colors.white54)),
            ),
          if (owner && _group != null)
            ListTile(
              leading: const Icon(Icons.group_add_rounded, color: PhlioColors.brandPeach),
              title: const Text('Edit collaborators', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(sheet, true),
            ),
        ]),
      ),
    );
    if (changed != true || !mounted) return;
    List<Map> friends;
    try {
      friends = [
        for (final r in await ref.read(messagingApiProvider).friends())
          if (r['peer'] is Map) Map.from(r['peer'] as Map)
      ];
    } catch (_) {
      friends = [];
    }
    if (!mounted) return;
    final picked = await pickExperienceCollaborators(context, friends: friends, selected: _team);
    if (picked == null || !mounted) return;
    try {
      final res = await getIt<ApiClient>().dio.put('/social/memories/groups/${Uri.encodeComponent(_group!)}/collaborators',
          data: {'collaborators': [for (final p in picked) p['username']]});
      setState(() => _team = ((res.data as Map)['collaborators'] as List).cast<Map>());
      ref.invalidate(memoriesProvider);
      _say('Collaborators updated');
    } catch (_) {
      _say('Could not update collaborators.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final me = ref.watch(authControllerProvider).valueOrNull?.id;
    final owner = items.first['author'] as Map? ?? const {};
    final current = items[_page.clamp(0, items.length - 1)];
    final author = current['author'] as Map? ?? owner;
    final mineCard = author['id'] == me;
    final isOwner = owner['id'] == me;
    final canAdd = _group != null && (isOwner || _team.any((p) => p['id'] == me));
    final t = DateTime.tryParse('${current['created_at']}')?.toLocal();
    final avatar = author['avatar_url'] as String?;
    final caption = '${items.first['caption'] ?? ''}'.trim();
    final places = [for (final m in items) if (m['location'] is Map) m];
    return Scaffold(
      backgroundColor: PhlioColors.background,
      appBar: AppBar(
        backgroundColor: PhlioColors.background,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Column(children: [
          const Row(mainAxisSize: MainAxisSize.min, children: [
            ExperienceMark(size: 20),
            SizedBox(width: 6),
            Text('Experience', style: TextStyle(fontWeight: FontWeight.w900)),
          ]),
          if (t != null)
            Text(_weekLabel(experienceWeek(t)),
                style: const TextStyle(color: Colors.white54, fontSize: 11.5, letterSpacing: 1.6, fontFamily: 'monospace')),
        ]),
        actions: [
          if (places.isNotEmpty)
            IconButton(
              tooltip: 'Map',
              icon: const Icon(Icons.map_outlined),
              onPressed: () => showExperienceMap(context, places, focus: current['location'] is Map ? current : null),
            ),
          if (canAdd)
            IconButton(
              tooltip: 'Add your photos',
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: () => shareExperience(context, ref, group: _group).then((_) {
                if (mounted) Navigator.of(context).maybePop();
              }),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (_team.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: GestureDetector(
                onTap: () => _showTeam(owner: isOwner),
                child: Row(children: [
                  _FaceStack(people: [owner, ..._team], size: 26),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'With ${_team.take(2).map((p) => '@${p['username']}').join(', ')}${_team.length > 2 ? ' +${_team.length - 2}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (isOwner) const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                ]),
              ),
            )
          else if (isOwner && _group != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: _CollaboratorBanner(team: const [], onTap: () => _showTeam(owner: true)),
            ),
          Expanded(
            child: Stack(children: [
              PageView.builder(
                controller: _pager,
                itemCount: items.length,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  _seen(i);
                },
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Stack(children: [
                    Positioned.fill(child: _Polaroid(item: items[i], autoplay: true)),
                    if (items[i]['location'] is Map)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _PlacePill(
                            name: '${(items[i]['location'] as Map)['name']}',
                            onTap: () => showExperienceMap(context, places, focus: items[i]),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
              Positioned(
                right: 28,
                top: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                  child: Text('${_page + 1} / ${items.length}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                ),
              ),
              if (_burst != null) Center(child: Text(_burst!, style: const TextStyle(fontSize: 96))),
            ]),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: PhlioColors.surfaceElevated,
              backgroundImage: avatar == null || avatar.isEmpty ? null : phlioImageProvider(AppConfig.mediaUrl(avatar)),
              child: avatar == null || avatar.isEmpty
                  ? Text('${author['display_name'] ?? author['username'] ?? '?'}'.characters.first.toUpperCase())
                  : null,
            ),
            title: Text('${author['display_name'] ?? author['username'] ?? 'Friend'}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            // When · where · with whom · mentions · effect · filter, a new
            // one every 3 seconds (Instagram), then the caption.
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 2),
              RotatingMeta(
                key: ValueKey('exp-meta-${current['id']}'),
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                lines: [
                  if (t != null)
                    MetaLine(
                        key: 'day',
                        lead: const Icon(Icons.schedule_rounded, size: 14, color: Colors.white70),
                        text: '${_weekdays[t.weekday - 1]} · ${TimeOfDay.fromDateTime(t).format(context)}'),
                  ...experienceMetaLines(
                    current,
                    collaborators: _team,
                    onPlace: places.isEmpty ? null : () => showExperienceMap(context, places, focus: current),
                    onProfile: (u) => openMentionProfile(context, u),
                  ),
                ],
              ),
              if (caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: MentionText(caption,
                      style: const TextStyle(color: Colors.white60, fontSize: 13.5)),
                ),
            ]),
            trailing: (current['reactions'] as List? ?? const []).isEmpty
                ? null
                : Text((current['reactions'] as List).map((r) => r['emoji']).take(4).join(' '),
                    style: const TextStyle(fontSize: 18)),
          ),
          if (!mineCard)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                for (final e in ['\u{1F602}', '\u{2764}\u{FE0F}', '\u{1F60D}', '\u{1F525}'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _react(e),
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: PhlioColors.surfaceElevated, shape: BoxShape.circle),
                        child: Text(e, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _reply,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Leave a comment…',
                      isDense: true,
                      filled: true,
                      fillColor: PhlioColors.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

// -- map ------------------------------------------------------------------------------------

/// Where the dump's photos were taken: pins on a map, the chosen place's
/// name and address, and Open in Maps.
Future<void> showExperienceMap(BuildContext context, List<Map> items, {Map? focus}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PhlioColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ExperienceMap(items: items, focus: focus),
    );

class _ExperienceMap extends StatefulWidget {
  const _ExperienceMap({required this.items, this.focus});
  final List<Map> items;
  final Map? focus;
  @override
  State<_ExperienceMap> createState() => _ExperienceMapState();
}

class _ExperienceMapState extends State<_ExperienceMap> {
  GoogleMapController? _map;
  late Map _selected = widget.focus ?? widget.items.first;

  /// One entry per distinct spot (several photos can share one).
  late final List<Map> _spots = () {
    final seen = <String>{};
    return [
      for (final m in widget.items)
        if (seen.add('${(m['location'] as Map)['lat']},${(m['location'] as Map)['lng']}')) m
    ];
  }();

  LatLng _at(Map m) {
    final l = m['location'] as Map;
    return LatLng((l['lat'] as num).toDouble(), (l['lng'] as num).toDouble());
  }

  void _fit() {
    final map = _map;
    if (map == null) return;
    if (_spots.length < 2) {
      map.moveCamera(CameraUpdate.newLatLngZoom(_at(_selected), 15.5));
      return;
    }
    var s = _at(_spots.first), n = s;
    for (final m in _spots) {
      final p = _at(m);
      s = LatLng(math.min(s.latitude, p.latitude), math.min(s.longitude, p.longitude));
      n = LatLng(math.max(n.latitude, p.latitude), math.max(n.longitude, p.longitude));
    }
    map.moveCamera(CameraUpdate.newLatLngBounds(LatLngBounds(southwest: s, northeast: n), 60));
  }

  @override
  Widget build(BuildContext context) {
    final place = _selected['location'] as Map;
    final at = _at(_selected);
    final photos = widget.items.where((m) => _at(m) == at).length;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Column(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: at, zoom: 15),
              style: phlioMapStyle,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              onMapCreated: (c) {
                _map = c;
                Future<void>.delayed(const Duration(milliseconds: 250), _fit);
              },
              markers: {
                for (final m in _spots)
                  Marker(
                    markerId: MarkerId('${m['id']}'),
                    position: _at(m),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        _at(m) == at ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueViolet),
                    infoWindow: InfoWindow(title: '${(m['location'] as Map)['name']}'),
                    onTap: () => setState(() => _selected = m),
                  ),
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 58,
              height: 58,
              child: ClipRRect(borderRadius: BorderRadius.circular(10), child: _Polaroid(item: _selected)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${place['name']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                if ('${place['address'] ?? ''}'.isNotEmpty)
                  Text('${place['address']}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 4),
                Text(
                    [
                      '$photos photo${photos == 1 ? '' : 's'} here',
                      if (place['source'] == 'photo') 'location from the photo',
                      '${at.latitude.toStringAsFixed(5)}, ${at.longitude.toStringAsFixed(5)}',
                    ].join(' · '),
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
            ),
          ]),
        ),
        if (_spots.length > 1)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final m in _spots)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${(m['location'] as Map)['name']}'),
                      selected: _at(m) == at,
                      onSelected: (_) {
                        setState(() => _selected = m);
                        _map?.animateCamera(CameraUpdate.newLatLngZoom(_at(m), 16));
                      },
                    ),
                  ),
              ],
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => openInMaps(at.latitude, at.longitude),
                icon: const Icon(Icons.directions_rounded),
                label: const Text('Open in Maps'),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
