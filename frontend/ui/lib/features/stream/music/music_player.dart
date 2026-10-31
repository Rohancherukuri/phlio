// Phlio Stream · Music — playback.
//
// just_audio plays the queue as one gapless playlist; just_audio_background
// publishes it to the system media session, which gives lock-screen and
// notification controls plus headset / Bluetooth media buttons (and pauses
// when headphones are unplugged). The queue, shuffle, repeat, speed, volume,
// sleep timer and play history live here.
//
// Background playback works like Spotify: the media service keeps running
// after you leave Phlio or swipe it out of recents (the handler doesn't stop
// on task removal), the notification stays while paused so Android doesn't
// kill the player, and the audio session is set up for music so iOS keeps
// playing with the screen locked.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/config/app_config.dart';
import 'music_models.dart';

/// Repeat: off, the whole queue, or the current song.
enum RepeatMode { off, all, one }

/// The one music player for the app. Owns the just_audio player and the
/// queue; widgets listen to it for the current track and transport state.
class MusicPlayer extends ChangeNotifier {
  MusicPlayer(this._store) {
    _subs.addAll([
      player.currentIndexStream.listen(_onIndex),
      player.playerStateStream.listen((_) => notifyListeners()),
      player.positionStream.listen(_onPosition),
      player.durationStream.listen((_) => notifyListeners()),
    ]);
  }

  final MusicStore _store;
  final player = AudioPlayer(handleInterruptions: true, maxSkipsOnError: 3);
  // ignore: deprecated_member_use
  ConcatenatingAudioSource? _playlist;
  final queue = <Track>[];
  final _subs = <StreamSubscription<dynamic>>[];
  int index = 0;
  RepeatMode repeat = RepeatMode.off;
  bool shuffle = false;
  String? _countedId;
  DateTime _lastSave = DateTime(0);

  // Sleep timer.
  DateTime? sleepAt;
  bool sleepAfterSong = false;
  Timer? _sleepTimer;

  /// The track at [index] in the queue, or null when nothing is queued.
  Track? get current => queue.isEmpty || index >= queue.length ? null : queue[index];
  /// Whether audio is playing (true while buffering after play).
  bool get playing => player.playing;
  /// Position in the current track.
  Duration get position => player.position;
  /// Length of the current track (from the stream, else its tags).
  Duration get duration => player.duration ?? current?.duration ?? Duration.zero;
  /// Position updates for seek bars and lyrics.
  Stream<Duration> get positionStream => player.positionStream;
  /// True while the current track is loading or buffering.
  bool get loading =>
      player.processingState == ProcessingState.loading || player.processingState == ProcessingState.buffering;

  // -- queue ------------------------------------------------------------------------

  AudioSource _source(Track t) {
    final tag = MediaItem(
      id: t.id,
      title: t.title,
      artist: t.artist,
      album: t.album,
      genre: t.genre,
      duration: t.durationMs > 0 ? t.duration : null,
      artUri: t.artUrl == null ? null : Uri.parse(AppConfig.mediaUrl(t.artUrl!)),
    );
    if (t.isDevice) return AudioSource.file(t.uri, tag: tag);
    return AudioSource.uri(Uri.parse(AppConfig.mediaUrl(t.uri)), tag: tag);
  }

  /// Replace the queue and start at [start].
  Future<void> playTracks(List<Track> tracks,
      {int start = 0, bool shuffled = false, Duration? at, bool autoplay = true}) async {
    if (tracks.isEmpty) return;
    _remember(tracks);
    unawaited(_askForNotifications());
    queue
      ..clear()
      ..addAll(tracks);
    index = start.clamp(0, tracks.length - 1);
    shuffle = shuffled;
    if (shuffled) {
      final first = queue.removeAt(index);
      queue.shuffle(math.Random());
      queue.insert(0, first);
      index = 0;
    }
    // ignore: deprecated_member_use
    _playlist = ConcatenatingAudioSource(useLazyPreparation: true, children: [for (final t in queue) _source(t)]);
    notifyListeners();
    try {
      await player.setAudioSource(_playlist!, initialIndex: index, initialPosition: at ?? Duration.zero);
      await player.setSpeed(_store.settings.speed);
      await player.setVolume(_store.settings.volume);
      await _applyLoop();
      if (autoplay) unawaited(player.play());
    } catch (e) {
      debugPrint('Could not play: $e');
    }
    _persist(force: true);
  }

