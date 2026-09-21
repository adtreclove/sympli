import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sympli/app_shell.dart';
import 'package:sympli/screens/course_screen.dart';
import 'package:sympli/screens/entry_screen.dart';
import 'package:sympli/screens/login_screen.dart';
import 'package:sympli/screens/pattern_screen.dart';
import 'package:sympli/screens/today_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/today',
  refreshListenable: GoRouterRefreshStream(
    Supabase.instance.client.auth.onAuthStateChange,
  ),
  redirect: (context, state) {
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    final onLoginPage = state.matchedLocation == '/login';

    if (!loggedIn && !onLoginPage) return '/login';
    if (loggedIn && onLoginPage) return '/today';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),

    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          navigatorKey: _shellNavigatorKey,
          routes: [
            GoRoute(path: '/today', builder: (_, __) => const TodayScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/course', builder: (_, __) => const CourseScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/pattern',
              builder: (_, __) => const PatternScreen(),
            ),
          ],
        ),
      ],
    ),

    // lies outside the app shell (own parentNavigatorKey)
    // to have the sheet above the actual screen
    GoRoute(
      path: '/entry',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => CustomTransitionPage(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        child: const EntryScreen(),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    ),
  ],
);

/// Makes the auth stream listenable for go_router
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
