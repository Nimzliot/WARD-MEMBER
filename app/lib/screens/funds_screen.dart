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

/// Ward Fund: fundraisers run by the Ward Admin; residents contribute through
/// Razorpay (test mode). Totals only count payments Razorpay has confirmed.
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

  Future<void> _newCampaign() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _NewCampaignSheet(),
    );
    if (created == true) _load();
  }

  Future<void> _contribute(Campaign c) async {
    final paid = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: false,
      builder: (_) => ContributeSheet(campaign: c, testMode: _state?.testMode ?? true),
    );
    if (paid == true) _load();
  }

  Future<void> _setStatus(Campaign c, String status) async {
    try {
      await FundsService.setStatus(c.id, status);
      _load();
    } catch (e) {
      if (mounted && !await showFailure(context, e) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final total = s?.campaigns.fold<int>(0, (a, c) => a + c.raised) ?? 0;
    return Scaffold(
      floatingActionButton: (s?.canManage ?? false)
          ? FloatingActionButton.extended(
              onPressed: _newCampaign,
              icon: const Icon(Icons.volunteer_activism_rounded),
              label: const Text('New fundraiser', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            BrandHeader(
              showBack: true,
              title: 'Ward Fund',
              subtitle: 'Chip in for projects your ward wants',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const HeaderLabel('Raised so far'),
                const SizedBox(height: 2),
                CountUpInr(
                  value: total,
                  style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
                const SizedBox(height: 10),
                if (s?.testMode ?? true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.science_outlined, size: 15, color: AppColors.leaf),
                      SizedBox(width: 6),
                      Text('Razorpay test mode · demo payments, no real money',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                    ]),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
              child: _error != null
                  ? SizedBox(height: 520, child: ErrorView(error: _error, onRetry: _load))
                  : s == null
                      ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (!s.paymentsEnabled) ...[
                            const MessageBanner(
                              'Payments are not switched on yet. The ward office needs to add Razorpay test keys on the server.',
                              isError: false,
                            ),
                            const SizedBox(height: 16),
                          ],
                          SectionTitle('Fundraisers', count: s.campaigns.length),
                          if (s.campaigns.isEmpty)
                            EmptyView(
                              icon: Icons.volunteer_activism_outlined,
                              message: s.canManage
                                  ? 'No fundraisers yet.\nTap "New fundraiser" to start one.'
                                  : 'No fundraisers yet.\nYour Ward Admin will start one when a project needs support.',
                            )
                          else
                            for (final c in s.campaigns) ...[
                              _CampaignCard(
                                campaign: c,
                                canPay: s.paymentsEnabled,
                                canManage: s.canManage,
                                onContribute: () => _contribute(c),
                                onStatus: (st) => _setStatus(c, st),
                              ),
                              const SizedBox(height: 14),
                            ],
                        ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.campaign,
    required this.canPay,
    required this.canManage,
    required this.onContribute,
    required this.onStatus,
  });

  final Campaign campaign;
  final bool canPay;
  final bool canManage;
  final VoidCallback onContribute;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    final c = campaign;
    final remaining = (c.goal - c.raised).clamp(0, c.goal);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Padding(
          // extra top room when the "you helped" ribbon is shown
          padding: EdgeInsets.fromLTRB(16, c.myTotal > 0 ? 34 : 16, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Title row
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(c.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.25)),
              ),
              if (c.isOpen && c.closesAt != null) ...[const SizedBox(width: 8), DaysLeftRing(closesAt: c.closesAt!)],
              if (!c.isOpen)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.canvas, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.lock_rounded, size: 16, color: AppColors.inkMuted),
                ),
              if (canManage)
                PopupMenuButton<String>(
                  onSelected: onStatus,
                  itemBuilder: (_) => [
                    if (c.status == 'active') const PopupMenuItem(value: 'closed', child: Text('Close fundraiser')),
                    if (c.status != 'active') const PopupMenuItem(value: 'active', child: Text('Reopen fundraiser')),
                  ],
                ),
            ]),
            const SizedBox(height: 14),
            // Ring + numbers
            Row(children: [
              ProgressRing(value: c.progress),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CountUpInr(
                    value: c.raised,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.forestDark),
                  ),
                  Row(children: [
                    const Icon(Icons.flag_rounded, size: 15, color: AppColors.inkMuted),
                    const SizedBox(width: 4),
                    Text(inr(c.goal), style: const TextStyle(color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    SupporterStack(names: [for (final r in c.recent) r.name], total: c.backers),
                    const SizedBox(width: 8),
                    Text('${c.backers}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest, fontSize: 16)),
                    const SizedBox(width: 2),
                    const Icon(Icons.favorite_rounded, size: 15, color: AppColors.emerald),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            MilestoneTrack(value: c.progress),
            if (remaining > 0 && c.isOpen) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.trending_up_rounded, size: 18, color: AppColors.emerald),
                const SizedBox(width: 6),
                Text(inrCompact(remaining),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.inkMuted),
                const SizedBox(width: 4),
                const Icon(Icons.forest_rounded, size: 18, color: AppColors.emerald),
              ]),
            ],
            if (c.isOpen) ...[
              const SizedBox(height: 14),
              PulseButton(
                label: c.myTotal > 0 ? 'Give again' : 'Contribute',
                icon: Icons.volunteer_activism_rounded,
                onPressed: canPay ? onContribute : null,
              ),
            ],
          ]),
        ),
        // "You helped" ribbon
        if (c.myTotal > 0)
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
              decoration: const BoxDecoration(
                gradient: AppTheme.aiGradient,
                borderRadius: BorderRadius.only(bottomRight: Radius.circular(14)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.favorite_rounded, size: 13, color: Colors.white),
                const SizedBox(width: 4),
                Text(inrCompact(c.myTotal),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Amount picker → Razorpay page in the browser → wait for confirmation.
class ContributeSheet extends StatefulWidget {
  const ContributeSheet({super.key, required this.campaign, required this.testMode});

  final Campaign campaign;
  final bool testMode;

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
        final o = await FundsService.checkout(widget.campaign.id, amount: amount, anonymous: _anonymous);
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
      final r = await FundsService.contribute(widget.campaign.id, amount: amount, anonymous: _anonymous);
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
        Text('Contribute', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(widget.campaign.title, style: const TextStyle(color: AppColors.inkMuted)),
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
        _ImpactBar(campaign: widget.campaign, gift: int.tryParse(_custom.text) ?? _amount),
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
        if (widget.testMode) ...[
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
        Text('${inr(_result!.amount)} to ${widget.campaign.title}',
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

class _NewCampaignSheet extends StatefulWidget {
  const _NewCampaignSheet();

  @override
  State<_NewCampaignSheet> createState() => _NewCampaignSheetState();
}

class _NewCampaignSheetState extends State<_NewCampaignSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _goal = TextEditingController();
  DateTime? _closes = DateTime.now().add(const Duration(days: 30));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final goal = int.tryParse(_goal.text);
    if (_title.text.trim().length < 3) return setState(() => _error = 'Give the fundraiser a title');
    if (goal == null || goal < 100) return setState(() => _error = 'Goal must be at least ₹100');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FundsService.create(title: _title.text.trim(), description: _description.text.trim(), goal: goal, closesAt: _closes);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('New fundraiser', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Benches for Gandhi Maidan'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'What the money is for', alignLabelWithHint: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _goal,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
              decoration: const InputDecoration(labelText: 'Goal', prefixText: '₹ '),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded, color: AppColors.forest),
              title: Text(_closes == null ? 'No end date' : 'Ends ${formatDateTime(_closes!)}'),
              trailing: TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _closes ?? DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => _closes = DateTime(d.year, d.month, d.day, 23, 59));
                },
                child: const Text('Change'),
              ),
            ),
            if (_error != null) ...[MessageBanner(_error!), const SizedBox(height: 12)],
            PrimaryButton(label: 'Start fundraiser', icon: Icons.volunteer_activism_rounded, loading: _saving, onPressed: _save),
          ]),
        ),
      );
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
  const _ImpactBar({required this.campaign, required this.gift});

  final Campaign campaign;
  final int gift;

  @override
  Widget build(BuildContext context) {
    final goal = campaign.goal.toDouble();
    final now = (campaign.raised / goal).clamp(0.0, 1.0);
    final after = ((campaign.raised + gift) / goal).clamp(0.0, 1.0);
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
          const Icon(Icons.favorite_rounded, size: 16, color: AppColors.emerald),
        ]),
      ]),
    );
  }
}
