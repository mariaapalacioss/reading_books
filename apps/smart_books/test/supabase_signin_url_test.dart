import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_books/core/supabase/supabase_http_client.dart';
import 'package:supabase/supabase.dart';

void main() {
  test('signInWithPassword usa /auth/v1/token en el host del proyecto', () async {
    final sent = <Uri>[];
    final inner = _CaptureClient(sent);
    final client = SupabaseHttpClient(
      inner: inner,
      supabaseHost: 'iqgpuohbjgknjrszmojy.supabase.co',
      apiKey: 'sb_publishable_test_key_1234567890',
    );

    final supabase = SupabaseClient(
      'https://iqgpuohbjgknjrszmojy.supabase.co',
      'sb_publishable_test_key_1234567890',
      httpClient: client,
    );

    try {
      await supabase.auth.signInWithPassword(
        email: 'probe@example.com',
        password: 'probe-password',
      );
    } catch (_) {}

    expect(sent, isNotEmpty);
    final authPost = sent.firstWhere(
      (u) => u.host == 'iqgpuohbjgknjrszmojy.supabase.co',
      orElse: () => sent.first,
    );
    expect(
      authPost.path,
      '/auth/v1/token',
      reason:
          'URLs enviadas: ${sent.map((u) => '${u.host}${u.path}?${u.query}').join(', ')}',
    );
    expect(authPost.queryParameters['grant_type'], 'password');
  });
}

class _CaptureClient extends http.BaseClient {
  _CaptureClient(this.sent);
  final List<Uri> sent;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request.url);
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"msg":"invalid","code":400}')),
      400,
      headers: {'content-type': 'application/json'},
    );
  }
}
