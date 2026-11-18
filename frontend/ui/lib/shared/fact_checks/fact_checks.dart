// Community fact checks ("Readers added context"), Community Notes style,
// for Phlio Social (posts, videos, clips), Rooms and News.
//
// * [FactCheckSection] sits under a piece of content (ContentSurface adds it
//   for social/rooms/news). It shows the note readers found helpful — only
//   notes rated helpful by people who usually disagree are shown — and a
//   slim "proposed notes need ratings" line otherwise.
// * [showAddFactCheck] writes a note: a classification, the context and
//   1–5 https sources.
// * [showRateFactChecks] lets people rate proposed notes.
//
// Feeds ask the server in batches (one POST /fact-checks/batch per frame for
// everything on screen). Backend: backend/app/api/v1/fact_checks.py.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../../design_system/colors.dart';

/// Platforms that take fact checks.
const factCheckPlatforms = {'social', 'rooms', 'news'};

const _accent = Color(0xFF3897F0);

const _classes = <(String, String, IconData)>[
  ('missing_context', 'Missing important context', Icons.info_outline_rounded),
  ('misleading', 'Misleading or false', Icons.report_gmailerrorred_rounded),
  ('outdated', 'Outdated', Icons.history_rounded),
  ('satire', 'Satire or parody', Icons.theater_comedy_outlined),
  ('accurate', 'Accurate, adds useful context', Icons.verified_outlined),
];

String _classLabel(String id) => _classes.firstWhere((c) => c.$1 == id, orElse: () => _classes.first).$2;

String _error(Object e) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is Map) {
      final msg = d['detail'] ?? (d['error'] is Map ? (d['error'] as Map)['message'] : null);
      if (msg is String) return msg;
      if (msg is List && msg.isNotEmpty && msg.first is Map) return '${(msg.first as Map)['msg']}';
    }
    if (e.response?.statusCode == 404) return 'Fact checks aren\'t on the server yet.';
    if (e.response == null) return 'You seem to be offline.';
  }
  return 'Something went wrong. Try again.';
}

/// Batches summary lookups for everything on screen into one request.
class _FactCheckStore {
  _FactCheckStore._();
  static final instance = _FactCheckStore._();

  final _values = <String, ValueNotifier<Map?>>{};
  final _pending = <String>{};
  Timer? _timer;

  ValueNotifier<Map?> watch(String target) {
    final n = _values.putIfAbsent(target, () => ValueNotifier<Map?>(null));
    if (n.value == null) {
      _pending.add(target);
      _timer ??= Timer(const Duration(milliseconds: 60), _flush);
    }
    return n;
  }

  void refresh(String target) {
    _values[target]?.value = null;
    watch(target);
  }

  Future<void> _flush() async {
    _timer = null;
    final batch = _pending.take(60).toList();
    _pending.removeAll(batch);
    if (_pending.isNotEmpty) _timer = Timer(const Duration(milliseconds: 60), _flush);
    if (batch.isEmpty) return;
    try {
      final res = await getIt<ApiClient>().dio.post<dynamic>('/fact-checks/batch', data: {'targets': batch});
      final data = Map<String, dynamic>.from(res.data as Map);
      for (final t in batch) {
        _values[t]?.value = (data[t] as Map?) ?? const {'shown': [], 'proposed_count': 0};
      }
    } catch (_) {
      // Server without fact checks / offline: show nothing.
      for (final t in batch) {
        _values[t]?.value = const {'shown': [], 'proposed_count': 0};
      }
    }
  }
}

/// The context note under a post, video, room or article.
class FactCheckSection extends StatelessWidget {
  const FactCheckSection({required this.target, super.key, this.padding = const EdgeInsets.only(top: 8)});

