import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/centers_repository.dart';
import '../../data/supabase.dart';

/// Center picker shown after login: the centers I belong to, plus creating one.
class CentersScreen extends ConsumerWidget {
  const CentersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    final centers = ref.watch(myCentersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('센터 선택'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createCenter(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('센터 만들기'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: profile.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => _ErrorView(onRetry: () => ref.invalidate(myProfileProvider)),
            data: (p) {
              if (p == null) {
                return _ErrorView(onRetry: () => ref.invalidate(myProfileProvider));
              }
              if (p.name.isEmpty) return _NameForm(profile: p);
              return centers.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => _ErrorView(onRetry: () => ref.invalidate(myCentersProvider)),
                data: (list) => list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          '아직 소속된 센터가 없습니다.\n'
                          '다니는 센터의 코치에게 이 전화번호로 회원 등록을 요청하거나,\n'
                          '센터를 운영 중이라면 새 센터를 만드세요.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 88),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text('${p.name}님, 어느 센터로 갈까요?',
                                style: Theme.of(context).textTheme.titleMedium),
                          ),
                          for (final c in list)
                            ListTile(
                              leading: const Icon(Icons.fitness_center),
                              title: Text(c.name),
                              subtitle: c.address == null ? null : Text(c.address!),
                              trailing: Chip(label: Text(c.role.label)),
                              onTap: () => context.go('/center/${c.centerId}'),
                            ),
                        ],
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _createCenter(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('센터 만들기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '센터 이름'),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: '주소 (선택)'),
            ),
            const SizedBox(height: 12),
            const Text('만든 사람이 이 센터의 관리자가 됩니다.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('만들기')),
        ],
      ),
    );
    final name = nameController.text.trim();
    if (created != true || name.isEmpty) return;
    try {
      await createCenter(name: name, address: addressController.text.trim());
      ref.invalidate(myCentersProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('센터를 만들지 못했습니다.')));
      }
    }
  }
}

/// First login: ask for the display name coaches and the kiosk will show.
class _NameForm extends ConsumerStatefulWidget {
  const _NameForm({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_NameForm> createState() => _NameFormState();
}

class _NameFormState extends ConsumerState<_NameForm> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await updateMyName(widget.profile.id, name);
      ref.invalidate(myProfileProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('이름을 저장하지 못했습니다.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('이름을 알려 주세요', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('센터 출석 화면과 코치에게 보이는 이름입니다.'),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: '이름', border: OutlineInputBorder()),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('계속')),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('정보를 불러오지 못했습니다.'),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    );
  }
}
