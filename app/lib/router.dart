import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'screens/admin_map_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/app_shell.dart';
import 'screens/assistant_screen.dart';
import 'screens/audit_screen.dart';
import 'screens/contact_verify_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/email_otp_screen.dart';
import 'screens/error_gallery_screen.dart';
import 'screens/funds_screen.dart';
import 'screens/home_screen.dart';
import 'screens/ideas_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/login_screen.dart';
import 'screens/map_screen.dart';
import 'screens/phone_otp_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/proposal_detail_screen.dart';
import 'screens/results_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/ward_admin_screen.dart';
import 'utils/failure.dart';
import 'widgets/failure_view.dart';

const _onboardingRoutes = {'/splash', '/login', '/email-otp', '/phone-otp', '/profile-setup', '/verify-contact'};

/// Route guard: signed out → login (+ the chosen OTP screen); verified but
/// profile incomplete → profile setup; otherwise the app.
GoRouter buildRouter(AuthProvider auth) => GoRouter(
      initialLocation: '/splash',
      refreshListenable: Listenable.merge([auth, introDone]),
      redirect: (context, state) {
        final loc = state.matchedLocation;
        if (!introDone.value) return loc == '/splash' ? null : '/splash'; // let the intro finish
        switch (auth.stage) {
          case AuthStage.loading:
          case AuthStage.error:
            return loc == '/splash' ? null : '/splash';
          case AuthStage.signedOut:
            if (loc == '/login') return null;
            if (loc == '/email-otp' && auth.pendingEmail != null) return null;
            if (loc == '/phone-otp' && auth.pendingPhone != null) return null;
            return '/login';
          case AuthStage.needsContact:
            return loc == '/verify-contact' ? null : '/verify-contact';
          case AuthStage.needsProfile:
            return loc == '/profile-setup' ? null : '/profile-setup';
          case AuthStage.ready:
            if (loc.startsWith('/admin') && !(auth.profile?.isAdmin ?? false)) return '/home';
            return _onboardingRoutes.contains(loc) ? '/home' : null;
        }
      },
      // Unknown links → 404 page
      errorBuilder: (_, state) => FailureScreen(
        failure: AppFailure.of(FailureKind.notFound, detail: 'No page at ${state.uri}'),
      ),
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(path: '/email-otp', builder: (_, _) => const EmailOtpScreen()),
        GoRoute(path: '/phone-otp', builder: (_, _) => const PhoneOtpScreen()),
        GoRoute(path: '/profile-setup', builder: (_, _) => const ProfileSetupScreen()),
        GoRoute(path: '/verify-contact', builder: (_, _) => const ContactVerifyScreen()),
        // Main tabs (bottom navigation)
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/map',
                builder: (_, state) => MapScreen(focusId: state.uri.queryParameters['focus']),
              ),
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
        GoRoute(path: '/funds', builder: (_, _) => const FundsScreen()),
        GoRoute(path: '/chat', builder: (_, _) => const ChatScreen()),
        GoRoute(path: '/inbox', builder: (_, _) => const InboxScreen()),
        GoRoute(path: '/ward-admin', builder: (_, _) => const WardAdminScreen()),
        GoRoute(path: '/admin/errors', builder: (_, _) => const ErrorGalleryScreen()),
        GoRoute(path: '/admin/map', builder: (_, _) => const AdminMapScreen()),
        GoRoute(
          path: '/proposal/:id',
          builder: (_, state) => ProposalDetailScreen(proposalId: state.pathParameters['id']!),
        ),
      ],
    );
