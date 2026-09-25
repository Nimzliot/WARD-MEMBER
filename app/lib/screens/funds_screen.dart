import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../services/funds_service.dart';
import '../theme.dart';
import '../utils/errors.dart';
import '../utils/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/failure_view.dart';
import '../widgets/fund_widgets.dart';

const _levelIcons = [
  Icons.eco_outlined,
  Icons.grass_rounded,
  Icons.spa_rounded,
  Icons.park_rounded,
  Icons.forest_rounded,
  Icons.emoji_events_rounded,
];

/// Ward Fund: one fund per ward. Any ward member can send money to it, any
/// time (Razorpay test mode). The ward grows through levels as money comes in.
class FundsScreen extends StatefulWidget {
  const FundsScreen({super.key});

  @override
  State<FundsScreen> createState() => _FundsScreenState();
}

class _FundsScreenState extends State<FundsScreen> {
  FundsState? _state;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await FundsService.load();
      if (mounted) {
        setState(() {
          _state = s;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _give() async {
    final s = _state;
    if (s == null) return;
    final paid = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: false,
      builder: (_) => ContributeSheet(fund: s),
    );
    if (paid == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    return Scaffold(
      bottomNavigationBar: s == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: PulseButton(
                  label: s.myTotal > 0 ? 'Give again' : 'Send to ward fund',
                  icon: Icons.volunteer_activism_rounded,
                  onPressed: s.paymentsEnabled ? _give : null,
                ),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            BrandHeader(
              showBack: true,
              title: 'Ward Fund',
              subtitle: s?.wardName,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const HeaderLabel('Raised by residents'),
                const SizedBox(height: 2),
                CountUpInr(
                  value: s?.raised ?? 0,
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _HeaderStat(icon: Icons.people_alt_rounded, value: '${s?.supporters ?? 0}'),
                  _HeaderStat(icon: Icons.favorite_rounded, value: '${s?.payments ?? 0}'),
                  if ((s?.myTotal ?? 0) > 0) _HeaderStat(icon: Icons.person_rounded, value: inrCompact(s!.myTotal), bright: true),
                  if (s?.testMode ?? true) const _HeaderStat(icon: Icons.science_outlined, value: 'TEST'),
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: _error != null
                  ? SizedBox(height: 480, child: ErrorView(error: _error, onRetry: _load))
                  : s == null
                      ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (!s.paymentsEnabled) ...[
                            const MessageBanner('Payments are not switched on yet.', isError: false),
                            const SizedBox(height: 16),
                          ],
                          _LevelCard(fund: s),
                          const SizedBox(height: 14),
                          _SupporterWall(fund: s),
                        ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.icon, required this.value, this.bright = false});

  final IconData icon;
  final String value;
  final bool bright;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bright ? AppColors.leaf : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: bright ? AppColors.forestDark : AppColors.leaf),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(
                  color: bright ? AppColors.forestDark : Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
      );
}

/// Ring to the next level + the level ladder (seed → trophy).
class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.fund});

  final FundsState fund;

  @override
  Widget build(BuildContext context) {
    final next = fund.nextLevel;
    final reached = fund.levelReached;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Row(children: [
            ProgressRing(
              value: fund.levelProgress,
              size: 128,
              stroke: 12,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(_levelIcons[(reached).clamp(0, _levelIcons.length - 1)], size: 34, color: AppColors.emerald),
                const SizedBox(height: 2),
                Text('${(fund.levelProgress * 100).round()}%',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.forestDark)),
              ]),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.military_tech_rounded, color: AppColors.emerald, size: 22),
                  const SizedBox(width: 6),
                  Text('Level $reached', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                ]),
                const SizedBox(height: 10),
                if (next != null) ...[
                  Row(children: [
                    const Icon(Icons.flag_rounded, size: 18, color: AppColors.inkMuted),
                    const SizedBox(width: 6),
                    Text(inrCompact(next),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.forestDark)),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.trending_up_rounded, size: 18, color: AppColors.emerald),
                    const SizedBox(width: 6),
                    Text(inrCompact(next - fund.raised),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.forest)),
                    const SizedBox(width: 4),
                    Icon(_levelIcons[(reached + 1).clamp(0, _levelIcons.length - 1)], size: 18, color: AppColors.emerald),
                  ]),
                ] else
                  const Icon(Icons.emoji_events_rounded, color: Color(0xFFD4A017), size: 34),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          _LevelLadder(levels: fund.levels, reached: reached),
        ]),
      ),
    );
  }
}

