import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/centers_repository.dart';
import '../../data/supabase.dart';

/// Coach / admin: everyone in the center, and registering a new member.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key, required this.centerId});

  final String centerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(centerMembersProvider(centerId));
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/center/$centerId')),
        title: const Text('회원 관리'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _register(context, ref),
        icon: const Icon(Icons.person_add),
        label: const Text('회원 등록'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: members.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => const Text('회원 목록을 불러오지 못했습니다.'),
            data: (list) => ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final m = list[i];
                final details = [
                  if (m.memberNo != null) '회원번호 ${m.memberNo}',
                  if (m.phone != null) formatPhone(m.phone!),
                  if (!m.usesApp) '앱 미가입',
                ].join(' · ');
                return ListTile(
                  leading: CircleAvatar(child: Text(m.name.isEmpty ? '?' : m.name.characters.first)),
                  title: Text(m.name.isEmpty ? '(이름 없음)' : m.name),
                  subtitle: details.isEmpty ? null : Text(details),
                  trailing: m.role == MemberRole.member ? null : Chip(label: Text(m.role.label)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _register(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final memberNo = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('회원 등록'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: '이름'),
                validator: (v) => (v == null || v.trim().isEmpty) ? '이름을 입력해 주세요' : null,
              ),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: '휴대폰 번호', hintText: '010-1234-5678'),
                validator: (v) => toE164(v ?? '') == null ? '휴대폰 번호를 확인해 주세요' : null,
              ),
              TextFormField(
                controller: memberNo,
                decoration: const InputDecoration(labelText: '회원번호 (선택)'),
              ),
              const SizedBox(height: 12),
              const Text('회원이 나중에 같은 번호로 앱에 가입하면 자동으로 연결됩니다.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('등록'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    String message = '등록했습니다.';
    try {
      await registerMember(
        centerId: centerId,
        name: name.text.trim(),
        phone: phone.text,
        memberNo: memberNo.text.trim(),
      );
      ref.invalidate(centerMembersProvider(centerId));
    } catch (_) {
      message = '등록하지 못했습니다. 회원번호가 겹치지 않는지 확인해 주세요.';
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
