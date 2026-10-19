import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import 'chatgpt_credentials.dart';
import 'credential_store.dart';
import 'oauth_loopback_server.dart';

class PlanApi {
  PlanApi({ChatGptCredentialStore? store, OAuthLoopbackServer? loopback})
    : _store = store ?? ChatGptCredentialStore(),
      _loopback = loopback ?? OAuthLoopbackServer();

  final ChatGptCredentialStore _store;
  final OAuthLoopbackServer _loopback;
  String? _preferredModel;

  Future<String> ensureAccessToken(String userId) async {
    final current = await _store.load(userId);
    if (current == null) {
      throw Exception('Conecta tu ChatGPT Plus desde Ajustes / ChatGPT.');
    }
    if (DateTime.now().millisecondsSinceEpoch < current.expiresAt) {
      return current.accessToken;
    }
    final refreshed = await _loopback.refreshAccessToken(
      clientId: current.clientId,
      refreshToken: current.refreshToken,
    );
    final next = ChatGptCredentials.fromTokenResponse(
      token: refreshed,
      clientId: current.clientId,
      hostId: current.extAgentHostId,
      smartbooksUserId: userId,
      email: current.email,
      subject: current.subject,
    );
    await _store.save(next);
    return next.accessToken;
  }

  Future<String> preferredModel(String userId) async {
    if (_preferredModel != null) return _preferredModel!;
    final token = await ensureAccessToken(userId);
    final response = await http.get(
      Uri.parse(AppConfig.chatgptModelsUrl),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode >= 400) {
      throw Exception('No se pudo listar modelos del plan ChatGPT.');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final models = (payload['models'] as List?) ?? [];
    for (final raw in models) {
      final map = raw as Map<String, dynamic>;
      if (map['visibility'] != 'list') continue;
      final slug = map['slug'] as String? ?? '';
      if (RegExp(
        r'gpt-4|gpt-5|sol|o4|mini',
        caseSensitive: false,
      ).hasMatch(slug)) {
        _preferredModel = slug;
        return slug;
      }
    }
    if (models.isEmpty) throw Exception('Sin modelos disponibles en tu plan.');
    _preferredModel = (models.first as Map)['slug'] as String;
    return _preferredModel!;
  }

  /// Mensajes para `/v1/responses`. [content] puede ser `String` o lista multimodal.
  Future<void> streamResponse({
    required String userId,
    required String instructions,
    required List<Map<String, dynamic>> input,
    required void Function(String delta) onDelta,
  }) async {
    final token = await ensureAccessToken(userId);
    final model = await preferredModel(userId);
    final request = http.Request(
      'POST',
      Uri.parse(AppConfig.chatgptResponsesUrl),
    );
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    });
    request.body = jsonEncode({
      'model': model,
      'instructions': instructions,
      'input': input,
      'store': false,
      'stream': true,
    });
    final client = http.Client();
    final response = await client.send(request);
    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      client.close();
      throw Exception(
        body.isEmpty ? 'ChatGPT HTTP ${response.statusCode}' : body,
      );
    }
    var buffer = '';
    var completed = false;
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.removeLast();
      for (final line in lines) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final data = trimmed.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        try {
          final event = jsonDecode(data) as Map<String, dynamic>;
          final type = event['type'] as String? ?? '';
          if (type == 'response.output_text.delta') {
            final delta = event['delta'] as String? ?? '';
            if (delta.isNotEmpty) onDelta(delta);
          } else if (type == 'response.completed') {
            completed = true;
          } else if (type == 'response.failed') {
            client.close();
            throw Exception('ChatGPT: respuesta fallida');
          }
        } catch (_) {}
      }
    }
    client.close();
    if (!completed) throw Exception('La respuesta se interrumpió.');
  }

  Future<String> completePlanText({
    required String userId,
    required String instructions,
    required List<Map<String, dynamic>> input,
  }) async {
    final buffer = StringBuffer();
    await streamResponse(
      userId: userId,
      instructions: instructions,
      input: input,
      onDelta: buffer.write,
    );
    return buffer.toString().trim();
  }

  /// Respuesta JSON en una sola petición (más rápido que SSE para repaso).
  Future<String> completePlanTextOnce({
    required String userId,
    required String instructions,
    required List<Map<String, dynamic>> input,
  }) async {
    final token = await ensureAccessToken(userId);
    final model = await preferredModel(userId);
    final response = await http.post(
      Uri.parse(AppConfig.chatgptResponsesUrl),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'instructions': instructions,
        'input': input,
        'store': false,
        'stream': false,
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(
        response.body.isEmpty
            ? 'ChatGPT HTTP ${response.statusCode}'
            : response.body,
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final text = _extractResponsesOutputText(body);
    if (text == null || text.isEmpty) {
      throw Exception('ChatGPT: respuesta vacía');
    }
    return text;
  }

  String? _extractResponsesOutputText(Map<String, dynamic> body) {
    final output = body['output'];
    if (output is! List) return null;
    final buffer = StringBuffer();
    for (final item in output) {
      if (item is! Map) continue;
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is! Map) continue;
        if (part['type'] == 'output_text') {
          buffer.write(part['text'] ?? '');
        }
      }
    }
    final text = buffer.toString().trim();
    return text.isEmpty ? null : text;
  }

  Future<T> completePlanJson<T>({
    required String userId,
    required String instructions,
    required String user,
    bool preferSingleRequest = false,
  }) async {
    final input = [
      {'role': 'user', 'content': user},
    ];
    final instr =
        '$instructions\nResponde únicamente con JSON válido, sin markdown.';
    var raw = '';
    if (preferSingleRequest) {
      try {
        raw = await completePlanTextOnce(
          userId: userId,
          instructions: instr,
          input: input,
        );
      } catch (_) {
        raw = await completePlanText(
          userId: userId,
          instructions: instr,
          input: input,
        );
      }
    } else {
      raw = await completePlanText(
        userId: userId,
        instructions: instr,
        input: input,
      );
    }
    var cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceFirst(
        RegExp(r'^```json\s*', caseSensitive: false),
        '',
      );
      cleaned = cleaned.replaceFirst(RegExp(r'```\s*$'), '');
    }
    return jsonDecode(cleaned.trim()) as T;
  }
}

Map<String, dynamic> planUserMessage(String text, {String? imageDataUrl}) {
  final trimmed = imageDataUrl?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return {'role': 'user', 'content': text};
  }
  return {
    'role': 'user',
    'content': [
      {'type': 'input_text', 'text': text},
      {'type': 'input_image', 'image_url': trimmed},
    ],
  };
}
