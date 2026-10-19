import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/features/chatgpt/chatgpt_oauth_browser.dart';

void main() {
  test('parseOAuthCallbackUri extrae code, state y client_id', () {
    final result = parseOAuthCallbackUri(
      Uri.parse(
        'http://127.0.0.1:1455/auth/callback?code=abc123&state=xyz&client_id=oaiapp_test',
      ),
    );
    expect(result.code, 'abc123');
    expect(result.state, 'xyz');
    expect(result.clientId, 'oaiapp_test');
  });

  test('parseOAuthCallbackUri rechaza error OAuth', () {
    expect(
      () => parseOAuthCallbackUri(
        Uri.parse('http://127.0.0.1:1455/auth/callback?error=access_denied'),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
