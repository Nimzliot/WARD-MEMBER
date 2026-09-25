import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/errors.dart';
import '../utils/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/failure_view.dart';
import '../widgets/otp_input.dart';

/// Login with an SMS code (the "Mobile" option on the login screen).
class PhoneOtpScreen extends StatefulWidget {
  const PhoneOtpScreen({super.key});

  @override
  State<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends State<PhoneOtpScreen> {
  final _code = TextEditingController();
  bool _sent = false; // first SMS request finished (successfully or with a cooldown)
  int _resendIn = 60;
  bool _verifying = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final wait = await _send();
      if (mounted) setState(() => _resendIn = wait ?? 0);
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Sends the SMS. Returns seconds until the next resend is allowed, or null on failure.
  static const _pageCodes = {'OFFLINE', 'SERVER_DOWN', 'RATE_LIMITED', 'SMS_FAILED'};

  Future<int?> _send() async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      final res = await context.read<AuthProvider>().sendPhoneOtp();
      if (!mounted) return null;
      setState(() {
        _sent = true;
        _code.clear();
        _info =
            '${res['message'] ?? 'OTP sent'}'
            '${res['devMode'] == true ? '\nDEV_MODE: the code is printed in the server console.' : ''}';
      });
      return (res['resendIn'] as num?)?.toInt() ?? 60;
    } on ApiException catch (e) {
      final retryAfter = (e.body['retryAfter'] as num?)?.toInt();
      // Network / hourly limit / SMS gateway → full page; the 60 s resend wait stays inline.
      if (mounted && _pageCodes.contains(e.body['code'])) {
        setState(() => _sent = true);
        await showFailure(context, e, onRetry: _send);
        return null;
      }
      if (mounted) {
        setState(() {
          _sent = true;
          _error = e.message;
        });
      }
      return retryAfter;
    } catch (e) {
      if (mounted) setState(() => _sent = true);
      if (mounted && await showFailure(context, e, onRetry: _send)) return null;
      if (mounted) setState(() => _error = friendlyError(e));
      return null;
    }
  }

  Future<void> _verify() async {
    if (_code.text.length != 6 || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      // On success Supabase signs in and the router moves on automatically.
      await context.read<AuthProvider>().verifyPhoneOtp(_code.text);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_pageCodes.contains(e.body['code'])) {
        await showFailure(context, e, onRetry: _verify);
        return;
      }
      setState(() {
        _error = e.message;
        if (e.body['attemptsLeft'] == 0) _info = 'Tap "Resend code" to get a new one.';
      });
      _code.clear();
    } catch (e) {
      if (mounted && await showFailure(context, e, onRetry: _verify)) return;
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.read<AuthProvider>().pendingPhone;
    final theme = Theme.of(context);

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            OnboardingHeader(
              step: 1,
              total: 2,
              icon: Icons.sms_outlined,
              title: 'Check your SMS',
              subtitle: TextSpan(
                children: [
                  const TextSpan(text: 'Enter the 6-digit code sent to\n'),
                  TextSpan(
                    text: formatPhone(phone),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OtpInput(
                    controller: _code,
                    enabled: !_verifying,
                    hasError: _error != null,
                    onCompleted: (_) => _verify(),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: _sent
                        ? ResendTimer(key: ValueKey(_resendIn), initialSeconds: _resendIn, onResend: _send)
                        : const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null) ...[MessageBanner(_error!), const SizedBox(height: 12)],
                  if (_info != null) ...[MessageBanner(_info!, isError: false), const SizedBox(height: 12)],
                  ListenableBuilder(
                    listenable: _code,
                    builder: (context, _) => PrimaryButton(
                      label: 'Verify & sign in',
                      loading: _verifying,
                      onPressed: _code.text.length == 6 ? _verify : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The code expires in 5 minutes. You have 3 attempts per code.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
