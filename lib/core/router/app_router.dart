import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_page.dart';
import '../../features/auth/splash_page.dart';
import '../../features/forecast/forecast_page.dart';
import '../../features/home/home_shell.dart';
import '../../features/home/overview_page.dart';
import '../../features/plan/plan_page.dart';
import '../../features/security/security_page.dart';
import '../../features/stock/stock_page.dart';
import '../auth/auth_controller.dart';

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
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      if (auth.initializing) return loc == '/splash' ? null : '/splash';
      if (auth.user == null) return loc == '/login' ? null : '/login';
      if (loc == '/login' || loc == '/splash') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
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