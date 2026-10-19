import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/supabase/supabase_auth_log.dart';
import 'chatgpt_oauth_log.dart';
import 'plan_api.dart';

class ChatGptVerifyResult {
  const ChatGptVerifyResult({
    required this.ok,
    required this.summary,
    this.detail,
  });

  final bool ok;
  final String summary;
  final String? detail;
}

/// Comprueba que hay credenciales persistidas y que el access token funciona contra la API oficial.
class ChatGptVerifyService {
  ChatGptVerifyService(this._ref);

  final Ref _ref;

  Future<ChatGptVerifyResult> verify({String? supabaseUserId}) async {
    final auth = _ref.read(chatGptAuthServiceProvider);
    final userId =
        supabaseUserId ??
        _ref.read(supabaseClientProvider).auth.currentUser?.id;

    final creds = userId != null
        ? await auth.load(userId)
        : await auth.loadPending();
    if (creds == null) {
      return const ChatGptVerifyResult(
        ok: false,
        summary: 'No hay credenciales guardadas.',
      );
    }
    if (!creds.hasPlanUsage) {
      return const ChatGptVerifyResult(
        ok: false,
        summary: 'Falta permiso chatgpt.tokens.use.direct en la autorización.',
      );
    }

    chatGptOAuthLog(
      'Verificación: credenciales presentes, probando access token (sin imprimir secretos)',
    );
    if (userId == null) {
      return ChatGptVerifyResult(
        ok: true,
        summary:
            'Credenciales guardadas (pendientes de vincular al entrar en Supabase).',
        detail: creds.email ?? creds.subject,
      );
    }

    try {
      final api = PlanApi(loopback: _ref.read(oauthLoopbackServerProvider));
      final token = await api.ensureAccessToken(userId);
      if (token.isEmpty) {
        return const ChatGptVerifyResult(
          ok: false,
          summary: 'Token de acceso vacío.',
        );
      }
      final model = await api.preferredModel(userId);
      supabaseAuthLog('ChatGPT verify OK model=$model');
      return ChatGptVerifyResult(
        ok: true,
        summary: 'Conexión funcional · modelo $model',
        detail: creds.email ?? creds.subject,
      );
    } catch (e) {
      chatGptOAuthLog('Verificación falló: $e');
      return ChatGptVerifyResult(
        ok: false,
        summary:
            'No se pudo usar la API con tu plan. Reconecta o revisa el consentimiento Plus.',
        detail: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }
}

final chatGptVerifyServiceProvider = Provider<ChatGptVerifyService>((ref) {
  return ChatGptVerifyService(ref);
});
