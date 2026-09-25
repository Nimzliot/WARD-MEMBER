import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../utils/errors.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  late LoginMethod _method;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _method = auth.method;
    _email.text = auth.pendingEmail ?? '';
    _phone.text = auth.pendingPhone ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();

    if (_method == LoginMethod.phone) {
      // The phone screen sends the SMS itself (so it can show the resend timer).
      auth.choosePhone(_phone.text);
      context.push('/phone-otp');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await auth.sendEmailOtp(_email.text);
      if (mounted) context.push('/email-otp');
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmail = _method == LoginMethod.email;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.how_to_vote_rounded, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Welcome, resident',
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in or register with a one-time code. Choose how you want to receive it.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<LoginMethod>(
                      segments: const [
                        ButtonSegment(
                          value: LoginMethod.email,
                          icon: Icon(Icons.email_outlined),
                          label: Text('Email'),
                        ),
                        ButtonSegment(
                          value: LoginMethod.phone,
                          icon: Icon(Icons.phone_android),
                          label: Text('Mobile'),
                        ),
                      ],
                      selected: {_method},
                      onSelectionChanged: (s) => setState(() {
                        _method = s.first;
                        _error = null;
                      }),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (isEmail)
                    TextFormField(
                      key: const ValueKey('email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')
                          ? null
                          : 'Enter a valid email address',
                    )
                  else
                    TextFormField(
                      key: const ValueKey('phone'),
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumberNational],
                      textInputAction: TextInputAction.done,
                      maxLength: 10,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Mobile number',
                        prefixIcon: Icon(Icons.phone_android),
                        prefixText: '+91 ',
                        counterText: '',
                      ),
                      validator: (v) => RegExp(r'^[6-9]\d{9}$').hasMatch(v ?? '')
                          ? null
                          : 'Enter a valid 10-digit Indian mobile number',
                    ),
                  const SizedBox(height: 20),
                  _StepsPreview(isEmail: isEmail),
                  const SizedBox(height: 20),
                  if (_error != null) ...[MessageBanner(_error!), const SizedBox(height: 16)],
                  PrimaryButton(
                    label: isEmail ? 'Send email code' : 'Send SMS code',
                    icon: Icons.arrow_forward,
                    loading: _loading,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepsPreview extends StatelessWidget {
  const _StepsPreview({required this.isEmail});

  final bool isEmail;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    Widget step(IconData icon, String text) => Expanded(
          child: Column(children: [
            Icon(icon, size: 20),
            const SizedBox(height: 4),
            Text(text, style: style, textAlign: TextAlign.center),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(children: [
          isEmail
              ? step(Icons.mark_email_read_outlined, '1. Email code')
              : step(Icons.sms_outlined, '1. SMS code'),
          const Icon(Icons.chevron_right, size: 16),
          step(Icons.badge_outlined, '2. Resident ID'),
          const Icon(Icons.chevron_right, size: 16),
          step(Icons.how_to_vote_outlined, '3. Vote'),
        ]),
      ),
    );
  }
}
