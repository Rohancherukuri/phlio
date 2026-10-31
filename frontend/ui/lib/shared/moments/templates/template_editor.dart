// Moment templates — the gallery and the editor.
//
// Create (Aa) in the moment camera, Templates in the composer and the
// "Templates" sticker all open [openMomentTemplates]:
//
//   Gallery  Portraits · Collages · Creator · Trending · Quotes & advice,
//            each design previewed live, plus "Start blank".
//   Editor   tap a frame to add a photo (double-tap to pan / zoom it, the
//            Photo sheet for looks and shapes), tap a text to restyle it:
//            any text, 16 fonts, size, weight, italic, case, spacing, line
//            height, alignment, colour, eight backgrounds (highlight, pill,
//            outline, neon, gradient, sticker…) and trending placements
//            (headline, lower third, caption bar, side, tilted, corner tag).
//            Add text, #tags, @mentions and locations; change the shader
//            background. Drag to move, pinch to resize, twist to rotate.
//   Next     exports a 1080 × 1920 PNG that opens in the composer, with the
//            tags and mentions added to the caption.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/config/app_config.dart';
import '../../../design_system/colors.dart';
import '../../media/phlio_look_data.dart';
import '../stickers/sticker_tray.dart' show askText;
import 'template_canvas.dart';
import 'template_catalog.dart';
import 'template_model.dart';
import 'template_store.dart';

const _brand = LinearGradient(colors: [PhlioColors.brandViolet, PhlioColors.brandPink, PhlioColors.brandPeach]);

/// What the template flow produced.
class TemplateOutcome {
  const TemplateOutcome.image(String this.path, {this.tags = const [], this.mentions = const []})
      : blank = false,
        prompt = null;
  const TemplateOutcome.blank()
      : path = null,
        tags = const [],
        mentions = const [],
        prompt = null,
        blank = true;

  /// Joining a trending "Add yours" prompt: the composer adds the sticker
  /// and opens the gallery.
  const TemplateOutcome.prompt(String this.prompt)
      : path = null,
        tags = const [],
        mentions = const [],
        blank = false;

  /// The exported PNG (null for [blank] and [prompt]).
  final String? path;

  /// #tags and @mentions used on the design (for the caption).
  final List<String> tags, mentions;

  /// "Start blank": the classic text-on-gradient moment.
  final bool blank;

  /// An "Add yours" prompt to answer.
  final String? prompt;
}

/// Opens the template gallery; returns the finished design or null.
Future<TemplateOutcome?> openMomentTemplates(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push<TemplateOutcome>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const MomentTemplateGallery()));

// -- gallery ----------------------------------------------------------------------------

/// Browse (community prompts, trending prompts, templates by group) and
/// Saved (your bookmarks and your own designs); + starts a blank design.
class MomentTemplateGallery extends StatefulWidget {
  const MomentTemplateGallery({super.key});
  @override
  State<MomentTemplateGallery> createState() => _MomentTemplateGalleryState();
}

class _MomentTemplateGalleryState extends State<MomentTemplateGallery> {
  bool _saved = false; // Browse / Saved tab
  late final Future<List<TrendingPrompt>> _prompts = loadTrendingPrompts();
  final _store = SavedTemplates.instance;

