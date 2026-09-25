import 'dart:async';

import 'package:flutter/material.dart';

import '../models/proposal.dart';
import '../services/ai_service.dart';
import '../theme.dart';
import '../utils/errors.dart';

// =====================================================================
// Building blocks
// =====================================================================

/// "✦ Ward Assistant" pill — the AI's visual signature across the app.
class AiBadge extends StatelessWidget {
  const AiBadge({super.key, this.label = 'Ward Assistant'});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(gradient: AppTheme.aiGradient, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
        ]),
      );
}

/// White card with a thin green gradient border — every AI output lives in one.
class AiPanel extends StatelessWidget {
  const AiPanel({super.key, required this.child, this.trailing, this.footer = true});

  final Widget child;
  final Widget? trailing;
  final bool footer;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(1.6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.leaf, AppColors.emerald, AppColors.forest]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.emerald.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18.4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [const AiBadge(), const Spacer(), ?trailing]),
            const SizedBox(height: 14),
            child,
            if (footer) ...[
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.info_outline, size: 13, color: muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text('AI-generated from ward data with Gemini · may contain mistakes',
                      style: TextStyle(fontSize: 11, color: muted)),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

/// EN / தமிழ் / हिंदी switch, shared app-wide through [aiLanguage].
class AiLanguagePicker extends StatelessWidget {
  const AiLanguagePicker({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AiLang>(
        valueListenable: aiLanguage,
        builder: (context, lang, _) => Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final l in AiLang.values)
              GestureDetector(
                onTap: () => aiLanguage.value = l,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: l == lang ? AppColors.forest : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(l.short,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: l == lang ? Colors.white : AppColors.forest,
                      )),
                ),
              ),
          ]),
        ),
      );
}

/// Skeleton lines with a moving green sheen while the AI is thinking.
class AiShimmer extends StatefulWidget {
  const AiShimmer({super.key, this.lines = 4, this.label = 'Reading the ward budget…'});

  final int lines;
  final String label;

  @override
  State<AiShimmer> createState() => _AiShimmerState();
}

class _AiShimmerState extends State<AiShimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * 3 - 1; // sweep from -1 → 2
        final sheen = LinearGradient(
          begin: Alignment(t - 1, 0),
          end: Alignment(t + 1, 0),
          colors: const [AppColors.mint, Color(0xFFF7FCF9), AppColors.mint],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const TypingDots(),
              const SizedBox(width: 8),
              Text(widget.label,
                  style: const TextStyle(fontSize: 13, color: AppColors.forest, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            for (var i = 0; i < widget.lines; i++)
              Container(
                height: 12,
                width: double.infinity,
                margin: EdgeInsets.only(bottom: 10, right: i == widget.lines - 1 ? 90 : (i.isOdd ? 30 : 0)),
                decoration: BoxDecoration(gradient: sheen, borderRadius: BorderRadius.circular(6)),
              ),
          ],
        );
      },
    );
  }
}

/// Three bouncing dots.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.color = AppColors.emerald});

  final Color color;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset(0, -3 * _bounce((_c.value - i * 0.15) % 1)),
              child: Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ),
        ]),
      );

  double _bounce(double t) => t < 0.5 ? Curves.easeOut.transform(t * 2) : Curves.easeIn.transform((1 - t) * 2);
}

/// Reveals text quickly, word by word, so answers feel alive (max ~1 s).
class TypewriterText extends StatefulWidget {
  const TypewriterText(this.text, {super.key, this.style, this.animate = true});

  final String text;
  final TextStyle? style;
  final bool animate;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late List<String> _words;

  @override
  void initState() {
    super.initState();
    _words = widget.text.split(' ');
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_words.length * 28).clamp(250, 1100)),
      value: widget.animate ? 0 : 1,
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final n = (_words.length * _c.value).ceil();
          return Text(_words.take(n).join(' '), style: widget.style);
        },
      );
}

/// Friendly error inside an AI panel with a retry link.
class _AiError extends StatelessWidget {
  const _AiError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(Icons.cloud_off_outlined, size: 18, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]);
}

Widget _sectionLabel(String text, IconData icon) => Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 14),
      child: Row(children: [
        Icon(icon, size: 16, color: AppColors.forest),
        const SizedBox(width: 6),
        Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: AppColors.forest)),
      ]),
    );

// =====================================================================
// 1. Explain this proposal (in EN / Tamil / Hindi)
// =====================================================================

