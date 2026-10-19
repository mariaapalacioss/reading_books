import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_books/core/supabase/supabase_http_client.dart';

void main() {
  test('reescribe POST /token hacia /auth/v1/token', () async {
    Uri? captured;
    final inner = _CaptureClient((r) => captured = r.url);
    final client = SupabaseHttpClient(
      inner: inner,
      supabaseHost: 'example.supabase.co',
      apiKey: 'sb_publishable_test',
    );

    await client.post(
      Uri.parse('https://example.supabase.co/token?grant_type=password'),
      headers: {
        'apikey': 'sb_publishable_test',
        'Authorization': 'Bearer sb_publishable_test',
      },
      body: '{}',
    );

    expect(captured!.path, '/auth/v1/token');
    expect(captured!.queryParameters['grant_type'], 'password');
    expect(inner.lastHeaders.containsKey('Authorization'), isFalse);
  });

  test('reescribe POST raíz con grant_type=password', () async {
    Uri? captured;
    final inner = _CaptureClient((r) => captured = r.url);
    final client = SupabaseHttpClient(
      inner: inner,
      supabaseHost: 'example.supabase.co',
      apiKey: 'sb_publishable_test',
    );

    await client.post(
      Uri.parse('https://example.supabase.co?grant_type=password'),
      headers: {
        'apikey': 'sb_publishable_test',
        'Content-Type': 'application/json',
      },
      body: '{"email":"a@b.com","password":"secret"}',
    );

    expect(captured!.path, '/auth/v1/token');
    expect(captured!.queryParameters['grant_type'], 'password');
  });
}

class _CaptureClient extends http.BaseClient {
  _CaptureClient(this._onSend);

  final void Function(http.BaseRequest) _onSend;
  Map<String, String> lastHeaders = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _onSend(request);
    lastHeaders = Map.from(request.headers);
    return http.StreamedResponse(Stream.value([]), 200);
  }
}
