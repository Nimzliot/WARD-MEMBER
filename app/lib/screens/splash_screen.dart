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
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: Stack(
          children: [
            // soft rings in the background
            Positioned(top: -80, right: -60, child: _ring(260)),
            Positioned(bottom: -100, left: -80, child: _ring(300)),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10)),
                          ],
                        ),
                        child: const Icon(Icons.how_to_vote_rounded, size: 54, color: AppColors.forest),
                      ),
                      const SizedBox(height: 24),
                      Text('Ward Budget',
                          style: theme.textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.8)),
                      const SizedBox(height: 8),
                      Text('Your ward. Your money. Your vote.',
                          style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.location_city, size: 16, color: AppColors.leaf),
                          SizedBox(width: 6),
                          Text('SDG 11 · Sustainable Cities',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                        ]),
                      ),
                      const SizedBox(height: 48),
                      if (auth.stage == AuthStage.error) ...[
                        Text(auth.loadError ?? 'Could not load your profile',
                            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.forest),
                          onPressed: auth.loadProfile,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                        TextButton(
                          onPressed: auth.signOut,
                          child: const Text('Sign out', style: TextStyle(color: Colors.white)),
                        ),
                      ] else
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _ring(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.07), width: 30),
        ),
      );
}
