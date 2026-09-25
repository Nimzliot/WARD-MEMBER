// ignore_for_file: invalid_use_of_visible_for_testing_member
// Renders every main screen to PNG with sample data, for design review.
//
//   cd app && flutter test tool/screenshots_test.dart --update-goldens
//   → images in tool/shots/
//
// No backend needed: Supabase REST and the Node API are answered by MockClients,
// and Live Results uses a fake controller (no Realtime socket).
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ward_budget/models/profile.dart';
import 'package:ward_budget/models/proposal.dart';
import 'package:ward_budget/models/vote.dart';
import 'package:ward_budget/models/ward.dart';
import 'package:ward_budget/providers/auth_provider.dart';
import 'package:ward_budget/providers/live_results.dart';
import 'package:ward_budget/providers/ward_provider.dart';
import 'package:ward_budget/screens/admin_screen.dart';
import 'package:ward_budget/screens/chat_screen.dart';
import 'package:ward_budget/screens/contact_verify_screen.dart';
import 'package:ward_budget/screens/chat_summary_screen.dart';
import 'package:ward_budget/screens/funds_screen.dart';
import 'package:ward_budget/screens/inbox_screen.dart';
import 'package:ward_budget/screens/ward_admin_screen.dart';
import 'package:ward_budget/services/chat_crypto.dart';
import 'package:ward_budget/services/chat_service.dart';
import 'package:ward_budget/screens/app_shell.dart';
import 'package:ward_budget/screens/assistant_screen.dart';
import 'package:ward_budget/screens/audit_screen.dart';
import 'package:ward_budget/screens/email_otp_screen.dart';
import 'package:ward_budget/screens/home_screen.dart';
import 'package:ward_budget/screens/ideas_screen.dart';
import 'package:ward_budget/screens/login_screen.dart';
import 'package:ward_budget/screens/map_screen.dart';
import 'package:ward_budget/screens/admin_map_screen.dart';
import 'package:ward_budget/widgets/map_widgets.dart';
import 'package:ward_budget/screens/phone_otp_screen.dart';
import 'package:ward_budget/screens/profile_screen.dart';
import 'package:ward_budget/screens/profile_setup_screen.dart';
import 'package:ward_budget/screens/proposal_form_screen.dart';
import 'package:ward_budget/screens/proposal_detail_screen.dart';
import 'package:ward_budget/screens/results_screen.dart';
import 'package:ward_budget/screens/splash_screen.dart';
import 'package:ward_budget/services/api_service.dart';
import 'package:ward_budget/theme.dart';
import 'package:ward_budget/widgets/vote_receipt_sheet.dart';
import 'package:ward_budget/screens/error_gallery_screen.dart';
import 'package:ward_budget/utils/failure.dart';
import 'package:ward_budget/widgets/failure_view.dart';

// ------------------------------------------------------------------ sample data

final ward = Ward(
  id: 1, name: 'Ward 1 – Gandhi Nagar', budgetPool: 7500000,
  votingOpensAt: DateTime.now().subtract(const Duration(days: 4)),
  votingClosesAt: DateTime.now().add(const Duration(days: 3, hours: 4, minutes: 12)),
);

BudgetItem _i(String l, int a) => BudgetItem(id: l, label: l, amount: a);

