import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/chat_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'chat_summary_screen.dart';

/// Ward Admin inbox: every resident conversation, newest first.
/// [embedded] = shown as a tab inside the Ward Admin console (no header).
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<ChatThread>? _threads;
  Object? _error;
  bool _summarizing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await ChatService.ensureKey(context.read<AuthProvider>().user!.id);
      final t = await ChatService.threads();
      if (mounted) {
        setState(() {
          _threads = t;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _open(ChatThread t) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(thread: t)));
    _load();
  }

  /// Decrypts every conversation on this phone, then asks the AI for one summary.
  Future<void> _summarizeAll() async {
    final threads = _threads ?? const [];
    if (threads.isEmpty) return;
    setState(() => _summarizing = true);
    try {
      final me = context.read<AuthProvider>().user!.id;
      final convos = [
        for (final t in threads) (resident: t.residentName, messages: await ChatService.messages(t.id, me)),
      ];
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatSummaryScreen(conversations: convos)));
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  Widget _list() {
    final threads = _threads;
    if (_error != null) return SizedBox(height: 520, child: ErrorView(error: _error, onRetry: _load));
    if (threads == null) return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    if (threads.isEmpty) {
      return const EmptyView(
        icon: Icons.forum_outlined,
        message: 'No messages yet.\nResidents can message you from their Home screen.',
      );
    }
    return Column(children: [
      for (final t in threads)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            onTap: () => _open(t),
            contentPadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            leading: InitialsAvatar(name: t.residentName, size: 44),
            title: Text(t.residentName, style: TextStyle(fontWeight: t.unreadAdmin > 0 ? FontWeight.w800 : FontWeight.w600)),
            subtitle: Text([
              if (t.residentRef != null) t.residentRef!,
              if (t.lastMessageAt != null) timeAgo(t.lastMessageAt!),
            ].join(' · ')),
            trailing: t.unreadAdmin > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.forest, borderRadius: BorderRadius.circular(12)),
                    child: Text('${t.unreadAdmin}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  )
                : const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.inkMuted),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final threads = _threads;
    final unread = threads?.fold<int>(0, (s, t) => s + t.unreadAdmin) ?? 0;

    if (widget.embedded) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
          const MessageBanner(
            'End-to-end encrypted. Only you, as Ward Admin, can read these, not the super admin or the server.',
            isError: false,
          ),
          const SizedBox(height: 12),
          if (threads?.isNotEmpty ?? false) ...[
            PrimaryButton(
              label: _summarizing ? 'Decrypting…' : 'Summarize all with AI',
              icon: Icons.auto_awesome,
              loading: _summarizing,
              onPressed: _summarizeAll,
            ),
            const SizedBox(height: 14),
          ],
          _list(),
        ]),
      );
    }

    return Scaffold(
      floatingActionButton: (threads?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: _summarizing ? null : _summarizeAll,
              icon: _summarizing
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(_summarizing ? 'Decrypting…' : 'Summarize all', style: const TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            BrandHeader(
              showBack: true,
              title: 'Resident messages',
              subtitle: unread > 0 ? '$unread unread · end-to-end encrypted' : 'End-to-end encrypted',
              bottomPadding: 18,
            ),
            Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), child: _list()),
          ],
        ),
      ),
    );
  }
}
