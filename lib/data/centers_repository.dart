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

class CenterSettings {
  const CenterSettings({
    required this.id,
    required this.name,
    this.address,
    this.latitude,
    this.longitude,
    required this.attendanceRadiusM,
  });

  final String id;
  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final int attendanceRadiusM;

  factory CenterSettings.fromJson(Map<String, dynamic> json) => CenterSettings(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        attendanceRadiusM: json['attendance_radius_m'] as int,
      );
}

final centerSettingsProvider =
    FutureProvider.autoDispose.family<CenterSettings, String>((ref, centerId) async {
  final row = await supabase
      .from('centers')
      .select('id, name, address, latitude, longitude, attendance_radius_m')
      .eq('id', centerId)
      .single();
  return CenterSettings.fromJson(row);
});

/// Admin only (RLS). Throws when no row was updated.
Future<void> updateCenter(
  String centerId, {
  required String name,
  String? address,
  double? latitude,
  double? longitude,
  required int attendanceRadiusM,
}) async {
  final rows = await supabase
      .from('centers')
      .update({
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'attendance_radius_m': attendanceRadiusM,
      })
      .eq('id', centerId)
      .select('id');
  if (rows.isEmpty) throw StateError('center not updated');
}

class CenterMember {
  const CenterMember({
    required this.membershipId,
    required this.profileId,
    required this.name,
    this.phone,
    required this.role,
    this.memberNo,
    required this.usesApp,
  });

  final String membershipId;
  final String profileId;
  final String name;
  final String? phone;
  final MemberRole role;
  final String? memberNo;

  /// False while the person was registered by a coach but has not signed up.
  final bool usesApp;

  factory CenterMember.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>;
    return CenterMember(
      membershipId: json['id'] as String,
      profileId: json['profile_id'] as String,
      name: profile['name'] as String? ?? '',
      phone: profile['phone'] as String?,
      role: MemberRole.values.byName(json['role'] as String),
      memberNo: json['member_no'] as String?,
      usesApp: profile['user_id'] != null,
    );
  }
}

/// Coach / admin only (RLS): everyone in the center.
final centerMembersProvider =
    FutureProvider.autoDispose.family<List<CenterMember>, String>((ref, centerId) async {
  final rows = await supabase
      .from('memberships')
      .select('id, profile_id, role, member_no, profiles(name, phone, user_id)')
      .eq('center_id', centerId)
      .eq('is_active', true)
      .order('created_at');
  return rows.map(CenterMember.fromJson).toList();
});

/// Coach / admin registers a member by name + phone, before they install the app.
Future<void> registerMember({
  required String centerId,
  required String name,
  required String phone,
  String? memberNo,
}) =>
    supabase.rpc('register_member', params: {
      'p_center_id': centerId,
      'p_name': name,
      'p_phone': phone,
      if (memberNo != null && memberNo.isNotEmpty) 'p_member_no': memberNo,
    });