class _LevelLadder extends StatelessWidget {
  const _LevelLadder({required this.levels, required this.reached});

  final List<int> levels;
  final int reached;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < levels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: i <= reached - 1 ? AppColors.emerald : AppColors.mint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: Duration(milliseconds: 500 + i * 120),
              curve: Curves.easeOutBack,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < reached ? AppColors.emerald : Colors.white,
                  border: Border.all(color: i < reached ? AppColors.emerald : AppColors.mintLine, width: 2),
                  boxShadow: i < reached ? [BoxShadow(color: AppColors.emerald.withValues(alpha: 0.35), blurRadius: 8)] : null,
                ),
                child: Icon(_levelIcons[(i + 1).clamp(0, _levelIcons.length - 1)],
                    size: 18, color: i < reached ? Colors.white : AppColors.mintLine),
              ),
            ),
            const SizedBox(height: 4),
            Text(levels[i] < 100000 ? '₹${levels[i] ~/ 1000}K' : inrCompact(levels[i]).replaceAll('.0', ''),
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: i < reached ? AppColors.forest : AppColors.inkMuted)),
          ]),
        ],
      ]);
}

/// Faces of the people who gave, with their amounts.
class _SupporterWall extends StatelessWidget {
  const _SupporterWall({required this.fund});

  final FundsState fund;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SupporterStack(names: [for (final r in fund.recent) r.name], total: fund.supporters, size: 40),
              const Spacer(),
              Text('${fund.supporters}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.forest)),
              const SizedBox(width: 4),
              const Icon(Icons.favorite_rounded, color: AppColors.emerald),
            ]),
            if (fund.recent.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in fund.recent)
                  Container(
                    padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
                    decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: AppColors.mint,
                        child: r.name == 'Anonymous'
                            ? const Icon(Icons.favorite_rounded, size: 12, color: AppColors.emerald)
                            : Text(r.name[0].toUpperCase(),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.forest)),
                      ),
                      const SizedBox(width: 6),
                      Text(inrCompact(r.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ]),
                  ),
              ]),
            ] else ...[
              const SizedBox(height: 12),
              const Row(children: [
                Icon(Icons.volunteer_activism_rounded, color: AppColors.emerald),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.inkMuted),
                SizedBox(width: 8),
                Icon(Icons.eco_outlined, color: AppColors.emerald),
              ]),
            ],
          ]),
        ),
      );
}

/// Amount picker → Razorpay page in the browser → wait for confirmation.
class ContributeSheet extends StatefulWidget {
  const ContributeSheet({super.key, required this.fund});

  final FundsState fund;

  @override
  State<ContributeSheet> createState() => _ContributeSheetState();
}

enum _Stage { choose, waiting, paid, failed }

