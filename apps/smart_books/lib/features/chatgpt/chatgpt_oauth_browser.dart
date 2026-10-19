import 'dart:async';
import 'dart:io';

import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chatgpt_oauth_log.dart';
import 'oauth_loopback_server.dart';

OAuthCallbackResult parseOAuthCallbackUri(Uri uri) {
  final error = uri.queryParameters['error'];
  if (error != null && error.isNotEmpty) {
    throw Exception('Autorización rechazada: $error');
  }
  final code = uri.queryParameters['code'];
  if (code == null || code.isEmpty) {
    throw Exception('El callback OAuth no incluyó un código de autorización.');
  }
  return OAuthCallbackResult(
    code: code,
    state: uri.queryParameters['state'] ?? '',
    clientId: uri.queryParameters['client_id'] ?? '',
  );
}

/// Abre la autorización OpenAI y devuelve el callback (PKCE + loopback OSS).
Future<OAuthCallbackResult> runChatGptOAuthBrowserFlow({
  required OAuthLoopbackServer loopback,
  required Uri authUri,
  Duration timeout = const Duration(minutes: 2),
}) async {
  if (Platform.isIOS) {
    return _runIosLoopbackWebAuth(
      loopback: loopback,
      authUri: authUri,
      timeout: timeout,
    );
  }
  return _runDesktopLoopbackExternalBrowser(
    loopback: loopback,
    authUri: authUri,
    timeout: timeout,
  );
}

/// iOS: ASWebAuthenticationSession captura `http://127.0.0.1:PORT/auth/callback`.
Future<OAuthCallbackResult> _runIosLoopbackWebAuth({
  required OAuthLoopbackServer loopback,
  required Uri authUri,
  required Duration timeout,
}) async {
  final redirect = Uri.parse(loopback.redirectUri);
  chatGptOAuthLog(
    'iOS WebAuth redirect=${loopback.redirectUri} host=${redirect.host} path=${redirect.path}',
  );

  await loopback.ensureListening();

  try {
    final callbackUrl = await FlutterWebAuth2.authenticate(
      url: authUri.toString(),
      callbackUrlScheme: redirect.scheme,
      options: FlutterWebAuth2Options(
        httpsHost: redirect.host,
        httpsPath: redirect.path,
        preferEphemeral: false,
      ),
    ).timeout(timeout);

    chatGptOAuthLog('iOS WebAuth callback recibido');
    return parseOAuthCallbackUri(Uri.parse(callbackUrl));
  } on TimeoutException {
    rethrow;
  } catch (e) {
    chatGptOAuthLog(
      'iOS WebAuth falló ($e); reintento con Safari + puente local',
    );
    return _runDesktopLoopbackExternalBrowser(
      loopback: loopback,
      authUri: authUri,
      timeout: timeout,
    );
  }
}

/// macOS (y fallback iOS): Safari externo + [HttpServer] en 127.0.0.1.
Future<OAuthCallbackResult> _runDesktopLoopbackExternalBrowser({
  required OAuthLoopbackServer loopback,
  required Uri authUri,
  required Duration timeout,
}) async {
  await loopback.ensureListening();

  final healthy = await loopback.checkHealth();
  if (!healthy) {
    throw Exception(
      'No responde el puente OAuth local en 127.0.0.1:${loopback.port}. '
      'Comprueba que ningún otro proceso use ese puerto.',
    );
  }

  final waitFuture = loopback.waitForAuthorization(timeout: timeout);

  if (!await launchUrl(authUri, mode: LaunchMode.externalApplication)) {
    throw Exception('No se pudo abrir el navegador para autorizar ChatGPT.');
  }

  return waitFuture;
}
