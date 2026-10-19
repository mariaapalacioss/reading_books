import 'dart:convert';

import 'package:http/http.dart' as http;

import 'supabase_http_client.dart';

/// Registra la URL solicitada y la URL efectiva tras correcciones (sin cuerpos ni secretos).
class DebugHttpClient extends SupabaseHttpClient {
  DebugHttpClient({super.supabaseHost, super.apiKey})
    : super(inner: http.Client());

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final before = request.url;
    final after = resolveOutgoingUri(request);
    print(
      '[HTTP] ${request.method} ${_describe(before)} → ${_describe(after)}',
    );

    final response = await super.send(request);

    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      print(
        '[HTTP] STATUS ${response.statusCode} ${body.length > 280 ? '${body.substring(0, 280)}…' : body}',
      );
      return http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        response.statusCode,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
        request: response.request,
      );
    }
    print('[HTTP] STATUS ${response.statusCode}');
    return response;
  }

  static String _describe(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    final q = uri.hasQuery ? '?${uri.query}' : '';
    return '${uri.scheme}://${uri.host}$path$q';
  }
}
