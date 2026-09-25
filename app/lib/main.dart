import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'providers/auth_provider.dart';
import 'providers/ward_provider.dart';
import 'router.dart';
import 'theme.dart';
import 'widgets/app_logo.dart';
import 'widgets/failure_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isConfigured) {
    runApp(const _NotConfiguredApp());
    return;
  }

  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);

  // A widget that throws while building shows the crash page instead of Flutter's red screen.
  ErrorWidget.builder = (details) => CrashView(details: details);

  runApp(RestartScope(builder: _appTree));
}

/// Providers + app. Rebuilt from scratch by RestartScope ("Restart app" on the crash page).
Widget _appTree() {
  final auth = AuthProvider();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: auth),
      // Ward data follows the signed-in, fully-onboarded user's ward.
      ChangeNotifierProxyProvider<AuthProvider, WardProvider>(
        create: (_) => WardProvider(),
        update: (_, auth, ward) => ward!
          ..setWard(
            userId: auth.stage == AuthStage.ready ? auth.user?.id : null,
            wardId: auth.stage == AuthStage.ready ? auth.profile?.wardId : null,
          ),
      ),
    ],
    child: WardBudgetApp(auth: auth),
  );
}

class WardBudgetApp extends StatefulWidget {
  const WardBudgetApp({super.key, required this.auth});
  final AuthProvider auth;

  @override
  State<WardBudgetApp> createState() => _WardBudgetAppState();
}

class _WardBudgetAppState extends State<WardBudgetApp> {
  late final GoRouter _router = buildRouter(widget.auth);

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        themeMode: ThemeMode.light, // brand is green & white
        routerConfig: _router,
      );
}

class _NotConfiguredApp extends StatelessWidget {
  const _NotConfiguredApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'App not configured.\n\nSet SUPABASE_URL and SUPABASE_ANON_KEY in lib/config.dart '
                'or run with --dart-define-from-file=config.json',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
