import '../config/app_config.dart';

/// Solo URLs de callback de Supabase Auth, nunca loopback ChatGPT ni otros `code`.
bool isSupabaseAuthDeepLink(Uri uri) {
  if (uri.host == '127.0.0.1' || uri.host == 'localhost') return false;

  final projectHost = Uri.parse(AppConfig.supabaseUrl).host;
  if (uri.host != projectHost) return false;

  final fragmentParameters = Uri.splitQueryString(uri.fragment);
  bool hasParameter(String key) =>
      uri.queryParameters.containsKey(key) ||
      fragmentParameters.containsKey(key);

  if (hasParameter('error') ||
      hasParameter('error_code') ||
      hasParameter('error_description')) {
    return true;
  }

  if (hasParameter('access_token')) {
    return uri.path.contains('callback') || uri.path.startsWith('/auth/');
  }

  // `code` aparece en OAuth de ChatGPT (127.0.0.1) y en PKCE de Supabase; exigir ruta Auth.
  if (hasParameter('code')) {
    return uri.path.contains('callback') || uri.path.startsWith('/auth/');
  }

  return false;
}
