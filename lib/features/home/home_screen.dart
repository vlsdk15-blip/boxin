import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/centers_repository.dart';
import '../../data/passes_repository.dart';

/// Center home: my passes, the schedule, and management entries for staff.
/// Check-in is still to come.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.centerId});

  final String centerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final centers = ref.watch(myCentersProvider);
    final center =
        centers.valueOrNull?.where((c) => c.centerId == centerId).firstOrNull;

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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: centers.isLoading
              ? const CircularProgressIndicator()
              : center == null
                  ? const Text('이 센터의 회원이 아닙니다.')
                  : ListView(
                      children: [
                        _MyPasses(centerId: centerId),
                        _MenuTile(
                          icon: Icons.calendar_month,
                          title: '수업 시간표',
                          subtitle: '수업 예약, 남은 자리',
                          path: '/center/$centerId/schedule',
                        ),
                        if (center.role != MemberRole.member)
                          _MenuTile(
                            icon: Icons.groups,
                            title: '회원 관리',
                            subtitle: '회원 목록, 새 회원 등록, 회원권 판매',
                            path: '/center/$centerId/members',
                          ),
                        if (center.role == MemberRole.admin) ...[
                          _MenuTile(
                            icon: Icons.confirmation_number_outlined,
                            title: '회원권 상품',
                            subtitle: '기간제·횟수제 상품과 가격',
                            path: '/center/$centerId/products',
                          ),
                          _MenuTile(
                            icon: Icons.settings,
                            title: '센터 설정',
                            subtitle: '주소, 좌표, 출석 반경',
                            path: '/center/$centerId/settings',
                          ),
                        ],
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('출석 기능은 준비 중입니다.', textAlign: TextAlign.center),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String path;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(path),
    );
  }
}

/// The signed-in user's usable passes in this center.
class _MyPasses extends ConsumerWidget {
  const _MyPasses({required this.centerId});

  final String centerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usable = (ref.watch(myPassesProvider(centerId)).valueOrNull ?? const <Pass>[])
        .where((p) => p.isUsable)
        .toList();
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('내 회원권', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (usable.isEmpty)
              const Text('사용할 수 있는 회원권이 없습니다.')
            else
              for (final pass in usable)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(pass.productName, style: theme.textTheme.titleMedium)),
                      Text(pass.summary),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
