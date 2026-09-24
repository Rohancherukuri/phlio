// App entrypoint.
//
// Two composition roots meet here: `get_it` (infrastructure singletons —
// see `core/di/service_locator.dart`) and Riverpod (reactive state — every
// `*ControllerProvider` across `features/*`). A `ProviderContainer` is
// created explicitly (rather than only relying on `ProviderScope` further
// down the tree) so `ApiClient.onSessionExpired` can be wired to
// `AuthController.forceSignOut()` *before* `runApp`, without needing a
// `BuildContext`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/di/service_locator.dart';
import 'core/network/api_client.dart';
import 'features/authentication/presentation/controllers/auth_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setupServiceLocator();

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
