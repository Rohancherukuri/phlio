// App routing (go_router).
//
// Route shape:
//   /splash                          — session bootstrap (see onboarding/presentation/splash_screen.dart)
//   /login, /signup                  — auth flow, outside the bottom-nav shell
//   StatefulShellRoute (bottom nav):  — see app/shell/app_shell.dart
//     /home      — current platform's home (platform picked via the App Tray)
//     /explore   — current platform's discovery surface
//     /profile   — shared across all platforms
//   /activity                        — pushed full-screen (cross-domain feed,
//                                      filtered by the current platform)
//   /rooms/:roomId                   — pushed full-screen room detail
//
// Platforms (Pay, Social, Rooms, Book, Shop, Stream, News, Agent) are NOT
// routes — they are state (`currentPlatformProvider`), flipped from the App
// Tray, quick actions, the create sheet and the Agent plan card. The Home
// and Explore branches render platform-switched `IndexedStack`s so each
// platform keeps its own live surface.
//
// Auth guarding lives entirely in `redirect`, driven by
// `authControllerProvider`'s `AsyncValue<UserEntity?>`: still loading ->
// stay on splash; null -> force to /login (unless already on an auth
// route); non-null -> bounce away from /login|/signup|/splash into /home.
//
// Transitions: pushed destinations use `_fadeThroughPage` — a deliberate
// fade+slight-rise transition rather than each platform's raw default.
// Tab switches inside the bottom-nav shell are intentionally instant (no
// transition) — that's the correct, native feel for a bottom nav, and
// `StatefulShellRoute.indexedStack` gives it for free.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity/presentation/screens/activity_screen.dart';
import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../../features/authentication/presentation/screens/login_screen.dart';
import '../../features/authentication/presentation/screens/signup_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/pay/presentation/screens/qr_scanner_screen.dart';
import '../../features/rooms/presentation/screens/dm_screen.dart';
import '../../features/rooms/presentation/screens/call_screen.dart';
import '../../features/rooms/presentation/screens/room_detail_screen.dart';
import '../../features/social/presentation/screens/creator_profile_screen.dart';
import '../shell/app_shell.dart';
import '../shell/platform_explore_screen.dart';
import '../shell/platform_home_screen.dart';
import '../shell/profile_dashboard_screen.dart';
import '../shell/profile_screen.dart';

/// Bridges Riverpod state changes to `GoRouter`'s `Listenable`-based
/// `refreshListenable` API, so a login/logout immediately re-runs
/// `redirect` instead of waiting for the next navigation event.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
  }
}

/// A fade + gentle upward-slide page transition — deliberately understated
/// (no full-screen slide-from-the-side, no bounce) so it reads as polish
/// rather than decoration. Used for every pushed destination in the app.
CustomTransitionPage<void> _fadeThroughPage(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: Transform.translate(
          offset: Offset(0, (1 - curved.value) * 16),
          child: child,
        ),
      );
    },
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      const authRoutes = ['/login', '/signup'];

      if (authState.isLoading) {
        return location == '/splash' ? null : '/splash';
      }

      final isSignedIn = authState.valueOrNull != null;
      final onAuthRoute = authRoutes.contains(location);

      if (!isSignedIn && !onAuthRoute) return '/login';
      if (isSignedIn && (onAuthRoute || location == '/splash')) return '/home';
      return null;
    },
    routes: [
      GoRoute(
          path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fadeThroughPage(const LoginScreen()),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (context, state) => _fadeThroughPage(const SignupScreen()),
      ),
      GoRoute(
        path: '/activity',
        pageBuilder: (context, state) =>
            _fadeThroughPage(const ActivityScreen()),
      ),
      GoRoute(
        path: '/profile-dashboard',
        pageBuilder: (context, state) => _fadeThroughPage(
          ProfileDashboardScreen(postCount: state.extra as int? ?? 0),
        ),
      ),
      GoRoute(
        path: '/qr-scanner',
        pageBuilder: (context, state) =>
            _fadeThroughPage(const QrScannerScreen()),
      ),
      GoRoute(
        path: '/call/:callId',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>? ?? {};
          return CallScreen(
              callId: state.pathParameters['callId']!,
              name: data['name'] as String? ?? 'Call',
              video: data['video'] == true,
              incoming: data['incoming'] == true);
        },
      ),
      GoRoute(
        path: '/dm/:username',
        pageBuilder: (context, state) => _fadeThroughPage(
          DmScreen(username: state.pathParameters['username']!),
        ),
      ),
      GoRoute(
        path: '/creator/:username',
        redirect: (context, state) {
          final me = ref.read(authControllerProvider).valueOrNull;
          final target = state.pathParameters['username'];
          return me != null && (target == me.id || target == me.username)
              ? '/profile'
              : null;
        },
        pageBuilder: (context, state) => _fadeThroughPage(
          CreatorProfileScreen(username: state.pathParameters['username']!),
        ),
      ),
      GoRoute(
        path: '/rooms/:roomId',
        pageBuilder: (context, state) => _fadeThroughPage(
          RoomDetailScreen(roomId: state.pathParameters['roomId']!),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/home',
                builder: (context, state) => const PlatformHomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/explore',
                builder: (context, state) => const PlatformExploreScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen()),
          ]),
        ],
      ),
    ],
  );
});
