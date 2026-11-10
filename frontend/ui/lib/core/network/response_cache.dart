// HTTP response cache for the app's API `Dio` — what makes content appear
// instantly at boot and keeps lists on screen when the network drops.
//
// Three behaviours, all transparent to data sources (they keep calling
// `apiClient.dio.get(...)` and receive a normal `Response`):
//
//  1. **In-flight de-duplication.** When several widgets ask for the same
//     URL at once (common at boot: shell, badge counters and the first tab
//     all mount together) only one request goes out and all callers get the
//     result. A response is also re-served for [_microCache] afterwards.
//
//  2. **Instant first paint.** For list/feed endpoints (see [_instantPaths]),
//     the *first* load of a URL in an app session races the network against a
//     copy saved on disk by the previous session. If the network hasn't
//     answered within [_slowAfter], the saved copy is shown at once and the
//     network response, when it lands, refreshes the saved copy for next
//     time. This is what hides a cold server (e.g. Render's free tier waking
//     up) behind real content instead of a spinner. After that first load the
//     URL always goes to the network, so pull-to-refresh is never served
//     stale data.
//
//  3. **Offline fallback.** If a feed/list request fails with a connection
//     error or timeout, the saved copy (up to [_maxStaleAge] old) is returned
//     with the header `x-phlio-cache: stale` instead of an error.
//
// Privacy / security:
//  * Only `GET`s with JSON bodies and 2xx status are stored; responses the
//    server marks `Cache-Control: no-store` (all `/auth` endpoints) and every
//    payment path are never cached.
//  * Entries are keyed by a hash of the Authorization header, so accounts on
//    a shared phone never see each other's data, and everything is wiped on
//    sign-out ([clear], called from `TokenStorage.clearTokens`).
//  * Files live in the app's private cache directory (not readable by other
//    apps, excluded from backups) and are bounded in size and age.
//  * Any successful write request (`POST/PUT/PATCH/DELETE`) drops the
//    in-memory copies and disables instant-paint for the rest of the session,
//    so a user never sees their own change "undone" by an old copy.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Endpoints whose saved copy may be shown before the network answers.
/// Prefix match on the request path (no query string).
const _instantPaths = <String>[
  '/home/overview',
  '/social/feed',
  '/social/moments/feed',
  '/social/videos',
  '/social/suggestions',
  '/social/connections',
  '/news/feed',
  '/shop/',
  '/book/',
  '/music/tracks',
  '/playlists',
  '/library/',
  '/content/',
  '/rooms/mine',
  '/realtime/spaces/scheduled',
];

/// Exact paths that are lists, where the prefix would also match detail
/// endpoints we must not serve stale (e.g. a conversation's messages).
const _instantExact = <String>{'/messaging/conversations', '/messaging/groups'};

/// Never cached, even in memory (balances and orders must always be live).
const _neverCache = <String>['/pay', '/auth/'];

const _microCache = Duration(seconds: 2);
const _slowAfter = Duration(milliseconds: 1500);
const _maxStaleAge = Duration(days: 3);
const _maxEntryBytes = 1024 * 1024;
const _maxMemoryEntries = 120;
const _maxDiskEntries = 300;

/// `extra` flag set on the internal network request so it skips this interceptor.
const _bypassKey = 'phlio_cache_bypass';

class _Entry {
  _Entry(this.body, this.statusCode, this.storedAt);

  final String body; // JSON text, decoded per hit so callers can't share mutable maps
  final int statusCode;
  final DateTime storedAt;
}

class ResponseCache extends Interceptor {
  /// [session] returns the signed-in access token (or null); it only feeds
  /// the cache key so each account gets its own entries.
  ResponseCache(this._dio, {required Future<String?> Function() session})
      : _session = session;

  final Dio _dio;
  final Future<String?> Function() _session;
  final _memory = <String, _Entry>{}; // insertion order = LRU order
  final _inFlight = <String, Future<Response<dynamic>>>{};
  final _seenThisSession = <String>{};
  bool _mutatedThisSession = false;
  Future<Directory?>? _dir;

