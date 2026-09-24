# Phlio — Flutter client

## Running

```bash
cd frontend/ui/flutter
flutter pub get
flutter run                     # pick a connected device/simulator
```

By default the app talks to the backend at `http://localhost:8000` (see
`lib/app/config/app_config.dart`). Override at build/run time:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1   # Android emulator
flutter run --dart-define=ENABLE_REQUEST_LOGGING=false                # quiet the network logger
```

See `.env.example` in this directory for the full list of available
`--dart-define` flags and what each does — Flutter has no `.env` file
loader by default, so that file is documentation you translate into
`--dart-define` flags, not something read at runtime.

## Structure

Clean Architecture, feature-first (see `lib/features/*`): each feature has
its own `domain` (entities/repository interfaces/use cases — plain Dart,
no Flutter or networking imports), `data` (DTOs, remote data sources,
repository implementations), and `presentation` (Riverpod controllers +
widgets) layers. `lib/design_system` holds the shared visual language;
`lib/core` holds cross-cutting infrastructure (networking, storage, DI,
logging, error handling).

## Logging

`lib/core/logging/app_logger.dart` wraps `dart:developer`'s `log()` —
visible in `flutter run`'s console and DevTools' Logging view. Every layer
that logs uses a named logger (`createLogger('phlio.api')`,
`createLogger('phlio.shop')`, ...) matching the backend's
`logging.getLogger("phlio.<module>")` convention, so a log line's origin
reads the same way on both sides of the stack. The API client logs one
line per HTTP request (method, path, status, duration) at `debug`, and
warnings/errors on failed requests and token-refresh attempts.

## Assets

`assets/agent/fox.svg` is Twitter's Twemoji fox illustration (CC-BY 4.0 —
see that directory's README for the full attribution). Rendered via
`flutter_svg` in `design_system/widgets/phlio_fox.dart`, which falls back
to a small hand-drawn `CustomPainter` illustration if the asset ever fails
to load.

## Tests

```bash
flutter test
```

See `test/README.md` for how the suite is organized and a note on the
sandbox this project was scaffolded in.

## Animations

A few deliberate, hand-built (no extra dependency) animations worth
knowing about if you're extending them:
- `app/router/app_router.dart`'s `_fadeThroughPage` — the fade+rise page
  transition used for every top-level pushed destination.
- `shared/widgets/shimmer_loading.dart` — skeleton loading states shaped
  like the real content (grid/list/row), replacing bare spinners.
- `features/onboarding/presentation/splash_screen.dart` — a choreographed
  entrance (mark, then tagline/progress) via one `AnimationController`
  with staggered `Interval`s.
- `design_system/widgets/phlio_bottom_nav.dart` — an animated icon pop +
  underline indicator on tab selection.
- `features/shop/presentation/widgets/product_card.dart` — an elastic
  "pop" on the favorite-heart toggle, plus a `Hero` tag shared with the
  Home screen's product strip for a smooth image transition between them.
