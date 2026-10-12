import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/centers_repository.dart';
import '../../data/classes_repository.dart';

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

String _dayLabel(DateTime d) => '${d.month}월 ${d.day}일 (${_weekdays[d.weekday - 1]})';
String _timeLabel(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Upcoming classes with live remaining seats. Everyone can book; coaches and
/// admins can also add and delete classes.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key, required this.centerId});

  final String centerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(upcomingClassesProvider(centerId));
    final bookings = ref.watch(myBookingsProvider(centerId)).valueOrNull ?? const {};
    final role = ref
        .watch(myCentersProvider)
        .valueOrNull
        ?.where((c) => c.centerId == centerId)
        .firstOrNull
        ?.role;
    final isStaff = role == MemberRole.coach || role == MemberRole.admin;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/center/$centerId')),
        title: const Text('수업 시간표'),
      ),
      floatingActionButton: isStaff
          ? FloatingActionButton.extended(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _AddClassDialog(centerId: centerId),
              ),
              icon: const Icon(Icons.add),
              label: const Text('수업 추가'),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: classes.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => const Text('시간표를 불러오지 못했습니다.'),
            data: (list) {
              if (list.isEmpty) return const Text('예정된 수업이 없습니다.');
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final session = list[i];
                  final newDay = i == 0 || !DateUtils.isSameDay(list[i - 1].startsAt, session.startsAt);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (newDay)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                          child: Text(_dayLabel(session.startsAt),
                              style: Theme.of(context).textTheme.titleSmall),
                        ),
                      _ClassTile(
                        centerId: centerId,
                        session: session,
                        booking: bookings[session.id],
                        isStaff: isStaff,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ClassTile extends ConsumerStatefulWidget {
  const _ClassTile({
    required this.centerId,
    required this.session,
    required this.booking,
    required this.isStaff,
  });

  final String centerId;
  final ClassSession session;
  final MyBooking? booking;
  final bool isStaff;

  @override
  ConsumerState<_ClassTile> createState() => _ClassTileState();
}

class _ClassTileState extends ConsumerState<_ClassTile> {
  bool _busy = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    String? message;
    try {
      final booking = widget.booking;
      if (booking != null) {
        await cancelBooking(booking.id);
        message = '예약을 취소했습니다.';
      } else {
        final status = await bookClass(widget.session.id);
        message = status == BookingStatus.booked ? '예약했습니다.' : '정원이 차서 대기로 등록했습니다.';
      }
    } on BookingException catch (e) {
      message = e.message;
    } catch (_) {
      message = '처리하지 못했습니다.';
    }
    ref.invalidate(myBookingsProvider(widget.centerId));
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('수업 삭제'),
        content: Text('${_dayLabel(widget.session.startsAt)} ${_timeLabel(widget.session.startsAt)} '
            '수업을 삭제할까요? 예약 ${widget.session.bookedCount}건도 함께 사라집니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) await deleteClass(widget.session.id);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final booking = widget.booking;
    final seats = '${session.bookedCount}/${session.capacity}명';
    return ListTile(
      leading: Text(_timeLabel(session.startsAt), style: Theme.of(context).textTheme.titleMedium),
      title: Text(session.displayTitle),
      subtitle: Text([
        '${session.durationMin}분',
        seats,
        if (booking != null) booking.status.label,
      ].join(' · ')),
      onLongPress: widget.isStaff ? _delete : null,
      trailing: booking != null
          ? OutlinedButton(onPressed: _busy ? null : _toggle, child: const Text('취소'))
          : FilledButton.tonal(
              onPressed: _busy ? null : _toggle,
              child: Text(session.isFull ? '대기' : '예약'),
            ),
    );
  }
}

class _AddClassDialog extends StatefulWidget {
  const _AddClassDialog({required this.centerId});

  final String centerId;

  @override
  State<_AddClassDialog> createState() => _AddClassDialogState();
}

class _AddClassDialogState extends State<_AddClassDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _capacity = TextEditingController(text: '12');
  final _weeks = TextEditingController(text: '1');
  DateTime _date = DateUtils.dateOnly(DateTime.now().add(const Duration(days: 1)));
  TimeOfDay _time = const TimeOfDay(hour: 19, minute: 0);
  ClassKind _kind = ClassKind.crossfit;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _capacity.dispose();
    _weeks.dispose();
    super.dispose();
  }

  String? _positive(String? value, {int max = 1000}) {
    final n = int.tryParse(value?.trim() ?? '');
    return (n == null || n < 1 || n > max) ? '1~$max 사이 숫자' : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final start = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    if (!start.isAfter(DateTime.now())) {
      setState(() => _error = '지난 시간에는 수업을 만들 수 없습니다.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await createClasses(
        centerId: widget.centerId,
        firstStart: start,
        kind: _kind,
        capacity: int.parse(_capacity.text.trim()),
        title: _title.text.trim(),
        weeks: int.parse(_weeks.text.trim()),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '수업을 만들지 못했습니다.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('수업 추가'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(_dayLabel(_date)),
                      onPressed: () async {
                        final today = DateUtils.dateOnly(DateTime.now());
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: today,
                          lastDate: today.add(const Duration(days: 365)),
                        );
                        if (picked != null) setState(() => _date = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_time.format(context)),
                    onPressed: () async {
                      final picked = await showTimePicker(context: context, initialTime: _time);
                      if (picked != null) setState(() => _time = picked);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<ClassKind>(
                segments: [
                  for (final kind in ClassKind.values)
                    ButtonSegment(value: kind, label: Text(kind.label)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: '수업 이름 (선택)'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _capacity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '정원', suffixText: '명'),
                      validator: _positive,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _weeks,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '매주 반복', suffixText: '주'),
                      validator: (v) => _positive(v, max: 26),
                    ),
                  ),
                ],
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
