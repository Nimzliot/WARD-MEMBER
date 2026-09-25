import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class ApiException implements Exception {
  final int statusCode; // 0 = network problem
  final String message;
  final Map<String, dynamic> body;

  ApiException(this.statusCode, this.message, [this.body = const {}]);

  @override
  String toString() => message;
}

/// Calls the Node API with the current Supabase access token.
class ApiService {
  static GoTrueClient get _auth => Supabase.instance.client.auth;

  /// Swappable for tests (e.g. package:http/testing.dart MockClient).
  static http.Client client = http.Client();

  static Future<Map<String, dynamic>> get(String path) => _send('GET', path);

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _send('POST', path, body);

  static Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) =>
      _send('PATCH', path, body);

  static Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  static Future<Map<String, dynamic>> _send(String method, String path,
      [Map<String, dynamic>? body]) async {
    var session = _auth.currentSession;
    if (session != null && session.isExpired) {
      session = (await _auth.refreshSession()).session;
    }

    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final headers = {
      'Content-Type': 'application/json',
      // Harmless elsewhere; stops ngrok's free-tier warning page when tunnelling.
      'ngrok-skip-browser-warning': 'true',
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    };

    http.Response res;
    try {
      final request = switch (method) {
        'GET' => client.get(uri, headers: headers),
        'DELETE' => client.delete(uri, headers: headers),
        'PATCH' => client.patch(uri, headers: headers, body: jsonEncode(body ?? {})),
        _ => client.post(uri, headers: headers, body: jsonEncode(body ?? {})),
      };
      // Generous timeout: a free Render instance can take ~50 s to wake up.
      res = await request.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw ApiException(0, 'The server took too long to respond. Please try again.');
    } catch (_) {
      throw ApiException(0, 'Cannot reach the server at ${AppConfig.apiBaseUrl}. Is it running?');
    }

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}

    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        data['error']?.toString() ?? 'Request failed (${res.statusCode})',
        data,
      );
    }
    return data;
  }
}
