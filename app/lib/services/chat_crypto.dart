import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// End-to-end encryption for resident ↔ Ward Admin chat.
///
/// * Each device holds an X25519 key pair. The private key stays in the
///   phone's secure storage (Android Keystore); only the public key is sent.
/// * Per conversation: shared secret = X25519(my private, their public),
///   stretched with HKDF-SHA256 (salt = thread id) into an AES-256-GCM key.
/// * Every message gets a fresh 12-byte nonce; GCM's tag detects tampering.
/// The server only ever sees ciphertext, nonces and public keys.
class ChatCrypto {
  ChatCrypto._();

  static final _x25519 = X25519();
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const _storage = FlutterSecureStorage();

  static SimpleKeyPair? _pair;
  static String? _publicKey; // base64
  static String? _userId;
  static final _keyCache = <String, SecretKey>{};

  static String? get publicKey => _publicKey;

  /// Loads this user's key pair from secure storage, creating one on first use.
  /// Returns the base64 public key and whether it is new (must be published).
  static Future<({String publicKey, bool created})> ensureKeys(String userId) async {
    if (_userId == userId && _publicKey != null) return (publicKey: _publicKey!, created: false);
    _keyCache.clear();
    final name = 'chat_x25519_$userId';
    final stored = await _storage.read(key: name);
    if (stored != null) {
      final parts = stored.split('.');
      final priv = base64Decode(parts[0]);
      final pub = base64Decode(parts[1]);
      _pair = SimpleKeyPairData(priv, publicKey: SimplePublicKey(pub, type: KeyPairType.x25519), type: KeyPairType.x25519);
      _publicKey = parts[1];
      _userId = userId;
      return (publicKey: _publicKey!, created: false);
    }
    final pair = await _x25519.newKeyPair();
    final priv = await pair.extractPrivateKeyBytes();
    final pub = (await pair.extractPublicKey()).bytes;
    _publicKey = base64Encode(pub);
    await _storage.write(key: name, value: '${base64Encode(priv)}.$_publicKey');
    _pair = pair;
    _userId = userId;
    return (publicKey: _publicKey!, created: true);
  }

  static Future<SecretKey> _conversationKey(String theirPublicKey, String threadId) async {
    final cacheKey = '$threadId|$theirPublicKey|$_publicKey';
    final hit = _keyCache[cacheKey];
    if (hit != null) return hit;
    final shared = await _x25519.sharedSecretKey(
      keyPair: _pair!,
      remotePublicKey: SimplePublicKey(base64Decode(theirPublicKey), type: KeyPairType.x25519),
    );
    final key = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('makkal-chat-v1:$threadId'),
      info: utf8.encode('resident-ward-admin'),
    );
    return _keyCache[cacheKey] = key;
  }

  /// Encrypts [text] for [theirPublicKey]. Returns the fields the server stores.
  static Future<({String ciphertext, String nonce, String senderKey, String recipientKey})> encrypt(
    String text, {
    required String theirPublicKey,
    required String threadId,
  }) async {
    final key = await _conversationKey(theirPublicKey, threadId);
    final box = await _aes.encrypt(utf8.encode(text), secretKey: key, aad: utf8.encode(threadId));
    return (
      ciphertext: base64Encode([...box.cipherText, ...box.mac.bytes]),
      nonce: base64Encode(box.nonce),
      senderKey: _publicKey!,
      recipientKey: theirPublicKey,
    );
  }

  /// Decrypts a stored message, or returns null if this device can't
  /// (sent to an older key / another device) or the message was tampered with.
  static Future<String?> decrypt({
    required String ciphertext,
    required String nonce,
    required String senderKey,
    required String recipientKey,
    required String threadId,
  }) async {
    if (_pair == null || _publicKey == null) return null;
    final String other;
    if (senderKey == _publicKey) {
      other = recipientKey;
    } else if (recipientKey == _publicKey) {
      other = senderKey;
    } else {
      return null; // encrypted for a key this device doesn't have
    }
    try {
      final key = await _conversationKey(other, threadId);
      final all = base64Decode(ciphertext);
      final box = SecretBox(
        all.sublist(0, all.length - 16),
        nonce: base64Decode(nonce),
        mac: Mac(all.sublist(all.length - 16)),
      );
      return utf8.decode(await _aes.decrypt(box, secretKey: key, aad: utf8.encode(threadId)));
    } catch (_) {
      return null;
    }
  }

  /// 12-digit safety code both sides can compare (same on both phones).
  static Future<String> safetyCode(String keyA, String keyB) async {
    final keys = [keyA, keyB]..sort();
    final hash = await Sha256().hash(utf8.encode(keys.join('|')));
    final digits = hash.bytes.take(6).map((b) => (b % 100).toString().padLeft(2, '0')).join();
    return '${digits.substring(0, 4)} ${digits.substring(4, 8)} ${digits.substring(8, 12)}';
  }

  /// Test hook: use an in-memory key pair instead of secure storage.
  static Future<void> useKeyPairForTesting(SimpleKeyPair pair) async {
    _keyCache.clear();
    _pair = pair;
    _publicKey = base64Encode((await pair.extractPublicKey()).bytes);
    _userId = 'test';
  }

  /// Forget the in-memory keys (e.g. on sign-out).
  static void reset() {
    _pair = null;
    _publicKey = null;
    _userId = null;
    _keyCache.clear();
  }
}
