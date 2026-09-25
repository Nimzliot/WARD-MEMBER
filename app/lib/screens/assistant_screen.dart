import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/ward_provider.dart';
import '../theme.dart';
import '../widgets/ai_widgets.dart';
import '../widgets/brand.dart';

/// "Assistant" tab — chat with the Ward Assistant about the whole ward budget.
class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wardName = context.watch<WardProvider>().ward?.name ?? 'your ward';
    final profile = context.watch<AuthProvider>().profile;

    return Scaffold(
      body: Column(
        children: [
          BrandHeader(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.leaf, AppColors.emerald]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
            ),
            title: 'Ward Assistant',
            subtitle: 'AI guide to $wardName',
            actions: [InitialsAvatar(name: profile?.fullName, onTap: () => context.push('/profile'))],
            bottomPadding: 18,
            child: Wrap(spacing: 6, runSpacing: 6, children: const [
              _Pill(icon: Icons.translate, text: 'English · தமிழ் · हिंदी'),
              _Pill(icon: Icons.fact_check_outlined, text: 'Answers from ward data'),
              _Pill(icon: Icons.balance_outlined, text: 'Neutral · never says how to vote'),
            ]),
          ),
          const Expanded(
            child: AiChat(
              greeting: 'Namaste! I know every proposal, budget line and live vote count in your ward. '
                  'Ask me anything, in English, தமிழ் or हिंदी.',
              suggestions: [
                'Explain our ward budget in simple words',
                'Which projects help children and students?',
                'Which proposal is the cheapest?',
                'How many votes are in so far?',
                'எந்த திட்டத்திற்கு அதிக செலவு?',
                'बजट से कौन-कौन से काम होंगे?',
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: AppColors.leaf),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      );
}
