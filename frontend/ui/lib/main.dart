// App entrypoint.
//
// Two composition roots meet here: `get_it` (infrastructure singletons —
// see `core/di/service_locator.dart`) and Riverpod (reactive state — every
// `*ControllerProvider` across `features/*`). A `ProviderContainer` is
// created explicitly (rather than only relying on `ProviderScope` further
// down the tree) so `ApiClient.onSessionExpired` can be wired to
// `AuthController.forceSignOut()` *before* `runApp`, without needing a
// `BuildContext`.
//
// Boot path (keep it short — everything here delays the first frame):
//  * Only work that MUST precede the first frame runs before `runApp`, and it
//    runs concurrently: the background-audio service (must exist before any
//    `AudioPlayer` is created) and the first secure-storage read of the
//    session tokens (so the auth check and the first API calls don't each pay
//    for a Keystore round trip).
//  * The audio init is capped at [_audioInitBudget]; on a device where the
//    media service is slow to bind we start the UI anyway rather than show a
//    blank screen.
//  * Content then paints from the response cache (see
//    `core/network/response_cache.dart`) while fresh data loads.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/di/service_locator.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'features/authentication/presentation/controllers/auth_controller.dart';
import 'features/stream/music/music_player.dart' show initMusicBackground;

const _audioInitBudget = Duration(milliseconds: 1500);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupServiceLocator();
  // Wake the server first: on a free host it may be asleep, and booting it
  // in parallel with our own startup hides most of that delay.
  unawaited(getIt<ApiClient>().wakeServer());
  // Feeds are image-heavy: a larger decoded-image cache means scrolling back
  // (or switching tabs) re-shows images without decoding them again.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 << 20;
  await Future.wait<void>([
    // Phlio Stream music: lock-screen / notification / headset controls.
    initMusicBackground().timeout(_audioInitBudget, onTimeout: () {}),
    getIt<TokenStorage>().warmUp(),
  ]);

  final container = ProviderContainer();

  // If a refresh-token attempt fails mid-session (see
  // `core/network/api_client.dart`'s `_onError`), force the app back to
  // the login flow rather than leaving the UI in a half-authenticated
  // state where every subsequent request would just 401 again.
  getIt<ApiClient>().onSessionExpired = () {
    container.read(authControllerProvider.notifier).forceSignOut();
  };

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PhlioApp(),
    ),
  );
}
