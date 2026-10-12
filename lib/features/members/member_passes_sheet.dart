import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/centers_repository.dart';
import '../../data/passes_repository.dart';

/// Coach / admin: one member's passes, and selling them a new one on site.
class MemberPassesSheet extends ConsumerWidget {
  const MemberPassesSheet({super.key, required this.centerId, required this.member});

  final String centerId;
  final CenterMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = (centerId: centerId, profileId: member.profileId);
    final passes = ref.watch(passesProvider(owner));
    final products = ref.watch(passProductsProvider(centerId));
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(member.name.isEmpty ? '(이름 없음)' : member.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('보유 회원권', style: theme.textTheme.titleSmall),
            passes.when(
              loading: () => const Padding(
                  padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => const Text('회원권을 불러오지 못했습니다.'),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12), child: Text('회원권이 없습니다.'))
                  : Column(
                      children: [
                        for (final pass in list)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(pass.productName),
                            subtitle: Text(pass.summary),
                            trailing: pass.isUsable ? const Chip(label: Text('사용 중')) : null,
                          ),
                      ],
                    ),
            ),
            const Divider(),
            Text('회원권 판매 (현장 결제)', style: theme.textTheme.titleSmall),
            products.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const Text('상품을 불러오지 못했습니다.'),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('판매할 상품이 없습니다. 관리자가 회원권 상품을 먼저 등록해야 합니다.'),
                    )
                  : Column(
                      children: [
                        for (final product in list)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(product.name),
                            subtitle: Text('${product.summary} · ${formatWon(product.price)}'),
                            trailing: FilledButton.tonal(
                              onPressed: () => _sell(context, ref, product),
                              child: const Text('판매'),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sell(BuildContext context, WidgetRef ref, PassProduct product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('회원권 판매'),
        content: Text('${member.name}님에게 "${product.name}"을(를) ${formatWon(product.price)}에 '
            '판매합니다. 오늘부터 시작되고 현장 결제로 기록됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('판매')),
        ],
      ),
    );
    if (ok != true) return;
    String message = '회원권을 발급했습니다.';
    try {
      await sellPass(centerId: centerId, profileId: member.profileId, productId: product.id);
      ref.invalidate(passesProvider((centerId: centerId, profileId: member.profileId)));
    } catch (_) {
      message = '판매하지 못했습니다.';
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
