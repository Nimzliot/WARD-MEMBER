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

class Campaign {
  Campaign.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        title = m['title'] as String,
        description = m['description'] as String? ?? '',
        goal = (m['goal'] as num).toInt(),
        raised = (m['raised'] as num?)?.toInt() ?? 0,
        backers = (m['backers'] as num?)?.toInt() ?? 0,
        myTotal = (m['my_total'] as num?)?.toInt() ?? 0,
        status = m['status'] as String? ?? 'active',
        closesAt = m['closes_at'] == null ? null : DateTime.parse(m['closes_at'] as String).toLocal(),
        recent = [for (final r in (m['recent'] as List? ?? const [])) Supporter.fromMap(r as Map<String, dynamic>)];

  final String id;
  final String title;
  final String description;
  final int goal; // INR
  final int raised; // INR, confirmed payments only
  final int backers;
  final int myTotal;
  final String status;
  final DateTime? closesAt;
  final List<Supporter> recent;

  bool get isOpen => status == 'active' && (closesAt == null || closesAt!.isAfter(DateTime.now()));
  double get progress => goal == 0 ? 0 : (raised / goal).clamp(0.0, 1.0);
}

class FundsState {
  FundsState.fromMap(Map<String, dynamic> m)
      : campaigns = [for (final c in (m['campaigns'] as List? ?? const [])) Campaign.fromMap(c as Map<String, dynamic>)],
        paymentsEnabled = m['payments_enabled'] as bool? ?? false,
        testMode = m['test_mode'] as bool? ?? true,
        canManage = m['can_manage'] as bool? ?? false;

  final List<Campaign> campaigns;
  final bool paymentsEnabled;
  final bool testMode;
  final bool canManage; // Ward Admin (or super admin)
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

/// Ward fundraising through the Node API (Razorpay test mode).
class FundsService {
  static Future<FundsState> load() async => FundsState.fromMap(await ApiService.get('/api/funds'));

  static Future<void> create({
    required String title,
    required String description,
    required int goal,
    DateTime? closesAt,
  }) =>
      ApiService.post('/api/funds', {
        'title': title,
        'description': description,
        'goal': goal,
        if (closesAt != null) 'closesAt': closesAt.toUtc().toIso8601String(),
      });

  static Future<void> setStatus(String id, String status) => ApiService.patch('/api/funds/$id', {'status': status});

  /// Starts a payment. Returns the contribution id and the Razorpay page to open.
  static Future<({String contributionId, String url, bool testMode})> contribute(
    String campaignId, {
    required int amount,
    required bool anonymous,
  }) async {
    final r = await ApiService.post('/api/funds/$campaignId/contribute', {'amount': amount, 'anonymous': anonymous});
    return (
      contributionId: r['contributionId'] as String,
      url: r['paymentUrl'] as String,
      testMode: r['testMode'] as bool? ?? true,
    );
  }

  /// Server re-checks with Razorpay while the payment is pending.
  static Future<Contribution> status(String contributionId) async => Contribution.fromMap(
      (await ApiService.get('/api/funds/contributions/$contributionId'))['contribution'] as Map<String, dynamic>);
}
