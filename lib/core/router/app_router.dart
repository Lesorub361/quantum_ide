import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/home/presentation/pages/bootstrap_page.dart';
import '../../features/file_explorer/presentation/pages/file_explorer_page.dart';
import '../../features/editor/presentation/pages/editor_page.dart';
import '../../features/preview/presentation/pages/preview_page.dart';
import '../../features/terminal/presentation/pages/terminal_page.dart';
import '../../features/home/presentation/pages/server_page.dart';
import '../../features/home/presentation/pages/package_page.dart';
import '../../features/home/presentation/pages/settings_page.dart';
import '../../shared/widgets/main_layout.dart';

class UnfocusRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    FocusManager.instance.primaryFocus?.unfocus();
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    FocusManager.instance.primaryFocus?.unfocus();
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    FocusManager.instance.primaryFocus?.unfocus();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

final appRouter = GoRouter(
  initialLocation: '/bootstrap',
  observers: [
    UnfocusRouteObserver(),
  ],
  routes: [
    GoRoute(
      path: '/bootstrap',
      builder: (context, state) => const BootstrapPage(),
    ),
    ShellRoute(
      builder: (context, state, child) => MainLayout(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomePage(),
        ),
        GoRoute(
          path: '/explorer',
          builder: (context, state) => const FileExplorerPage(),
        ),
        GoRoute(
          path: '/editor',
          builder: (context, state) => const EditorPage(),
        ),
        GoRoute(
          path: '/preview',
          builder: (context, state) => const PreviewPage(),
        ),
        GoRoute(
          path: '/terminal',
          builder: (context, state) => const TerminalPage(),
        ),
        GoRoute(
          path: '/servers',
          builder: (context, state) => const ServerPage(),
        ),
        GoRoute(
          path: '/packages',
          builder: (context, state) => const PackagePage(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),
  ],
);
