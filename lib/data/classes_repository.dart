import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'centers_repository.dart';
import 'supabase.dart';

enum ClassKind {
  crossfit('크로스핏'),
  hyrox('하이록스');

  const ClassKind(this.label);
  final String label;
}

enum BookingStatus {
  booked('예약됨'),
  waitlisted('대기 중');

  const BookingStatus(this.label);
  final String label;
}

class ClassSession {
  const ClassSession({
    required this.id,
    required this.kind,
    required this.startsAt,
    required this.durationMin,
    required this.capacity,
    required this.bookedCount,
    this.title,
  });

  final String id;
  final String? title;
  final ClassKind kind;

  /// Device-local time.
  final DateTime startsAt;
  final int durationMin;
  final int capacity;
  final int bookedCount;

  bool get isFull => bookedCount >= capacity;
  String get displayTitle => (title == null || title!.isEmpty) ? kind.label : title!;

  factory ClassSession.fromJson(Map<String, dynamic> json) => ClassSession(
        id: json['id'] as String,
        title: json['title'] as String?,
        kind: ClassKind.values.byName(json['kind'] as String),
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        durationMin: json['duration_min'] as int,
        capacity: json['capacity'] as int,
        bookedCount: json['booked_count'] as int,
      );
}

class MyBooking {
  const MyBooking({required this.id, required this.status});

  final String id;
  final BookingStatus status;
}

/// Upcoming classes of a center, updated live (remaining seats) over Realtime.
final upcomingClassesProvider =
    StreamProvider.autoDispose.family<List<ClassSession>, String>((ref, centerId) {
  return supabase
      .from('classes')
      .stream(primaryKey: ['id'])
      .eq('center_id', centerId)
      .map((rows) {
    final now = DateTime.now();
    final sessions = rows
        .map(ClassSession.fromJson)
        .where((c) => c.startsAt.isAfter(now))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return sessions;
  });
});

/// My live (not cancelled) bookings in a center, keyed by class id.
final myBookingsProvider =
    FutureProvider.autoDispose.family<Map<String, MyBooking>, String>((ref, centerId) async {
  final profile = await ref.watch(myProfileProvider.future);
  if (profile == null) return {};
  final rows = await supabase
      .from('bookings')
      .select('id, class_id, status')
      .eq('center_id', centerId)
      .eq('profile_id', profile.id)
      .neq('status', 'cancelled');
  return {
    for (final row in rows)
      row['class_id'] as String: MyBooking(
        id: row['id'] as String,
        status: BookingStatus.values.byName(row['status'] as String),
      ),
  };
});

/// Thrown with a message that can be shown to the user as is.
class BookingException implements Exception {
  const BookingException(this.message);
  final String message;
}

/// Books a class through the capacity-checking server function.
Future<BookingStatus> bookClass(String classId) async {
  try {
    final status = await supabase.rpc('book_class', params: {'p_class_id': classId});
    return BookingStatus.values.byName(status as String);
  } on PostgrestException catch (e) {
    throw BookingException(switch (e.message) {
      'no usable pass' => '사용할 수 있는 회원권이 없습니다.',
      'class already started' => '이미 시작한 수업입니다.',
      _ => '예약하지 못했습니다.',
    });
  }
}

Future<void> cancelBooking(String bookingId) =>
    supabase.rpc('cancel_booking', params: {'p_booking_id': bookingId});

/// Coach / admin: creates one class, or the same slot weekly for [weeks] weeks.
Future<void> createClasses({
  required String centerId,
  required DateTime firstStart,
  required ClassKind kind,
  required int capacity,
  String? title,
  int durationMin = 60,
  int weeks = 1,
}) async {
  final seriesId = weeks > 1 ? _uuidV4() : null;
  await supabase.from('classes').insert([
    for (var week = 0; week < weeks; week++)
      {
        'center_id': centerId,
        'kind': kind.name,
        'title': (title == null || title.isEmpty) ? null : title,
        // Same wall-clock time each week, even across a DST change.
        'starts_at': DateTime(firstStart.year, firstStart.month, firstStart.day + 7 * week,
                firstStart.hour, firstStart.minute)
            .toUtc()
            .toIso8601String(),
        'duration_min': durationMin,
        'capacity': capacity,
        'series_id': seriesId,
      },
  ]);
}

Future<void> deleteClass(String classId) =>
    supabase.from('classes').delete().eq('id', classId);

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