final proposals = [
  Proposal(
    id: 'p1', wardId: 1, lat: 13.0089, lng: 80.2552, locationName: 'MG Road, Gandhi Nagar', title: 'Resurface MG Road & Lanes 4–7', category: 'Roads & Transport',
    description: 'Potholed 1.4 km stretch used by 3 schools and the weekly market. Includes side drains to stop monsoon waterlogging.',
    totalCost: 3255000, createdAt: DateTime(2026, 9, 1),
    items: [_i('Bituminous resurfacing (1.4 km)', 1960000), _i('Storm-water side drains', 840000),
      _i('Road markings & signage', 180000), _i('Contingency (5%)', 155000), _i('Speed tables near school zones', 120000)],
  ),
  Proposal(
    id: 'p2', wardId: 1, lat: 13.0041, lng: 80.2601, locationName: 'Lanes 9–14', title: 'Solar LED Street Lights', category: 'Street Lighting',
    description: '120 solar LED lights on dark lanes flagged by residents as unsafe after 8 pm. Zero electricity bill.',
    totalCost: 2850000, createdAt: DateTime(2026, 9, 1),
    items: [_i('120 × 40W solar LED fixtures', 1740000), _i('Poles & foundations', 600000),
      _i('3-year maintenance contract', 270000), _i('Installation & wiring', 240000)],
  ),
  Proposal(
    id: 'p3', wardId: 1, lat: 13.0072, lng: 80.2598, locationName: 'Gandhi Maidan', title: 'Gandhi Maidan Park Revamp', category: 'Parks & Environment',
    description: 'Walking track, open-air gym and a safe play area for children, plus 300 native trees.',
    totalCost: 2500000, createdAt: DateTime(2026, 9, 1),
    items: [_i('Walking track (600 m)', 900000), _i("Children's play equipment", 650000),
      _i('Open-air gym', 450000), _i('Benches & lighting', 350000), _i('Native trees', 150000)],
  ),
  Proposal(
    id: 'p4', wardId: 1, lat: 13.0053, lng: 80.2533, locationName: 'Ward health sub-centre', title: 'Ward Health Sub-centre Upgrade', category: 'Health',
    description: 'Renovate the sub-centre and add basic diagnostics so residents avoid the 6 km trip to the district hospital.',
    totalCost: 2200000, createdAt: DateTime(2026, 9, 1),
    items: [_i('Building renovation', 800000), _i('Diagnostic equipment', 700000),
      _i('Medicines & supplies (1 year)', 400000), _i('Solar power backup', 300000)],
  ),
];

final myIdeas = [
  Proposal(
    id: 'i1', wardId: 1, lat: 13.0101, lng: 80.2585, locationName: 'Station Road', title: 'Bus shelters on Station Road', category: 'Roads & Transport',
    description: 'Four shelters with benches for the morning school rush.', totalCost: 540000,
    createdAt: DateTime.now().subtract(const Duration(hours: 5)), status: ProposalStatus.pending, fromResident: true,
    items: [_i('4 steel shelters with benches', 480000), _i('Installation', 60000)],
  ),
  Proposal(
    id: 'i2', wardId: 1, title: 'Drinking water ATM near the market', category: 'Water & Sanitation',
    description: 'RO water ATM for vendors and shoppers.', totalCost: 350000,
    createdAt: DateTime.now().subtract(const Duration(days: 3)), status: ProposalStatus.approved, fromResident: true,
    reviewNote: 'Approved. Thanks! It is on the ballot now.',
    items: [_i('RO water ATM', 300000), _i('Plumbing & power', 50000)],
  ),
  Proposal(
    id: 'i3', wardId: 1, title: 'Flyover at MG Road junction', category: 'Roads & Transport',
    description: 'A flyover to remove the traffic signal.', totalCost: 90000000,
    createdAt: DateTime.now().subtract(const Duration(days: 6)), status: ProposalStatus.rejected, fromResident: true,
    reviewNote: 'Costs more than the whole ward pool. Please raise it with the state PWD.',
    items: [_i('Flyover', 90000000)],
  ),
];

Map<String, dynamic> proposalJson(Proposal p) => {
  'id': p.id, 'ward_id': p.wardId, 'title': p.title, 'description': p.description, 'category': p.category,
  'total_cost': p.totalCost, 'created_at': p.createdAt.toUtc().toIso8601String(), 'status': p.status.name,
  'origin': p.fromResident ? 'resident' : 'official', 'review_note': p.reviewNote,
  'lat': p.lat, 'lng': p.lng, 'location_name': p.locationName,
  'budget_items': [for (final i in p.items) {'id': i.id, 'label': i.label, 'amount': i.amount}],
};

const profileJson = {
  'id': 'u1', 'full_name': 'Padma Raman', 'email': 'padma@example.com', 'phone': '9876543210',
  'phone_verified': true, 'ward_id': 1, 'resident_id': 'RES-1-1004', 'role': 'admin',
  'wards': {'name': 'Ward 1 – Gandhi Nagar'},
};

