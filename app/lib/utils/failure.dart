import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/api_service.dart';

/// Every kind of failure the app has a dedicated page for.
enum FailureKind {
  offline,
  serverDown,
  sessionExpired,
  accessDenied,
  notEligible,
  votingNotOpen,
  votingClosed,
  alreadyVoted,
  overBudget,
  notFound,
  rateLimited,
  aiUnavailable,
  serverError,
  crash,

  /// Small input mistakes (wrong code, empty field). Shown inline, never as a page.
  invalid,
}

/// A classified failure: what to show and what the resident can do next.
class AppFailure {
  AppFailure({
    required this.kind,
    required this.code,
    required this.title,
    required this.message,
    this.detail,
    this.until,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final FailureKind kind;
  final String code; // short reference shown in "Technical details", e.g. 404, E-OFFLINE
  final String title;
  final String message;
  final String? detail; // raw error text for bug reports
  final DateTime? until; // countdown target (voting opens, rate limit ends)
  final DateTime at;

  /// Worth showing as a full page (small input mistakes stay inline).
  bool get isPage => kind != FailureKind.invalid;

  /// Classifies any exception thrown by the API client, Supabase or Flutter.
  factory AppFailure.from(Object error, [StackTrace? stack]) {
    if (error is AppFailure) return error;
    final detail = '$error${stack == null ? '' : '\n$stack'}';

    if (error is ApiException) return _fromApi(error, detail);
    if (error is SocketException || error is HandshakeException) {
      return AppFailure.of(FailureKind.offline, detail: detail);
    }
    if (error is TimeoutException) return AppFailure.of(FailureKind.serverDown, detail: detail);
    if (error is AuthException) {
      final m = error.message.toLowerCase();
      if (error.statusCode == '429' || m.contains('rate limit')) {
        return AppFailure.of(FailureKind.rateLimited,
            detail: detail, until: DateTime.now().add(const Duration(minutes: 1)));
      }
      if (m.contains('refresh token') || m.contains('session') || m.contains('jwt')) {
        return AppFailure.of(FailureKind.sessionExpired, detail: detail);
      }
      if (m.contains('socket') || m.contains('host lookup') || m.contains('network')) {
        return AppFailure.of(FailureKind.offline, detail: detail);
      }
      return AppFailure.of(FailureKind.invalid, message: error.message, detail: detail);
    }
    if (error is PostgrestException) {
      if (error.code == 'PGRST116') return AppFailure.of(FailureKind.notFound, detail: detail);
      if (error.code == '42501') return AppFailure.of(FailureKind.accessDenied, detail: detail);
      if (error.code == 'PGRST301' || error.code == 'PGRST303') {
        return AppFailure.of(FailureKind.sessionExpired, detail: detail);
      }
      if (error.code == '23505') {
        return AppFailure.of(FailureKind.invalid,
            message: 'This value is already registered to another account.', detail: detail);
      }
      return AppFailure.of(FailureKind.serverError, detail: detail);
    }
    final text = '$error'.toLowerCase();
    if (error is String) {
      if (text.contains('no internet')) return AppFailure.of(FailureKind.offline, detail: detail);
      if (text.contains('cannot reach') || text.contains('too long to respond') || text.contains('not responding')) {
        return AppFailure.of(FailureKind.serverDown, detail: detail);
      }
      if (text.contains('not found')) return AppFailure.of(FailureKind.notFound, detail: detail);
      return AppFailure.of(FailureKind.serverError, detail: detail);
    }
    if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('clientexception')) {
      return AppFailure.of(FailureKind.offline, detail: detail);
    }
    return AppFailure.of(FailureKind.serverError, detail: detail);
  }

  static AppFailure _fromApi(ApiException e, String detail) {
    final code = e.body['code'] as String?;
    final msg = e.message;
    DateTime? after(Object? seconds) =>
        seconds is num ? DateTime.now().add(Duration(seconds: seconds.toInt())) : null;

    final kind = switch (code) {
      'OFFLINE' => FailureKind.offline,
      'SERVER_DOWN' || 'SERVER_BUSY' => FailureKind.serverDown,
      'SESSION_EXPIRED' => FailureKind.sessionExpired,
      'ADMIN_ONLY' || 'NOT_YOUR_WARD' => FailureKind.accessDenied,
      'NOT_ELIGIBLE' => FailureKind.notEligible,
      'VOTING_NOT_OPEN' => FailureKind.votingNotOpen,
      'VOTING_CLOSED' => FailureKind.votingClosed,
      'ALREADY_VOTED' => FailureKind.alreadyVoted,
      'OVER_BUDGET' || 'BALLOT_CHANGED' => FailureKind.overBudget,
      'NOT_FOUND' => FailureKind.notFound,
      'PAYMENTS_NOT_CONFIGURED' || 'PAYMENT_FAILED' || 'FUND_CLOSED' || 'KEY_CHANGED' => FailureKind.invalid,
      'RATE_LIMITED' => FailureKind.rateLimited,
      'AI_UNAVAILABLE' => FailureKind.aiUnavailable,
      'SERVER_ERROR' || 'SMS_FAILED' => FailureKind.serverError,
      _ => switch (e.statusCode) {
          // Older server without codes: fall back on the HTTP status
          0 => FailureKind.serverDown,
          401 => FailureKind.sessionExpired,
          403 => FailureKind.accessDenied,
          404 => FailureKind.notFound,
          409 => FailureKind.alreadyVoted,
          429 => FailureKind.rateLimited,
          502 || 503 || 504 => FailureKind.serverDown,
          >= 500 => FailureKind.serverError,
          _ => FailureKind.invalid,
        },
    };
    final until = switch (kind) {
      FailureKind.votingNotOpen =>
        e.body['opens_at'] is String ? DateTime.tryParse(e.body['opens_at'] as String)?.toLocal() : null,
      FailureKind.rateLimited => after(e.body['retry_after'] ?? 60),
      _ => null,
    };
    // The server's own sentence is the most specific explanation for these kinds.
    final useServerText = const {
      FailureKind.accessDenied,
      FailureKind.notEligible,
      FailureKind.votingNotOpen,
      FailureKind.votingClosed,
      FailureKind.overBudget,
      FailureKind.rateLimited,
      FailureKind.aiUnavailable,
      FailureKind.invalid,
    }.contains(kind);
    return AppFailure.of(
      kind,
      message: useServerText ? msg : null,
      detail: 'HTTP ${e.statusCode}${code == null ? '' : ' · $code'}\n$detail',
      until: until,
    );
  }

  /// A failure of [kind] with its standard wording (optionally overridden).
  factory AppFailure.of(FailureKind kind, {String? message, String? detail, DateTime? until}) {
    final spec = failureSpecs[kind]!;
    return AppFailure(
      kind: kind,
      code: spec.code,
      title: spec.title,
      message: message ?? spec.message,
      detail: detail,
      until: until,
    );
  }
}

/// Standard wording + artwork for each failure kind.
class FailureSpec {
  const FailureSpec(this.code, this.title, this.message, this.icon, this.badge);

