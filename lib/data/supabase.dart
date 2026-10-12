import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get supabase => Supabase.instance.client;

/// Notifies the router whenever the user signs in or out.
class AuthNotifier extends ChangeNotifier {
  AuthNotifier() {
    supabase.auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  bool get isSignedIn => supabase.auth.currentSession != null;
}

final authNotifierProvider = Provider<AuthNotifier>((ref) => AuthNotifier());

/// Converts Korean domestic input (010-1234-5678) to E.164 (+821012345678).
/// Returns null when the input is not a plausible mobile number.
String? toE164(String input) {
  var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('82')) digits = '0${digits.substring(2)}';
  if (!RegExp(r'^01[0-9]{8,9}$').hasMatch(digits)) return null;
  return '+82${digits.substring(1)}';
}

/// Formats stored domestic digits (01012345678) as 010-1234-5678.
String formatPhone(String digits) {
  if (digits.length < 10) return digits;
  final tail = digits.length - 4;
  return '${digits.substring(0, 3)}-${digits.substring(3, tail)}-${digits.substring(tail)}';
}