  /// Inserts [t] right after the current track.
  Future<void> playNext(Track t) async {
    if (queue.isEmpty) return playTracks([t]);
    _remember([t]);
    final at = math.min(index + 1, queue.length);
    queue.insert(at, t);
    await _playlist?.insert(at, _source(t));
    notifyListeners();
    _persist(force: true);
  }

  /// Appends [tracks] to the end of the queue (or starts playing them).
  Future<void> addToQueue(Iterable<Track> tracks) async {
    if (queue.isEmpty) return playTracks(tracks.toList());
    _remember(tracks);
    queue.addAll(tracks);
    await _playlist?.addAll([for (final t in tracks) _source(t)]);
    notifyListeners();
    _persist(force: true);
  }

  /// Moves a queued track from [from] to [to] (drag to sort).
  Future<void> moveInQueue(int from, int to) async {
    if (from == to || from < 0 || from >= queue.length) return;
    final t = queue.removeAt(from);
    queue.insert(to.clamp(0, queue.length), t);
    await _playlist?.move(from, to.clamp(0, queue.length - 1));
    index = player.currentIndex ?? index;
    notifyListeners();
    _persist(force: true);
  }

  /// Removes the track at [i]; removing the last one stops playback.
  Future<void> removeFromQueue(int i) async {
    if (i < 0 || i >= queue.length) return;
    if (queue.length == 1) return stop();
    queue.removeAt(i);
    await _playlist?.removeAt(i);
    index = player.currentIndex ?? math.min(index, queue.length - 1);
    notifyListeners();
    _persist(force: true);
  }

  /// Stops playback and empties the queue.
  Future<void> clearQueue() async => stop();

  /// Starts the track at queue position [i] from the beginning.
  Future<void> jumpTo(int i) async {
    if (i < 0 || i >= queue.length) return;
    await player.seek(Duration.zero, index: i);
    if (!player.playing) unawaited(player.play());
  }

  void _remember(Iterable<Track> tracks) {
    for (final t in tracks) {
      _store.rememberRemote(t);
    }
  }

  /// Android 13+: the playback notification (and its controls) needs the
  /// notification permission. Asked once, the first time music plays.
  static bool _askedNotifications = false;
  Future<void> _askForNotifications() async {
    if (_askedNotifications || !Platform.isAndroid) return;
    _askedNotifications = true;
    try {
      if (await Permission.notification.isDenied) await Permission.notification.request();
    } catch (_) {}
  }

  // -- transport -------------------------------------------------------------------

  /// Play / pause.
  Future<void> toggle() async => player.playing ? player.pause() : player.play();
  /// Resumes playback.
  Future<void> play() => player.play();
  /// Pauses playback.
  Future<void> pause() => player.pause();

  /// Next track; wraps to the start of the queue at the end.
  Future<void> next() async {
    if (player.hasNext) {
      await player.seekToNext();
    } else if (queue.isNotEmpty) {
      await player.seek(Duration.zero, index: 0);
    }
  }

