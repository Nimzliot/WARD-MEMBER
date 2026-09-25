import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_service.dart';
import 'chat_crypto.dart';

class ChatPeer {
  ChatPeer({required this.id, required this.name, required this.publicKey});

  final String id;
  final String name;
  final String? publicKey; // null = hasn't opened secure chat yet
}

class ChatThread {
  ChatThread.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        wardId = m['ward_id'] as int,
        residentId = m['resident_id'] as String,
        residentName = m['resident_name'] as String? ?? 'Resident',
        residentRef = m['resident_ref'] as String?,
        residentKey = m['resident_key'] as String?,
        lastMessageAt = m['last_message_at'] == null ? null : DateTime.parse(m['last_message_at'] as String).toLocal(),
        unreadAdmin = (m['unread_admin'] as num?)?.toInt() ?? 0,
        unreadResident = (m['unread_resident'] as num?)?.toInt() ?? 0;

  final String id;
  final int wardId;
  final String residentId;
  final String residentName;
  final String? residentRef;
  final String? residentKey;
  final DateTime? lastMessageAt;
  final int unreadAdmin;
  final int unreadResident;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.createdAt,
    required this.readAt,
    required this.mine,
  });

  final String id;
  final String? senderId;
  final String? text; // null = can't be decrypted on this device
  final DateTime createdAt;
  final DateTime? readAt;
  final bool mine;
}

/// Resident ↔ Ward Admin chat. Text is encrypted/decrypted on the phone
/// ([ChatCrypto]); the API and database only handle ciphertext.
class ChatService {
  static SupabaseClient get _sb => Supabase.instance.client;

  /// Off in offline screenshot tests (no Realtime socket there).
  static bool realtimeEnabled = true;
  static String? _publishedFor;

  /// Creates this device's key pair if needed and publishes the public key.
  static Future<void> ensureKey(String userId) async {
    final k = await ChatCrypto.ensureKeys(userId);
    if (k.created || _publishedFor != userId) {
      await ApiService.post('/api/chat/key', {'publicKey': k.publicKey});
      _publishedFor = userId;
    }
  }

  /// Resident: my Ward Admin + my thread (created on first use).
  static Future<({ChatPeer? admin, ChatThread? thread, bool isWardAdmin, String? wardName})> peer() async {
    final r = await ApiService.get('/api/chat/peer');
    final a = r['admin'] as Map<String, dynamic>?;
    final t = r['thread'] as Map<String, dynamic>?;
    return (
      admin: a == null
          ? null
          : ChatPeer(id: a['id'] as String, name: a['name'] as String, publicKey: a['public_key'] as String?),
      thread: t == null ? null : ChatThread.fromMap(t),
      isWardAdmin: r['is_ward_admin'] as bool? ?? false,
      wardName: r['ward_name'] as String?,
    );
  }

  /// Ward Admin inbox.
  static Future<List<ChatThread>> threads() async {
    final r = await ApiService.get('/api/chat/threads');
    return [for (final t in r['threads'] as List) ChatThread.fromMap(t as Map<String, dynamic>)];
  }

  static Future<ChatMessage> _decode(Map<String, dynamic> m, String threadId, String myId) async {
    final text = await ChatCrypto.decrypt(
      ciphertext: m['ciphertext'] as String,
      nonce: m['nonce'] as String,
      senderKey: m['sender_key'] as String,
      recipientKey: m['recipient_key'] as String,
      threadId: threadId,
    );
    return ChatMessage(
      id: m['id'] as String,
      senderId: m['sender_id'] as String?,
      text: text,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      readAt: m['read_at'] == null ? null : DateTime.parse(m['read_at'] as String).toLocal(),
      mine: m['sender_id'] == myId,
    );
  }

  /// All messages in a thread, decrypted on this device (read through RLS).
  static Future<List<ChatMessage>> messages(String threadId, String myId) async {
    final rows = await _sb
        .from('chat_messages')
        .select('id, sender_id, ciphertext, nonce, sender_key, recipient_key, created_at, read_at')
        .eq('thread_id', threadId)
        .order('created_at', ascending: true);
    return Future.wait([for (final r in rows) _decode(r, threadId, myId)]);
  }

  static Future<void> send(String threadId, String text, {required String theirKey}) async {
    final e = await ChatCrypto.encrypt(text, theirPublicKey: theirKey, threadId: threadId);
    await ApiService.post('/api/chat/threads/$threadId/messages', {
      'ciphertext': e.ciphertext,
      'nonce': e.nonce,
      'senderKey': e.senderKey,
      'recipientKey': e.recipientKey,
    });
  }

  static Future<void> markRead(String threadId) => ApiService.post('/api/chat/threads/$threadId/read', {});

  /// Live updates for one thread: new messages + read receipts (null when disabled).
  static RealtimeChannel? subscribe(String threadId, void Function() onChange) => !realtimeEnabled
      ? null
      : _sb
      .channel('chat-$threadId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'chat_messages',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'thread_id', value: threadId),
        callback: (_) => onChange(),
      )
      .subscribe();

  /// Ward Admin: sends the decrypted conversations to Gemini for a summary.
  static Future<Map<String, dynamic>> summarize(List<({String resident, List<ChatMessage> messages})> convos) =>
      ApiService.post('/api/ai/chat-summary', {
        'threads': [
          for (final c in convos)
            {
              'resident': c.resident,
              'messages': [
                for (final m in c.messages)
                  if (m.text != null)
                    {'from': m.mine ? 'admin' : 'resident', 'text': m.text, 'at': m.createdAt.toIso8601String()},
              ],
            },
        ],
      });

  static void unsubscribe(RealtimeChannel c) => _sb.removeChannel(c);
}
