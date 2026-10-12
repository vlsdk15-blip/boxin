import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'config/env.dart';
import 'data/supabase.dart';
import 'features/auth/login_screen.dart';
import 'features/centers/centers_screen.dart';
import 'features/home/home_screen.dart';
import 'features/kiosk/kiosk_screen.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authNotifierProvider);
  return GoRouter(
    refreshListenable: auth,
    redirect: (context, state) {
      final path = state.matchedLocation;
      // The kiosk runs on a registered device token, not a person's login.
      if (path == '/kiosk') return null;
      if (!auth.isSignedIn) return path == '/login' ? null : '/login';
      return path == '/login' ? '/' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/', builder: (context, state) => const CentersScreen()),
      GoRoute(
        path: '/center/:centerId',
        builder: (context, state) =>
            HomeScreen(centerId: state.pathParameters['centerId']!),
      ),
      // Opened in a browser on the center's tablet / PC; no app install needed.
      GoRoute(path: '/kiosk', builder: (context, state) => const KioskScreen()),
    ],
  );
});

class BoxInApp extends ConsumerWidget {
  const BoxInApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE8452C)),
      useMaterial3: true,
    );

    if (!Env.isConfigured) {
      return MaterialApp(
        title: '박스인',
        theme: theme,
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Supabase 설정이 없습니다.\n'
                '.env 파일을 만들고 --dart-define-from-file=.env 로 실행하세요.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp.router(
      title: '박스인',
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(_routerProvider),
    );
  }
}
