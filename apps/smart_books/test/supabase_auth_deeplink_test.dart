import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/core/config/app_config.dart';
import 'package:smart_books/core/supabase/supabase_auth_deeplink.dart';

void main() {
  test('ignora callback loopback ChatGPT (code en 127.0.0.1)', () {
    final uri = Uri.parse(
      'http://127.0.0.1:1455/auth/callback?code=abc&state=xyz',
    );
    expect(isSupabaseAuthDeepLink(uri), isFalse);
  });

  test('acepta solo host del proyecto Supabase', () {
    if (!AppConfig.supabaseReady) return;
    final host = Uri.parse(AppConfig.supabaseUrl).host;
    final ok = Uri.parse('https://$host/auth/v1/callback?code=abc');
    expect(isSupabaseAuthDeepLink(ok), isTrue);
    expect(
      isSupabaseAuthDeepLink(Uri.parse('https://evil.example.com/?code=abc')),
      isFalse,
    );
  });

  test(
    'ignora code en la raíz del proyecto (evita 404 requested path is invalid)',
    () {
      if (!AppConfig.supabaseReady) return;
      final host = Uri.parse(AppConfig.supabaseUrl).host;
      expect(
        isSupabaseAuthDeepLink(Uri.parse('https://$host/?code=abc')),
        isFalse,
      );
    },
  );
}
