// The smart filter editor (Snapchat-style info filters), used by the
// moment composer, the snap "Send to…" screen and "Edit filters" on posted
// moments and snaps.
//
// Swipe the strip at the bottom (or tap a card) to add Time, Date,
// Weather, Place, Speed, Battery, Day or Greeting — each reads the real
// value now. Drag an overlay to move it, pinch to resize / rotate, tap to
// select it and change its style or colour, or delete it. "My filters"
// saves the arrangement to your account (/social/filters/presets) to reuse.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';
import '../location/location_service.dart' show LocationProblem;
import 'smart_filters.dart';

/// Opens the editor over [media] (a widget showing the photo / video).
/// [aspectRatio] is the media's shape (9/16 for moments, 1 for snaps).
/// Returns the edited spec, or null when cancelled.
Future<FilterSpec?> openSmartFilterEditor(
  BuildContext context, {
  required Widget media,
  FilterSpec? initial,
  double aspectRatio = 9 / 16,
}) =>
    Navigator.of(context, rootNavigator: true).push<FilterSpec>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _SmartFilterEditor(media: media, initial: initial, aspectRatio: aspectRatio),
    ));

class _SmartFilterEditor extends StatefulWidget {
  const _SmartFilterEditor({required this.media, required this.aspectRatio, this.initial});
  final Widget media;
  final FilterSpec? initial;
  final double aspectRatio;

  @override
  State<_SmartFilterEditor> createState() => _SmartFilterEditorState();
}

class _SmartFilterEditorState extends State<_SmartFilterEditor> {
  late final FilterSpec spec = widget.initial?.copy() ?? FilterSpec();
  SmartOverlay? selected;
  String? adding;
  List<Map> presets = const [];