class _ContributeSheetState extends State<ContributeSheet> with WidgetsBindingObserver {
  static const _presets = [100, 250, 500, 1000];
  final _custom = TextEditingController();
  int _amount = 250;
  bool _anonymous = false;
  bool _starting = false;
  String? _error;
  _Stage _stage = _Stage.choose;
  String? _contributionId;
  String? _paymentUrl;
  Contribution? _result;
  Timer? _poll;
  int _checks = 0;
  Razorpay? _rzp; // native Checkout (Android)
  String? _orderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _rzp?.clear();
    _custom.dispose();
    super.dispose();
  }

  // Coming back from the browser → check straight away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _stage == _Stage.waiting) _check();
  }

  Future<void> _start() async {
    final custom = int.tryParse(_custom.text);
    final amount = custom ?? _amount;
    if (amount < 10 || amount > 100000) {
      setState(() => _error = 'Choose an amount between ₹10 and ₹1,00,000');
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        // APK: Razorpay's native Checkout opens inside the app (test mode).
        final o = await FundsService.checkout(amount: amount, anonymous: _anonymous);
        _contributionId = o['contributionId'] as String;
        _orderId = o['orderId'] as String;
        _rzp ??= Razorpay()
          ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onRazorpaySuccess)
          ..on(Razorpay.EVENT_PAYMENT_ERROR, _onRazorpayError)
          ..on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
        _rzp!.open({
          'key': o['keyId'],
          'amount': o['amount'],
          'currency': o['currency'],
          'order_id': o['orderId'],
          'name': o['name'],
          'description': o['description'],
          'prefill': o['prefill'],
          'theme': {'color': '#0B5D3B'},
          'retry': {'enabled': true, 'max_count': 2},
        });
        return;
      }
      // Web: Razorpay payment page in a new tab, then we poll for confirmation.
      final r = await FundsService.contribute(amount: amount, anonymous: _anonymous);
      _contributionId = r.contributionId;
      _paymentUrl = r.url;
      await _open();
      if (!mounted) return;
      setState(() => _stage = _Stage.waiting);
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
    } catch (e) {
      if (!mounted) return;
      if (await showFailure(context, e)) return;
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// Checkout says paid → the server verifies Razorpay's signature and confirms capture.
  Future<void> _onRazorpaySuccess(PaymentSuccessResponse r) async {
    if (!mounted) return;
    setState(() => _stage = _Stage.waiting);
    try {
      final c = await FundsService.verify(
        _contributionId!,
        orderId: r.orderId ?? _orderId!,
        paymentId: r.paymentId ?? '',
        signature: r.signature ?? '',
      );
      if (!mounted) return;
      if (c.isPaid) {
        HapticFeedback.mediumImpact();
        setState(() {
          _result = c;
          _stage = _Stage.paid;
        });
      } else {
        // Capture still settling on Razorpay's side: keep checking.
        _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.choose;
        _error = friendlyError(e);
      });
    }
  }

  void _onRazorpayError(PaymentFailureResponse r) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.choose;
      _error = r.code == Razorpay.PAYMENT_CANCELLED
          ? 'Payment cancelled. Nothing was charged.'
          : 'Payment failed: ${r.message ?? 'please try again'}. Nothing was charged.';
    });
  }

  Future<void> _open() async {
    final url = Uri.parse(_paymentUrl!);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank')) {
      throw Exception('Could not open the payment page');
    }
  }

  Future<void> _check() async {
    if (_contributionId == null || _stage != _Stage.waiting) return;
    _checks++;
    try {
      final c = await FundsService.status(_contributionId!);
      if (!mounted) return;
      if (c.isPaid) {
        _poll?.cancel();
        HapticFeedback.mediumImpact();
        setState(() {
          _result = c;
          _stage = _Stage.paid;
        });
      } else if (c.isOver || _checks > 150) {
        _poll?.cancel();
        setState(() => _stage = _Stage.failed);
      }
    } catch (_) {/* keep polling; network hiccup */}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          child: switch (_stage) {
            _Stage.choose => _choose(theme),
            _Stage.waiting => _waiting(theme),
            _Stage.paid => _paid(theme),
            _Stage.failed => _failed(theme),
          },
        ),
      ),
    );
  }

  Widget _choose(ThemeData theme) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Send to ward fund', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(widget.fund.wardName, style: const TextStyle(color: AppColors.inkMuted)),
        const SizedBox(height: 18),
        Row(children: [
          for (final (i, a) in _presets.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _AmountCard(
                amount: a,
                icon: const [Icons.grass_rounded, Icons.spa_rounded, Icons.park_rounded, Icons.forest_rounded][i],
                selected: _custom.text.isEmpty && _amount == a,
                onTap: () => setState(() {
                  _amount = a;
                  _custom.clear();
                }),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 14),
        _ImpactBar(fund: widget.fund, gift: int.tryParse(_custom.text) ?? _amount),
        const SizedBox(height: 12),
        TextField(
          controller: _custom,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          decoration: const InputDecoration(labelText: 'Other amount', prefixText: '₹ ', isDense: true),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _anonymous,
          onChanged: (v) => setState(() => _anonymous = v),
          secondary: const Icon(Icons.visibility_off_rounded, color: AppColors.forest),
          title: const Text('Give anonymously', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (widget.fund.testMode) ...[
          const MessageBanner(
            'Razorpay TEST MODE: use test UPI "success@razorpay" or card 4111 1111 1111 1111. No real money is charged.',
            isError: false,
          ),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[MessageBanner(_error!), const SizedBox(height: 12)],
        PrimaryButton(
          label: 'Pay ${inr(int.tryParse(_custom.text) ?? _amount)} with Razorpay',
          icon: Icons.lock_rounded,
          loading: _starting,
          onPressed: _start,
        ),
        const SizedBox(height: 8),
        Center(child: TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel'))),
      ]);

  Widget _waiting(ThemeData theme) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 4)),
        const SizedBox(height: 18),
        Text('Complete the payment in Razorpay',
            textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'We\'ll confirm it with Razorpay automatically when you come back.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 18),
        PrimaryButton(label: 'I\'ve paid: check now', icon: Icons.refresh_rounded, onPressed: _check),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _open, child: const Text('Open payment page again'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close'))),
        ]),
      ]);

  Widget _paid(ThemeData theme) => ConfettiBurst(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.elasticOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              gradient: AppTheme.aiGradient,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.emerald.withValues(alpha: 0.45), blurRadius: 24, spreadRadius: 2)],
            ),
            child: const Icon(Icons.favorite_rounded, size: 44, color: Colors.white),
          ),
        ),
        const SizedBox(height: 14),
        Text('Thank you!', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('${inr(_result!.amount)} to ${widget.fund.wardName}',
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkMuted)),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Razorpay payment ID', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            SelectableText(_result!.paymentId ?? '—', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
            if (_result!.paidAt != null) ...[
              const SizedBox(height: 6),
              Text(formatDateTime(_result!.paidAt!), style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.mark_email_read_outlined, size: 18, color: AppColors.forest),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _result!.receiptEmail != null
                  ? 'Receipt emailed to ${_result!.receiptEmail}'
                  : context.read<AuthProvider>().hasVerifiedEmail
                      ? 'A receipt is on its way to your verified email.'
                      : 'Verify your email in Profile to get receipts by email.',
              style: const TextStyle(color: AppColors.forestDark, fontSize: 13),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        PrimaryButton(label: 'Done', onPressed: () => Navigator.pop(context, true)),
      ]));

  Widget _failed(ThemeData theme) => Column(mainAxisSize: MainAxisSize.min, children: [
        const CircleAvatar(
          radius: 34,
          backgroundColor: Color(0xFFFDEEEC),
          child: Icon(Icons.close_rounded, size: 36, color: Color(0xFF9B1C1C)),
        ),
        const SizedBox(height: 14),
        Text('Payment not completed', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Nothing was charged. You can try again.', style: TextStyle(color: AppColors.inkMuted)),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Try again',
          onPressed: () => setState(() {
            _stage = _Stage.choose;
            _checks = 0;
          }),
        ),
      ]);
}

