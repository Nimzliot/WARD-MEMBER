import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/proposal.dart';
import '../models/ward.dart';
import '../providers/auth_provider.dart';
import '../providers/ward_provider.dart';
import '../services/ai_service.dart';
import '../services/api_service.dart';
import '../utils/categories.dart';
import '../utils/errors.dart';
import '../utils/format.dart';
import '../theme.dart';
import '../widgets/ai_widgets.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';

enum ProposalFormMode {
  idea, // resident suggests a project for their own ward (goes to review)
  create, // admin publishes straight onto any ward's ballot
  edit, // admin edits an existing proposal / reviews a resident idea
}

/// One form for resident ideas and admin proposals, with the AI draft helper.
/// Pops with `true` when something was saved.
class ProposalFormScreen extends StatefulWidget {
  const ProposalFormScreen({super.key, required this.mode, this.proposal});

  final ProposalFormMode mode;
  final Proposal? proposal; // required for edit

  @override
  State<ProposalFormScreen> createState() => _ProposalFormScreenState();
}

class _BudgetLine {
  final label = TextEditingController();
  final amount = TextEditingController();

  int get value => int.tryParse(amount.text) ?? 0;

  void dispose() {
    label.dispose();
    amount.dispose();
  }
}

class _ProposalFormScreenState extends State<ProposalFormScreen> {
  static const _maxLines = 20;

  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final List<_BudgetLine> _lines = [_BudgetLine()];
  final _idea = TextEditingController();
  late Future<List<Ward>> _wards;
  int? _wardId;
  String? _category;
  bool _saving = false;
  bool _drafting = false;
  bool _aiFilled = false; // show "review before publishing" hint
  String? _error;
  String? _draftError;

  bool get _isIdea => widget.mode == ProposalFormMode.idea;
  bool get _isEdit => widget.mode == ProposalFormMode.edit;
  bool get _isPendingIdea => _isEdit && widget.proposal!.status == ProposalStatus.pending;

  @override
  void initState() {
    super.initState();
    final p = widget.proposal;
    if (p != null) {
      _wardId = p.wardId;
      _title.text = p.title;
      _description.text = p.description;
      _category = p.category;
      _lines
        ..clear()
        ..addAll([
          for (final i in p.items)
            _BudgetLine()
              ..label.text = i.label
              ..amount.text = '${i.amount}',
        ]);
      if (_lines.isEmpty) _lines.add(_BudgetLine());
    } else {
      _wardId = context.read<AuthProvider>().profile?.wardId;
    }
    _wards = _loadWards();
  }

