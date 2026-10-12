import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/centers_repository.dart';

/// Center home. Placeholder until today's classes, check-in and passes land.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.centerId});

  final String centerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final centers = ref.watch(myCentersProvider).valueOrNull ?? const <MyCenter>[];
    final center = centers.where((c) => c.centerId == centerId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '센터 선택',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: Text(center?.name ?? '박스인'),
      ),
      body: Center(
        child: Text(
          center == null ? '이 센터의 회원이 아닙니다.' : '${center.role.label} 홈 — 준비 중',
        ),
      ),
    );
  }
}
