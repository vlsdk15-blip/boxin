import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/centers_repository.dart';

/// Center home. Staff get management entries; the member home (today's
/// classes, check-in, passes) is still to come.
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
                        if (center.role != MemberRole.member)
                          ListTile(
                            leading: const Icon(Icons.groups),
                            title: const Text('회원 관리'),
                            subtitle: const Text('회원 목록, 새 회원 등록'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go('/center/$centerId/members'),
                          ),
                        if (center.role == MemberRole.admin)
                          ListTile(
                            leading: const Icon(Icons.settings),
                            title: const Text('센터 설정'),
                            subtitle: const Text('주소, 좌표, 출석 반경'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go('/center/$centerId/settings'),
                          ),
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('수업 예약과 출석은 준비 중입니다.', textAlign: TextAlign.center),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
