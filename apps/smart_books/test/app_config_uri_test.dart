import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/core/config/app_config.dart';

void main() {
  test('supabaseUrl normalizada sin ?# y token con path /auth/v1/token', () {
    expect(
      AppConfig.supabaseReady,
      isTrue,
      reason: AppConfig.supabaseConfigError,
    );
    expect(AppConfig.supabaseUrl, isNot(contains('?#')));
    expect(AppConfig.supabaseUrl, 'https://iqgpuohbjgknjrszmojy.supabase.co');

    final token = AppConfig.supabaseAuthTokenUri;
    expect(token.path, '/auth/v1/token');

    final withGrant = token.replace(
      queryParameters: {'grant_type': 'password'},
    );
    expect(withGrant.path, '/auth/v1/token');
    expect(withGrant.queryParameters['grant_type'], 'password');
    expect(withGrant.fragment, isEmpty);
  });
}
