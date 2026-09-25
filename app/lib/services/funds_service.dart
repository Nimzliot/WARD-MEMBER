import 'api_service.dart';

class Supporter {
  Supporter.fromMap(Map<String, dynamic> m)
      : name = m['name'] as String? ?? 'Resident',
        amount = (m['amount'] as num).toInt(),
        paidAt = m['paid_at'] == null ? null : DateTime.parse(m['paid_at'] as String).toLocal();

  final String name;
  final int amount;
  final DateTime? paidAt;
}

/// The ward's single fund: any ward member can send money to it, any time.
class FundsState {
  FundsState.fromMap(Map<String, dynamic> m)
      : wardName = m['ward_name'] as String? ?? 'Your ward',
        raised = (m['raised'] as num?)?.toInt() ?? 0,
        payments = (m['payments'] as num?)?.toInt() ?? 0,
        supporters = (m['supporters'] as num?)?.toInt() ?? 0,
        myTotal = (m['my_total'] as num?)?.toInt() ?? 0,
        levels = [for (final l in (m['levels'] as List? ?? const [10000, 50000, 100000, 500000])) (l as num).toInt()],
        recent = [for (final r in (m['recent'] as List? ?? const [])) Supporter.fromMap(r as Map<String, dynamic>)],
        paymentsEnabled = m['payments_enabled'] as bool? ?? false,
        testMode = m['test_mode'] as bool? ?? true;

  final String wardName;
  final int raised; // INR, confirmed payments only
  final int payments;
  final int supporters;
  final int myTotal;
  final List<int> levels; // ₹ milestones the ward grows through
  final List<Supporter> recent;
  final bool paymentsEnabled;
  final bool testMode;

  /// Levels reached so far (0..levels.length).
  int get levelReached => levels.where((l) => raised >= l).length;

  /// The next milestone, or null when every level is reached.
  int? get nextLevel => levelReached < levels.length ? levels[levelReached] : null;

  /// Progress from the previous milestone to the next (0..1).
  double get levelProgress {
    final next = nextLevel;
    if (next == null) return 1;
    final prev = levelReached == 0 ? 0 : levels[levelReached - 1];
    return ((raised - prev) / (next - prev)).clamp(0.0, 1.0);
  }
}

class Contribution {
  Contribution.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        amount = (m['amount'] as num).toInt(),
        status = m['status'] as String,
        paymentId = m['razorpay_payment_id'] as String?,
        receiptEmail = m['receipt_email'] as String?,
        paidAt = m['paid_at'] == null ? null : DateTime.parse(m['paid_at'] as String).toLocal();

  final String id;
  final int amount;
  final String status; // created | paid | failed | expired
  final String? paymentId;
  final String? receiptEmail; // set once the emailed receipt has gone out
  final DateTime? paidAt;

  bool get isPaid => status == 'paid';
  bool get isOver => status == 'failed' || status == 'expired';
}

/// Ward Fund through the Node API (Razorpay test mode).
class FundsService {
  static Future<FundsState> load() async => FundsState.fromMap(await ApiService.get('/api/funds'));

  /// APK: Razorpay order for the in-app Checkout (key id, amount in paise, prefill…).
  static Future<Map<String, dynamic>> checkout({required int amount, required bool anonymous}) =>
      ApiService.post('/api/funds/checkout', {'amount': amount, 'anonymous': anonymous});

  /// Web: Razorpay payment page to open in a new tab.
  static Future<({String contributionId, String url, bool testMode})> contribute({
    required int amount,
    required bool anonymous,
  }) async {
    final r = await ApiService.post('/api/funds/contribute', {'amount': amount, 'anonymous': anonymous});
    return (
      contributionId: r['contributionId'] as String,
      url: r['paymentUrl'] as String,
      testMode: r['testMode'] as bool? ?? true,
    );
  }

  /// APK: after Checkout success, the server verifies the signature and confirms capture.
  static Future<Contribution> verify(String contributionId,
          {required String orderId, required String paymentId, required String signature}) async =>
      Contribution.fromMap((await ApiService.post('/api/funds/contributions/$contributionId/verify',
          {'orderId': orderId, 'paymentId': paymentId, 'signature': signature}))['contribution'] as Map<String, dynamic>);

  /// Server re-checks with Razorpay while the payment is pending.
  static Future<Contribution> status(String contributionId) async => Contribution.fromMap(
      (await ApiService.get('/api/funds/contributions/$contributionId'))['contribution'] as Map<String, dynamic>);
}