  Future<List<Ward>> _loadWards() async {
    final rows = await Supabase.instance.client.from('wards').select().order('id', ascending: true);
    return rows.map(Ward.fromMap).toList();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _idea.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  /// Ward Assistant turns one sentence into a full draft the admin can edit.
  Future<void> _draftWithAi() async {
    FocusScope.of(context).unfocus();
    if (_wardId == null) {
      setState(() => _draftError = 'Choose a ward first');
      return;
    }
    if (_idea.text.trim().length < 5) {
      setState(() => _draftError = 'Describe the project in a sentence');
      return;
    }
    setState(() {
      _drafting = true;
      _draftError = null;
    });
    try {
      final d = await AiService.draft(_idea.text.trim(), _wardId!); // server ignores wardId for residents
      if (!mounted) return;
      setState(() {
        _title.text = d.title;
        _description.text = d.description;
        _category = kCategories.contains(d.category) ? d.category : null;
        for (final l in _lines) {
          l.dispose();
        }
        _lines
          ..clear()
          ..addAll([
            for (final i in d.items)
              _BudgetLine()
                ..label.text = i.label
                ..amount.text = '${i.amount}',
          ]);
        if (_lines.isEmpty) _lines.add(_BudgetLine());
        _aiFilled = true;
      });
    } catch (e) {
      if (mounted) setState(() => _draftError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  int get _total => _lines.fold(0, (sum, l) => sum + l.value);

  void _addLine() => setState(() => _lines.add(_BudgetLine()));

  void _removeLine(int i) => setState(() => _lines.removeAt(i).dispose());

  Map<String, dynamic> get _body => {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'category': _category,
        'items': [
          for (final l in _lines) {'label': l.label.text.trim(), 'amount': l.value},
        ],
      };

  /// [approve]: for a pending resident idea, save the edits and put it on the ballot.
  Future<void> _publish({bool approve = false}) async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final wp = context.read<WardProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      String message;
      switch (widget.mode) {
        case ProposalFormMode.idea:
          await wp.submitIdea(
            title: _title.text.trim(),
            category: _category!,
            description: _description.text.trim(),
            items: [for (final l in _lines) (label: l.label.text.trim(), amount: l.value)],
          );
          message = 'Idea sent to the ward office for review';
        case ProposalFormMode.create:
          final res = await ApiService.post('/api/admin/proposals', {'wardId': _wardId, ..._body});
          final p = res['proposal'] as Map<String, dynamic>;
          message = 'Published "${p['title']}" · ${inr(p['total_cost'] as num)}';
        case ProposalFormMode.edit:
          await ApiService.patch('/api/admin/proposals/${widget.proposal!.id}', {
            'wardId': _wardId,
            ..._body,
            if (approve) 'status': 'approved',
          });
          message = approve ? 'Approved: it is now on the ballot' : 'Changes saved';
      }
      if (!_isIdea) wp.load(); // Realtime also refreshes residents' phones
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(message)));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String title, String subtitle) = switch (widget.mode) {
      ProposalFormMode.idea => ('Suggest an idea', 'The ward office reviews it for the ballot'),
      ProposalFormMode.create => ('New proposal', 'Admin · publish to any ward'),
      ProposalFormMode.edit => (_isPendingIdea ? 'Review idea' : 'Edit proposal', 'Admin · changes go live instantly'),
    };
    return Scaffold(
      body: Column(
        children: [
          BrandHeader(showBack: true, title: title, subtitle: subtitle, bottomPadding: 16),
          Expanded(
            child: FutureBuilder<List<Ward>>(
              future: _wards,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return ErrorView(
                    message: friendlyError(snap.error!),
                    onRetry: () => setState(() => _wards = _loadWards()),
                  );
                }
                final wards = snap.data!;
                final ward = wards.where((w) => w.id == _wardId).firstOrNull;

                return Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    children: [
                      if (_isIdea)
                        MessageBanner(
                          'For ${ward?.name ?? 'your ward'}. If approved, it goes on the ballot and '
                          'residents can vote for it.',
                          isError: false,
                        )
                      else
                        DropdownButtonFormField<int>(
                          initialValue: _wardId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Ward',
                            prefixIcon: Icon(Icons.location_city),
                          ),
                          items: [
                            for (final w in wards)
                              DropdownMenuItem(
                                value: w.id,
                                child: Text(
                                  '${w.name}  ·  pool ${inrCompact(w.budgetPool)}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _wardId = v),
                          validator: (v) => v == null ? 'Choose a ward' : null,
                        ),
                      if (_isPendingIdea && (widget.proposal!.reviewNote?.isNotEmpty ?? false)) ...[
                        const SizedBox(height: 12),
                        MessageBanner('Note: ${widget.proposal!.reviewNote}', isError: false),
                      ],
                      const SizedBox(height: 16),
                      if (!_isEdit) ...[
                        _DraftPanel(
                          idea: _idea,
                          drafting: _drafting,
                          error: _draftError,
                          onDraft: _draftWithAi,
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (_aiFilled) ...[
                        const MessageBanner(
                          'Drafted by Ward Assistant. Check every line and amount before submitting.',
                          isError: false,
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _title,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.title)),
                        validator: (v) =>
                            (v?.trim().length ?? 0) >= 3 ? null : 'Enter a title (min 3 characters)',
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: ValueKey('category-$_category'),
                        initialValue: _category,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: [
                          for (final c in kCategories)
                            DropdownMenuItem(
                              value: c,
                              child: Row(
                                children: [
                                  Icon(categoryIcon(c), size: 18),
                                  const SizedBox(width: 8),
                                  Text(c),
                                ],
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _category = v),
                        validator: (v) => v == null ? 'Choose a category' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _description,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Description (why residents should fund it)',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Budget lines',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _lines.length; i++) _buildLine(i),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _lines.length < _maxLines ? _addLine : null,
                          icon: const Icon(Icons.add),
                          label: const Text('Add budget line'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _TotalCard(total: _total, pool: ward?.budgetPool),
                      const SizedBox(height: 20),
                      if (_error != null) ...[MessageBanner(_error!), const SizedBox(height: 16)],
                      if (_isPendingIdea) ...[
                        PrimaryButton(
                          label: 'Save & approve',
                          icon: Icons.check_circle_outline,
                          loading: _saving,
                          onPressed: () => _publish(approve: true),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton(
                            onPressed: _saving ? null : () => _publish(),
                            child: const Text('Save without approving'),
                          ),
                        ),
                      ] else
                        PrimaryButton(
                          label: switch (widget.mode) {
                            ProposalFormMode.idea => 'Submit idea',
                            ProposalFormMode.create => 'Publish proposal',
                            ProposalFormMode.edit => 'Save changes',
                          },
                          icon: _isIdea ? Icons.send_rounded : Icons.publish,
                          loading: _saving,
                          onPressed: () => _publish(),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(int i) {
    final line = _lines[i];
    return Padding(
      key: ObjectKey(line),
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: line.label,
              decoration: InputDecoration(labelText: 'Item ${i + 1}', isDense: true),
              validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Required',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: line.amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', isDense: true),
              onChanged: (_) => setState(() {}), // live total
              validator: (_) => line.value > 0 ? null : 'Enter ₹',
            ),
          ),
          IconButton(
            tooltip: 'Remove line',
            onPressed: _lines.length > 1 ? () => _removeLine(i) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _DraftPanel extends StatelessWidget {
  const _DraftPanel({required this.idea, required this.drafting, required this.error, required this.onDraft});

  final TextEditingController idea;
  final bool drafting;
  final String? error;
  final VoidCallback onDraft;

  static const _examples = [
    '4 bus shelters with benches on Station Road',
    'Free drinking water ATMs near 3 schools',
    'LED lights and CCTV for the children\'s park',
  ];

  @override
  Widget build(BuildContext context) {
    return AiPanel(
      footer: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Describe the project in one line.',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 2),
          const Text(
            'The assistant drafts the title, category, description and a realistic ₹ breakdown.',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: idea,
            minLines: 1,
            maxLines: 3,
            enabled: !drafting,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. 4 bus shelters on Station Road',
              fillColor: AppColors.canvas,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _examples)
                ActionChip(
                  label: Text(e, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  onPressed: drafting ? null : () => idea.text = e,
                ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: drafting
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: AiShimmer(lines: 3, label: 'Drafting your proposal…'),
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppTheme.aiGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextButton.icon(
                        onPressed: onDraft,
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('Draft with AI', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total, required this.pool});

  final int total;
  final int? pool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final share = (pool == null || pool == 0) ? 0.0 : total / pool!;
    final over = share > 1;

    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL COST',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.leaf,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            inr(total),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          if (pool != null) ...[
            const SizedBox(height: 14),
            HeroProgress(value: math.min(1.0, share), warning: over),
            const SizedBox(height: 8),
            Text(
              over
                  ? 'Exceeds the ward pool (${inrCompact(pool!)}): it can never be funded.'
                  : '${(share * 100).toStringAsFixed(0)}% of the ward pool (${inrCompact(pool!)})',
              style: theme.textTheme.bodySmall?.copyWith(
                color: over ? const Color(0xFFFFD2CB) : Colors.white.withValues(alpha: 0.85),
                fontWeight: over ? FontWeight.bold : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
