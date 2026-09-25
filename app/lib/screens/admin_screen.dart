import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
import '../widgets/common.dart';

/// Admins only (guarded in router.dart and again by the server):
/// create a proposal with its budget lines for any ward.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
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

class _AdminScreenState extends State<AdminScreen> {
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

  @override
  void initState() {
    super.initState();
    _wardId = context.read<AuthProvider>().profile?.wardId;
    _wards = _loadWards();
  }

  Future<List<Ward>> _loadWards() async {
    final rows = await Supabase.instance.client.from('wards').select().order('id');
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
      final d = await AiService.draft(_idea.text.trim(), _wardId!);
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

  void _resetForm() {
    _title.clear();
    _description.clear();
    for (final l in _lines) {
      l.dispose();
    }
    _lines
      ..clear()
      ..add(_BudgetLine());
    _category = null;
    _idea.clear();
    _aiFilled = false;
    _form.currentState?.reset();
  }

  Future<void> _publish() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await ApiService.post('/api/admin/proposals', {
        'wardId': _wardId,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'category': _category,
        'items': [
          for (final l in _lines) {'label': l.label.text.trim(), 'amount': l.value},
        ],
      });
      if (!mounted) return;
      final p = res['proposal'] as Map<String, dynamic>;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Published "${p['title']}" · ${inr(p['total_cost'] as num)}'),
      ));
      // Residents' lists refresh on pull-to-refresh; refresh ours right away.
      if (_wardId == context.read<WardProvider>().wardId) context.read<WardProvider>().load();
      setState(_resetForm);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Admin · New proposal')),
      body: FutureBuilder<List<Ward>>(
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
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
                        child: Text('${w.name}  ·  pool ${inrCompact(w.budgetPool)}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _wardId = v),
                  validator: (v) => v == null ? 'Choose a ward' : null,
                ),
                const SizedBox(height: 16),
                _DraftPanel(
                  idea: _idea,
                  drafting: _drafting,
                  error: _draftError,
                  onDraft: _draftWithAi,
                ),
                const SizedBox(height: 20),
                if (_aiFilled) ...[
                  const MessageBanner(
                    'Drafted by Ward Assistant. Check every line and amount before publishing.',
                    isError: false,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.title)),
                  validator: (v) => (v?.trim().length ?? 0) >= 3 ? null : 'Enter a title (min 3 characters)',
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
                        child: Row(children: [
                          Icon(categoryIcon(c), size: 18),
                          const SizedBox(width: 8),
                          Text(c),
                        ]),
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
                Text('Budget lines',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
                PrimaryButton(
                  label: 'Publish proposal',
                  icon: Icons.publish,
                  loading: _saving,
                  onPressed: _publish,
                ),
              ],
            ),
          );
        },
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
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
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
  const _DraftPanel({
    required this.idea,
    required this.drafting,
    required this.error,
    required this.onDraft,
  });

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
          const Text('Describe the project in one line.',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 2),
          const Text('The assistant drafts the title, category, description and a realistic ₹ breakdown.',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
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
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in _examples)
              ActionChip(
                label: Text(e, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onPressed: drafting ? null : () => idea.text = e,
              ),
          ]),
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
          Text('TOTAL COST',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: AppColors.leaf, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text(inr(total),
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
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
