import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ward_provider.dart';
import '../theme.dart';
import '../widgets/ai_widgets.dart';

/// "Assistant" tab — chat with the Ward Assistant about the whole ward budget.
class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wardName = context.watch<WardProvider>().ward?.name ?? 'your ward';

    return Scaffold(
      body: Column(
        children: [
          _Header(wardName: wardName),
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

class _Header extends StatelessWidget {
  const _Header({required this.wardName});

  final String wardName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -30,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 22),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.leaf, AppColors.emerald]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ward Assistant',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                        const SizedBox(height: 2),
                        Text('AI guide to $wardName · powered by Gemini',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
