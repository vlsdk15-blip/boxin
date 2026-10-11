import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'config/env.dart';
import 'features/home/home_screen.dart';
import 'features/kiosk/kiosk_screen.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    // Opened in a browser on the center's tablet / PC; no app install needed.
    GoRoute(path: '/kiosk', builder: (context, state) => const KioskScreen()),
  ],
);

class BoxInApp extends StatelessWidget {
  const BoxInApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '박스인',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE8452C)),
        useMaterial3: true,
      ),
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
      builder: (context, child) => Env.isConfigured
          ? child!
          : const Scaffold(
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
}