  /// `platform/contentId`, e.g. `social/abc123`.
  final String target;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map?>(
      valueListenable: _FactCheckStore.instance.watch(target),
      builder: (context, summary, _) {
        if (summary == null) return const SizedBox.shrink();
        final shown = (summary['shown'] as List? ?? const []).cast<Map>();
        final proposed = (summary['proposed_count'] as num?)?.toInt() ?? 0;
        if (shown.isNotEmpty) {
          return Padding(padding: padding, child: FactCheckCard(note: shown.first, target: target));
        }
        if (proposed == 0) return const SizedBox.shrink();
        return Padding(
          padding: padding,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => showRateFactChecks(context, target),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Row(children: [
                const Icon(Icons.groups_2_outlined, size: 16, color: _accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    proposed == 1 ? '1 proposed note needs ratings' : '$proposed proposed notes need ratings',
                    style: const TextStyle(color: _accent, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                const Text('Rate', style: TextStyle(color: _accent, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// "Readers added context" card.
class FactCheckCard extends StatelessWidget {
  const FactCheckCard({required this.note, required this.target, super.key});
  final Map note;
  final String target;

  @override
  Widget build(BuildContext context) {
    final sources = (note['sources'] as List? ?? const []).cast<Map>();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: PhlioColors.surfaceElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PhlioColors.borderSubtle),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.groups_2_rounded, size: 18, color: _accent),
          SizedBox(width: 6),
          Text('Readers added context', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        Text('${note['text']}', style: const TextStyle(height: 1.35)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in sources)
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.link_rounded, size: 15),
              label: Text('${s['host']}', style: const TextStyle(fontSize: 12)),
              onPressed: () => launchUrl(Uri.parse('${s['url']}'), mode: LaunchMode.externalApplication),
            ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Text(
              'Rated helpful by people with different points of view',
              style: TextStyle(color: PhlioColors.textMuted.withValues(alpha: 0.9), fontSize: 11.5),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => showRateFactChecks(context, target, focus: '${note['id']}'),
            child: const Text('Rate it'),
          ),
        ]),
      ]),
    );
  }
}

/// Long-press actions for content that takes fact checks.
Future<void> showFactCheckActions(BuildContext context, String target, {required VoidCallback onShare}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: PhlioColors.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: const Text('Share'),
            onTap: () {
              Navigator.pop(sheet);
              onShare();
            },
          ),
          ListTile(
            leading: const Icon(Icons.note_add_outlined, color: _accent),
            title: const Text('Add context (fact check)'),
            subtitle: const Text('Help others with credible sources'),
            onTap: () {
              Navigator.pop(sheet);
              showAddFactCheck(context, target);
            },
          ),
          ListTile(
            leading: const Icon(Icons.how_to_vote_outlined),
            title: const Text('Rate proposed notes'),
            onTap: () {
              Navigator.pop(sheet);
              showRateFactChecks(context, target);
            },
          ),
        ]),
      ),
    );

Future<void> showAddFactCheck(BuildContext context, String target) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PhlioColors.surface,
      showDragHandle: true,
      builder: (_) => _AddNoteSheet(target: target),
    );

class _AddNoteSheet extends StatefulWidget {
  const _AddNoteSheet({required this.target});
  final String target;

