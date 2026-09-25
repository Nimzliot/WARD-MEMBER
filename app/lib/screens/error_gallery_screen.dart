import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/failure.dart';
import '../widgets/brand.dart';
import '../widgets/failure_view.dart';

/// Admin → Error pages: preview every failure page with sample data
/// (for demos and design checks). Nothing here touches real data.
class ErrorGalleryScreen extends StatelessWidget {
  const ErrorGalleryScreen({super.key});

  static AppFailure sample(FailureKind k) => AppFailure.of(
        k,
        detail: 'Sample preview from the admin error gallery',
        until: switch (k) {
          FailureKind.votingNotOpen => DateTime.now().add(const Duration(days: 1, hours: 3)),
          FailureKind.rateLimited => DateTime.now().add(const Duration(minutes: 4)),
          _ => null,
        },
      );

  @override
  Widget build(BuildContext context) {
    final kinds = FailureKind.values.where((k) => k != FailureKind.invalid).toList();
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const BrandHeader(showBack: true, title: 'Error pages', subtitle: 'Admin · preview every failure screen'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(children: [
              for (final k in kinds)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
                      child: Icon(failureSpecs[k]!.icon, color: AppColors.forest),
                    ),
                    title: Text(failureSpecs[k]!.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${failureSpecs[k]!.code} · ${k.name}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => FailureScreen(
                        failure: sample(k),
                        onRetry: const {
                          FailureKind.offline,
                          FailureKind.serverDown,
                          FailureKind.serverError,
                          FailureKind.aiUnavailable,
                          FailureKind.rateLimited,
                        }.contains(k)
                            ? () {}
                            : null,
                      ),
                    )),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}