  // Gesture start values.
  double _startScale = 1, _startRotation = 0;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    try {
      final data = (await getIt<ApiClient>().dio.get<dynamic>('/social/filters/presets')).data as Map;
      if (mounted) setState(() => presets = (data['items'] as List? ?? const []).cast<Map>());
    } catch (_) {}
  }

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _add(String type) async {
    if (spec.overlays.length >= 6) {
      _say('Up to six filters on one photo.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => adding = type);
    try {
      final data = await captureOverlayData(type);
      if (!mounted) return;
      // New overlays stack down the canvas so they don't land on each other.
      final y = (.18 + spec.overlays.length * .13).clamp(.1, .9);
      final overlay = SmartOverlay(type: type, style: smartOverlayStyles[type]!.first, y: y, data: data);
      setState(() {
        spec.overlays.add(overlay);
        selected = overlay;
      });
    } on LocationProblem catch (e) {
      _say(e.toString());
    } catch (_) {
      _say(type == 'weather' || type == 'place' || type == 'speed'
          ? 'Could not read your location. Check location access and your connection.'
          : 'Could not add that filter.');
    } finally {
      if (mounted) setState(() => adding = null);
    }
  }

  Future<void> _applyPreset(Map preset) async {
    final p = FilterSpec.fromJson(preset['spec']);
    if (p == null) return;
    setState(() => adding = 'preset');
    final filled = <SmartOverlay>[];
    for (final o in p.overlays) {
      try {
        o.data = await captureOverlayData(o.type); // fresh values, saved layout
        filled.add(o);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      spec.overlays
        ..clear()
        ..addAll(filled);
      selected = null;
      adding = null;
    });
    if (filled.length < p.overlays.length) _say('Some filters need location access.');
  }

  Future<void> _savePreset() async {
    if (spec.overlays.isEmpty) {
      _say('Add a filter first.');
      return;
    }
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Save to My filters'),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'e.g. Road trip'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
        ],
      ),
    );
    final label = name.text.trim();
    name.dispose();
    if (ok != true || label.isEmpty) return;
    try {
      await getIt<ApiClient>().dio.post<dynamic>('/social/filters/presets', data: {'name': label, 'spec': spec.toJson()});
      _say('Saved to My filters');
      _loadPresets();
    } catch (e) {
      final detail = e is DioException && e.response?.data is Map ? (e.response!.data as Map)['detail'] : null;
      _say(detail is String ? detail : 'Could not save. Try again.');
    }
  }

  Future<void> _deletePreset(Map preset) async {
    try {
      await getIt<ApiClient>().dio.delete<dynamic>('/social/filters/presets/${preset['id']}');
      _loadPresets();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
            child: Row(children: [
              IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Text('Filters',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Save to My filters',
                icon: const Icon(Icons.bookmark_add_outlined, color: Colors.white),
                onPressed: _savePreset,
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, spec),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFD60A), foregroundColor: Colors.black),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: widget.aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LayoutBuilder(builder: (context, box) {
                    final canvas = Size(box.maxWidth, box.maxHeight);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => selected = null),
                      child: Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
                        IgnorePointer(child: widget.media),
                        for (final o in spec.overlays)
                          positionedOverlay(o, canvas, wrap: (view) => _gestures(o, canvas, view)),
                        if (adding != null)
                          const Center(child: CircularProgressIndicator(color: Colors.white)),
                      ]),
                    );
                  }),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (selected != null) _selectedTools(selected!) else _strip(),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  Widget _gestures(SmartOverlay o, Size canvas, Widget view) => GestureDetector(
        onTap: () => setState(() => selected = o),
        onScaleStart: (_) {
          _startScale = o.scale;
          _startRotation = o.rotation;
          setState(() => selected = o);
        },
        onScaleUpdate: (d) => setState(() {
          o
            ..x = (o.x + d.focalPointDelta.dx / canvas.width).clamp(0.02, .98)
            ..y = (o.y + d.focalPointDelta.dy / canvas.height).clamp(0.02, .98);
          if (d.pointerCount > 1) {
            o
              ..scale = (_startScale * d.scale).clamp(.3, 4)
              ..rotation = (_startRotation + d.rotation).clamp(-3.1, 3.1);
          }
        }),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: selected == o ? Colors.white70 : Colors.transparent, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(padding: const EdgeInsets.all(4), child: view),
        ),
      );

  /// Snapchat-style strip of filter cards, plus My filters.
  Widget _strip() => Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final entry in smartOverlayInfo.entries)
                _Card(
                  icon: entry.value.$2,
                  label: entry.value.$1,
                  busy: adding == entry.key,
                  onTap: () => _add(entry.key),
                ),
            ],
          ),
        ),
        if (presets.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              children: [
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text('My filters', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700)),
                  ),
                ),
                for (final p in presets)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      label: Text('${p['name']}'),
                      avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                      onPressed: () => _applyPreset(p),
                      onDeleted: () => _deletePreset(p),
                    ),
                  ),
              ],
            ),
          ),
      ]);

  Widget _selectedTools(SmartOverlay o) => Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final style in smartOverlayStyles[o.type]!)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(style[0].toUpperCase() + style.substring(1)),
                    selected: o.style == style,
                    onSelected: (_) => setState(() => o.style = style),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final c in smartOverlayColors)
                GestureDetector(
                  onTap: () => setState(() => o.color = c),
                  child: Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: o.color == c ? const Color(0xFFFFD60A) : Colors.white38, width: 3),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton.icon(
            onPressed: () async {
              try {
                final data = await captureOverlayData(o.type);
                if (mounted) setState(() => o.data = data);
              } catch (_) {}
            },
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            label: const Text('Refresh value', style: TextStyle(color: Colors.white70)),
          ),
          TextButton.icon(
            onPressed: () => setState(() {
              spec.overlays.remove(o);
              selected = null;
            }),
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF4D67)),
            label: const Text('Remove', style: TextStyle(color: Color(0xFFFF4D67))),
          ),
          TextButton(
            onPressed: () => setState(() => selected = null),
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ]),
      ]);
}

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.label, required this.onTap, this.busy = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            width: 78,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A2E37), Color(0xFF1A1D24)],
              ),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              busy
                  ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(icon, color: Colors.white, size: 28),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}
