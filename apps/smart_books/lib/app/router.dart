import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/auth_page.dart';
import '../features/chatgpt/connect_chatgpt_page.dart';
import '../features/library/library_page.dart';
import '../features/reader/reader_search_focus.dart';
import '../features/workspace/book_practice_page.dart';
import '../features/workspace/book_study_page.dart';
import '../features/workspace/book_workspace_leer_shell.dart';
import '../features/workspace/book_workspace_nav.dart';
import '../features/review/repaso_generated_questions_page.dart';
import '../features/review/repaso_session_page.dart';
import '../features/review/review_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';
import '../features/setup/setup_page.dart';
import 'app_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

/// Snackbars globales (p. ej. Repaso en escritorio sin [Scaffold] en el árbol).
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>(
  debugLabel: 'rootMessenger',
);

GoRouter createRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final loc = state.matchedLocation;
      final loggingIn = loc == '/login';
      const publicRoutes = {'/login', '/setup', '/conectar-chatgpt'};

      if (session == null && !publicRoutes.contains(loc)) {
        return '/login';
      }

      if (session != null && loggingIn) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (_, __) => const SetupPage()),
      GoRoute(path: '/login', builder: (_, __) => const AuthPage()),
      GoRoute(
        path: '/conectar-chatgpt',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const ConnectChatGptPage(),
      ),
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const LibraryPage()),
          GoRoute(path: '/repaso', builder: (_, __) => const ReviewPage()),
          GoRoute(path: '/buscar', builder: (_, __) => const SearchPage()),
          GoRoute(path: '/ajustes', builder: (_, __) => const SettingsPage()),
        ],
      ),
      GoRoute(
        path: '/repaso/preguntas',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const RepasoGeneratedQuestionsPage(),
      ),
      GoRoute(
        path: '/repaso/sesion',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => RepasoSessionPage.fromRoute(state),
      ),
      GoRoute(
        path: '/libro/:bookId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) {
          final bookId = state.pathParameters['bookId']!;
          final page = int.tryParse(state.uri.queryParameters['page'] ?? '');
          final view = bookWorkspaceModeFromQuery(
            state.uri.queryParameters['view'],
          );
          return switch (view) {
            BookWorkspaceMode.estudiar => BookStudyPage(
              bookId: bookId,
              initialPage: page,
            ),
            BookWorkspaceMode.practicar => BookPracticePage(
              bookId: bookId,
              initialPage: page,
            ),
            BookWorkspaceMode.leer => BookWorkspaceLeerShell(
              bookId: bookId,
              initialPage: page,
              searchFocus: ReaderSearchFocus.fromRouteExtra(state.extra),
            ),
          };
        },
      ),
    ],
  );
}

/// Una sola instancia de router para toda la app (evita colisiones de claves en Navigator).
final appRouter = createRouter();
