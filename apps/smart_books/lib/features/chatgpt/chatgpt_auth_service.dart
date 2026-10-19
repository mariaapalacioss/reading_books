import 'dart:async';
import 'dart:convert';

import '../../core/config/app_config.dart';
import 'chatgpt_credentials.dart';
import 'chatgpt_oauth_browser.dart';
import 'chatgpt_oauth_log.dart';
import 'chatgpt_platform.dart';
import 'credential_store.dart';
import 'host_id.dart';
import 'oauth_loopback_server.dart';
import 'pkce.dart';

class ChatGptAuthService {
  ChatGptAuthService({
    ChatGptCredentialStore? store,
    OAuthLoopbackServer? loopback,
  }) : _store = store ?? ChatGptCredentialStore(),
       _loopback = loopback ?? OAuthLoopbackServer();

  final ChatGptCredentialStore _store;
  final OAuthLoopbackServer _loopback;

  Future<ChatGptCredentials?> load(String smartbooksUserId) =>
      _store.load(smartbooksUserId);

  Future<ChatGptCredentials?> loadPending() => _store.loadPending();

  Future<void> signOut(String smartbooksUserId) =>
      _store.clear(smartbooksUserId);

  Future<void> signOutPending() => _store.clearPending();

  Future<bool> adoptPendingForUser(String smartbooksUserId) =>
      _store.adoptPendingForUser(smartbooksUserId);

  /// OAuth ChatGPT; si [sessionUserId] es null guarda credenciales pendientes hasta login Supabase.
  Future<ChatGptCredentials> signInOrLink({String? sessionUserId}) async {
    if (!chatGptConnectEnabled) {
      throw UnsupportedError(
        'ChatGPT Plus solo está disponible en la app para iPhone, iPad y Mac.',
      );
    }
    final linkedUserId = sessionUserId?.trim();
    final persistUserId = (linkedUserId != null && linkedUserId.isNotEmpty)
        ? linkedUserId
        : kChatGptPendingUserId;

    chatGptOAuthLog(
      'Inicio signInOrLink (${persistUserId == kChatGptPendingUserId ? "pre-Supabase" : "usuario ${persistUserId.substring(0, 8)}…"})',
    );

    final existing = persistUserId == kChatGptPendingUserId
        ? await _store.loadPending()
        : await _store.load(persistUserId);
    final hostId = await getOrCreateExtAgentHostId();
    final pkce = createPkce();
    final state = randomState();
    final clientId = existing?.clientId ?? 'dynamic_agent_client';

    chatGptOAuthLog(
      'OAuth loopback ${AppConfig.chatgptOAuthPort} redirect=${_loopback.redirectUri}',
    );

    final params = {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': _loopback.redirectUri,
      'scope': [
        'openid',
        'profile',
        'email',
        'offline_access',
        'resource.invoke',
        AppConfig.chatgptPlanScope,
      ].join(' '),
      'resource': AppConfig.chatgptResource,
      'state': state,
      'nonce': randomState(),
      'code_challenge_method': 'S256',
      'code_challenge': pkce.challenge,
      'ext_agent_host_id': hostId,
    };
    if (existing == null) {
      params['agent_name_hint'] = AppConfig.chatgptAgentName;
      chatGptOAuthLog(
        'Registro nuevo agente (dynamic_agent_client + agent_name_hint)',
      );
    } else if (existing.idToken.isNotEmpty) {
      params['id_token_hint'] = existing.idToken;
      chatGptOAuthLog(
        'Reutilizando client_id guardado (${existing.clientId.substring(0, 8)}…)',
      );
    }
    if (existing?.email != null) {
      params['login_hint'] = existing!.email!;
    }

    final authUri = Uri.parse(
      AppConfig.chatgptAuthUrl,
    ).replace(queryParameters: params);
    chatGptOAuthLog('Abriendo autorización: ${AppConfig.chatgptAuthUrl}');

    OAuthCallbackResult callback;
    try {
      callback = await runChatGptOAuthBrowserFlow(
        loopback: _loopback,
        authUri: authUri,
      );
    } on TimeoutException {
      throw Exception(
        'Tiempo agotado esperando la autorización (2 min). '
        'Vuelve a intentar y completa el consentimiento en la ventana de OpenAI.',
      );
    }

    chatGptOAuthLog('Callback recibido (state OK: ${callback.state == state})');
    if (callback.state != state) {
      throw Exception('Estado OAuth inválido. Intenta de nuevo.');
    }
    final issuedClientId =
        callback.clientId.isNotEmpty &&
            callback.clientId != 'dynamic_agent_client'
        ? callback.clientId
        : clientId;
    chatGptOAuthLog(
      'Intercambiando código por tokens (client_id emitido: ${issuedClientId.substring(0, 8)}…)',
    );

    final token = await _loopback.exchangeAuthorizationCode(
      code: callback.code,
      codeVerifier: pkce.verifier,
      clientId: issuedClientId,
    );

    final idToken = token['id_token']?.toString() ?? '';
    final claims = _decodeJwtPayload(idToken);
    var record = ChatGptCredentials.fromTokenResponse(
      token: token,
      clientId: issuedClientId,
      hostId: hostId,
      smartbooksUserId: persistUserId,
      email: claims?['email'] as String?,
      subject: claims?['sub'] as String?,
    );

    chatGptOAuthLog(
      'Token recibido; scopes concedidos: ${record.scopes.isEmpty ? "(vacío)" : record.scopes.join(", ")}; '
      'plan direct: ${record.hasPlanUsage}',
    );

    if (!record.hasPlanUsage) {
      throw Exception(
        'OpenAI no concedió el permiso «chatgpt.tokens.use.direct». '
        'Acepta compartir tu plan ChatGPT en la pantalla de consentimiento.',
      );
    }

    if (persistUserId == kChatGptPendingUserId) {
      await _store.savePending(record);
      chatGptOAuthLog(
        'Credenciales guardadas (pendientes hasta login Supabase).',
      );
    } else {
      await _store.save(record);
      chatGptOAuthLog(
        'Credenciales guardadas en llavero para este usuario Smart Books.',
      );
    }
    return record;
  }

  /// Compatibilidad con pantallas que ya tienen userId Supabase.
  Future<ChatGptCredentials> signIn(String smartbooksUserId) =>
      signInOrLink(sessionUserId: smartbooksUserId);

  Map<String, dynamic>? _decodeJwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    var payload = parts[1];
    payload = payload.padRight(
      payload.length + (4 - payload.length % 4) % 4,
      '=',
    );
    try {
      return jsonDecode(utf8.decode(base64Url.decode(payload)))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