  @override
  State<_AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends State<_AddNoteSheet> {
  final _text = TextEditingController();
  final _sources = [TextEditingController()];
  String classification = 'missing_context';
  bool busy = false;
  String? error;

  @override
  void dispose() {
    _text.dispose();
    for (final s in _sources) {
      s.dispose();
    }
    super.dispose();
  }

  List<String> get _links => [for (final s in _sources) if (s.text.trim().isNotEmpty) s.text.trim()];

  bool get _valid =>
      _text.text.trim().length >= 20 && _links.isNotEmpty && _links.every((l) => Uri.tryParse(l)?.scheme == 'https');

  Future<void> _submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await getIt<ApiClient>().dio.post<dynamic>('/fact-checks', data: {
        'target': widget.target,
        'classification': classification,
        'text': _text.text.trim(),
        'sources': _links,
      });
      _FactCheckStore.instance.refresh(widget.target);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Thanks! Your note will show once people with different views rate it helpful.')));
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = _error(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('Add context', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Write for people who may disagree with you. Stick to facts, cite credible sources, skip opinions.',
            style: TextStyle(color: PhlioColors.textMuted),
          ),
          const SizedBox(height: 14),
          const Text('This content is…', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final (id, label, icon) in _classes)
            RadioListTile<String>(
              value: id,
              groupValue: classification,
              onChanged: (v) => setState(() => classification = v!),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Row(children: [Icon(icon, size: 18), const SizedBox(width: 8), Flexible(child: Text(label))]),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            maxLength: 500,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Context',
              hintText: 'What should people know? e.g. "This photo is from 2019, not this week."',
              alignLabelWithHint: true,
            ),
          ),
          const Text('Sources (https links)', style: TextStyle(fontWeight: FontWeight.w700)),
          for (var i = 0; i < _sources.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _sources[i],
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'https://…',
                  prefixIcon: const Icon(Icons.link_rounded),
                  suffixIcon: _sources.length == 1
                      ? IconButton(
                          tooltip: 'Paste',
                          icon: const Icon(Icons.content_paste_rounded),
                          onPressed: () async {
                            final clip = await Clipboard.getData(Clipboard.kTextPlain);
                            if (clip?.text != null) setState(() => _sources[i].text = clip!.text!.trim());
                          })
                      : IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() => _sources.removeAt(i).dispose()),
                        ),
                ),
              ),
            ),
          if (_sources.length < 5)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _sources.add(TextEditingController())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add another source'),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error!, style: const TextStyle(color: Color(0xFFFF5C5C))),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _valid && !busy ? _submit : null,
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Submit note'),
          ),
        ]),
      ),
    );
  }
}

/// Rate proposed notes on [target] (or the shown one, via [focus]).
Future<void> showRateFactChecks(BuildContext context, String target, {String? focus}) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PhlioColors.surface,
      showDragHandle: true,
      builder: (_) => _RateSheet(target: target, focus: focus),
    );

class _RateSheet extends StatefulWidget {
  const _RateSheet({required this.target, this.focus});
  final String target;
  final String? focus;

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  List<Map> notes = const [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = (await getIt<ApiClient>().dio.get<dynamic>('/fact-checks', queryParameters: {'target': widget.target}))
          .data as Map;
      final all = [...(data['shown'] as List? ?? const []), ...(data['proposed'] as List? ?? const [])].cast<Map>();
      if (mounted) {
        setState(() {
          notes = all;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _error(e);
          loading = false;
        });
      }
    }
  }

  Future<void> _rate(Map note, String rating) async {
    HapticFeedback.selectionClick();
    try {
      final res = await getIt<ApiClient>()
          .dio
          .put<dynamic>('/fact-checks/${note['id']}/rating', data: {'rating': rating});
      final updated = Map<String, dynamic>.from(res.data as Map);
      setState(() => notes = [for (final n in notes) n['id'] == note['id'] ? updated : n]);
      _FactCheckStore.instance.refresh(widget.target);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error(e))));
    }
  }

  Future<void> _delete(Map note) async {
    try {
      await getIt<ApiClient>().dio.delete<dynamic>('/fact-checks/${note['id']}');
      setState(() => notes = notes.where((n) => n['id'] != note['id']).toList());
      _FactCheckStore.instance.refresh(widget.target);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Row(children: [
          const Expanded(child: Text('Community notes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              showAddFactCheck(context, widget.target);
            },
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Add'),
          ),
        ]),
        const Text(
          'Notes appear only when people who usually disagree both rate them helpful.',
          style: TextStyle(color: PhlioColors.textMuted),
        ),
        const SizedBox(height: 14),
        if (loading) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
        if (error != null) Padding(padding: const EdgeInsets.all(20), child: Text(error!)),
        if (!loading && error == null && notes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No notes yet. Know something useful? Add context.',
                textAlign: TextAlign.center, style: TextStyle(color: PhlioColors.textMuted)),
          ),
        for (final n in notes) _NoteTile(note: n, highlighted: n['id'] == widget.focus, onRate: _rate, onDelete: _delete),
      ]),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.highlighted, required this.onRate, required this.onDelete});
  final Map note;
  final bool highlighted;
  final void Function(Map, String) onRate;
  final void Function(Map) onDelete;

  @override
  Widget build(BuildContext context) {
    final status = '${note['status']}';
    final mine = note['mine'] == true;
    final my = note['my_rating'] as String?;
    final (statusLabel, statusColor) = switch (status) {
      'helpful' => ('Shown: rated helpful', const Color(0xFF39D98A)),
      'not_helpful' => ('Not shown: rated not helpful', const Color(0xFFFF5C5C)),
      _ => ('Needs more ratings', PhlioColors.textMuted),
    };
    Widget choice(String id, String label, IconData icon) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: my == id ? _accent.withValues(alpha: 0.18) : null,
                side: BorderSide(color: my == id ? _accent : PhlioColors.borderSubtle),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              ),
              onPressed: () => onRate(note, id),
              icon: Icon(icon, size: 16),
              label: FittedBox(child: Text(label)),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PhlioColors.surfaceElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlighted ? _accent : PhlioColors.borderSubtle),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(_classLabel('${note['classification']}'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Text('${note['text']}', style: const TextStyle(height: 1.35)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          for (final s in (note['sources'] as List? ?? const []).cast<Map>())
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text('${s['host']}', style: const TextStyle(fontSize: 12)),
              onPressed: () => launchUrl(Uri.parse('${s['url']}'), mode: LaunchMode.externalApplication),
            ),
        ]),
        const SizedBox(height: 8),
        if (mine)
          Row(children: [
            Text('Your note · ${note['rating_count'] ?? 0} ratings',
                style: const TextStyle(color: PhlioColors.textMuted, fontSize: 12)),
            const Spacer(),
            TextButton(onPressed: () => onDelete(note), child: const Text('Delete')),
          ])
        else ...[
          const Text('Is this note helpful?', style: TextStyle(fontSize: 12.5, color: PhlioColors.textMuted)),
          const SizedBox(height: 6),
          Row(children: [
            choice('helpful', 'Yes', Icons.thumb_up_alt_outlined),
            choice('somewhat', 'Somewhat', Icons.thumbs_up_down_outlined),
            choice('not_helpful', 'No', Icons.thumb_down_alt_outlined),
          ]),
        ],
      ]),
    );
  }
}

