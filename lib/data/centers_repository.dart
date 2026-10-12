import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'supabase.dart';

enum MemberRole {
  member('회원'),
  coach('코치'),
  admin('관리자');

  const MemberRole(this.label);
  final String label;
}

class Profile {
  const Profile({required this.id, required this.name, this.phone});

  final String id;
  final String name;
  final String? phone;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String?,
      );
}

/// One center the signed-in user belongs to, with their role there.
class MyCenter {
  const MyCenter({
    required this.centerId,
    required this.name,
    required this.role,
    this.address,
  });

  final String centerId;
  final String name;
  final String? address;
  final MemberRole role;

  factory MyCenter.fromJson(Map<String, dynamic> json) {
    final center = json['centers'] as Map<String, dynamic>;
    return MyCenter(
      centerId: center['id'] as String,
      name: center['name'] as String,
      address: center['address'] as String?,
      role: MemberRole.values.byName(json['role'] as String),
    );
  }
}

final myProfileProvider = FutureProvider.autoDispose<Profile?>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;
  final row = await supabase
      .from('profiles')
      .select('id, name, phone')
      .eq('user_id', userId)
      .maybeSingle();
  return row == null ? null : Profile.fromJson(row);
});

final myCentersProvider = FutureProvider.autoDispose<List<MyCenter>>((ref) async {
  final profile = await ref.watch(myProfileProvider.future);
  if (profile == null) return [];
  final rows = await supabase
      .from('memberships')
      .select('role, centers(id, name, address)')
      .eq('profile_id', profile.id)
      .eq('is_active', true)
      .order('created_at');
  return rows.map(MyCenter.fromJson).toList();
});

Future<void> updateMyName(String profileId, String name) =>
    supabase.from('profiles').update({'name': name}).eq('id', profileId);

/// Creates a center; the caller becomes its admin. Returns the center id.
Future<String> createCenter({required String name, String? address}) async {
  final id = await supabase.rpc('create_center', params: {
    'p_name': name,
    if (address != null && address.isNotEmpty) 'p_address': address,
  });
  return id as String;
}