class ExplainCard extends StatefulWidget {
  const ExplainCard({super.key, required this.proposal});

  final Proposal proposal;

  @override
  State<ExplainCard> createState() => _ExplainCardState();
}

class _ExplainCardState extends State<ExplainCard> {
  final Map<AiLang, ProposalExplanation> _cache = {};
  bool _open = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    aiLanguage.addListener(_onLang);
  }

  @override
  void dispose() {
    aiLanguage.removeListener(_onLang);
    super.dispose();
  }

  void _onLang() {
    if (_open) _load();
  }

  Future<void> _load() async {
    final lang = aiLanguage.value;
    setState(() {
      _open = true;
      _error = null;
      _loading = !_cache.containsKey(lang);
    });
    if (_cache.containsKey(lang)) return;
    try {
      final e = await AiService.explain(widget.proposal.id, lang);
      if (!mounted) return;
      setState(() => _cache[lang] = e);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) return _cta(context);
    final lang = aiLanguage.value;
    final e = _cache[lang];

    return AiPanel(
      trailing: const AiLanguagePicker(),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _error != null
            ? _AiError(message: _error!, onRetry: _load)
            : (_loading || e == null)
                ? AiShimmer(lines: 5, label: 'Explaining in ${lang.label}…')
                : _content(context, e),
      ),
    );
  }

  Widget _cta(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _load,
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.mint, Colors.white]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.mintLine),
            ),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(gradient: AppTheme.aiGradient, shape: BoxShape.circle),
                child: const Icon(Icons.auto_awesome, color: Colors.white),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Explain this proposal',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.forestDark)),
                  SizedBox(height: 2),
                  Text('Plain words · English, தமிழ், हिंदी',
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                ]),
              ),
              const Icon(Icons.arrow_forward_rounded, color: AppColors.forest),
            ]),
          ),
        ),
      );

  Widget _content(BuildContext context, ProposalExplanation e) {
    final body = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45);
    return Column(
      key: ValueKey(aiLanguage.value),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TypewriterText(e.summary,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.35)),
        if (e.keyNumbers.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(children: [
            for (final (i, k) in e.keyNumbers.take(3).indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.forestDark)),
                    const SizedBox(height: 2),
                    Text(k.label,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 11, color: AppColors.inkMuted, height: 1.2)),
                  ]),
                ),
              ),
            ],
          ]),
        ],
        if (e.whoBenefits.isNotEmpty) ...[
          _sectionLabel('Who benefits', Icons.groups_outlined),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final w in e.whoBenefits)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.mintLine),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(w, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
          ]),
        ],
        _sectionLabel('Why it costs this much', Icons.payments_outlined),
        Text(e.whyThisCost, style: body),
        _sectionLabel('Trade-off', Icons.balance_outlined),
        Text(e.tradeoff, style: body),
      ],
    );
  }
}

// =====================================================================
// 2. Ask about this proposal (grounded chat)
// =====================================================================

Future<void> showAskSheet(BuildContext context, Proposal proposal) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AskSheet(proposal: proposal),
    );

/// Bottom sheet: chat about one proposal.
class AskSheet extends StatelessWidget {
  const AskSheet({super.key, required this.proposal});

