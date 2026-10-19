import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Cliente HTTP para Supabase: corrige rutas GoTrue mal resueltas y el Bearer
/// con claves `sb_publishable_` (GoTrue aún envía Bearer; la API espera solo apikey).
class SupabaseHttpClient extends http.BaseClient {
  SupabaseHttpClient({http.Client? inner, String? supabaseHost, String? apiKey})
    : _inner = inner ?? http.Client(),
      _host = supabaseHost ?? Uri.parse(AppConfig.supabaseUrl).host,
      _apiKey = apiKey ?? AppConfig.supabaseAnonKey;

  final http.Client _inner;
  final String _host;
  final String _apiKey;

  static const _gotrueRootPaths = {
    '/token',
    '/signup',
    '/logout',
    '/user',
    '/verify',
    '/recover',
    '/authorize',
    '/callback',
    '/otp',
    '/sso',
  };

  static const _tokenGrantTypes = {
    'password',
    'refresh_token',
    'pkce',
    'authorization_code',
    'id_token',
    'web3',
  };

  /// URI que se enviará tras aplicar correcciones (para logs).
  Uri resolveOutgoingUri(http.BaseRequest request) =>
      _fixGoTruePath(request.url, request);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _maybeStripPublishableBearer(request);

    final fixed = _fixGoTruePath(request.url, request);
    if (fixed == request.url) {
      return _inner.send(request);
    }

    if (request is http.Request) {
      final clone = http.Request(request.method, fixed)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes
        ..encoding = request.encoding
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection;
      return _inner.send(clone);
    }

    final streamed = http.StreamedRequest(request.method, fixed);
    request.headers.forEach((key, value) {
      streamed.headers[key] = value;
    });
    streamed.followRedirects = request.followRedirects;
    streamed.maxRedirects = request.maxRedirects;
    streamed.persistentConnection = request.persistentConnection;
    await request.finalize().pipe(streamed.sink);
    return _inner.send(streamed);
  }

  void _maybeStripPublishableBearer(http.BaseRequest request) {
    if (!_apiKey.startsWith('sb_publishable_')) return;
    final auth = request.headers['Authorization'];
    if (auth == 'Bearer $_apiKey') {
      request.headers.remove('Authorization');
    }
  }

  Uri _fixGoTruePath(Uri uri, http.BaseRequest request) {
    if (uri.host != _host) return uri;
    if (uri.path.startsWith('/auth/v1')) return uri;

    final path = uri.path.isEmpty ? '/' : uri.path;

    if (_gotrueRootPaths.contains(path) ||
        _gotrueRootPaths.any((p) => path.startsWith('$p/'))) {
      return uri.replace(path: '/auth/v1$path');
    }

    // POST a la raíz del proyecto con grant_type (p. ej. ?grant_type=password) → 404 «requested path is invalid».
    if (request.method == 'POST' && (path == '/' || uri.path.isEmpty)) {
      if (_isGoTrueTokenRequest(uri, request)) {
        return uri.replace(path: '/auth/v1/token');
      }
      if (_looksLikeSignupBody(request)) {
        return uri.replace(path: '/auth/v1/signup');
      }
    }

    return uri;
  }

  bool _isGoTrueTokenRequest(Uri uri, http.BaseRequest request) {
    final grant = uri.queryParameters['grant_type'];
    if (grant != null && _tokenGrantTypes.contains(grant)) return true;
    if (request is http.Request) {
      try {
        final body = jsonDecode(request.body);
        if (body is Map &&
            (body.containsKey('refresh_token') ||
                body.containsKey('auth_code') ||
                (body.containsKey('password') &&
                    (body.containsKey('email') ||
                        body.containsKey('phone'))))) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  bool _looksLikeSignupBody(http.BaseRequest request) {
    if (request is! http.Request) return false;
    try {
      final body = jsonDecode(request.body);
      return body is Map &&
          body.containsKey('password') &&
          (body.containsKey('email') || body.containsKey('phone'));
    } catch (_) {
      return false;
    }
  }

  @override
  void close() => _inner.close();
}
