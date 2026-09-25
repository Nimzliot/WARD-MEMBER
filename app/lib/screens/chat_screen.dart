import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../providers/auth_provider.dart';
import '../services/chat_crypto.dart';
import '../services/chat_service.dart';
import '../theme.dart';
import '../utils/errors.dart';
import '../utils/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/failure_view.dart';
import 'chat_summary_screen.dart';

/// End-to-end encrypted conversation between a resident and the Ward Admin.
/// Residents open it without arguments (it finds their Ward Admin); the Ward
/// Admin opens it from the inbox with [thread].
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.thread});

  final ChatThread? thread; // set when the Ward Admin opens a resident's thread

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  RealtimeChannel? _channel;
  Timer? _debounce;

  bool get _asAdmin => widget.thread != null;
  String? _threadId;
  String? _peerName;
  String? _peerKey;
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Object? _error;
  String? _blocked; // why chat isn't available (no ward admin / no key yet)

  String get _myId => context.read<AuthProvider>().user!.id;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_channel != null) ChatService.unsubscribe(_channel!);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ChatService.ensureKey(_myId);
      if (_asAdmin) {
        final t = widget.thread!;
        _threadId = t.id;
        _peerName = t.residentName;
        _peerKey = t.residentKey;
        if (_peerKey == null) _blocked = '${t.residentName} needs to open the app again to finish setting up secure chat.';
      } else {
        final p = await ChatService.peer();
        if (!mounted) return;
        if (p.isWardAdmin) {
          context.pushReplacement('/inbox');
          return;
        }
        if (p.admin == null) {
          _blocked = 'Your ward doesn\'t have a Ward Admin yet. The ward office will assign one soon.';
        } else {
          _threadId = p.thread!.id;
          _peerName = p.admin!.name;
          _peerKey = p.admin!.publicKey;
          if (_peerKey == null) {
            _blocked = '${p.admin!.name} hasn\'t opened the app since becoming Ward Admin, so secure chat isn\'t ready yet.';
          }
        }
      }
      if (_threadId != null) {
        await _reload();
        _channel ??= ChatService.subscribe(_threadId!, () {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 250), _reload);
        });
      }
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reload() async {
    if (_threadId == null) return;
    final msgs = await ChatService.messages(_threadId!, _myId);
    if (!mounted) return;
    final hadNew = msgs.length != _messages.length;
    setState(() => _messages = msgs);
    if (msgs.any((m) => !m.mine && m.readAt == null)) ChatService.markRead(_threadId!).ignore();
    if (hadNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending || _peerKey == null) return;
    setState(() => _sending = true);
    try {
      await ChatService.send(_threadId!, text, theirKey: _peerKey!);
      _text.clear();
      await _reload();
    } catch (e) {
      if (mounted && !await showFailure(context, e) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showSafetyCode() async {
    final mine = ChatCrypto.publicKey;
    if (mine == null || _peerKey == null) return;
    final code = await ChatCrypto.safetyCode(mine, _peerKey!);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.verified_user_rounded, color: AppColors.forest),
        title: const Text('Verify encryption'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Compare this code with $_peerName. If it matches on both phones, nobody is in the middle.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(code,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 2, color: AppColors.forestDark)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
      ),
    );
  }

  Future<void> _summarize() async {
    final convo = (resident: _peerName ?? 'Resident', messages: _messages);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatSummaryScreen(conversations: [convo])));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        BrandHeader(
          showBack: true,
          title: _peerName ?? (_asAdmin ? 'Resident' : 'Ward Admin'),
          subtitle: _asAdmin ? 'Resident · end-to-end encrypted' : 'Your Ward Admin · end-to-end encrypted',
          bottomPadding: 12,
          actions: [
            if (_peerKey != null)
              HeaderIconButton(icon: Icons.verified_user_outlined, tooltip: 'Verify encryption', onPressed: _showSafetyCode),
            if (_asAdmin && _messages.isNotEmpty) ...[
              const SizedBox(width: 6),
              HeaderIconButton(icon: Icons.auto_awesome, tooltip: 'Summarize with AI', onPressed: _summarize),
            ],
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorView(error: _error, onRetry: _open)
                  : _blocked != null && _threadId == null
                      ? EmptyView(icon: Icons.support_agent_rounded, message: _blocked!)
                      : _messageList(),
        ),
        if (_threadId != null && !_loading && _error == null) _composer(),
      ]),
    );
  }

  Widget _messageList() => ListView(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          for (final m in _messages.reversed) _Bubble(message: m),
          const SizedBox(height: 8),
          _E2eNotice(asAdmin: _asAdmin),
        ],
      );

  Widget _composer() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: AppColors.forestDark.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -2))],
          ),
          child: _peerKey == null
              ? Padding(padding: const EdgeInsets.all(8), child: MessageBanner(_blocked ?? 'Secure chat is not ready yet.', isError: false))
              : Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        counterText: '',
                        prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded),
                  ),
                ]),
        ),
      );
}

class _E2eNotice extends StatelessWidget {
  const _E2eNotice({required this.asAdmin});

  final bool asAdmin;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lock_rounded, size: 18, color: Color(0xFF8A5A00)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              asAdmin
                  ? 'Messages are end-to-end encrypted. Only you and this resident can read them. '
                      'If you use "Summarize with AI", your phone sends the decrypted text to Ward Assistant for that summary only.'
                  : 'Messages are end-to-end encrypted. Only you and your Ward Admin can read them, not even the server. '
                      'Your Ward Admin may ask Ward Assistant (AI) to summarise conversations to follow up on issues.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF5C4300), height: 1.4),
            ),
          ),
        ]),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final mine = m.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
        decoration: BoxDecoration(
          color: mine ? AppColors.forest : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: AppColors.mintLine),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          m.text == null
              ? Text('🔒 This message can\'t be read on this device',
                  style: TextStyle(fontStyle: FontStyle.italic, color: mine ? Colors.white70 : AppColors.inkMuted))
              : SelectableText(m.text!, style: TextStyle(color: mine ? Colors.white : AppColors.ink, height: 1.35)),
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(timeAgo(m.createdAt), style: TextStyle(fontSize: 10.5, color: mine ? Colors.white70 : AppColors.inkMuted)),
            if (mine) ...[
              const SizedBox(width: 4),
              Icon(m.readAt != null ? Icons.done_all_rounded : Icons.done_rounded,
                  size: 14, color: m.readAt != null ? AppColors.leaf : Colors.white70),
            ],
          ]),
        ]),
      ),
    );
  }
}