String h(String seed) => (seed * 64).substring(0, 64);

final auditJson = {
  'ward_id': 1, 'ward_name': 'Ward 1 – Gandhi Nagar', 'valid': true, 'broken_at': null,
  'head_hash': h('9f3c2a'), 'verified_at': DateTime.now().toUtc().toIso8601String(),
  'chain': [
    for (final (i, t) in ['Resurface MG Road & Lanes 4–7', 'Solar LED Street Lights', 'Resurface MG Road & Lanes 4–7'].indexed)
      {
        'index': i + 1, 'id': 'v$i', 'proposal_ids': ['p1'], 'proposal_titles': i == 1 ? [t, 'Gandhi Maidan Park Revamp'] : [t],
        'voter_hash': h('a${i}c7'), 'prev_hash': i == 0 ? '0' * 64 : h('b${i - 1}e4'), 'hash': h('b${i}e4'),
        'created_at': DateTime(2026, 9, 25, 10, 5 + i * 7).toUtc().toIso8601String(),
        'hash_ok': true, 'link_ok': true,
      },
  ],
};

// ------------------------------------------------------------------ chat fixture

late String adminPubKey;
List<Map<String, dynamic>> chatRows = [];

Future<void> buildChatFixture() async {
  final resident = await X25519().newKeyPair();
  final admin = await X25519().newKeyPair();
  final rPriv = await resident.extractPrivateKeyBytes();
  final rPub = base64Encode((await resident.extractPublicKey()).bytes);
  adminPubKey = base64Encode((await admin.extractPublicKey()).bytes);
  FlutterSecureStorage.setMockInitialValues({'chat_x25519_u1': '${base64Encode(rPriv)}.$rPub'});

  final script = [
    (true, 'Vanakkam! The streetlight near 4th Lane bus stop has been off for a week. It is very dark after 7 pm.'),
    (false, 'Thanks for flagging this, Padma. I have logged it with TANGEDCO. Is it the pole opposite the temple?'),
    (true, 'Yes, the one opposite the temple. Children walk home from tuition there.'),
    (false, 'Understood. The crew is scheduled for Thursday. I will update you here once it is fixed.'),
  ];
  chatRows = [];
  for (final (i, (fromResident, text)) in script.indexed) {
    await ChatCrypto.useKeyPairForTesting(fromResident ? resident : admin);
    final e = await ChatCrypto.encrypt(text, theirPublicKey: fromResident ? adminPubKey : rPub, threadId: 't1');
    chatRows.add({
      'id': 'm$i', 'sender_id': fromResident ? 'u1' : 'a1', 'ciphertext': e.ciphertext, 'nonce': e.nonce,
      'sender_key': e.senderKey, 'recipient_key': e.recipientKey,
      'created_at': DateTime.now().subtract(Duration(minutes: 90 - i * 20)).toUtc().toIso8601String(),
      'read_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
  ChatCrypto.reset(); // the screen loads the resident key from (mock) secure storage
}

const fundsJson = {
  'ward_name': 'Ward 1 – Gandhi Nagar', 'payments_enabled': true, 'test_mode': true,
  'raised': 72400, 'payments': 64, 'supporters': 58, 'my_total': 500,
  'levels': [10000, 50000, 100000, 500000, 1000000, 5000000],
  'recent': [
    {'name': 'Padma Raman', 'amount': 500, 'paid_at': '2026-09-26T04:00:00Z'},
    {'name': 'Anonymous', 'amount': 2000, 'paid_at': '2026-09-26T03:00:00Z'},
    {'name': 'Karthik V.', 'amount': 250, 'paid_at': '2026-09-25T13:00:00Z'},
    {'name': 'Meena S.', 'amount': 1000, 'paid_at': '2026-09-25T12:00:00Z'},
    {'name': 'Arun K.', 'amount': 100, 'paid_at': '2026-09-25T11:00:00Z'},
  ],
};

final contributionsJson = {
  'wards': [
    {'ward_id': 1, 'raised': 72400, 'payments': 64, 'supporters': 58},
    {'ward_id': 2, 'raised': 18500, 'payments': 21, 'supporters': 19},
    {'ward_id': 3, 'raised': 41200, 'payments': 37, 'supporters': 30},
  ],
  'contributions': [
    for (final (i, (name, amt, st, anon)) in [
      ('Padma Raman', 500, 'paid', false),
      ('Karthik Venkat', 2000, 'paid', true),
      ('Meena Sundar', 250, 'created', false),
      ('Arun Kumar', 1000, 'paid', false),
    ].indexed)
      {
        'id': 'k', 'ward_id': 1, 'name': name, 'amount': amt, 'status': st, 'anonymous': anon,
        'razorpay_payment_id': st == 'paid' ? 'pay_Q8x2aTEST' : null,
        'created_at': DateTime(2026, 9, 26, 9 - i).toUtc().toIso8601String(),
        'paid_at': st == 'paid' ? DateTime(2026, 9, 26, 9 - i, 2).toUtc().toIso8601String() : null,
      },
  ],
};

final overviewJson = {
  'totals': {'wards': 3, 'residents': 231, 'ballots': 118, 'pending_ideas': 4, 'raised': 132100, 'budget': 18500000, 'ward_admins': 2},
  'wards': [
    {'id': 1, 'name': 'Ward 1 – Gandhi Nagar', 'phase': 'open', 'budget_pool': 7500000, 'ward_admin': 'Kavitha Selvam', 'residents': 96, 'ballots': 58, 'turnout': 0.6, 'approved': 4, 'pending_ideas': 1, 'raised': 72400, 'supporters': 58},
    {'id': 2, 'name': 'Ward 2 – Lake View', 'phase': 'upcoming', 'budget_pool': 6000000, 'ward_admin': null, 'residents': 71, 'ballots': 0, 'turnout': 0.0, 'approved': 4, 'pending_ideas': 3, 'raised': 18500, 'supporters': 19},
    {'id': 3, 'name': 'Ward 3 – Old Market', 'phase': 'closed', 'budget_pool': 5000000, 'ward_admin': 'Ravi Kumar', 'residents': 64, 'ballots': 60, 'turnout': 0.94, 'approved': 3, 'pending_ideas': 0, 'raised': 41200, 'supporters': 30},
  ],
};

const chatSummaryJson = {
  'headline': 'Streetlights and drainage lead resident concerns',
  'overview': 'Residents mainly reported a dark stretch near the 4th Lane bus stop and water stagnation near the market. '
      'Most messages are constructive and ask for timelines.',
  'key_issues': [
    {'issue': 'Streetlight out near 4th Lane bus stop', 'residents': 3},
    {'issue': 'Water stagnation after rain near the market', 'residents': 2},
  ],
  'requests': ['Share a repair date for the streetlight', 'Clear the drain before the monsoon'],
  'urgent': ['Dark stretch on a route children use after tuition'],
  'sentiment': 'mixed',
  'sentiment_note': 'Concerned but appreciative of quick replies',
  'follow_ups': ['Confirm the Thursday TANGEDCO visit', 'Ask the sanitation team to inspect the market drain'],
  'ward_name': 'Ward 1 – Gandhi Nagar', 'conversations': 3, 'generated_at': '2026-09-26T05:30:00Z',
};

// ------------------------------------------------------------------ fakes

class FakeAuth extends AuthProvider {
  FakeAuth(this._stage, {String? email, String? phone}) {
    profile = Profile.fromMap(profileJson);
    pendingEmail = email;
    pendingPhone = phone;
  }

  final AuthStage _stage;
  final _user = User(
    id: 'u1', appMetadata: const {}, userMetadata: const {}, aud: 'authenticated',
    createdAt: '2026-09-25T00:00:00Z', email: 'padma@example.com', emailConfirmedAt: '2026-09-25T00:00:00Z',
  );

  @override
  AuthStage get stage => _stage;
  @override
  User? get user => _stage == AuthStage.signedOut ? null : _user;
  @override
  Session? get session =>
      _stage == AuthStage.signedOut ? null : Session(accessToken: 'x', tokenType: 'bearer', user: _user);
}

class FakeResults extends LiveResults {
  FakeResults() : super(wardId: 1) {
    counts = {'p1': 14, 'p2': 9, 'p3': 11, 'p4': 6};
    totalVotes = 40;
    eligible = 96;
    lastVoteAt = DateTime.now().subtract(const Duration(minutes: 3));
    loading = false;
    live = true;
  }

  @override
  Future<void> start() async {}
  @override
  Future<void> refresh() async {}
}

WardProvider fakeWard({List<String>? myBallot = const ['p1', 'p3'], Set<String> picks = const {}}) => WardProvider()
  ..wardId = 1
  ..ward = ward
  ..proposals = proposals
  ..myIdeas = myIdeas
  ..myBallot = myBallot
  ..picks.addAll(picks);

final apiMock = MockClient((req) async {
  final p = req.url.path;
  Object body = {};
  if (p.startsWith('/api/audit/')) body = auditJson;
  if (p == '/api/votes/me') body = {'vote': null};
  if (p == '/api/funds') body = fundsJson;
  if (p == '/api/admin/overview') body = overviewJson;
  if (p == '/api/ward-admin/overview') {
    body = {
      'ward': {'id': 1, 'name': 'Ward 1 – Gandhi Nagar', 'budget_pool': 7500000,
        'voting_opens_at': DateTime.now().subtract(const Duration(days: 4)).toUtc().toIso8601String(),
        'voting_closes_at': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(), 'admin_user_id': 'u1'},
      'approved': 4, 'pending_ideas': 1, 'ballots': 40, 'residents': 96, 'active_funds': 2, 'raised': 108900, 'unread_messages': 3,
    };
  }
  if (p == '/api/ward-admin/proposals') body = {'proposals': [for (final x in [...myIdeas, ...proposals]) proposalJson(x)]};
  if (p == '/api/ward-admin/contributions' || p == '/api/admin/funds') body = contributionsJson;
  if (p == '/api/chat/peer') {
    body = {
      'is_ward_admin': false, 'ward_name': 'Ward 1 – Gandhi Nagar',
      'admin': {'id': 'a1', 'name': 'Kavitha Selvam', 'public_key': adminPubKey},
      'thread': {'id': 't1', 'ward_id': 1, 'resident_id': 'u1', 'unread_admin': 0, 'unread_resident': 0},
    };
  }
  if (p == '/api/chat/threads') {
    body = {
      'threads': [
        {'id': 't1', 'ward_id': 1, 'resident_id': 'r1', 'resident_name': 'Padma Raman', 'resident_ref': 'RES-1-1004',
          'resident_key': adminPubKey, 'last_message_at': DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String(), 'unread_admin': 2},
        {'id': 't2', 'ward_id': 1, 'resident_id': 'r2', 'resident_name': 'Karthik Venkat', 'resident_ref': 'RES-1-1022',
          'resident_key': adminPubKey, 'last_message_at': DateTime.now().subtract(const Duration(hours: 3)).toUtc().toIso8601String(), 'unread_admin': 0},
        {'id': 't3', 'ward_id': 1, 'resident_id': 'r3', 'resident_name': 'Meena Sundar', 'resident_ref': 'RES-1-1031',
          'resident_key': adminPubKey, 'last_message_at': DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String(), 'unread_admin': 1},
      ],
    };
  }
  if (p == '/api/ai/chat-summary') body = chatSummaryJson;
  if (p == '/api/admin/wards') {
    final open = DateTime.now().subtract(const Duration(days: 4)).toUtc().toIso8601String();
    body = {
      'wards': [
        {'id': 1, 'name': 'Ward 1 – Gandhi Nagar', 'budget_pool': 7500000, 'voting_opens_at': open,
          'voting_closes_at': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(), 'approved': 4, 'pending': 1, 'ballots': 40},
        {'id': 2, 'name': 'Ward 2 – Lake View', 'budget_pool': 6000000,
          'voting_opens_at': DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String(),
          'voting_closes_at': DateTime.now().add(const Duration(days: 16)).toUtc().toIso8601String(), 'approved': 4, 'pending': 0, 'ballots': 0},
        {'id': 3, 'name': 'Ward 3 – Old Market', 'budget_pool': 5000000, 'voting_opens_at': open,
          'voting_closes_at': DateTime.now().subtract(const Duration(hours: 6)).toUtc().toIso8601String(), 'approved': 3, 'pending': 0, 'ballots': 27},
      ],
    };
  }
  if (p == '/api/ai/insight') {
    body = {
      'headline': 'MG Road leads, Park close behind',
      'summary': 'Road resurfacing has the most votes so far. With the park, it would use ₹57.6 lakh of the ₹75 lakh pool, leaving room for no other full proposal yet.',
      'highlights': ['40 of 96 verified residents have voted (42%).', 'MG Road has 14 votes, Park 11, Street Lights 9.', 'Health Sub-centre is currently not funded.'],
      'total_votes': 40,
    };
  }
  if (p == '/api/ai/explain') {
    body = {
      'summary': 'This proposal repairs 1.4 km of MG Road and lanes 4–7 and adds side drains so the road stops flooding in the monsoon.',
      'who_benefits': ['Students of 3 schools', 'Weekly market visitors', 'Residents along MG Road'],
      'why_this_cost': 'Most of the money (₹19.6 lakh) is for resurfacing the road. Side drains cost another ₹8.4 lakh.',
      'tradeoff': 'It uses 43% of the ward pool. If funded, only one more large proposal can fit in the remaining ₹42.5 lakh.',
      'key_numbers': [
        {'label': 'Total cost', 'value': '₹32.6 L'},
        {'label': 'Share of pool', 'value': '43%'},
        {'label': 'Road length', 'value': '1.4 km'},
      ],
    };
  }
  return http.Response(jsonEncode(body), 200, request: req, headers: {'content-type': 'application/json; charset=utf-8'});
});

final supabaseMock = MockClient((req) async {
  final p = req.url.path;
  Object body = [];
  if (p.endsWith('/wards')) {
    body = [
      {'id': 1, 'name': 'Ward 1 – Gandhi Nagar', 'budget_pool': 7500000},
      {'id': 2, 'name': 'Ward 2 – Lake View', 'budget_pool': 6000000},
      {'id': 3, 'name': 'Ward 3 – Old Market', 'budget_pool': 5000000},
    ];
  }
  if (p.endsWith('/profiles')) body = profileJson;
  if (p.endsWith('/chat_messages')) body = chatRows;
  if (p.endsWith('/proposals')) body = [for (final x in [...myIdeas, ...proposals]) proposalJson(x)];
  return http.Response(jsonEncode(body), 200, request: req, headers: {'content-type': 'application/json; charset=utf-8'});
});

// ------------------------------------------------------------------ harness

Future<void> loadFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final f in manifest) {
    final loader = FontLoader(f['family'] as String);
    for (final a in f['fonts'] as List) {
      loader.addFont(rootBundle.load(a['asset'] as String));
    }
    await loader.load();
  }
  // Hashes use 'monospace' (a system font on Android) — borrow Consolas on Windows.
  final consolas = File('C:/Windows/Fonts/consola.ttf');
  if (consolas.existsSync()) {
    await (FontLoader('monospace')..addFont(Future.value(ByteData.sublistView(consolas.readAsBytesSync())))).load();
  }
}

Widget app(Widget screen,
    {AuthStage stage = AuthStage.ready, WardProvider? wp, int? tab, String? email, String? phone}) {
  final auth = FakeAuth(stage, email: email, phone: phone);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<WardProvider>.value(value: wp ?? fakeWard()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: tab == null ? screen : Scaffold(body: screen, bottomNavigationBar: AppNavBar(index: tab, onSelect: (_) {})),
    ),
  );
}

