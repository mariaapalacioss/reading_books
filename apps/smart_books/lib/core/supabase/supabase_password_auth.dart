import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'supabase_auth_log.dart';
import 'supabase_http_client.dart';

/// Login/registro email+contraseña con rutas GoTrue explícitas (evita POST a la raíz del proyecto).
class SupabasePasswordAuth {
  SupabasePasswordAuth({SupabaseHttpClient? httpClient})
    : _http =
          httpClient ??
          SupabaseHttpClient(
            supabaseHost: Uri.parse(AppConfig.supabaseUrl).host,
            apiKey: AppConfig.supabaseAnonKey,
          );

  final SupabaseHttpClient _http;

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final uri = AppConfig.supabaseAuthTokenUri.replace(
      queryParameters: {'grant_type': 'password'},
    );
    supabaseAuthLog('password grant POST ${uri.host}${uri.path}?${uri.query}');

    final response = await _http.post(
      uri,
      headers: _headers(),
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'gotrue_meta_security': {'captcha_token': null},
      }),
    );

    return _finishAuthResponse(response);
  }

  Future<void> resetPasswordForEmail({required String email}) async {
    final uri = AppConfig.supabaseOrigin.replace(path: '/auth/v1/recover');
    supabaseAuthLog('recover POST ${uri.host}${uri.path}');

    final response = await _http.post(
      uri,
      headers: _headers(),
      body: jsonEncode({'email': email.trim()}),
    );

    final body = response.body.isEmpty ? '{}' : response.body;
    Map<String, dynamic> jsonMap;
    try {
      jsonMap = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw AuthException(
        'Respuesta inválida del servidor (${response.statusCode}).',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          jsonMap['msg']?.toString() ??
          jsonMap['message']?.toString() ??
          jsonMap['error']?.toString() ??
          jsonMap['error_description']?.toString() ??
          'Error HTTP ${response.statusCode}';
      throw AuthException(
        message,
        statusCode: response.statusCode.toString(),
        code: jsonMap['code']?.toString() ?? jsonMap['error_code']?.toString(),
      );
    }
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    final uri = AppConfig.supabaseOrigin.replace(path: '/auth/v1/signup');
    supabaseAuthLog('signup POST ${uri.host}${uri.path}');

    final response = await _http.post(
      uri,
      headers: _headers(),
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        if (data != null) 'data': data,
        'gotrue_meta_security': {'captcha_token': null},
      }),
    );

    return _finishAuthResponse(response);
  }

  Map<String, String> _headers() => {
    'apikey': AppConfig.supabaseAnonKey,
    'Content-Type': 'application/json',
    'X-Supabase-Api-Version': '2024-01-01',
  };

  Future<AuthResponse> _finishAuthResponse(http.Response response) async {
    final body = response.body.isEmpty ? '{}' : response.body;
    Map<String, dynamic> jsonMap;
    try {
      jsonMap = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw AuthException(
        'Respuesta inválida del servidor (${response.statusCode}).',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          jsonMap['msg']?.toString() ??
          jsonMap['message']?.toString() ??
          jsonMap['error']?.toString() ??
          jsonMap['error_description']?.toString() ??
          'Error HTTP ${response.statusCode}';
      throw AuthException(
        message,
        statusCode: response.statusCode.toString(),
        code: jsonMap['code']?.toString() ?? jsonMap['error_code']?.toString(),
      );
    }

    final authResponse = AuthResponse.fromJson(jsonMap);
    final session = authResponse.session;
    if (session != null && session.accessToken.isNotEmpty) {
      // recoverSession evita GET /user con rutas mal resueltas (setSession llama getUser).
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode(session.toJson()),
      );
    }
    return authResponse;
  }
}
