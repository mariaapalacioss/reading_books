import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_auth_log.dart';

/// Mensajes de error comprensibles sin filtrar secretos.
String friendlyAuthError(Object error) {
  if (error is AuthException) {
    supabaseAuthLog(
      'AuthException status=${error.statusCode} msg=${error.message}',
    );
    final msg = error.message;
    if (msg.toLowerCase().contains('invalid login') ||
        msg.toLowerCase().contains('invalid_credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (msg.toLowerCase().contains('email not confirmed')) {
      return 'Confirma tu correo antes de entrar (revisa tu bandeja de entrada).';
    }
    if (msg.toLowerCase().contains('rate limit') ||
        msg.toLowerCase().contains('too many requests')) {
      return 'Demasiados intentos. Espera un momento e inténtalo otra vez.';
    }
    if (msg.contains('requested path is invalid')) {
      return 'No se pudo contactar con el servicio de acceso de Supabase (ruta incorrecta). '
          'Comprueba SUPABASE_URL en dart_defines.json (solo la base https://TU_PROYECTO.supabase.co), '
          'reconstruye con --dart-define-from-file y vuelve a pulsar Entrar. ChatGPT y Supabase son independientes.';
    }
    return msg;
  }
  final text = error.toString();
  supabaseAuthLog(
    'Auth error: ${text.replaceAll(RegExp(r'password=\S+'), 'password=***')}',
  );
  if (text.contains('No host specified in URI')) {
    return 'Supabase no está configurado: la URL del proyecto es inválida. '
        'Revisa dart_defines.json o --dart-define=SUPABASE_URL.';
  }
  if (text.contains('SocketException') || text.contains('Failed host lookup')) {
    return 'No hay conexión con el servidor. Comprueba tu red y la URL de Supabase.';
  }
  return text
      .replaceFirst('Exception: ', '')
      .replaceFirst('AuthException: ', '');
}