  final Proposal proposal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
            child: Row(children: [
              const AiBadge(label: 'Ask Ward Assistant'),
              const Spacer(),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('About: ${proposal.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
          ),
          const Divider(height: 20),
          Expanded(
            child: AiChat(
              proposalId: proposal.id,
              greeting: 'Hi! Ask me anything about this proposal: its cost, who it helps, '
                  'or how it compares. You can ask in English, தமிழ் or हिंदी.',
              suggestions: const [
                'Who benefits the most?',
                'Why does it cost this much?',
                'What if this is not funded?',
                'இதனால் யாருக்கு பயன்?',
                'इसमें सबसे बड़ा खर्च क्या है?',
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Grounded chat with the Ward Assistant. With [proposalId] it answers about that
/// proposal; without it, about the resident's whole ward.
class AiChat extends StatefulWidget {
  const AiChat({super.key, this.proposalId, required this.greeting, required this.suggestions});

  final String? proposalId;
  final String greeting;
  final List<String> suggestions;

  @override
  State<AiChat> createState() => _AiChatState();
}

class _AiChatState extends State<AiChat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatTurn> _turns = [];
  bool _thinking = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final q = text.trim();
    if (q.isEmpty || _thinking) return;
    final history = List<ChatTurn>.from(_turns);
    setState(() {
      _turns.add(ChatTurn(true, q));
      _thinking = true;
      _input.clear();
    });
    _scrollDown();
    try {
      final answer = await AiService.ask(q, history, proposalId: widget.proposalId);
      if (mounted) setState(() => _turns.add(ChatTurn(false, answer)));
    } catch (e) {
      if (mounted) setState(() => _turns.add(ChatTurn(false, '⚠️ ${friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _thinking = false);
      _scrollDown();
    }
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
              duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
        }
      });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            children: [
              _Bubble(fromUser: false, text: widget.greeting, animate: false),
              if (_turns.isEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in widget.suggestions)
                    ActionChip(
                      avatar: const Icon(Icons.auto_awesome, size: 14, color: AppColors.emerald),
                      label: Text(s, style: const TextStyle(fontSize: 12.5)),
                      onPressed: () => _send(s),
                    ),
                ]),
              ],
              for (final (i, t) in _turns.indexed)
                _Bubble(fromUser: t.fromUser, text: t.text, animate: !t.fromUser && i == _turns.length - 1),
              if (_thinking)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(padding: EdgeInsets.only(top: 8, left: 36), child: TypingDots()),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.mintLine)),
          ),
          child: SafeArea(
            top: false,
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText: 'Ask in English, தமிழ், हिंदी…',
                    fillColor: AppColors.canvas,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    enabledBorder:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.forest, width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: _input,
                builder: (context, _) {
                  final enabled = _input.text.trim().isNotEmpty && !_thinking;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      gradient: enabled ? AppTheme.aiGradient : null,
                      color: enabled ? null : AppColors.mintLine,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: enabled ? () => _send(_input.text) : null,
                      icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                    ),
                  );
                },
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromUser, required this.text, this.animate = false});

  final bool fromUser;
  final String text;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: fromUser ? Colors.white : AppColors.ink, height: 1.45, fontSize: 14.5);
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: fromUser ? AppColors.forest : AppColors.mint,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(fromUser ? 18 : 4),
          bottomRight: Radius.circular(fromUser ? 4 : 18),
        ),
      ),
      child: animate ? TypewriterText(text, style: style) : Text(text, style: style),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: fromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!fromUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(gradient: AppTheme.aiGradient, shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome, size: 15, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

/// Floating "Ask AI" button for the proposal page.
class AskAiButton extends StatelessWidget {
  const AskAiButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.aiGradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: AppColors.forest.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onPressed,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Ask AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      );
}

// =====================================================================
// 4. Results insight
// =====================================================================

class InsightCard extends StatefulWidget {
  const InsightCard({super.key, required this.wardId, required this.totalVotes});

  final int wardId;
  final int totalVotes; // re-generate when the vote count changes

  @override
  State<InsightCard> createState() => _InsightCardState();
}

class _InsightCardState extends State<InsightCard> {
  ResultsInsight? _insight;
  bool _loading = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    aiLanguage.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(InsightCard old) {
    super.didUpdateWidget(old);
    if (old.totalVotes != widget.totalVotes || old.wardId != widget.wardId) {
      // Votes arrive in bursts during a demo; wait for things to settle.
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), _load);
    }
  }

  @override
  void dispose() {
    aiLanguage.removeListener(_load);
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.totalVotes == 0) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final i = await AiService.insight(widget.wardId, aiLanguage.value);
      if (mounted) setState(() => _insight = i);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.totalVotes == 0) return const SizedBox.shrink();
    final i = _insight;
    return AiPanel(
      trailing: const AiLanguagePicker(),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _error != null
            ? _AiError(message: _error!, onRetry: _load)
            : (i == null || (_loading && i.isEmpty))
                ? const AiShimmer(lines: 3, label: 'Reading the live results…')
                : Opacity(
                    opacity: _loading ? 0.5 : 1,
                    child: Column(
                      key: ValueKey('${i.headline}${aiLanguage.value}'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (i.headline != null)
                          Text(i.headline!,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800, color: AppColors.forestDark)),
                        const SizedBox(height: 6),
                        if (i.summary != null)
                          TypewriterText(i.summary!,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45)),
                        const SizedBox(height: 10),
                        for (final h in i.highlights)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                margin: const EdgeInsets.only(top: 6, right: 10),
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(color: AppColors.emerald, shape: BoxShape.circle),
                              ),
                              Expanded(child: Text(h, style: const TextStyle(fontSize: 13.5, height: 1.4))),
                            ]),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