  final String code;
  final String title;
  final String message;
  final IconData icon; // main illustration icon
  final IconData badge; // small badge on the illustration
}

const failureSpecs = <FailureKind, FailureSpec>{
  FailureKind.offline: FailureSpec('E-OFFLINE', 'You\'re offline',
      'Your phone isn\'t connected to the internet. Check mobile data or Wi-Fi. We\'ll retry automatically.',
      Icons.signal_cellular_connected_no_internet_4_bar_rounded, Icons.wifi_off_rounded),
  FailureKind.serverDown: FailureSpec('E-503', 'The ward server is waking up',
      'It can take up to a minute after a quiet spell. We\'ll keep trying for you.',
      Icons.dns_rounded, Icons.bedtime_rounded),
  FailureKind.sessionExpired: FailureSpec('E-401', 'Your session has expired',
      'For your security you\'ve been signed out. Sign in again with a one-time code to continue.',
      Icons.lock_clock_rounded, Icons.key_rounded),
  FailureKind.accessDenied: FailureSpec('E-403', 'You don\'t have access',
      'This page is for a different ward or for ward officials only.',
      Icons.shield_rounded, Icons.block_rounded),
  FailureKind.notEligible: FailureSpec('E-403V', 'You can\'t vote yet',
      'Voting needs a verified account and a completed resident profile.',
      Icons.badge_rounded, Icons.priority_high_rounded),
  FailureKind.votingNotOpen: FailureSpec('E-423', 'Voting hasn\'t started yet',
      'You can browse the projects and suggest ideas until voting opens.',
      Icons.event_rounded, Icons.schedule_rounded),
  FailureKind.votingClosed: FailureSpec('E-423C', 'Voting has closed',
      'Ballots are no longer accepted. The results are final.',
      Icons.how_to_vote_rounded, Icons.lock_rounded),
  FailureKind.alreadyVoted: FailureSpec('E-409', 'You\'ve already voted',
      'Each resident gets one ballot per ward, and yours is safely recorded in the chain.',
      Icons.receipt_long_rounded, Icons.check_rounded),
  FailureKind.overBudget: FailureSpec('E-422', 'Your ballot needs a change',
      'Your picks no longer fit the ward budget, or a project was removed. Review your ballot and try again.',
      Icons.account_balance_wallet_rounded, Icons.edit_rounded),
  FailureKind.notFound: FailureSpec('404', 'Page not found',
      'This page doesn\'t exist or the proposal was removed by the ward office.',
      Icons.signpost_rounded, Icons.question_mark_rounded),
  FailureKind.rateLimited: FailureSpec('E-429', 'Too many tries',
      'Please wait a little before trying again. This keeps the service fair for everyone.',
      Icons.hourglass_top_rounded, Icons.timer_rounded),
  FailureKind.aiUnavailable: FailureSpec('E-502AI', 'Ward Assistant is resting',
      'The AI helper is busy right now. Everything else in the app still works.',
      Icons.auto_awesome_rounded, Icons.bedtime_rounded),
  FailureKind.serverError: FailureSpec('E-500', 'Something went wrong on our side',
      'The ward server hit a problem. Try again, and if it keeps happening, share the details below.',
      Icons.build_rounded, Icons.priority_high_rounded),
  FailureKind.crash: FailureSpec('E-APP', 'The app ran into a problem',
      'Sorry, this screen stopped working. Restart the app to carry on. Your ballot and data are safe.',
      Icons.broken_image_rounded, Icons.refresh_rounded),
  FailureKind.invalid: FailureSpec('E-400', 'Please check and try again',
      'Something in the form needs a fix.', Icons.edit_note_rounded, Icons.priority_high_rounded),
};
