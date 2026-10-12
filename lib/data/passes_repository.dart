import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'centers_repository.dart';
import 'supabase.dart';

enum PassType {
  period('기간제'),
  count('횟수제');

  const PassType(this.label);
  final String label;
}

/// 250000 → "250,000원"
String formatWon(int amount) {
  final digits = amount.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '$buffer원';
}

class PassProduct {
  const PassProduct({
    required this.id,
    required this.name,
    required this.type,
    required this.price,
    this.durationDays,
    this.count,
    this.usageExpiryDays,
  });

  final String id;
  final String name;
  final PassType type;
  final int price;
  final int? durationDays;
  final int? count;
  final int? usageExpiryDays;

  String get summary => switch (type) {
        PassType.period => '$durationDays일',
        PassType.count => '$count회 · $usageExpiryDays일 안에 사용',
      };

  factory PassProduct.fromJson(Map<String, dynamic> json) => PassProduct(
        id: json['id'] as String,
        name: json['name'] as String,
        type: PassType.values.byName(json['type'] as String),
        price: json['price'] as int,
        durationDays: json['duration_days'] as int?,
        count: json['count'] as int?,
        usageExpiryDays: json['usage_expiry_days'] as int?,
      );
}

class Pass {
  const Pass({
    required this.id,
    required this.productName,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.remainingCount,
  });

  final String id;
  final String productName;
  final PassType type;
  final DateTime startDate;
  final DateTime endDate;
  final String status;
  final int? remainingCount;

  bool get isUsable {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    return status == 'active' &&
        !day.isBefore(startDate) &&
        !day.isAfter(endDate) &&
        (remainingCount == null || remainingCount! > 0);
  }

  String get summary => [
        '${endDate.year}.${endDate.month}.${endDate.day}까지',
        if (remainingCount != null) '$remainingCount회 남음',
        if (status == 'paused') '일시정지',
      ].join(' · ');

  factory Pass.fromJson(Map<String, dynamic> json) {
    final product = json['pass_products'] as Map<String, dynamic>;
    return Pass(
      id: json['id'] as String,
      productName: product['name'] as String,
      type: PassType.values.byName(product['type'] as String),
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      status: json['status'] as String,
      remainingCount: json['remaining_count'] as int?,
    );
  }
}

final passProductsProvider =
    FutureProvider.autoDispose.family<List<PassProduct>, String>((ref, centerId) async {
  final rows = await supabase
      .from('pass_products')
      .select()
      .eq('center_id', centerId)
      .eq('is_active', true)
      .order('price');
  return rows.map(PassProduct.fromJson).toList();
});

typedef PassOwner = ({String centerId, String profileId});

/// Passes of one person in a center, newest end date first. RLS allows the
/// owner and the center's coaches / admins.
final passesProvider =
    FutureProvider.autoDispose.family<List<Pass>, PassOwner>((ref, owner) async {
  final rows = await supabase
      .from('passes')
      .select('id, start_date, end_date, remaining_count, status, pass_products(name, type)')
      .eq('center_id', owner.centerId)
      .eq('profile_id', owner.profileId)
      .order('end_date', ascending: false);
  return rows.map(Pass.fromJson).toList();
});

/// The signed-in user's own passes in a center.
final myPassesProvider =
    FutureProvider.autoDispose.family<List<Pass>, String>((ref, centerId) async {
  final profile = await ref.watch(myProfileProvider.future);
  if (profile == null) return [];
  return ref.watch(passesProvider((centerId: centerId, profileId: profile.id)).future);
});

/// Admin only (RLS).
Future<void> createPassProduct({
  required String centerId,
  required String name,
  required PassType type,
  required int price,
  int? durationDays,
  int? count,
  int? usageExpiryDays,
}) =>
    supabase.from('pass_products').insert({
      'center_id': centerId,
      'name': name,
      'type': type.name,
      'price': price,
      'duration_days': type == PassType.period ? durationDays : null,
      'count': type == PassType.count ? count : null,
      'usage_expiry_days': type == PassType.count ? usageExpiryDays : null,
    });

/// Admin only (RLS). Products are hidden rather than deleted so that passes
/// already sold keep pointing at them.
Future<void> retirePassProduct(String productId) =>
    supabase.from('pass_products').update({'is_active': false}).eq('id', productId);

/// Coach / admin: issues a pass starting today and records the on-site payment.
Future<void> sellPass({
  required String centerId,
  required String profileId,
  required String productId,
}) =>
    supabase.rpc('sell_pass', params: {
      'p_center_id': centerId,
      'p_profile_id': profileId,
      'p_product_id': productId,
    });