  /// Previews are built once (fresh elements per template).
  final _previews = <String, (TBackdrop, List<TElement>)>{};
  (TBackdrop, List<TElement>) _preview(MomentTemplate t) => _previews[t.id] ??= (t.backdrop(), t.build());

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    _previews.removeWhere((id, _) => id.startsWith('mine_')); // a design was re-saved
    if (mounted) setState(() {});
  }

  Future<void> _open(MomentTemplate t) async {
    HapticFeedback.selectionClick();
    final out = await Navigator.of(context)
        .push<TemplateOutcome>(MaterialPageRoute(builder: (_) => MomentTemplateEditor(template: t)));
    if (out != null && mounted) Navigator.pop(context, out);
  }

  void _addYours(String prompt) => Navigator.pop(context, TemplateOutcome.prompt(prompt));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhlioColors.background,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
            child: Row(children: [
              IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white)),
              const Spacer(),
              for (final (saved, label) in const [(false, 'Browse'), (true, 'Saved')])
                GestureDetector(
                  onTap: () => setState(() => _saved = saved),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(label,
                        style: TextStyle(
                            color: _saved == saved ? Colors.white : Colors.white54, fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Design your own',
                onPressed: () => _open(blankTemplate()),
                icon: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
              ),
            ]),
          ),
          Expanded(child: _saved ? _savedTab() : _browse()),
        ]),
      ),
    );
  }

  // -- Browse ------------------------------------------------------------------------------

  Widget _browse() => FutureBuilder<List<TrendingPrompt>>(
        future: _prompts,
        builder: (_, snap) {
          final prompts = snap.data ?? [for (final p in curatedPrompts) TrendingPrompt(p)];
          final community = prompts.where((p) => p.coverUrl != null).toList();
          return ListView(padding: const EdgeInsets.only(bottom: 28), children: [
            if (community.isNotEmpty) ...[
              _header('From the community'),
              SizedBox(
                height: 236,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: community.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _CommunityCard(prompt: community[i], onAdd: () => _addYours(community[i].prompt)),
                ),
              ),
            ],
            _header('Trending prompts'),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: prompts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _PromptCard(prompt: prompts[i], onAdd: () => _addYours(prompts[i].prompt)),
              ),
            ),
            _shelf('Trending templates', momentTemplates.where((t) => t.category == TemplateCategory.trending).toList(), big: true),
            for (final c in TemplateCategory.values)
              if (c != TemplateCategory.trending)
                _shelf(templateCategoryNames[c]!, momentTemplates.where((t) => t.category == c).toList()),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.all(14)),
                onPressed: () => Navigator.pop(context, const TemplateOutcome.blank()),
                icon: const Text('Aa', style: TextStyle(fontWeight: FontWeight.w800)),
                label: const Text('Type on a gradient instead'),
              ),
            ),
          ]);
        },
      );

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
      );

  Widget _shelf(String title, List<MomentTemplate> list, {bool big = false}) {
    final w = big ? 200.0 : 132.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(title),
      SizedBox(
        height: w * 16 / 9 + 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(width: w, child: _tile(list[i])),
        ),
      ),
    ]);
  }

  /// A template preview with its name and a save (bookmark) button.
  Widget _tile(MomentTemplate t) {
    final (bd, els) = _preview(t);
    final saved = _store.isSaved(t.id);
    return GestureDetector(
      onTap: () => _open(t),
      // The preview takes whatever height is left after the two text lines,
      // so larger text sizes never overflow the shelf.
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: AspectRatio(
          aspectRatio: 9 / 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(fit: StackFit.expand, children: [
              IgnorePointer(child: TemplateCanvas(backdrop: bd, elements: els, animate: false, thumbnail: true)),
              Positioned(
                right: 4,
                top: 4,
                child: Material(
                  color: Colors.black38,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: saved ? 'Remove from saved' : 'Save template',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      if (t.id.startsWith('mine_')) {
                        _store.remove(t.id);
                      } else {
                        _store.toggle(t.id);
                      }
                    },
                    icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ]),
          ),
        ),
        ),
        const SizedBox(height: 6),
        Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        Text(t.trend ?? '${t.slots} photo${t.slots == 1 ? '' : 's'}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ]),
    );
  }

  // -- Saved -------------------------------------------------------------------------------

  Widget _savedTab() {
    final list = _store.templates;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.bookmark_border_rounded, color: Colors.white38, size: 54),
            const SizedBox(height: 12),
            const Text('No saved templates yet', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Tap the bookmark on any template, or save your own design from the editor.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: () => _open(blankTemplate()), icon: const Icon(Icons.add_rounded), label: const Text('Design your own')),
          ]),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 170, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 9 / 19.4),
      itemCount: list.length,
      itemBuilder: (_, i) => _tile(list[i]),
    );
  }
}

