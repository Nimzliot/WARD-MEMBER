import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ward_budget/services/chat_crypto.dart';
import 'package:ward_budget/services/chat_service.dart';
import 'package:ward_budget/utils/summary_pdf.dart';

Future<String> pub(SimpleKeyPair p) async => base64Encode((await p.extractPublicKey()).bytes);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SimpleKeyPair resident;
  late SimpleKeyPair admin;
  late String residentPub;
  late String adminPub;

  setUpAll(() async {
    resident = await X25519().newKeyPair();
    admin = await X25519().newKeyPair();
    residentPub = await pub(resident);
    adminPub = await pub(admin);
  });

  test('resident encrypts, Ward Admin decrypts (and the sender can re-read it)', () async {
    await ChatCrypto.useKeyPairForTesting(resident);
    final e = await ChatCrypto.encrypt('Streetlight on 4th Lane is broken', theirPublicKey: adminPub, threadId: 't1');
    expect(e.ciphertext, isNot(contains('Streetlight'))); // server only sees ciphertext
    expect(base64Decode(e.nonce).length, 12);

    final back = await ChatCrypto.decrypt(
        ciphertext: e.ciphertext, nonce: e.nonce, senderKey: e.senderKey, recipientKey: e.recipientKey, threadId: 't1');
    expect(back, 'Streetlight on 4th Lane is broken');

    await ChatCrypto.useKeyPairForTesting(admin);
    final atAdmin = await ChatCrypto.decrypt(
        ciphertext: e.ciphertext, nonce: e.nonce, senderKey: e.senderKey, recipientKey: e.recipientKey, threadId: 't1');
    expect(atAdmin, 'Streetlight on 4th Lane is broken');
  });

  test('tampering, wrong thread or a stranger all fail to decrypt', () async {
    await ChatCrypto.useKeyPairForTesting(resident);
    final e = await ChatCrypto.encrypt('hello', theirPublicKey: adminPub, threadId: 't1');
    await ChatCrypto.useKeyPairForTesting(admin);

    final bytes = base64Decode(e.ciphertext)..[0] ^= 1;
    expect(
        await ChatCrypto.decrypt(
            ciphertext: base64Encode(bytes), nonce: e.nonce, senderKey: e.senderKey, recipientKey: e.recipientKey, threadId: 't1'),
        isNull);
    expect(
        await ChatCrypto.decrypt(
            ciphertext: e.ciphertext, nonce: e.nonce, senderKey: e.senderKey, recipientKey: e.recipientKey, threadId: 't2'),
        isNull);

    await ChatCrypto.useKeyPairForTesting(await X25519().newKeyPair()); // someone else
    expect(
        await ChatCrypto.decrypt(
            ciphertext: e.ciphertext, nonce: e.nonce, senderKey: e.senderKey, recipientKey: e.recipientKey, threadId: 't1'),
        isNull);
  });

  test('safety code is the same on both phones', () async {
    final a = await ChatCrypto.safetyCode(residentPub, adminPub);
    final b = await ChatCrypto.safetyCode(adminPub, residentPub);
    expect(a, b);
    expect(RegExp(r'^\d{4} \d{4} \d{4}$').hasMatch(a), isTrue);
  });

  test('summary PDF builds with the app fonts', () async {
    final s = ChatSummary.fromMap({
      'headline': 'Streetlights and drainage top concerns',
      'overview': 'Residents raised broken lights and flooding near the market.',
      'key_issues': [
        {'issue': 'Broken streetlights on 4th Lane', 'residents': 3},
      ],
      'requests': ['Fix lights before festival season'],
      'urgent': ['Open drain near the school'],
      'sentiment': 'mixed',
      'sentiment_note': 'Frustrated but hopeful',
      'follow_ups': ['Log a complaint with the electricity department'],
      'ward_name': 'Ward 1 – Gandhi Nagar',
      'conversations': 2,
      'generated_at': DateTime(2026, 9, 26, 10).toIso8601String(),
    });
    final msgs = [
      ChatMessage(id: '1', senderId: 'r', text: 'Light is broken', createdAt: DateTime(2026, 9, 25), readAt: null, mine: false),
      ChatMessage(id: '2', senderId: 'a', text: 'Noted, will check', createdAt: DateTime(2026, 9, 25, 1), readAt: null, mine: true),
    ];
    final bytes = await buildSummaryPdf(s, transcripts: [(resident: 'Padma', messages: msgs)]);
    expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(5000));
  });
}
