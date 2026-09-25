import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/ward_provider.dart';
import '../utils/format.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/civic.dart';
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
    final isWardAdmin = context.watch<WardProvider>().isWardAdmin;
    final theme = Theme.of(context);
    if (p == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: auth.loadProfile,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            BrandHeader(
              showBack: true,
              title: 'My profile',
              child: Row(children: [
                InitialsAvatar(name: p.fullName, size: 64),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.fullName ?? '',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _HeaderChip(
                        icon: p.isAdmin ? Icons.admin_panel_settings : Icons.home_outlined,
                        text: p.isAdmin ? 'Super admin' : 'Resident',
                      ),
                      if (isWardAdmin) const _HeaderChip(icon: Icons.shield_rounded, text: 'Ward Admin'),
                      if (p.wardName != null) _HeaderChip(icon: Icons.location_city, text: p.wardName!),
                    ]),
                  ]),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SectionTitle('Verification'),
                Card(
                  // Shows whichever method(s) this account verified with.
                  child: Column(children: [
                    if (p.hasRealEmail)
                      _InfoRow(
                        icon: Icons.email_outlined,
                        label: 'Email',
                        value: p.email!,
                        trailing: VerifiedBadge(verified: auth.user?.emailConfirmedAt != null),
                      ),
                    if (p.hasRealEmail && p.phoneVerified) const Divider(height: 1, indent: 64),
                    if (p.phoneVerified)
                      _InfoRow(
                        icon: Icons.phone_android,
                        label: 'Mobile',
                        value: formatPhone(p.phone),
                        trailing: const VerifiedBadge(verified: true),
                      ),
                  ]),
                ),
                const SizedBox(height: 20),
                const SectionTitle('Residency'),
                Card(
                  child: Column(children: [
                    _InfoRow(icon: Icons.location_city, label: 'Ward', value: p.wardName ?? 'Ward ${p.wardId}'),
                    const Divider(height: 1, indent: 64),
                    _InfoRow(
                      icon: Icons.badge_outlined,
                      label: 'Resident ID',
                      value: p.residentId ?? '—',
                      trailing: VerifiedBadge(verified: p.isComplete),
                    ),
                  ]),
                ),
                if (p.isAdmin) ...[
                  const SizedBox(height: 20),
                  Material(
                    color: AppColors.forest,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => context.push('/admin'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.admin_panel_settings, color: Colors.white),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Admin panel',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                              Text('Super admin · every ward, funds, roles',
                                  style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                            ]),
                          ),
                          const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                        ]),
                      ),
                    ),
                  ),
                ],
                if (isWardAdmin) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      onTap: () => context.push('/ward-admin'),
                      leading: const Icon(Icons.shield_rounded, color: AppColors.forest),
                      title: const Text('Ward Admin console', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: const Text('Your ward: ideas, proposals, fund, messages'),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: () => _confirmLogout(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 20),
                const PrototypeNotice(),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppColors.leaf),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value, this.trailing});

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: AppColors.forest),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              const SizedBox(height: 1),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ]),
          ),
          ?trailing,
        ]),
      );
}