/// White prompt card (like Instagram's), in Phlio colours: the prompt,
/// who joined, and "Add yours".
class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.prompt, required this.onAdd});
  final TrendingPrompt prompt;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Container(
        width: 240,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(prompt.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF111925), fontSize: 20, fontWeight: FontWeight.w600, height: 1.2)),
                const SizedBox(height: 10),
                _Joined(prompt: prompt),
              ]),
            ),
          ),
          const Divider(height: 1, color: Color(0x1A111925)),
          InkWell(
            onTap: onAdd,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 13),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.photo_camera_rounded, color: PhlioColors.brandViolet, size: 20),
                SizedBox(width: 8),
                Text('Add yours', style: TextStyle(color: PhlioColors.brandViolet, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      );
}

/// Reply arrow + up to three faces + "+N", or "Be the first".
class _Joined extends StatelessWidget {
  const _Joined({required this.prompt});
  final TrendingPrompt prompt;

  @override
  Widget build(BuildContext context) {
    if (prompt.count == 0) {
      return const Text('Be the first', style: TextStyle(color: Color(0xFF858D9E), fontWeight: FontWeight.w600));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _brand),
        child: const Icon(Icons.reply_rounded, color: Colors.white, size: 16),
      ),
      for (final p in prompt.people)
        Align(
          widthFactor: .7,
          child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
            child: CircleAvatar(
              radius: 13,
              backgroundColor: const Color(0xFFE6E4EF),
              backgroundImage: p['avatar_url'] is String ? NetworkImage(AppConfig.mediaUrl(p['avatar_url'] as String)) : null,
              child: p['avatar_url'] is String
                  ? null
                  : Text('${p['display_name'] ?? '?'}'.characters.first,
                      style: const TextStyle(color: Color(0xFF111925), fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      const SizedBox(width: 8),
      Text('+${_compact(prompt.count)}', style: const TextStyle(color: Color(0xFF858D9E), fontWeight: FontWeight.w600)),
    ]);
  }
}

String _compact(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M'
    : n >= 1000
        ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K'
        : '$n';

/// A community moment answering a prompt, with an "Add yours" pill.
class _CommunityCard extends StatelessWidget {
  const _CommunityCard({required this.prompt, required this.onAdd});
  final TrendingPrompt prompt;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onAdd,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 200,
            child: Stack(fit: StackFit.expand, children: [
              Image.network(AppConfig.mediaUrl(prompt.coverUrl!), fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const DecoratedBox(decoration: BoxDecoration(gradient: _brand))),
              const DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xAA000000)])),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(prompt.prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Text('+${_compact(prompt.count)}  ·  Add yours',
                        style: const TextStyle(color: PhlioColors.brandViolet, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );
}

// -- editor -----------------------------------------------------------------------------

class MomentTemplateEditor extends StatefulWidget {
  const MomentTemplateEditor({required this.template, super.key});
  final MomentTemplate template;
  @override
  State<MomentTemplateEditor> createState() => _MomentTemplateEditorState();
}

class _MomentTemplateEditorState extends State<MomentTemplateEditor> {
  late final TBackdrop _backdrop = widget.template.backdrop();
  late final List<TElement> _els = widget.template.build();
  final _canvasKey = GlobalKey();
  TElement? _selected;
  TElement? _adjusting; // slot whose photo is being panned / zoomed
  bool _exporting = false;
  double _k = 1; // screen px per design unit

  // Gesture bookkeeping.
  double _startFont = 0, _startScale = 1, _startRotation = 0;
  Size _startSize = Size.zero;

  void _select(TElement? e) => setState(() {
        _selected = e;
        if (e != _adjusting) _adjusting = null;
      });

  // -- photos -------------------------------------------------------------------------------

  Future<void> _pickInto(TElement slot) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2160, imageQuality: 92);
    if (picked == null) return;
    setState(() {
      slot
        ..photo = picked.path
        ..photoOffset = Offset.zero
        ..photoScale = 1;
    });
  }

