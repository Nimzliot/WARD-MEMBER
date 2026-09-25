import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to verify your email again to sign back in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true && context.mounted) await context.read<AuthProvider>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final p = auth.profile;
    final theme = Theme.of(context);
    if (p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final initials = (p.fullName ?? '?')
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
        .join();

    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: RefreshIndicator(
        onRefresh: auth.loadProfile,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: CircleAvatar(
                radius: 40,
                child: Text(initials, style: theme.textTheme.headlineSmall),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(p.fullName ?? '',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 6),
            Center(
              child: Chip(
                avatar: Icon(p.isAdmin ? Icons.admin_panel_settings : Icons.home_outlined, size: 18),
                label: Text(p.isAdmin ? 'Admin' : 'Resident'),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              // Shows whichever method(s) this account verified with.
              child: Column(children: [
                if (p.hasRealEmail)
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: const Text('Email'),
                    subtitle: Text(p.email!),
                    trailing: VerifiedBadge(verified: auth.user?.emailConfirmedAt != null),
                  ),
                if (p.hasRealEmail && p.phoneVerified) const Divider(height: 1),
                if (p.phoneVerified)
                  ListTile(
                    leading: const Icon(Icons.phone_android),
                    title: const Text('Mobile'),
                    subtitle: Text(formatPhone(p.phone)),
                    trailing: const VerifiedBadge(verified: true),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.location_city),
                  title: const Text('Ward'),
                  subtitle: Text(p.wardName ?? 'Ward ${p.wardId}'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Resident ID'),
                  subtitle: Text(p.residentId ?? '—'),
                  trailing: VerifiedBadge(verified: p.isComplete),
                ),
              ]),
            ),
            if (p.isAdmin) ...[
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.tertiaryContainer,
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.admin_panel_settings),
                  title: const Text('Admin panel', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Create proposals with budget lines'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/admin'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => _confirmLogout(context),
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
