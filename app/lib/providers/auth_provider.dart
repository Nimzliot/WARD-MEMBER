import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../services/api_service.dart';
import '../utils/errors.dart';

/// Where the user is in onboarding. The router redirects based on this.
enum AuthStage { loading, error, signedOut, needsProfile, ready }

/// How the user chose to verify themselves on the login screen.
enum LoginMethod { email, phone }

class AuthProvider extends ChangeNotifier {
  final SupabaseClient _sb = Supabase.instance.client;
  late final StreamSubscription<AuthState> _sub;

  bool _loading = true; // true until the first auth event + profile load
  String? loadError;
  Profile? profile;

  // Entered on the login screen, used by the OTP screens.
  LoginMethod method = LoginMethod.email;
  String? pendingEmail;
  String? pendingPhone;

  AuthProvider() {
    _sub = _sb.auth.onAuthStateChange.listen((state) {
      switch (state.event) {
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.signedIn:
          loadProfile();
        case AuthChangeEvent.signedOut:
          profile = null;
          loadError = null;
          _loading = false;
          notifyListeners();
        default:
          break; // token refreshes etc. don't change the stage
      }
    }, onError: (Object e) {
      // e.g. an expired refresh token on startup → treat as signed out
      _loading = false;
      notifyListeners();
    });
  }

  Session? get session => _sb.auth.currentSession;
  User? get user => _sb.auth.currentUser;

  /// A session only exists after ONE successful verification (email code or
  /// SMS code), so "signed in" already means "verified".
  AuthStage get stage {
    if (_loading) return AuthStage.loading;
    if (session == null) return AuthStage.signedOut;
    if (loadError != null || profile == null) return AuthStage.error;
    if (!profile!.isComplete) return AuthStage.needsProfile;
    return AuthStage.ready;
  }

  /// Loads (or refreshes) the signed-in user's profile. Only the first load shows
  /// the splash screen; later refreshes keep the current screen.
  Future<void> loadProfile() async {
    final uid = user?.id;
    if (uid == null) {
      profile = null;
      _loading = false;
      notifyListeners();
      return;
    }
    if (profile == null || profile!.id != uid) {
      _loading = true;
      notifyListeners();
    }
    try {
      final row = await _sb.from('profiles').select('*, wards(name)').eq('id', uid).single();
      profile = Profile.fromMap(row);
      loadError = null;
    } catch (e) {
      loadError = friendlyError(e);
    }
    _loading = false;
    notifyListeners();
  }

  // ---------- Option 1: email code (Supabase Auth) ----------

  Future<void> sendEmailOtp(String email) async {
    method = LoginMethod.email;
    pendingEmail = email.trim().toLowerCase();
    await _sb.auth.signInWithOtp(email: pendingEmail!, shouldCreateUser: true);
  }

  Future<void> resendEmailOtp() => _sb.auth.signInWithOtp(email: pendingEmail!, shouldCreateUser: true);

  /// On success Supabase emits `signedIn`, which loads the profile and lets the
  /// router move on.
  Future<void> verifyEmailOtp(String code) async {
    await _sb.auth.verifyOTP(type: OtpType.email, email: pendingEmail!, token: code);
  }

  // ---------- Option 2: SMS code (Node + Fast2SMS) ----------

  void choosePhone(String phone) {
    method = LoginMethod.phone;
    pendingPhone = phone.trim();
  }

  Future<Map<String, dynamic>> sendPhoneOtp() =>
      ApiService.post('/api/auth/phone/send-otp', {'phone': pendingPhone});

  /// The server checks the SMS code and returns a one-time token hash, which
  /// Supabase exchanges for a normal session (→ `signedIn` event).
  Future<void> verifyPhoneOtp(String otp) async {
    final res = await ApiService.post('/api/auth/phone/verify-otp', {'phone': pendingPhone, 'otp': otp});
    await _sb.auth.verifyOTP(type: OtpType.email, tokenHash: res['token_hash'] as String);
  }

  // ---------- Profile ----------

  Future<void> saveProfile({
    required String fullName,
    required int wardId,
    required String residentId,
  }) async {
    await _sb.from('profiles').update({
      'full_name': fullName.trim(),
      'ward_id': wardId,
      'resident_id': residentId.trim().toUpperCase(),
    }).eq('id', user!.id);
    await loadProfile();
  }

  Future<void> signOut() async {
    pendingEmail = null;
    pendingPhone = null;
    await _sb.auth.signOut();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