  /// Drops every cached response (memory and disk). Called on sign-out.
  Future<void> clear() async {
    _memory.clear();
    _seenThisSession.clear();
    final dir = await _directory();
    if (dir != null && await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Best effort: a file in use is overwritten or expires anyway.
      }
      _dir = null;
    }
  }

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra[_bypassKey] == true || !_cacheable(options)) {
      handler.next(options);
      return;
    }
    final key = _key(options, await _session() ?? '');

    final recent = _memory[key];
    if (recent != null &&
        DateTime.now().difference(recent.storedAt) < _microCache) {
      handler.resolve(await _toResponse(options, recent, stale: false));
      return;
    }

    final shared = _inFlight[key];
    if (shared != null) {
      try {
        final response = await shared;
        handler.resolve(_copy(options, response));
      } on DioException catch (e) {
        handler.reject(e);
      }
      return;
    }

    final network = _fetch(options, key);
    _inFlight[key] = network;
    unawaited(network.then((_) {}, onError: (_) {}).whenComplete(() {
      _inFlight.remove(key);
    }));

    final instant = _isInstant(options.path);
    final firstLoad = _seenThisSession.add(key);
    _Entry? saved;
    if (instant && firstLoad && !_mutatedThisSession) {
      saved = _memory[key] ?? await _readDisk(key);
    }

    try {
      if (saved == null) {
        handler.resolve(await network);
        return;
      }
      // Race the network against the clock; the saved copy wins only if the
      // network is slow. Either way the network result refreshes the cache.
      final winner = await Future.any<Response<dynamic>?>([
        network,
        Future<Response<dynamic>?>.delayed(_slowAfter, () => null),
      ]);
      handler.resolve(winner ?? await _toResponse(options, saved, stale: true));
    } on DioException catch (e) {
      final fallback = instant ? (saved ?? _memory[key] ?? await _readDisk(key)) : null;
      if (fallback != null && _isConnectivityError(e)) {
        handler.resolve(await _toResponse(options, fallback, stale: true));
      } else {
        handler.reject(e);
      }
    } on Object catch (e, stack) {
      // Never leave a request hanging because of a cache bug.
      handler.reject(DioException(requestOptions: options, error: e, stackTrace: stack));
    }
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    final method = response.requestOptions.method.toUpperCase();
    final ok = (response.statusCode ?? 0) >= 200 && (response.statusCode ?? 0) < 300;
    if (ok && method != 'GET' && method != 'HEAD' && method != 'OPTIONS') {
      _memory.clear();
      _mutatedThisSession = true;
    }
    handler.next(response);
  }

  // -- internals ------------------------------------------------------------

  Future<Response<dynamic>> _fetch(RequestOptions options, String key) async {
    final request = options.copyWith(extra: {...options.extra, _bypassKey: true});
    final response = await _dio.fetch<dynamic>(request);
    _store(key, options.path, response);
    return response;
  }

  void _store(String key, String path, Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) return;
    final cacheControl = response.headers['cache-control']?.join(',') ?? '';
    if (cacheControl.contains('no-store')) return;
    final data = response.data;
    if (data is! Map && data is! List) return;
    final String body;
    try {
      body = jsonEncode(data);
    } on Object {
      return;
    }
    if (body.length > _maxEntryBytes) return;
    final entry = _Entry(body, status, DateTime.now());
    _memory.remove(key);
    _memory[key] = entry;
    while (_memory.length > _maxMemoryEntries) {
      _memory.remove(_memory.keys.first);
    }
    if (_isInstant(path)) unawaited(_writeDisk(key, entry));
  }

  bool _cacheable(RequestOptions o) =>
      o.method.toUpperCase() == 'GET' &&
      o.responseType == ResponseType.json &&
      !o.path.startsWith('http') &&
      !_neverCache.any(o.path.startsWith) &&
      o.extra['cache'] != false;

  bool _isInstant(String path) =>
      _instantExact.contains(path) || _instantPaths.any(path.startsWith);

  String _key(RequestOptions o, String session) {
    final query = (o.queryParameters.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    // Only a hash of the token goes into the key (and file name).
    return _fnv1a('${_fnv1a(session)}|${o.path}?$query');
  }

  Future<Response<dynamic>> _toResponse(RequestOptions o, _Entry e,
      {required bool stale}) async {
    final data = e.body.length > 50 * 1024
        ? await compute(jsonDecode, e.body)
        : jsonDecode(e.body);
    return Response<dynamic>(
      requestOptions: o,
      data: data,
      statusCode: e.statusCode,
      headers: Headers.fromMap({
        'content-type': ['application/json'],
        'x-phlio-cache': [stale ? 'stale' : 'hit'],
        'x-phlio-cache-age': ['${DateTime.now().difference(e.storedAt).inSeconds}'],
      }),
    );
  }

  Response<dynamic> _copy(RequestOptions o, Response<dynamic> r) {
    final data = r.data;
    return Response<dynamic>(
      requestOptions: o,
      // Re-decode so each caller owns its own Map/List.
      data: data is Map || data is List ? jsonDecode(jsonEncode(data)) : data,
      statusCode: r.statusCode,
      statusMessage: r.statusMessage,
      headers: r.headers,
    );
  }

  bool _isConnectivityError(DioException e) => const [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
      ].contains(e.type) ||
      (e.response?.statusCode ?? 0) >= 502;

  Future<Directory?> _directory() => _dir ??= () async {
        try {
          final base = await getApplicationCacheDirectory();
          final dir = Directory('${base.path}/phlio_http');
          await dir.create(recursive: true);
          unawaited(_prune(dir));
          return dir;
        } on Object {
          return null; // tests / platforms without path_provider
        }
      }();

  Future<_Entry?> _readDisk(String key) async {
    final dir = await _directory();
    if (dir == null) return null;
    final file = File('${dir.path}/$key.json');
    try {
      if (!await file.exists()) return null;
      final stat = await file.stat();
      if (DateTime.now().difference(stat.modified) > _maxStaleAge) return null;
      final raw = await file.readAsString();
      final split = raw.indexOf('\n');
      if (split <= 0) return null;
      final status = int.tryParse(raw.substring(0, split)) ?? 200;
      return _Entry(raw.substring(split + 1), status, stat.modified);
    } on Object {
      return null; // corrupt or concurrently replaced — treat as a miss
    }
  }

  Future<void> _writeDisk(String key, _Entry e) async {
    final dir = await _directory();
    if (dir == null) return;
    try {
      // Write-then-rename so a crash never leaves a half-written entry.
      final tmp = File('${dir.path}/$key.tmp');
      await tmp.writeAsString('${e.statusCode}\n${e.body}', flush: true);
      await tmp.rename('${dir.path}/$key.json');
    } on Object {
      // Disk full or similar: the cache is an optimisation, never an error.
    }
  }

  Future<void> _prune(Directory dir) async {
    try {
      final files = <File, DateTime>{};
      await for (final f in dir.list()) {
        if (f is File) files[f] = (await f.stat()).modified;
      }
      final now = DateTime.now();
      final ordered = files.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (var i = 0; i < ordered.length; i++) {
        final old = now.difference(ordered[i].value) > _maxStaleAge;
        if (old || i >= _maxDiskEntries) await ordered[i].key.delete();
      }
    } on Object {
      // Best effort.
    }
  }
}

/// 64-bit FNV-1a, hex. Stable across runs (unlike `String.hashCode`), so it
/// can name files; not a security boundary (keys only need to be distinct).
String _fnv1a(String input) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final unit in utf8.encode(input)) {
    hash ^= unit;
    hash = hash * prime; // Dart VM ints wrap at 64 bits, which FNV relies on
  }
  String half(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return half(hash >> 32) + half(hash);
}
