import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ward.dart';
import '../providers/auth_provider.dart';
import '../utils/errors.dart';
import '../utils/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _residentId = TextEditingController();
  late Future<List<Ward>> _wards;
  int? _wardId;
  bool _saving = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = context.read<AuthProvider>().profile;
    _name.text = p?.fullName ?? '';
    _residentId.text = p?.residentId ?? '';
    _wardId = p?.wardId;
    _wards = _loadWards();
  }

  Future<List<Ward>> _loadWards() async {
    final rows = await Supabase.instance.client.from('wards').select().order('id', ascending: true);
    return rows.map(Ward.fromMap).toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _residentId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final residentId = _residentId.text.trim().toUpperCase();

    setState(() {
      _saving = true;
      _error = null;
      _status = 'Checking Resident ID with municipal records…';
    });

    // Simulated verification: a real deployment would call the municipality's
    // property-tax / voter-roll API. Demo IDs look like RES-<ward>-<4 digits>.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final match = RegExp(r'^RES-(\d{1,2})-(\d{4})$').firstMatch(residentId);
    if (match == null || int.parse(match.group(1)!) != _wardId) {
      setState(() {
        _saving = false;
        _status = null;
        _error =
            'Resident ID not found in Ward $_wardId records. '
            'Demo IDs look like RES-$_wardId-1234.';
      });
      return;
    }

    setState(() => _status = 'Resident verified ✓ Saving your profile…');
    try {
      // On success the router takes the user to Home.
      await auth.saveProfile(fullName: _name.text, wardId: _wardId!, residentId: residentId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _error = e is PostgrestException && e.code == '23505'
            ? 'This Resident ID is already registered to another account.'
            : friendlyError(e);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    return Scaffold(
      body: Column(
        children: [
          OnboardingHeader(
            step: 2,
            total: 2,
            showBack: false,
            icon: Icons.badge_outlined,
            title: 'Almost there',
            subtitle: const TextSpan(text: 'Tell us who you are and which ward you live in.'),
            actions: [
              TextButton(
                onPressed: auth.signOut,
                child: const Text(
                  'Sign out',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          Expanded(
            child: FutureBuilder<List<Ward>>(
              future: _wards,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(friendlyError(snap.error!)),
                        TextButton(
                          onPressed: () => setState(() => _wards = _loadWards()),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final wards = snap.data!;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v?.trim().length ?? 0) >= 3 ? null : 'Enter your full name',
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          initialValue: _wardId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Your ward',
                            prefixIcon: Icon(Icons.location_city),
                          ),
                          items: [
                            for (final w in wards)
                              DropdownMenuItem(
                                value: w.id,
                                child: Text(
                                  '${w.name}  ·  ${inrCompact(w.budgetPool)}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _wardId = v),
                          validator: (v) => v == null ? 'Choose your ward' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _residentId,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: 'Resident ID',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            helperText: 'Demo format: RES-${_wardId ?? 1}-1234',
                          ),
                          validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Enter your Resident ID',
                        ),
                        const SizedBox(height: 24),
                        if (_error != null) ...[MessageBanner(_error!), const SizedBox(height: 16)],
                        if (_status != null) ...[
                          MessageBanner(_status!, isError: false),
                          const SizedBox(height: 16),
                        ],
                        PrimaryButton(
                          label: 'Verify & continue',
                          icon: Icons.verified_user_outlined,
                          loading: _saving,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
