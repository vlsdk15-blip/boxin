import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/passes_repository.dart';

/// Admin: the pass products this center sells.
class PassProductsScreen extends ConsumerWidget {
  const PassProductsScreen({super.key, required this.centerId});

  final String centerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(passProductsProvider(centerId));
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/center/$centerId')),
        title: const Text('회원권 상품'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await showDialog<bool>(
            context: context,
            builder: (_) => _AddProductDialog(centerId: centerId),
          );
          if (added == true) ref.invalidate(passProductsProvider(centerId));
        },
        icon: const Icon(Icons.add),
        label: const Text('상품 추가'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: products.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => const Text('상품을 불러오지 못했습니다.'),
            data: (list) => list.isEmpty
                ? const Text('등록된 회원권 상품이 없습니다.')
                : ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      for (final p in list)
                        ListTile(
                          leading: Chip(label: Text(p.type.label)),
                          title: Text(p.name),
                          subtitle: Text('${p.summary} · ${formatWon(p.price)}'),
                          trailing: IconButton(
                            tooltip: '판매 중지',
                            icon: const Icon(Icons.visibility_off_outlined),
                            onPressed: () => _retire(context, ref, p),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _retire(BuildContext context, WidgetRef ref, PassProduct product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('판매 중지'),
        content: Text('"${product.name}" 판매를 중지할까요? 이미 판매된 회원권은 그대로 유지됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('중지')),
        ],
      ),
    );
    if (ok != true) return;
    await retirePassProduct(product.id);
    ref.invalidate(passProductsProvider(centerId));
  }
}

class _AddProductDialog extends StatefulWidget {
  const _AddProductDialog({required this.centerId});

  final String centerId;

  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _days = TextEditingController(text: '30');
  final _count = TextEditingController(text: '10');
  final _expiry = TextEditingController(text: '60');
  PassType _type = PassType.period;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _price, _days, _count, _expiry]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _number(String? value, {int min = 1}) {
    final n = int.tryParse(value?.trim() ?? '');
    return (n == null || n < min) ? '$min 이상의 숫자' : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await createPassProduct(
        centerId: widget.centerId,
        name: _name.text.trim(),
        type: _type,
        price: int.parse(_price.text.trim()),
        durationDays: int.tryParse(_days.text.trim()),
        count: int.tryParse(_count.text.trim()),
        usageExpiryDays: int.tryParse(_expiry.text.trim()),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '상품을 추가하지 못했습니다. 관리자만 추가할 수 있습니다.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('회원권 상품 추가'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<PassType>(
                segments: [
                  for (final type in PassType.values)
                    ButtonSegment(value: type, label: Text(type.label)),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: '상품 이름', hintText: '1개월 무제한'),
                validator: (v) => (v == null || v.trim().isEmpty) ? '이름을 입력해 주세요' : null,
              ),
              if (_type == PassType.period)
                TextFormField(
                  controller: _days,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '기간', suffixText: '일'),
                  validator: _number,
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _count,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '횟수', suffixText: '회'),
                        validator: _number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _expiry,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '사용 만료', suffixText: '일'),
                        validator: _number,
                      ),
                    ),
                  ],
                ),
              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '가격', suffixText: '원'),
                validator: (v) => _number(v, min: 0),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('추가')),
      ],
    );
  }
}
