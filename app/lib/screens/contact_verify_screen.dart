import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/errors.dart';
import '../widgets/brand.dart';
import '../widgets/civic.dart';
import '../widgets/common.dart';
import '../widgets/failure_view.dart';
import '../widgets/otp_input.dart';

/// Onboarding step 3: every resident needs BOTH a verified email and a verified
/// mobile. They signed in with one; here they add and verify the other (their
/// choice of sign-in method stays open, and receipts go to the verified email).
class ContactVerifyScreen extends StatefulWidget {
  const ContactVerifyScreen({super.key, this.channel});

  /// 'email' or 'phone' when opened from Profile (optional verification);
  /// null = onboarding (verify whichever is missing).
  final String? channel;

  @override
  State<ContactVerifyScreen> createState() => _ContactVerifyScreenState();
}

class _ContactVerifyScreenState extends State<ContactVerifyScreen> {
  final _value = TextEditingController();
  final _code = TextEditingController();
  bool _sending = false;
  bool _verifying = false;
  bool _sent = false;
  String? _error;
  String? _info;

  AuthProvider get _auth => context.read<AuthProvider>();

  /// Which contact this screen verifies.
  bool get _needEmail => widget.channel != null ? widget.channel == 'email' : !_auth.hasVerifiedEmail;
  bool get _fromProfile => widget.channel != null;

  @override
  void dispose() {
    _value.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _channel => _needEmail ? 'email' : 'phone';
  String get _target => _needEmail ? _value.text.trim().toLowerCase() : _value.text.trim();

  String? _validate() {
    if (_needEmail) {
      return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(_target) ? null : 'Enter a valid email address';
    }
    return RegExp(r'^[6-9]\d{9}$').hasMatch(_target) ? null : 'Enter a valid 10-digit Indian mobile number';
  }

  Future<int?> _send() async {
    final invalid = _validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return null;
    }
    setState(() {
      _sending = true;
      _error = null;
      _info = null;
    });
    try {
      final r = await ApiService.post('/api/contact/$_channel/send', {_channel: _target});
      if (!mounted) return null;
      setState(() {
        _sent = true;
        _code.clear();
        _info = '${_needEmail ? 'We emailed a code to' : 'We sent an SMS code to'} $_target.'
            '${r['devMode'] == true ? '\nDEV_MODE: the code is printed in the server console.' : ''}';
      });
      return (r['resendIn'] as num?)?.toInt() ?? 60;
    } on ApiException catch (e) {
      if (!mounted) return null;
      final retry = (e.body['retryAfter'] as num?)?.toInt();
      if (retry == null && await showFailure(context, e)) return null;
      if (mounted) setState(() => _error = e.message);
      return retry;
    } catch (e) {
      if (mounted && !await showFailure(context, e) && mounted) setState(() => _error = friendlyError(e));
      return null;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    if (_code.text.length != 6 || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ApiService.post('/api/contact/$_channel/verify', {_channel: _target, 'otp': _code.text});
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      await _auth.contactVerified();
      if (_fromProfile && mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(
          content: Text(_needEmail ? 'Email verified. You can now sign in with it too.' : 'Mobile verified. You can now sign in with it too.'),
        ));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 0 && await showFailure(context, e)) return;
      setState(() => _error = e.message);
      _code.clear();
    } catch (e) {
      if (mounted && !await showFailure(context, e) && mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final needEmail = widget.channel != null ? widget.channel == 'email' : !auth.hasVerifiedEmail;
    final signedInWith = needEmail ? 'mobile number' : 'email';

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          if (_fromProfile)
            BrandHeader(
              showBack: true,
              title: needEmail ? 'Verify your email' : 'Verify your mobile',
              subtitle: 'Optional · lets you sign in either way',
              bottomPadding: 18,
            )
          else
          OnboardingHeader(
            step: 3,
            total: 3,
            showBack: false,
            icon: needEmail ? Icons.alternate_email_rounded : Icons.phone_android_rounded,
            title: needEmail ? 'Add your email' : 'Add your mobile number',
            subtitle: TextSpan(
              text: 'You signed in with your $signedInWith. Verify your ${needEmail ? 'email' : 'mobile'} too, '
                  'so you can sign in either way${needEmail ? ' and get payment receipts by email' : ''}.',
            ),
            actions: [
              TextButton(
                onPressed: auth.signOut,
                child: const Text('Sign out', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _value,
                enabled: !_sent,
                keyboardType: needEmail ? TextInputType.emailAddress : TextInputType.phone,
                autofillHints: [needEmail ? AutofillHints.email : AutofillHints.telephoneNumberNational],
                inputFormatters: needEmail
                    ? null
                    : [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                decoration: InputDecoration(
                  labelText: needEmail ? 'Email address' : 'Mobile number',
                  prefixIcon: Icon(needEmail ? Icons.email_outlined : Icons.phone_android),
                  prefixText: needEmail ? null : '+91 ',
                  suffixIcon: _sent
                      ? IconButton(
                          tooltip: 'Change',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => setState(() {
                            _sent = false;
                            _info = null;
                            _error = null;
                          }),
                        )
                      : null,
                ),
                onSubmitted: (_) => _sent ? null : _send(),
              ),
              const SizedBox(height: 16),
              if (!_sent)
                PrimaryButton(
                  label: needEmail ? 'Email me a code' : 'Send SMS code',
                  icon: Icons.arrow_forward,
                  loading: _sending,
                  onPressed: _send,
                )
              else ...[
                if (_info != null) ...[MessageBanner(_info!, isError: false), const SizedBox(height: 16)],
                OtpInput(controller: _code, onCompleted: (_) => _verify(), hasError: _error != null),
                const SizedBox(height: 16),
                PrimaryButton(label: 'Verify', icon: Icons.verified_rounded, loading: _verifying, onPressed: _verify),
                Center(child: ResendTimer(onResend: _send)),
              ],
              if (_error != null) ...[const SizedBox(height: 12), MessageBanner(_error!)],
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(14)),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.shield_outlined, color: AppColors.forest, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Codes expire in 5 minutes and allow 3 tries. We only store a scrambled (hashed) copy. '
                      'An email or number can belong to one account only.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.forestDark, height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              const PrototypeNotice(),
            ]),
          ),
        ]),
      ),
    );
  }
}
