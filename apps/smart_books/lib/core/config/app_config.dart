/// Variables inyectadas en build/run (nunca commitear secretos).
class AppConfig {
  AppConfig._();

  static const supabaseUrlRaw = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKeyRaw = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Alias usados por el resto de la app (URL normalizada cuando es válida).
  static String get supabaseUrl =>
      _validated?.normalizedUrl ?? supabaseUrlRaw.trim();
  static String get supabaseAnonKey => supabaseAnonKeyRaw.trim();

  /// Origen del proyecto (sin path, query ni fragment).
  static Uri get supabaseOrigin {
    _validated ??= _validateSupabase();
    final raw = _validated?.normalizedUrl ?? supabaseUrlRaw.trim();
    return _originFrom(Uri.parse(raw.contains('://') ? raw : 'https://$raw'));
  }

  /// Endpoint GoTrue para login email/contraseña.
  static Uri get supabaseAuthTokenUri =>
      supabaseOrigin.replace(path: '/auth/v1/token');

  /// @deprecated Preferir [supabaseAuthTokenUri].
  static String get supabaseAuthTokenUrl => supabaseAuthTokenUri.toString();

  static _ValidatedSupabase? _validated;

  static bool get supabaseReady {
    _validated ??= _validateSupabase();
    return _validated!.ok;
  }

  /// Mensaje en español para pantalla de configuración / login (sin secretos).
  static String? get supabaseConfigError {
    _validated ??= _validateSupabase();
    return _validated!.ok ? null : _validated!.message;
  }

  static _ValidatedSupabase _validateSupabase() {
    final urlRaw = supabaseUrlRaw.trim();
    final keyRaw = supabaseAnonKeyRaw.trim();

    if (urlRaw.isEmpty || keyRaw.isEmpty) {
      return _ValidatedSupabase.fail(
        'Faltan SUPABASE_URL y SUPABASE_ANON_KEY. Ejecuta con --dart-define o dart_defines.json (ver README).',
      );
    }

    if (_isPlaceholder(urlRaw) || _isPlaceholder(keyRaw)) {
      return _ValidatedSupabase.fail(
        'Las variables Supabase siguen siendo valores de ejemplo («...»). '
        'Sustitúyelas por la URL https://TU_PROYECTO.supabase.co y la clave pública (anon / sb_publishable_).',
      );
    }

    if (keyRaw.toLowerCase().contains('service_role') ||
        keyRaw.startsWith('sb_secret_')) {
      return _ValidatedSupabase.fail(
        'La clave parece ser service_role o secreta. Usa solo la clave pública (anon o sb_publishable_).',
      );
    }

    var normalized = urlRaw;
    if (!normalized.contains('://')) {
      normalized = 'https://$normalized';
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) {
      return _ValidatedSupabase.fail(
        'SUPABASE_URL no tiene un host válido. Debe ser como https://abcdefgh.supabase.co',
      );
    }

    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' &&
            (uri.host == 'localhost' || uri.host == '127.0.0.1'))) {
      return _ValidatedSupabase.fail(
        'SUPABASE_URL debe usar HTTPS (excepto localhost en desarrollo).',
      );
    }

    if (keyRaw.length < 20) {
      return _ValidatedSupabase.fail(
        'SUPABASE_ANON_KEY parece demasiado corta o inválida.',
      );
    }

    // Origen limpio: uri.replace(path:'') deja «?#» y rompe «$base/auth/v1/...» (path vacío).
    var base = _originFrom(uri).toString();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    for (final suffix in ['/auth/v1', '/rest/v1', '/storage/v1']) {
      if (base.endsWith(suffix)) {
        base = base.substring(0, base.length - suffix.length);
      }
    }

    return _ValidatedSupabase.ok(base, keyRaw);
  }

  static Uri _originFrom(Uri uri) {
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
  }

  static bool _isPlaceholder(String value) {
    final v = value.trim().toLowerCase();
    if (v == '...' || v == '…') return true;
    if (v.contains('tu_proyecto') || v.contains('tu_anon')) return true;
    if (v.startsWith('https://...') || v == 'https://tu_proyecto.supabase.co')
      return true;
    return false;
  }

  static const chatgptOAuthPort = 1455;
  static const chatgptAgentName = 'Smart Books';
  static const chatgptPlanScope = 'chatgpt.tokens.use.direct';
  static const chatgptAuthUrl =
      'https://auth.openai.com/api/accounts/authorize';
  static const chatgptTokenUrl =
      'https://auth.openai.com/api/accounts/oauth/token';
  static const chatgptResource = 'https://api.openai.com/v1';
  static const chatgptResponsesUrl = 'https://api.openai.com/v1/responses';
  static const chatgptModelsUrl = 'https://api.openai.com/v1/models';
}

class _ValidatedSupabase {
  _ValidatedSupabase._({
    required this.ok,
    this.message,
    this.normalizedUrl,
    this.anonKey,
  });

  factory _ValidatedSupabase.ok(String url, String key) =>
      _ValidatedSupabase._(ok: true, normalizedUrl: url, anonKey: key);

  factory _ValidatedSupabase.fail(String message) =>
      _ValidatedSupabase._(ok: false, message: message);

  final bool ok;
  final String? message;
  final String? normalizedUrl;
  final String? anonKey;
}
