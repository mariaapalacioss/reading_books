import 'dart:io';
import 'debug_http_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'supabase_auth_deeplink.dart';
import 'supabase_auth_log.dart';

Future<void> initializeSupabase() async {
  final url = AppConfig.supabaseUrl;
  final key = AppConfig.supabaseAnonKey;
  final host = Uri.parse(url).host;
  supabaseAuthLog(
    'Inicializando Supabase host=$host authTokenPath=/auth/v1/token keyFormat=${_keyKind(key)}',
  );

  // Hot restart: Supabase.initialize ignora un segundo init; liberar instancia previa.
  try {
    await Supabase.instance.dispose();
    supabaseAuthLog('Instancia Supabase previa liberada (hot restart)');
  } catch (_) {
    // Arranque en frío: aún no hay Supabase.instance.
  }

  await Supabase.initialize(
    url: url,
    publishableKey: key,
    httpClient: DebugHttpClient(supabaseHost: host, apiKey: key),
    authOptions: FlutterAuthClientOptions(
      // macOS: solo email/contraseña; deep links (p. ej. `code` de ChatGPT) no deben
      // disparar getSessionFromUrl → 404 «requested path is invalid» en /token.
      detectSessionInUri: !Platform.isMacOS,
      detectSessionInUriPredicate: isSupabaseAuthDeepLink,
    ),
  );
  supabaseAuthLog('Supabase listo');
}

String _keyKind(String key) {
  if (key.startsWith('sb_publishable_')) return 'sb_publishable';
  if (key.startsWith('eyJ')) return 'jwt_anon';
  return 'other';
}
