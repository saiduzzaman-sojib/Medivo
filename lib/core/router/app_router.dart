import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_page.dart';
import '../../features/auth/mfa_page.dart';
import '../../features/auth/splash_page.dart';
import '../../features/forecast/forecast_page.dart';
import '../../features/home/home_shell.dart';
import '../../features/home/overview_page.dart';
import '../../features/plan/plan_page.dart';
import '../../features/security/security_page.dart';
import '../../features/stock/stock_page.dart';
import '../auth/auth_controller.dart';

/// Decides where a person must be, based on how far they got in signing in.
/// A pure function, so it is easy to test.
String? redirectFor(AuthState auth, String location) {
  if (auth.initializing) return location == '/splash' ? null : '/splash';
  switch (auth.stage) {
    case AuthStage.signedOut:
      return location == '/login' ? null : '/login';
    case AuthStage.needsMfaSetup:
    case AuthStage.needsMfaChallenge:
      return location == '/mfa' ? null : '/mfa';
    case AuthStage.ready:
      if (location == '/login' || location == '/splash' || location == '/mfa') {
        return '/home';
      }
      return null;
  }
}

/// Re-runs the router redirect whenever the sign-in state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) =>
        redirectFor(ref.read(authControllerProvider), state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/mfa', builder: (context, state) => const MfaPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (context, state) => const OverviewPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/stock', builder: (context, state) => const StockPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/forecast', builder: (context, state) => const ForecastPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/plan', builder: (context, state) => const PlanPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/security', builder: (context, state) => const SecurityPage()),
          ]),
        ],
      ),
    ],
  );
});