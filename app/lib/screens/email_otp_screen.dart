import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../utils/errors.dart';
import '../widgets/common.dart';
import '../widgets/otp_input.dart';

class EmailOtpScreen extends StatefulWidget {
  const EmailOtpScreen({super.key});

  @override
  State<EmailOtpScreen> createState() => _EmailOtpScreenState();
}

class _EmailOtpScreenState extends State<EmailOtpScreen> {
  final _code = TextEditingController();
  bool _verifying = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.text.length != 6 || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      // On success the router moves to the phone step automatically.
      await context.read<AuthProvider>().verifyEmailOtp(_code.text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
      _code.clear();
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<int?> _resend() async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      await context.read<AuthProvider>().resendEmailOtp();
      if (mounted) setState(() => _info = 'A new code has been sent.');
      return 60;
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = context.read<AuthProvider>().pendingEmail ?? '';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StepHeader(step: 1, total: 2, title: 'Verify your email'),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Enter the 6-digit code we sent to '),
                  TextSpan(text: email, style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              OtpInput(
                controller: _code,
                enabled: !_verifying,
                hasError: _error != null,
                onCompleted: (_) => _verify(),
              ),
              const SizedBox(height: 8),
              Center(child: ResendTimer(onResend: _resend)),
              const SizedBox(height: 8),
              if (_error != null) ...[MessageBanner(_error!), const SizedBox(height: 16)],
              if (_info != null && _error == null) ...[
                MessageBanner(_info!, isError: false),
                const SizedBox(height: 16),
              ],
              ListenableBuilder(
                listenable: _code,
                builder: (context, _) => PrimaryButton(
                  label: 'Verify email',
                  loading: _verifying,
                  onPressed: _code.text.length == 6 ? _verify : null,
                ),
              ),
              const SizedBox(height: 16),
              Text("Can't find it? Check your spam folder.",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