  /// Fills empty frames, in order, from a multi-select.
  Future<void> _fillAll() async {
    final empty = _els.where((e) => e.isSlot && e.photo == null).toList();
    if (empty.isEmpty) {
      _say('Every frame already has a photo — tap one to replace it.');
      return;
    }
    final picked = await ImagePicker()
        .pickMultiImage(maxWidth: 2160, imageQuality: 92, limit: empty.length >= 2 ? empty.length : null);
    setState(() {
      for (final (i, p) in picked.take(empty.length).indexed) {
        empty[i].photo = p.path;
      }
    });
  }

  Future<void> _slotSheet(TElement slot) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: PhlioColors.surface,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, set) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
              title: Text(slot.photo == null ? 'Add photo' : 'Replace photo', style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheet);
                _pickInto(slot);
              },
            ),
            if (slot.photo != null) ...[
              ListTile(
                leading: const Icon(Icons.open_with_rounded, color: Colors.white),
                title: const Text('Move & zoom photo', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Or double-tap the frame', style: TextStyle(color: Colors.white54)),
                onTap: () {
                  Navigator.pop(sheet);
                  setState(() => _adjusting = slot);
                },
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Align(alignment: Alignment.centerLeft, child: Text('LOOK', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.4))),
              ),
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (final e in phlioLookNames.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: slot.look == e.key,
                        onSelected: (_) {
                          set(() {});
                          setState(() => slot.look = e.key);
                        },
                      ),
                    ),
                ]),
              ),
            ],
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Align(alignment: Alignment.centerLeft, child: Text('FRAME', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.4))),
            ),
            Wrap(spacing: 8, children: [
              for (final s in SlotShape.values)
                ChoiceChip(
                  label: Text(s.name[0].toUpperCase() + s.name.substring(1)),
                  selected: slot.shape == s,
                  onSelected: (_) {
                    set(() {});
                    setState(() {
                      slot.shape = s;
                      if (s == SlotShape.rounded && slot.radius == 0) slot.radius = 18;
                    });
                  },
                ),
            ]),
            if (slot.photo != null)
              ListTile(
                leading: const Icon(Icons.hide_image_outlined, color: PhlioColors.danger),
                title: const Text('Remove photo', style: TextStyle(color: PhlioColors.danger)),
                onTap: () {
                  Navigator.pop(sheet);
                  setState(() => slot.photo = null);
                },
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  // -- text ---------------------------------------------------------------------------------

  Future<void> _addText({TextRole role = TextRole.text}) async {
    String? value;
    switch (role) {
      case TextRole.tag:
        value = await askText(context, 'Hashtag', '#hashtag');
        value = value == null ? null : '#${value.replaceAll(' ', '').replaceFirst('#', '')}';
      case TextRole.mention:
        value = await askText(context, 'Mention', '@username');
        value = value == null ? null : '@${value.replaceAll(' ', '').replaceFirst('@', '')}';
      case TextRole.location:
        value = await askText(context, 'Location', 'Where are you?');
        value = value == null ? null : '📍 $value';
      default:
        value = 'Your text';
    }
    if (value == null || !mounted) return;
    final e = TElement.text(value, const Offset(180, 320),
        fontSize: role == TextRole.text ? 32 : 17,
        role: role,
        bg: role == TextRole.text ? TextBg.none : TextBg.sticker,
        bgColor: Colors.white,
        color: role == TextRole.text ? Colors.white : PhlioColors.brandViolet);
    setState(() {
      _els.add(e);
      _selected = e;
    });
    if (role == TextRole.text) await _textSheet(e, editText: true);
  }

  Future<void> _textSheet(TElement e, {bool editText = false}) async {
    _select(e);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.transparent,
      backgroundColor: const Color(0xF2111925),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => _TextSheet(e: e, focusText: editText, onChanged: () => setState(() {})),
    );
    if (mounted && e.text.trim().isEmpty) setState(() => _els.remove(e));
  }

  // -- background ---------------------------------------------------------------------------

  Future<void> _backgroundSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      barrierColor: Colors.transparent,
      backgroundColor: const Color(0xF2111925),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, set) {
          void update(VoidCallback f) {
            set(f);
            setState(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Background', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final s in BackdropStyle.values)
                    ChoiceChip(
                      label: Text(backdropNames[s]!),
                      selected: _backdrop.style == s,
                      onSelected: (_) => update(() => _backdrop.style = s),
                    ),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final p in backdropPalettes)
                      GestureDetector(
                        onTap: () => update(() => _backdrop.colors = [...p]),
                        child: Container(
                          width: 64,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(colors: [p[0], p[1], p[2]]),
                            border: Border.all(color: _backdrop.colors[0] == p[0] && _backdrop.colors[1] == p[1] ? Colors.white : Colors.white24, width: 2),
                          ),
                        ),
                      ),
                  ]),
                ),
                Row(children: [
                  const Text('Grain', style: TextStyle(color: Colors.white70)),
                  Expanded(child: Slider(value: _backdrop.grain, onChanged: (v) => update(() => _backdrop.grain = v))),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Animate while editing', style: TextStyle(color: Colors.white)),
                  value: _backdrop.animate,
                  onChanged: (v) => update(() => _backdrop.animate = v),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // -- export -------------------------------------------------------------------------------

  Future<void> _export() async {
    final empty = _els.where((e) => e.isSlot && e.photo == null).length;
    if (empty > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('$empty empty frame${empty == 1 ? '' : 's'}'),
          content: const Text('Empty frames show as soft gradients. Use the design anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Add photos')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Use it')),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() {
      _exporting = true;
      _selected = null;
      _adjusting = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    try {
      final boundary = _canvasKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/phlio_template_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(png!.buffer.asUint8List());
      if (!mounted) return;
      Navigator.pop(
          context,
          TemplateOutcome.image(file.path,
              tags: [for (final e in _els) if (e.isText && e.role == TextRole.tag) e.text.trim()],
              mentions: [for (final e in _els) if (e.isText && e.role == TextRole.mention) e.text.trim()]));
    } catch (_) {
      _say('Couldn\'t export the design. Try again.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Saves the layout (not the photos) to Templates → Saved.
  Future<void> _saveTemplate() async {
    final own = widget.template.id.startsWith('mine_');
    final name = await askText(context, 'Save template', 'Template name',
        initial: widget.template.id == 'blank' ? 'My design' : widget.template.name);
    if (name == null || !mounted) return;
    SavedTemplates.instance.saveDesign(name, _backdrop, _els, id: own ? widget.template.id : null);
    _say('Saved to your templates');
  }

  /// Adds an empty photo frame in the middle.
  void _addFrame() {
    final e = TElement.slot(const Offset(180, 320), const Size(220, 290), shape: SlotShape.rounded, radius: 18, shadow: true);
    setState(() {
      _els.add(e);
      _selected = e;
    });
  }

  void _say(String t) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t)));

  // -- gestures -------------------------------------------------------------------------------

  Widget _interactive(TElement e, Widget child) {
    final selected = _selected == e && !_exporting;
    final adjusting = _adjusting == e;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_selected == e) {
          if (e.isText) _textSheet(e);
          if (e.isSlot) e.photo == null ? _pickInto(e) : _slotSheet(e);
        } else {
          _select(e);
          if (e.isSlot && e.photo == null) _pickInto(e);
        }
      },
      onDoubleTap: e.isSlot && e.photo != null ? () => setState(() => _adjusting = adjusting ? null : e) : null,
      onScaleStart: (_) {
        if (_selected != e) _select(e);
        _startFont = e.fontSize;
        _startSize = e.size;
        _startScale = e.photoScale;
        _startRotation = e.rotation;
      },
      onScaleUpdate: (d) => setState(() {
        final delta = d.focalPointDelta / _k;
        if (adjusting) {
          e.photoOffset += delta;
          e.photoScale = (_startScale * d.scale).clamp(1.0, 5.0);
          return;
        }
        e.center = Offset((e.center.dx + delta.dx).clamp(0.0, templateSize.width), (e.center.dy + delta.dy).clamp(0.0, templateSize.height));
        if (d.pointerCount > 1) {
          if (e.isText) {
            e.fontSize = (_startFont * d.scale).clamp(8.0, 160.0);
          } else {
            e.size = Size((_startSize.width * d.scale).clamp(24.0, 720.0), (_startSize.height * d.scale).clamp(2.0, 1280.0));
          }
          e.rotation = _startRotation + d.rotation;
        }
      }),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: selected ? Border.all(color: adjusting ? PhlioColors.brandPeach : Colors.white, width: 1.5) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: child,
      ),
    );
  }

  // -- layout ---------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
            child: Row(children: [
              IconButton(
                  tooltip: 'Back', onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
              Expanded(
                child: Text(widget.template.name,
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              IconButton(
                tooltip: 'Save as a template',
                onPressed: _saveTemplate,
                icon: const Icon(Icons.bookmark_add_outlined, color: Colors.white),
              ),
              DecoratedBox(
                decoration: BoxDecoration(gradient: _brand, borderRadius: BorderRadius.circular(20)),
                child: TextButton(
                  onPressed: _exporting ? null : _export,
                  style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 18)),
                  child: _exporting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Next', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _select(null),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: LayoutBuilder(builder: (_, box) {
                    _k = box.maxWidth / templateSize.width;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: RepaintBoundary(
                        key: _canvasKey,
                        child: TemplateCanvas(
                          backdrop: _backdrop,
                          elements: _els,
                          animate: !_exporting,
                          elementBuilder: _interactive,
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          if (_adjusting != null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Drag and pinch to frame the photo · double-tap when done',
                  style: TextStyle(color: PhlioColors.brandPeach, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          SizedBox(
            height: 76,
            child: sel == null
                ? ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
                    _Tool('Aa', 'Text', () => _addText()),
                    _Tool('#', 'Tag', () => _addText(role: TextRole.tag)),
                    _Tool('@', 'Mention', () => _addText(role: TextRole.mention)),
                    _Tool(Icons.place_outlined, 'Location', () => _addText(role: TextRole.location)),
                    _Tool(Icons.add_photo_alternate_outlined, 'Frame', _addFrame),
                    _Tool(Icons.photo_library_outlined, 'Photos', _fillAll),
                    _Tool(Icons.gradient_rounded, 'Background', _backgroundSheet),
                  ])
                : ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
                    if (sel.isText) _Tool(Icons.text_fields_rounded, 'Style', () => _textSheet(sel)),
                    if (sel.isSlot) _Tool(Icons.photo_outlined, 'Photo', () => _slotSheet(sel)),
                    _Tool(Icons.flip_to_front_rounded, 'Front', () => setState(() {
                          _els
                            ..remove(sel)
                            ..add(sel);
                        })),
                    _Tool(Icons.copy_rounded, 'Duplicate', () => setState(() {
                          final c = sel.copy()..center = sel.center + const Offset(14, 14);
                          _els.add(c);
                          _selected = c;
                        })),
                    _Tool(Icons.rotate_right_rounded, 'Straighten', () => setState(() => sel.rotation = 0)),
                    _Tool(Icons.delete_outline_rounded, 'Delete', () => setState(() {
                          _els.remove(sel);
                          _selected = null;
                        })),
                    _Tool(Icons.check_rounded, 'Done', () => _select(null)),
                  ]),
          ),
        ]),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool(this.icon, this.label, this.onTap);

  /// An [IconData] or a short string glyph.
  final Object icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 70,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1E2532)),
              alignment: Alignment.center,
              child: icon is IconData
                  ? Icon(icon as IconData, color: Colors.white, size: 21)
                  : Text('$icon', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

// -- text style sheet -------------------------------------------------------------------------

/// Trending text placements: where and how a text sits on the canvas.
final _placements = <(String, IconData, void Function(TElement))>[
  ('Headline', Icons.vertical_align_top_rounded, (e) {
    e
      ..center = const Offset(180, 90)
      ..size = const Size(320, 0)
      ..rotation = 0
      ..align = TextAlign.center;
  }),
  ('Center', Icons.vertical_align_center_rounded, (e) {
    e
      ..center = const Offset(180, 320)
      ..size = const Size(300, 0)
      ..rotation = 0
      ..align = TextAlign.center;
  }),
  ('Lower third', Icons.subtitles_outlined, (e) {
    e
      ..center = const Offset(180, 470)
      ..size = const Size(310, 0)
      ..rotation = 0
      ..align = TextAlign.left
      ..bg = e.bg == TextBg.none ? TextBg.highlight : e.bg;
  }),
  ('Caption bar', Icons.view_agenda_outlined, (e) {
    e
      ..center = const Offset(180, 595)
      ..size = const Size(360, 0)
      ..rotation = 0
      ..align = TextAlign.center
      ..bg = TextBg.block
      ..bgColor = const Color(0xCC111925)
      ..color = Colors.white;
  }),
  ('Side', Icons.text_rotate_up_rounded, (e) {
    e
      ..center = const Offset(32, 320)
      ..size = const Size(560, 0)
      ..rotation = -math.pi / 2
      ..align = TextAlign.center;
  }),
  ('Tilted', Icons.rotate_left_rounded, (e) {
    e
      ..center = const Offset(190, 300)
      ..size = const Size(260, 0)
      ..rotation = -.12
      ..bg = TextBg.sticker
      ..bgColor = Colors.white
      ..color = const Color(0xFF111925);
  }),
  ('Corner tag', Icons.label_outline_rounded, (e) {
    e
      ..center = const Offset(270, 60)
      ..size = const Size(170, 0)
      ..rotation = .06
      ..fontSize = math.min(e.fontSize, 18.0)
      ..bg = TextBg.pill
      ..bgColor = PhlioColors.brandViolet
      ..color = Colors.white;
  }),
];

class _TextSheet extends StatefulWidget {
  const _TextSheet({required this.e, required this.onChanged, this.focusText = false});
  final TElement e;
  final VoidCallback onChanged;
  final bool focusText;
  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final _text = TextEditingController(text: widget.e.text);
  int _tab = 0;
  static const _tabs = ['Font', 'Size', 'Colour', 'Style', 'Place'];

  TElement get e => widget.e;

  void _set(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _text,
              autofocus: widget.focusText,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontSize: 17),
              decoration: InputDecoration(
                hintText: 'Type something…',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: PhlioColors.surfaceElevated,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check_circle_rounded, color: PhlioColors.brandViolet),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              onChanged: (v) => _set(() => e.text = v),
            ),
            const SizedBox(height: 8),
            Row(children: [
              for (final (i, t) in _tabs.indexed)
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => _tab = i),
                    child: Text(t,
                        style: TextStyle(
                            color: _tab == i ? Colors.white : Colors.white54, fontWeight: _tab == i ? FontWeight.w800 : FontWeight.w500)),
                  ),
                ),
            ]),
            SizedBox(height: 132, child: _body()),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_tab) {
      case 0: // fonts
        return ListView(scrollDirection: Axis.horizontal, children: [
          for (final f in templateFonts)
            GestureDetector(
              onTap: () => _set(() => e.font = f),
              child: Container(
                width: 92,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2532),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: e.font == f ? PhlioColors.brandViolet : Colors.transparent, width: 2),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Aa', style: templateFont(f, const TextStyle(color: Colors.white, fontSize: 30))),
                  const SizedBox(height: 4),
                  Text(f, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 10.5)),
                ]),
              ),
            ),
        ]);
      case 1: // size, spacing, line height
        return ListView(children: [
          _slider('Size', e.fontSize, 8, 120, (v) => e.fontSize = v),
          _slider('Spacing', e.spacing, -2, 12, (v) => e.spacing = v),
          _slider('Line height', e.lineHeight, .8, 2, (v) => e.lineHeight = v),
          _slider('Width', e.size.width, 80, 600, (v) => e.size = Size(v, 0)),
        ]);
      case 2: // colours
        return ListView(children: [
          _swatches('Text', e.color, (c) => e.color = c),
          _swatches('Background', e.bgColor, (c) => e.bgColor = c),
          Row(children: [
            const SizedBox(width: 70, child: Text('Custom', style: TextStyle(color: Colors.white70, fontSize: 12.5))),
            Expanded(
              child: Container(
                height: 18,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: LinearGradient(colors: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), .75, 1).toColor()]),
                ),
                child: LayoutBuilder(
                  builder: (_, box) => GestureDetector(
                    onPanUpdate: (d) => _set(() => e.color = HSVColor.fromAHSV(1, (d.localPosition.dx / box.maxWidth * 360).clamp(0.0, 360.0), .75, 1).toColor()),
                    onTapDown: (d) => _set(() => e.color = HSVColor.fromAHSV(1, (d.localPosition.dx / box.maxWidth * 360).clamp(0.0, 360.0), .75, 1).toColor()),
                  ),
                ),
              ),
            ),
          ]),
        ]);
      case 3: // style: weight, italic, case, align, background
        return ListView(children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (w, label) in const [(FontWeight.w400, 'Regular'), (FontWeight.w600, 'Medium'), (FontWeight.w800, 'Bold'), (FontWeight.w900, 'Black')])
              ChoiceChip(label: Text(label), selected: e.weight == w, onSelected: (_) => _set(() => e.weight = w)),
            FilterChip(label: const Text('Italic'), selected: e.italic, onSelected: (v) => _set(() => e.italic = v)),
            FilterChip(label: const Text('ABC'), selected: e.upper, onSelected: (v) => _set(() => e.upper = v)),
            for (final (a, icon) in const [
              (TextAlign.left, Icons.format_align_left_rounded),
              (TextAlign.center, Icons.format_align_center_rounded),
              (TextAlign.right, Icons.format_align_right_rounded)
            ])
              ChoiceChip(label: Icon(icon, size: 18), selected: e.align == a, onSelected: (_) => _set(() => e.align = a)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final b in TextBg.values)
              ChoiceChip(label: Text(b.name[0].toUpperCase() + b.name.substring(1)), selected: e.bg == b, onSelected: (_) => _set(() => e.bg = b)),
          ]),
        ]);
      default: // placements
        return GridView.count(
          crossAxisCount: 4,
          childAspectRatio: 1.25,
          children: [
            for (final (label, icon, apply) in _placements)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _set(() => apply(e)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: Colors.white),
                  const SizedBox(height: 4),
                  Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ),
          ],
        );
    }
  }

  Widget _slider(String label, double value, double min, double max, void Function(double) apply) => Row(children: [
        SizedBox(width: 82, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5))),
        Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: (v) => _set(() => apply(v)))),
      ]);

  Widget _swatches(String label, Color current, void Function(Color) apply) => SizedBox(
        height: 40,
        child: Row(children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5))),
          Expanded(
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final c in templateTextColors)
                GestureDetector(
                  onTap: () => _set(() => apply(c)),
                  child: Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: current.toARGB32() == c.toARGB32() ? PhlioColors.brandViolet : Colors.white30, width: 2.5),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      );
}