/// Tappable amount with a growth icon (seed → tree).
class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.amount, required this.icon, required this.selected, required this.onTap});

  final int amount;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: selected ? 1.06 : 1,
        duration: const Duration(milliseconds: 180),
        child: Material(
          color: selected ? AppColors.forest : Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: selected ? AppColors.forest : AppColors.mintLine, width: 1.5),
              ),
              child: Column(children: [
                Icon(icon, color: selected ? AppColors.leaf : AppColors.emerald, size: 26),
                const SizedBox(height: 4),
                Text(inrCompact(amount),
                    style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.forestDark)),
              ]),
            ),
          ),
        ),
      );
}

/// Where the fund is now (solid) and how far this gift pushes it (glowing).
class _ImpactBar extends StatelessWidget {
  const _ImpactBar({required this.fund, required this.gift});

  final FundsState fund;
  final int gift;

  @override
  Widget build(BuildContext context) {
    // progress towards the next level (or the top level once everything is reached)
    final goal = (fund.nextLevel ?? fund.levels.last).toDouble();
    final now = (fund.raised / goal).clamp(0.0, 1.0);
    final after = ((fund.raised + gift) / goal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        LayoutBuilder(builder: (_, box) {
          final w = box.maxWidth;
          return Stack(children: [
            Container(height: 12, decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(6))),
            TweenAnimationBuilder<double>(
              tween: Tween(end: after),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Container(
                width: w * v,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.leaf,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [BoxShadow(color: AppColors.leaf.withValues(alpha: 0.8), blurRadius: 8)],
                ),
              ),
            ),
            Container(
              width: w * now,
              height: 12,
              decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(6)),
            ),
          ]);
        }),
        const SizedBox(height: 8),
        Row(children: [
          Text('${(now * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.emerald),
          const SizedBox(width: 6),
          Text('${(after * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest, fontSize: 16)),
          const Spacer(),
          const Icon(Icons.flag_rounded, size: 16, color: AppColors.inkMuted),
          const SizedBox(width: 4),
          Text(inrCompact(goal), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
        ]),
      ]),
    );
  }
}