/// Settings → Rate community notes: proposed notes from across Phlio that
/// you haven't rated yet.
class FactCheckQueueScreen extends StatefulWidget {
  const FactCheckQueueScreen({super.key});

  @override
  State<FactCheckQueueScreen> createState() => _FactCheckQueueScreenState();
}

class _FactCheckQueueScreenState extends State<FactCheckQueueScreen> {
  List<Map> items = const [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final data = (await getIt<ApiClient>().dio.get<dynamic>('/fact-checks/queue')).data as Map;
      if (mounted) {
        setState(() {
          items = (data['items'] as List? ?? const []).cast<Map>();
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _error(e);
          loading = false;
        });
      }
    }
  }

  Future<void> _rate(Map note, String rating) async {
    HapticFeedback.selectionClick();
    try {
      await getIt<ApiClient>().dio.put<dynamic>('/fact-checks/${note['id']}/rating', data: {'rating': rating});
      _FactCheckStore.instance.refresh('${note['target']}');
      setState(() => items = items.where((n) => n['id'] != note['id']).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error(e))));
    }
  }

  static String _where(String target) => switch (target.split('/').first) {
        'news' => 'On a news story',
        'rooms' => 'On a room',
        _ => 'On a post or video',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rate community notes')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
            'Rate honestly, including notes you disagree with. A note is shown only when people with different views find it helpful.',
            style: TextStyle(color: PhlioColors.textMuted),
          ),
          const SizedBox(height: 14),
          if (loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (error != null) Padding(padding: const EdgeInsets.all(20), child: Text(error!)),
          if (!loading && error == null && items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Text("You're all caught up.", textAlign: TextAlign.center, style: TextStyle(color: PhlioColors.textMuted)),
            ),
          for (final n in items) ...[
            Text(_where('${n['target']}'), style: const TextStyle(color: PhlioColors.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            _NoteTile(note: n, highlighted: false, onRate: _rate, onDelete: (_) {}),
          ],
        ]),
      ),
    );
  }
}
