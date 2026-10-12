import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/centers_repository.dart';

/// Admin: center name, address, coordinates and check-in radius.
class CenterSettingsScreen extends ConsumerWidget {
  const CenterSettingsScreen({super.key, required this.centerId});

  final String centerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(centerSettingsProvider(centerId));
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/center/$centerId')),
        title: const Text('센터 설정'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: settings.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => const Text('센터 정보를 불러오지 못했습니다.'),
            data: (s) => _SettingsForm(settings: s),
          ),
        ),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings});

  final CenterSettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.settings.name);
  late final _address = TextEditingController(text: widget.settings.address ?? '');
  late final _latitude =
      TextEditingController(text: widget.settings.latitude?.toString() ?? '');
  late final _longitude =
      TextEditingController(text: widget.settings.longitude?.toString() ?? '');
  late final _radius =
      TextEditingController(text: widget.settings.attendanceRadiusM.toString());
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _latitude, _longitude, _radius]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _coordinate(String? value, double limit) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final number = double.tryParse(text);
    if (number == null || number.abs() > limit) return '올바른 값이 아닙니다';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final hasLat = _latitude.text.trim().isNotEmpty;
    final hasLng = _longitude.text.trim().isNotEmpty;
    if (hasLat != hasLng) {
      _notify('위도와 경도는 함께 입력해 주세요.');
      return;
    }
    setState(() => _busy = true);
    try {
      final address = _address.text.trim();
      await updateCenter(
        widget.settings.id,
        name: _name.text.trim(),
        address: address.isEmpty ? null : address,
        latitude: double.tryParse(_latitude.text.trim()),
        longitude: double.tryParse(_longitude.text.trim()),
        attendanceRadiusM: int.parse(_radius.text.trim()),
      );
      ref.invalidate(centerSettingsProvider(widget.settings.id));
      ref.invalidate(myCentersProvider);
      _notify('저장했습니다.');
    } catch (_) {
      _notify('저장하지 못했습니다. 관리자만 변경할 수 있습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: '센터 이름', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.trim().isEmpty) ? '이름을 입력해 주세요' : null,
          ),
          gap,
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: '주소', border: OutlineInputBorder()),
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _latitude,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(
                      labelText: '위도', hintText: '37.4979', border: OutlineInputBorder()),
                  validator: (v) => _coordinate(v, 90),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _longitude,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(
                      labelText: '경도', hintText: '127.0276', border: OutlineInputBorder()),
                  validator: (v) => _coordinate(v, 180),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '위도·경도를 입력해야 회원이 센터 근처에서만 출석할 수 있습니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          gap,
          TextFormField(
            controller: _radius,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: '출석 반경', suffixText: 'm', border: OutlineInputBorder()),
            validator: (v) {
              final meters = int.tryParse(v?.trim() ?? '');
              return (meters == null || meters <= 0) ? '1 이상의 숫자를 입력해 주세요' : null;
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('저장'),
            ),
          ),
        ],
      ),
    );
  }
}
