// App routing (go_router).
//
// Route shape:
//   /splash                          — session bootstrap (see onboarding/presentation/splash_screen.dart)
//   /login, /signup                  — auth flow, outside the bottom-nav shell
//   StatefulShellRoute (bottom nav):  — see app/shell/app_shell.dart for why
//   only Home/Explore(Rooms)/Activity/Profile are tabs
//     /home
//     /rooms, /rooms/:roomId
//     /activity
//     /profile
//   /social                          — pushed as its own destination, not a shell tab
//   /shop                            — same
//   /agent                           — same
//
// Auth guarding lives entirely in `redirect`, driven by
// `authControllerProvider`'s `AsyncValue<UserEntity?>`: still loading ->
// stay on splash; null -> force to /login (unless already on an auth
// route); non-null -> bounce away from /login|/signup|/splash into /home.
// This is the single source of truth for "can this route be shown" — no
// screen re-checks auth itself.
//
// Transitions: top-level pushed destinations (/social, /shop, /agent) and
// the auth flow use `_fadeThroughPage` — a deliberate fade+slight-rise
// transition (see that function) rather than each platform's raw default,
// so navigation feels like one consistent product instead of "whatever the
// OS does." Tab switches inside the bottom-nav shell are intentionally
// instant (no transition) — that's the correct, native feel for a bottom
// nav, and `StatefulShellRoute.indexedStack` gives it for free.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/controllers/auth_controller.dart';
import '../../features/authentication/presentation/screens/login_screen.dart';
import '../../features/authentication/presentation/screens/signup_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/phlio_agent/presentation/screens/agent_screen.dart';
import '../../features/rooms/presentation/screens/room_detail_screen.dart';
import '../../features/rooms/presentation/screens/rooms_screen.dart';
import '../../features/shop/presentation/screens/shop_screen.dart';
import '../../features/social/presentation/screens/social_feed_screen.dart';
import '../shell/activity_placeholder_screen.dart';
import '../shell/app_shell.dart';
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
/// rather than decoration. Used for every top-level destination in the app
/// (see the module doc-comment for which routes skip it and why).
CustomTransitionPage<void> _fadeThroughPage(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
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
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fadeThroughPage(const LoginScreen()),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (context, state) => _fadeThroughPage(const SignupScreen()),
      ),

      GoRoute(
        path: '/social',
        pageBuilder: (context, state) => _fadeThroughPage(const SocialFeedScreen()),
      ),
      GoRoute(
        path: '/shop',
        pageBuilder: (context, state) => _fadeThroughPage(const ShopScreen()),
      ),
      GoRoute(
        path: '/agent',
        pageBuilder: (context, state) => _fadeThroughPage(const AgentScreen()),
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/rooms',
              builder: (context, state) => const RoomsScreen(),
              routes: [
                GoRoute(
                  path: ':roomId',
                  pageBuilder: (context, state) => _fadeThroughPage(
                    RoomDetailScreen(roomId: state.pathParameters['roomId']!),
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/activity', builder: (context, state) => const ActivityPlaceholderScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
          ]),
        ],
      ),
    ],
  );
});
