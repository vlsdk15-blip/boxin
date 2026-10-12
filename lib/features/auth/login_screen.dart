import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase.dart';

/// Phone number → SMS code. The router moves on once a session exists.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  String? _sentTo;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = '연결에 실패했습니다. 잠시 후 다시 시도해 주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final phone = toE164(_phoneController.text);
    if (phone == null) {
      setState(() => _error = '휴대폰 번호를 확인해 주세요. 예: 010-1234-5678');
      return;
    }
    await _run(() async {
      await supabase.auth.signInWithOtp(phone: phone);
      _sentTo = phone;
    });
  }

  Future<void> _verify() async {
    await _run(() => supabase.auth.verifyOTP(
          phone: _sentTo!,
          token: _codeController.text.trim(),
          type: OtpType.sms,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeSent = _sentTo != null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text('박스인', style: theme.textTheme.displaySmall),
                const SizedBox(height: 8),
                Text('휴대폰 번호로 로그인하세요.', style: theme.textTheme.bodyLarge),
                const SizedBox(height: 32),
                TextField(
                  controller: _phoneController,
                  enabled: !codeSent && !_busy,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(
                    labelText: '휴대폰 번호',
                    hintText: '010-1234-5678',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendCode(),
                ),
                if (codeSent) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codeController,
                    enabled: !_busy,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '인증번호 6자리',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _verify(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : (codeSent ? _verify : _sendCode),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(codeSent ? '로그인' : '인증번호 받기'),
                  ),
                ),
                if (codeSent)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _sentTo = null;
                              _error = null;
                              _codeController.clear();
                            }),
                    child: const Text('번호 다시 입력'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
