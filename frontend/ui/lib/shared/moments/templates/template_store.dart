// Moment templates — saved templates and trending prompts.
//
// Saved: bookmarked catalogue templates (by id) and your own designs (the
// full layout, photos left out so they're reusable), kept in
// `phlio_templates.json` in the app documents folder.
//
// Trending prompts: "Add yours" prompts people are using right now
// (GET /social/moments/prompts), topped up with a curated set so the
// section is never empty.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/network/api_client.dart';
import 'template_catalog.dart';
import 'template_model.dart';

/// Saved templates for this device. Listen to it to rebuild on changes.
class SavedTemplates extends ChangeNotifier {
  SavedTemplates._() {
    unawaited(_load());
  }

  static final instance = SavedTemplates._();

  final ids = <String>[]; // catalogue templates, newest first
  final custom = <Map<String, dynamic>>[]; // your designs: {id, name, backdrop, elements}
  bool loaded = false;

  Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/phlio_templates.json');

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        ids.addAll([for (final i in (j['ids'] as List? ?? const [])) '$i']);
        custom.addAll([for (final c in (j['custom'] as List? ?? const [])) Map<String, dynamic>.from(c as Map)]);
      }
    } catch (e) {
      debugPrint('Saved templates could not load: $e');
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      await (await _file()).writeAsString(jsonEncode({'ids': ids, 'custom': custom}));
    } catch (e) {
      debugPrint('Saved templates could not save: $e');
    }
  }

  bool isSaved(String id) => ids.contains(id) || custom.any((c) => c['id'] == id);

  /// Bookmarks or un-bookmarks a catalogue template.
  void toggle(String id) {
    if (!ids.remove(id)) ids.insert(0, id);
    unawaited(_save());
  }

  /// Saves a design as your own template (photos are not kept).
  String saveDesign(String name, TBackdrop backdrop, List<TElement> elements, {String? id}) {
    final key = id ?? 'mine_${DateTime.now().millisecondsSinceEpoch}';
    custom.removeWhere((c) => c['id'] == key);
    custom.insert(0, {
      'id': key,
      'name': name,
      'backdrop': backdrop.toJson(),
      'elements': [for (final e in elements) e.toJson()],
      'saved_at': DateTime.now().toIso8601String(),
    });
    unawaited(_save());
    return key;
  }

  void remove(String id) {
    ids.remove(id);
    custom.removeWhere((c) => c['id'] == id);
    unawaited(_save());
  }

  /// Saved templates, ready to open: your designs first, then bookmarks.
  List<MomentTemplate> get templates => [
        for (final c in custom)
          MomentTemplate(
            id: '${c['id']}',
            name: '${c['name'] ?? 'My design'}',
            category: TemplateCategory.creator,
            backdrop: () => backdropFromJson(c['backdrop'] as Map? ?? const {}),
            build: () => [for (final e in (c['elements'] as List? ?? const [])) elementFromJson(e as Map)],
          ),
        for (final id in ids)
          if (momentTemplates.where((t) => t.id == id).firstOrNull case final t?) t,
      ];
}

/// One "Add yours" prompt for Trending prompts.
class TrendingPrompt {
  const TrendingPrompt(this.prompt, {this.count = 0, this.people = const [], this.coverUrl});
  final String prompt;

  /// Moments using it right now.
  final int count;

  /// Up to three people who joined: `{display_name, avatar_url, …}`.
  final List<Map> people;

  /// The newest moment's picture.
  final String? coverUrl;
}

/// Always-available prompts (shown after the live ones).
const curatedPrompts = [
  'Add your profile pic 🔥',
  'Add your photo story 📸',
  'Show your view right now',
  'Your pet 🐾',
  'Last photo you took',
  'Coffee order ☕',
  'Fit of the day',
  'Your happy place 🌅',
];

/// Live prompts from the server plus the curated ones (deduplicated).
Future<List<TrendingPrompt>> loadTrendingPrompts() async {
  final live = <TrendingPrompt>[];
  try {
    final data = (await getIt<ApiClient>().dio.get('/social/moments/prompts')).data as List;
    for (final g in data.cast<Map>()) {
      live.add(TrendingPrompt('${g['prompt']}',
          count: (g['count'] as num? ?? 0).toInt(),
          people: [for (final p in (g['people'] as List? ?? const [])) p as Map],
          coverUrl: g['cover_url'] as String?));
    }
  } catch (_) {
    // Offline or older server: curated prompts only.
  }
  final seen = {for (final p in live) p.prompt.toLowerCase()};
  return [...live, for (final p in curatedPrompts) if (seen.add(p.toLowerCase())) TrendingPrompt(p)];
}
