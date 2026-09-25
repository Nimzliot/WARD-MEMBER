import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'screens/admin_screen.dart';
import 'screens/app_shell.dart';
import 'screens/assistant_screen.dart';
import 'screens/audit_screen.dart';
import 'screens/email_otp_screen.dart';
import 'screens/home_screen.dart';
import 'screens/ideas_screen.dart';
import 'screens/login_screen.dart';
import 'screens/phone_otp_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/proposal_detail_screen.dart';
import 'screens/results_screen.dart';
import 'screens/splash_screen.dart';

const _onboardingRoutes = {'/splash', '/login', '/email-otp', '/phone-otp', '/profile-setup'};

/// Route guard: signed out → login (+ the chosen OTP screen); verified but
/// profile incomplete → profile setup; otherwise the app.
GoRouter buildRouter(AuthProvider auth) => GoRouter(
      initialLocation: '/splash',
      refreshListenable: auth,
      redirect: (context, state) {
        final loc = state.matchedLocation;
        switch (auth.stage) {
          case AuthStage.loading:
          case AuthStage.error:
            return loc == '/splash' ? null : '/splash';
          case AuthStage.signedOut:
            if (loc == '/login') return null;
            if (loc == '/email-otp' && auth.pendingEmail != null) return null;
            if (loc == '/phone-otp' && auth.pendingPhone != null) return null;
            return '/login';
          case AuthStage.needsProfile:
            return loc == '/profile-setup' ? null : '/profile-setup';
          case AuthStage.ready:
            if (loc == '/admin' && !(auth.profile?.isAdmin ?? false)) return '/home';
            return _onboardingRoutes.contains(loc) ? '/home' : null;
        }
      },
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(path: '/email-otp', builder: (_, _) => const EmailOtpScreen()),
        GoRoute(path: '/phone-otp', builder: (_, _) => const PhoneOtpScreen()),
        GoRoute(path: '/profile-setup', builder: (_, _) => const ProfileSetupScreen()),
        // Main tabs (bottom navigation)
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/results', builder: (_, _) => const ResultsScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/assistant', builder: (_, _) => const AssistantScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/audit', builder: (_, _) => const AuditScreen()),
            ]),
          ],
        ),
        // Full-screen pages pushed over the tabs
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
        GoRoute(path: '/ideas', builder: (_, _) => const IdeasScreen()),
        GoRoute(
          path: '/proposal/:id',
          builder: (_, state) => ProposalDetailScreen(proposalId: state.pathParameters['id']!),
        ),
      ],
    );
