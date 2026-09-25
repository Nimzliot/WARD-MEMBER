import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.how_to_vote_rounded, size: 80, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Ward Budget',
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Your ward. Your money. Your vote.',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Chip(
                avatar: const Icon(Icons.location_city, size: 18, color: Colors.white),
                label: const Text('SDG 11 · Sustainable Cities',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                backgroundColor: AppTheme.sdgOrange,
                side: BorderSide.none,
              ),
              const SizedBox(height: 40),
              if (auth.stage == AuthStage.error) ...[
                Text(auth.loadError ?? 'Could not load your profile',
                    textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: auth.loadProfile,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                TextButton(onPressed: auth.signOut, child: const Text('Sign out')),
              ] else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
