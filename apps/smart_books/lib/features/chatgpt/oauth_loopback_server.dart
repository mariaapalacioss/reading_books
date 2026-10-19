import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/config/app_config.dart';
import 'chatgpt_oauth_log.dart';

/// Puente loopback equivalente a `scripts/chatgpt-oauth-bridge.mjs` (macOS).
class OAuthLoopbackServer {
  OAuthLoopbackServer({this.port = AppConfig.chatgptOAuthPort});

  final int port;
  HttpServer? _server;

  String get redirectUri => 'http://127.0.0.1:$port/auth/callback';

  Future<void> ensureListening() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
      _server!.listen(_handle);
      chatGptOAuthLog('HttpServer escuchando en $redirectUri');
    } on SocketException catch (e) {
      chatGptOAuthLog('Error al abrir puerto $port: ${e.message}');
      throw Exception(
        'No se pudo abrir el puerto $port en 127.0.0.1. '
        'Cierra otra instancia de Smart Books o el puente npm de la app web (`npm run dev`). Detalle: ${e.message}',
      );
    }
  }

  @Deprecated('Use ensureListening')
  Future<void> start() => ensureListening();

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    chatGptOAuthLog('HttpServer detenido');
  }

  Future<bool> checkHealth() async {
    await ensureListening();
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/health'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      final ok = response.statusCode == 200;
      chatGptOAuthLog(
        'Health check: ${ok ? "OK" : "HTTP ${response.statusCode}"}',
      );
      return ok;
    } catch (e) {
      chatGptOAuthLog('Health check falló: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> exchangeAuthorizationCode({
    required String code,
    required String codeVerifier,
    required String clientId,
  }) async {
    return _tokenRequest({
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': codeVerifier,
      'resource': AppConfig.chatgptResource,
    });
  }

  Future<Map<String, dynamic>> refreshAccessToken({
    required String clientId,
    required String refreshToken,
  }) async {
    return _tokenRequest({
      'grant_type': 'refresh_token',
      'client_id': clientId,
      'refresh_token': refreshToken,
      'resource': AppConfig.chatgptResource,
    });
  }

  Future<Map<String, dynamic>> _tokenRequest(Map<String, String> body) async {
    final client = HttpClient();
    try {
      chatGptOAuthLog('POST token (${body['grant_type']})');
      final request = await client.postUrl(
        Uri.parse(AppConfig.chatgptTokenUrl),
      );
      request.headers.set('accept', 'application/json');
      request.headers.set('content-type', 'application/x-www-form-urlencoded');
      request.write(
        body.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&'),
      );
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        chatGptOAuthLog(
          'Respuesta token no JSON (HTTP ${response.statusCode})',
        );
        throw Exception(
          'Respuesta inesperada del servidor de tokens (HTTP ${response.statusCode}).',
        );
      }
      if (response.statusCode >= 400) {
        final err = payload['error']?.toString() ?? 'unknown';
        final desc = payload['error_description']?.toString();
        chatGptOAuthLog('Error token: $err${desc != null ? " — $desc" : ""}');
        throw Exception(desc ?? err);
      }
      return payload;
    } finally {
      client.close(force: true);
    }
  }

  Future<OAuthCallbackResult> waitForAuthorization({
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (_pendingAuth != null && !_pendingAuth!.isCompleted) {
      chatGptOAuthLog('Cancelando espera OAuth anterior');
      _pendingAuth!.completeError(Exception('Nueva autorización iniciada'));
    }
    final completer = Completer<OAuthCallbackResult>();
    _pendingAuth = completer;
    chatGptOAuthLog(
      'Esperando callback OAuth (timeout ${timeout.inSeconds}s)…',
    );
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      rethrow;
    } finally {
      if (identical(_pendingAuth, completer)) {
        _pendingAuth = null;
      }
    }
  }

  Completer<OAuthCallbackResult>? _pendingAuth;

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/health') {
        _json(request, 200, {'ok': true, 'redirectUri': redirectUri});
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/auth/callback') {
        chatGptOAuthLog(
          'GET /auth/callback desde ${request.connectionInfo?.remoteAddress}',
        );
        final error = request.uri.queryParameters['error'];
        if (error != null) {
          chatGptOAuthLog('OAuth error query: $error');
          _pendingAuth?.completeError(
            Exception('Autorización rechazada: $error'),
          );
          _html(
            request,
            'Smart Books',
            '<p>Autorización cancelada ($error). Vuelve a Smart Books.</p>',
          );
          return;
        }
        final code = request.uri.queryParameters['code'];
        final state = request.uri.queryParameters['state'] ?? '';
        final clientId = request.uri.queryParameters['client_id'] ?? '';
        if (code == null || code.isEmpty) {
          chatGptOAuthLog('Callback sin code');
          _text(request, 400, 'Falta code');
          return;
        }
        chatGptOAuthLog(
          'Callback con code (state len=${state.length}, client_id presente=${clientId.isNotEmpty})',
        );
        _pendingAuth?.complete(
          OAuthCallbackResult(code: code, state: state, clientId: clientId),
        );
        _html(
          request,
          'Smart Books',
          '<p>ChatGPT conectado. Puedes cerrar esta ventana y volver a Smart Books.</p>',
        );
        return;
      }

      _text(request, 404, 'Not found');
    } catch (error) {
      chatGptOAuthLog('Error manejando request: $error');
      _json(request, 500, {'error': error.toString()});
    }
  }

  void _json(HttpRequest request, int status, Map<String, dynamic> body) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    request.response.close();
  }

  void _text(HttpRequest request, int status, String body) {
    request.response.statusCode = status;
    request.response.write(body);
    request.response.close();
  }

  void _html(HttpRequest request, String title, String body) {
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.html;
    request.response.write(
      '<!doctype html><html lang="es"><head><meta charset="utf-8"/><title>$title</title></head><body>$body</body></html>',
    );
    request.response.close();
  }
}

class OAuthCallbackResult {
  OAuthCallbackResult({
    required this.code,
    required this.state,
    required this.clientId,
  });

  final String code;
  final String state;
  final String clientId;
}
