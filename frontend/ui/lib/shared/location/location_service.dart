// Location sharing — device location, history and live sharing.
//
// * [currentPosition] asks for permission (once) and returns a fix.
// * [LocationHistory] remembers the places you've sent (newest first) for
//   the "Recent" list in the send-location screen.
// * [LiveLocationSharer] keeps live sessions going while Phlio runs: it
//   starts a session on the server (POST /messaging/live), pushes a new
//   position whenever you've moved ~15 m (at most every 10 s, plus a
//   heartbeat each minute), and stops at the end time or when you tap Stop.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';

/// Why a location couldn't be read, in words for a snackbar.
class LocationProblem implements Exception {
  const LocationProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The phone's position, asking for permission first. Throws [LocationProblem].
Future<Position> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationProblem('Turn on location services to share where you are.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.denied) {
    throw const LocationProblem('Allow location access to share where you are.');
  }
  if (permission == LocationPermission.deniedForever) {
    throw const LocationProblem('Location access is off for Phlio. Turn it on in Settings.');
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
  );
}

/// A place: coordinates plus a name and address for display.
class Place {
  const Place({required this.lat, required this.lng, required this.name, this.address = '', this.kind});
  final double lat, lng;
  final String name, address;

  /// What it is (cafe, temple, mall…), when known.
  final String? kind;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'name': name, 'address': address, if (kind != null) 'kind': kind};

  static Place fromJson(Map j) => Place(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        name: '${j['name'] ?? 'Location'}',
        address: '${j['address'] ?? ''}',
        kind: j['kind'] as String?,
      );
}

/// Places you've sent, newest first (kept on this phone).
class LocationHistory extends ChangeNotifier {
  LocationHistory._() {
    unawaited(_load());
  }

  static final instance = LocationHistory._();
  final items = <(Place, DateTime)>[];

  Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/phlio_locations.json');

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        for (final e in (jsonDecode(await f.readAsString()) as List).cast<Map>()) {
          items.add((Place.fromJson(e), DateTime.tryParse('${e['at']}') ?? DateTime.now()));
        }
      }
    } catch (e) {
      debugPrint('Location history could not load: $e');
    }
    notifyListeners();
  }

  /// Records a sent place (moving it to the top if it was there already).
  void add(Place p) {
    items.removeWhere((e) => (e.$1.lat - p.lat).abs() < 1e-5 && (e.$1.lng - p.lng).abs() < 1e-5);
    items.insert(0, (p, DateTime.now()));
    if (items.length > 25) items.removeRange(25, items.length);
    notifyListeners();
    unawaited(() async {
      try {
        await (await _file()).writeAsString(jsonEncode([
          for (final (p, at) in items) {...p.toJson(), 'at': at.toIso8601String()}
        ]));
      } catch (_) {}
    }());
  }

  void clear() {
    items.clear();
    notifyListeners();
    unawaited(_file().then((f) => f.exists().then((e) => e ? f.delete() : null)));
  }
}

/// One live session this phone is sharing.
class LiveSession {
  LiveSession(this.id, this.peer, this.until);
  final String id, peer;
  final DateTime until;
}

/// Keeps live location sessions updated while the app runs.
class LiveLocationSharer extends ChangeNotifier {
  LiveLocationSharer._();
  static final instance = LiveLocationSharer._();

  final sessions = <String, LiveSession>{};
  StreamSubscription<Position>? _stream;
  Timer? _heartbeat;
  Position? _last;
  DateTime _lastSent = DateTime(0);

  bool isSharing(String id) => sessions.containsKey(id);

  /// Starts sharing with [peer] for [minutes]; returns the session id.
  Future<String> start(String peer, int minutes, Position from) async {
    final res = await getIt<ApiClient>().dio.post('/messaging/live', data: {
      'peer': peer,
      'minutes': minutes,
      'lat': from.latitude,
      'lng': from.longitude,
      'accuracy': from.accuracy,
    });
    final data = res.data as Map;
    final id = '${data['id']}';
    sessions[id] = LiveSession(id, peer, DateTime.parse('${data['until']}').toLocal());
    _last = from;
    _listen();
    notifyListeners();
    return id;
  }

  /// Stops one session (on the server too).
  Future<void> stop(String id) async {
    sessions.remove(id);
    notifyListeners();
    try {
      await getIt<ApiClient>().dio.delete('/messaging/live/$id');
    } catch (_) {}
    if (sessions.isEmpty) _quiet();
  }

  void _listen() {
    _stream ??= Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).listen((p) {
      _last = p;
      _push();
    }, onError: (_) {});
    _heartbeat ??= Timer.periodic(const Duration(minutes: 1), (_) => _push(force: true));
  }

  void _quiet() {
    _stream?.cancel();
    _stream = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  /// Sends the latest fix to every session (throttled), ending expired ones.
  Future<void> _push({bool force = false}) async {
    final p = _last;
    final now = DateTime.now();
    for (final s in sessions.values.where((s) => s.until.isBefore(now)).toList()) {
      sessions.remove(s.id);
    }
    if (sessions.isEmpty) {
      _quiet();
      notifyListeners();
      return;
    }
    if (p == null || (!force && now.difference(_lastSent).inSeconds < 10)) return;
    _lastSent = now;
    for (final s in sessions.values.toList()) {
      try {
        await getIt<ApiClient>()
            .dio
            .put('/messaging/live/${s.id}', data: {'lat': p.latitude, 'lng': p.longitude, 'accuracy': p.accuracy});
      } catch (_) {
        // Offline for a moment: the next fix or heartbeat tries again.
      }
    }
  }
}
