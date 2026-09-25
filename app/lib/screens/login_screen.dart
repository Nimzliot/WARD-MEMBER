import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../utils/errors.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/civic.dart';
import '../widgets/common.dart';
import '../widgets/failure_view.dart';

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
      if (!mounted) return;
      if (await showFailure(context, e, onRetry: _submit)) return;
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmail = _method == LoginMethod.email;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const _LoginHeader(),
            // White form card overlapping the green header
            Transform.translate(
              offset: const Offset(0, -36),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sign in or register',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'We send you a one-time code. No passwords.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
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
                              validator: (v) =>
                                  RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')
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
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: PrototypeNotice(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ShaderMask(
              shaderCallback: (r) =>
                  const LinearGradient(colors: [Colors.transparent, Colors.white], stops: [0.2, 1]).createShader(r),
              blendMode: BlendMode.dstIn,
              child: CustomPaint(painter: KolamPatternPainter()),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.paddingOf(context).top,
            child: const TricolourStrip(),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 64),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: const Center(child: AppLogo(size: 38)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text(kAppName,
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                        const SizedBox(height: 3),
                        Row(children: [
                          const KolamMark(size: 14, color: AppColors.leaf),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(kAuthorityLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1)),
                          ),
                        ]),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 22),
                  Text(
                    'Welcome, resident',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Decide how your ward\'s budget is spent.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
          ),
        ],
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
      child: Column(
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 4),
          Text(text, style: style, textAlign: TextAlign.center),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            isEmail
                ? step(Icons.mark_email_read_outlined, '1. Email code')
                : step(Icons.sms_outlined, '1. SMS code'),
            const Icon(Icons.chevron_right, size: 16),
            step(Icons.badge_outlined, '2. Resident ID'),
            const Icon(Icons.chevron_right, size: 16),
            step(Icons.how_to_vote_outlined, '3. Vote'),
          ],
        ),
      ),
    );
  }
}