  /// Retro-style: restart the song if more than 3s in, else previous.
  Future<void> previous() async {
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  /// Seeks within the current track.
  Future<void> seek(Duration to) => player.seek(to);

  /// Cycles repeat: off → all → one → off.
  Future<void> cycleRepeat() async {
    repeat = RepeatMode.values[(repeat.index + 1) % RepeatMode.values.length];
    await _applyLoop();
    notifyListeners();
  }

  Future<void> _applyLoop() => player.setLoopMode(switch (repeat) {
        RepeatMode.off => LoopMode.off,
        RepeatMode.all => LoopMode.all,
        RepeatMode.one => LoopMode.one,
      });

  /// Shuffles the upcoming songs in place (the current one keeps playing).
  Future<void> toggleShuffle() async {
    shuffle = !shuffle;
    if (shuffle && queue.length > 2) {
      final upcoming = queue.sublist(index + 1)..shuffle(math.Random());
      final keep = queue.sublist(0, index + 1);
      final pos = player.position;
      final wasPlaying = player.playing;
      await playTracks([...keep, ...upcoming], start: index, at: pos, autoplay: wasPlaying);
      shuffle = true;
    }
    notifyListeners();
  }

  /// Phlio's own volume (0–1, saved). Pauses at zero if that setting is on.
  Future<void> setVolume(double v) async {
    _store.settings.volume = v.clamp(0.0, 1.0);
    await player.setVolume(_store.settings.volume);
    if (_store.settings.pauseOnZeroVolume && v <= 0 && player.playing) await player.pause();
    _store.save();
    notifyListeners();
  }

  /// Playback speed (saved).
  Future<void> setSpeed(double v) async {
    _store.settings.speed = v;
    await player.setSpeed(v);
    _store.save();
    notifyListeners();
  }

  /// Stops, clears the queue and cancels the sleep timer.
  Future<void> stop() async {
    await player.stop();
    queue.clear();
    _playlist = null;
    index = 0;
    cancelSleep();
    notifyListeners();
    _persist(force: true);
  }

  // -- sleep timer ----------------------------------------------------------------------

  /// Pauses after [after]; with [finishSong], waits for the song playing at
  /// that moment to end first.
  void setSleepTimer(Duration after, {bool finishSong = false}) {
    _sleepTimer?.cancel();
    sleepAt = DateTime.now().add(after);
    sleepAfterSong = finishSong;
    _sleepTimer = Timer(after, () async {
      if (sleepAfterSong) {
        // Wait for the current song to end, then pause.
        final i = player.currentIndex;
        await player.positionStream.firstWhere((p) =>
            player.currentIndex != i || (player.duration != null && p >= player.duration! - const Duration(milliseconds: 400)));
      }
      await player.pause();
      sleepAt = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Cancels the sleep timer.
  void cancelSleep() {
    _sleepTimer?.cancel();
    sleepAt = null;
    notifyListeners();
  }

  // -- bookkeeping -------------------------------------------------------------------------

  void _onIndex(int? i) {
    if (i == null) return;
    index = i;
    _countedId = null;
    notifyListeners();
    _persist(force: true);
  }

  void _onPosition(Duration p) {
    final t = current;
    // Count a play after 30s (or half a short song), like most players.
    if (t != null && _countedId != t.id) {
      final d = duration.inMilliseconds;
      if (p.inSeconds >= 30 || (d > 0 && p.inMilliseconds > d / 2)) {
        _countedId = t.id;
        _store.recordPlay(t.id);
      }
    }
    _persist();
  }

  void _persist({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastSave).inSeconds < 10) return;
    _lastSave = now;
    _store.rememberQueue([for (final t in queue) t.id], index, player.position.inMilliseconds);
  }

  /// Restores the last session's queue (paused) once the library is loaded.
  bool _restored = false;
  /// Restores the last session's queue (paused) once the library is loaded.
  /// Runs once; does nothing if something is already queued.
  Future<void> restore(Map<String, Track> byId) async {
    if (_restored || queue.isNotEmpty || !_store.loaded) return;
    _restored = true;
    final tracks = [for (final id in _store.lastQueue) if (byId[id] != null) byId[id]!];
    if (tracks.isEmpty) return;
    final i = _store.lastIndex.clamp(0, tracks.length - 1);
    await playTracks(tracks, start: i, at: Duration(milliseconds: _store.lastPositionMs), autoplay: false);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _sleepTimer?.cancel();
    player.dispose();
    super.dispose();
  }
}

/// The app-wide [MusicPlayer]. Never disposed, so music keeps playing
/// while you browse the rest of Phlio.
final musicPlayerProvider = ChangeNotifierProvider<MusicPlayer>((ref) {
  final player = MusicPlayer(ref.read(musicStoreProvider));
  return player;
});

/// Call before runApp (lock screen / notification / headset controls).
Future<void> initMusicBackground() async {
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.phlio.stream.music',
      androidNotificationChannelName: 'Phlio Stream music',
      // Stay a foreground service while paused (like Spotify), so the
      // player survives leaving the app and can resume from the notification.
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidShowNotificationBadge: false,
      preloadArtwork: true,
    );
  } catch (e) {
    debugPrint('Background audio unavailable: $e');
  }
  try {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
  } catch (e) {
    debugPrint('Audio session not configured: $e');
  }
}
