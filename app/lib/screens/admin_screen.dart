import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ward.dart';
import '../providers/auth_provider.dart';
import '../providers/ward_provider.dart';
import '../services/api_service.dart';
import '../utils/categories.dart';
import '../utils/errors.dart';
import '../utils/format.dart';
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
  late Future<List<Ward>> _wards;
  int? _wardId;
  String? _category;
  bool _saving = false;
  String? _error;

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
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
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

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total, required this.pool});

  final int total;
  final int? pool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final share = (pool == null || pool == 0) ? 0.0 : total / pool!;
    final over = share > 1;

    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total cost',
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(inr(total),
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
            if (pool != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: math.min(1.0, share),
                  minHeight: 8,
                  color: over ? scheme.error : null,
                  backgroundColor: scheme.onPrimaryContainer.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                over
                    ? 'Exceeds the ward pool (${inrCompact(pool!)}) — it can never be funded.'
                    : '${(share * 100).toStringAsFixed(0)}% of the ward pool (${inrCompact(pool!)})',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: over ? scheme.error : scheme.onPrimaryContainer,
                    fontWeight: over ? FontWeight.bold : null),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
