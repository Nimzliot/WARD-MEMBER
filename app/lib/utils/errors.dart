import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/api_service.dart';

/// Turns any exception into a short message suitable for the UI.
String friendlyError(Object e) {
  if (e is ApiException) return e.message;
  if (e is AuthException) {
    final msg = e.message.toLowerCase();
    if (msg.contains('expired') || msg.contains('invalid')) {
      return 'That code is wrong or has expired. Check it or request a new one.';
    }
    if (msg.contains('rate limit') || e.statusCode == '429') {
      return 'Too many emails requested. Please wait a minute and try again.';
    }
    return e.message;
  }
  if (e is PostgrestException) {
    if (e.code == '23505') return 'This value is already registered to another account.';
    return e.message;
  }
  return 'Something went wrong. Check your connection and try again.';
}
