import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/core/config/app_config.dart';

void main() {
  test('supabaseReady false cuando faltan defines en test runner', () {
    if (AppConfig.supabaseUrlRaw.isNotEmpty) return;
    expect(AppConfig.supabaseReady, isFalse);
    expect(AppConfig.supabaseConfigError, isNotNull);
  });
}

/// Con `--dart-define-from-file=dart_defines.json` (ver test/app_config_uri_test.dart).