Future<void> shot(WidgetTester tester, String name, Widget widget,
    {Future<void> Function(WidgetTester t)? before}) async {
  await tester.pumpWidget(widget);
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 400));
  }
  if (before != null) await before(tester);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
  await tester.pumpWidget(const SizedBox()); // dispose animations
  await tester.pump(const Duration(seconds: 1));
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await loadFonts();
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
      httpClient: supabaseMock,
      authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage(), detectSessionInUri: false),
    );
    ApiService.client = apiMock;
    ResultsScreen.createResults = (_) => FakeResults();
    mapTilesEnabled = false;
    await buildChatFixture();
    ChatService.realtimeEnabled = false;
  });

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(412 * 2.5, 892 * 2.5);
    view.devicePixelRatio = 2.5;
  });

  testWidgets('01 splash', (t) => shot(t, '01_splash', app(const SplashScreen(), stage: AuthStage.loading)));
  testWidgets('02 login', (t) => shot(t, '02_login', app(const LoginScreen(), stage: AuthStage.signedOut)));
  testWidgets('03 email otp', (t) => shot(t, '03_email_otp',
      app(const EmailOtpScreen(), stage: AuthStage.signedOut, email: 'padma@example.com'), before: (t) async {
        await t.enterText(find.byType(TextField).first, '4821');
        await settle(t);
      }));
  testWidgets('03b phone otp', (t) => shot(t, '03b_phone_otp',
      app(const PhoneOtpScreen(), stage: AuthStage.signedOut, phone: '9876543210')));
  testWidgets('04 profile setup', (t) => shot(t, '04_profile_setup', app(const ProfileSetupScreen(), stage: AuthStage.needsProfile)));
  testWidgets('04b verify email from profile', (t) => shot(t, '04b_verify_contact', app(const ContactVerifyScreen(channel: 'email'))));
  testWidgets('05 home', (t) => shot(t, '05_home', app(const HomeScreen(), tab: 0, wp: fakeWard(myBallot: null))));
  testWidgets('05b home building ballot', (t) => shot(t, '05b_home_ballot',
      app(const HomeScreen(), tab: 0, wp: fakeWard(myBallot: null, picks: {'p1', 'p3'})), before: (t) async {
        await t.drag(find.byType(Scrollable).first, const Offset(0, -560));
        await settle(t);
      }));
  testWidgets('05c ballot review', (t) => shot(t, '05c_ballot_review',
      app(const HomeScreen(), tab: 0, wp: fakeWard(myBallot: null, picks: {'p1', 'p3'})), before: (t) async {
        await t.tap(find.text('Review'));
        await settle(t);
      }));
  testWidgets('06 home scrolled', (t) => shot(t, '06_home_scrolled', app(const HomeScreen(), tab: 0),
      before: (t) async {
        await t.drag(find.byType(Scrollable).first, const Offset(0, -520));
        await settle(t);
      }));
  testWidgets('07 proposal', (t) => shot(t, '07_proposal', app(const ProposalDetailScreen(proposalId: 'p1'), wp: fakeWard(myBallot: null))));
  testWidgets('07b proposal voted', (t) => shot(t, '07b_proposal_voted', app(const ProposalDetailScreen(proposalId: 'p1'))));
  testWidgets('08 proposal explain', (t) => shot(t, '08_proposal_explain',
      app(const ProposalDetailScreen(proposalId: 'p1'), wp: fakeWard(myBallot: null)), before: (t) async {
        await t.tap(find.text('Explain this proposal'));
        await settle(t);
        await t.drag(find.byType(Scrollable).first, const Offset(0, -380));
        await settle(t);
      }));
  testWidgets('18 map', (t) => shot(t, '18_map', app(const MapScreen(), tab: 1)));
  testWidgets('18b map selected', (t) => shot(t, '18b_map_selected', app(const MapScreen(focusId: 'p1'), tab: 1)));
  testWidgets('19 admin 3D map', (t) => shot(t, '19_admin_map', app(const AdminMapScreen())));
  testWidgets('19b admin 3D map selected', (t) => shot(t, '19b_admin_map_selected', app(const AdminMapScreen()),
      before: (t) async {
        await t.tap(find.text('Solar LED Street Lights').first);
        await settle(t);
      }));
  testWidgets('09 results', (t) => shot(t, '09_results', app(const ResultsScreen(), tab: 2)));
  testWidgets('10 results scrolled', (t) => shot(t, '10_results_scrolled', app(const ResultsScreen(), tab: 2),
      before: (t) async {
        await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
        await settle(t);
      }));
  testWidgets('11 assistant', (t) => shot(t, '11_assistant', app(const AssistantScreen(), tab: 3)));
  testWidgets('12 audit', (t) => shot(t, '12_audit', app(const AuditScreen(), tab: 4)));
  testWidgets('13 profile', (t) => shot(t, '13_profile', app(const ProfileScreen())));
  testWidgets('14 admin', (t) => shot(t, '14_admin', app(const AdminScreen())));
  testWidgets('14b admin ideas', (t) => shot(t, '14b_admin_ideas', app(const AdminScreen()), before: (t) async {
        await t.tap(find.text('Ideas'));
        await settle(t);
      }));
  testWidgets('16 my ideas', (t) => shot(t, '16_ideas', app(const IdeasScreen())));
  testWidgets('17 idea form', (t) => shot(t, '17_idea_form', app(const ProposalFormScreen(mode: ProposalFormMode.idea))));
  for (final (name, kind, retry) in [
    ('20_err_404', FailureKind.notFound, false),
    ('21_err_offline', FailureKind.offline, true),
    ('22_err_server_down', FailureKind.serverDown, true),
    ('23_err_session', FailureKind.sessionExpired, false),
    ('24_err_voting_closed', FailureKind.votingClosed, false),
    ('25_err_not_open', FailureKind.votingNotOpen, false),
    ('26_err_already_voted', FailureKind.alreadyVoted, false),
    ('27_err_crash', FailureKind.crash, false),
    ('28_err_rate_limited', FailureKind.rateLimited, true),
  ]) {
    testWidgets(name, (t) => shot(t, name,
        app(FailureScreen(failure: ErrorGalleryScreen.sample(kind), onRetry: retry ? () {} : null))));
  }
  testWidgets('29 error gallery', (t) => shot(t, '29_err_gallery', app(const ErrorGalleryScreen())));
  testWidgets('30 ward fund', (t) => shot(t, '30_funds', app(const FundsScreen())));
  testWidgets('30b contribute sheet', (t) => shot(t, '30b_contribute', app(const FundsScreen()), before: (t) async {
        await t.tap(find.text('Give again').first);
        await settle(t);
      }));
  testWidgets('31 chat (E2E)', (t) => shot(t, '31_chat', app(const ChatScreen())));
  testWidgets('32 admin inbox', (t) => shot(t, '32_inbox', app(const InboxScreen())));
  testWidgets('33 AI chat summary', (t) => shot(t, '33_chat_summary', app(ChatSummaryScreen(conversations: [
        (resident: 'Padma Raman', messages: [
          ChatMessage(id: '1', senderId: 'r1', text: 'Streetlight near 4th Lane is off.', createdAt: DateTime(2026, 9, 25), readAt: null, mine: false),
        ]),
      ]))));
  testWidgets('34 ward admin console', (t) => shot(t, '34_ward_admin', app(const WardAdminScreen())));
  testWidgets('35 ward admin fund', (t) => shot(t, '35_ward_admin_fund', app(const WardAdminScreen()), before: (t) async {
        await t.tap(find.text('Fund'));
        await settle(t);
      }));
  testWidgets('36 super admin funds', (t) => shot(t, '36_admin_funds', app(const AdminScreen()), before: (t) async {
        await t.ensureVisible(find.text('Funds'));
        await t.pumpAndSettle();
        await t.tap(find.text('Funds'));
        await settle(t);
      }));
  testWidgets('15 receipt', (t) => shot(t, '15_receipt', app(Scaffold(
        body: VoteReceiptSheet(
          justVoted: true,
          onViewResults: () {},
          receipt: VoteReceipt(
            id: 'v', proposalIds: const ['p1', 'p3'],
            proposalTitles: const ['Resurface MG Road & Lanes 4–7', 'Gandhi Maidan Park Revamp'], totalCost: 5755000,
            voterHash: h('a3c7'), prevHash: h('b1e4'), hash: h('9f3c2a'), createdAt: DateTime(2026, 9, 25, 10, 40),
          ),
        ),
      ))));
}
