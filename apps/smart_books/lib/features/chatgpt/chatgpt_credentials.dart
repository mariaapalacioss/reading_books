import 'dart:convert';

class ChatGptCredentials {
  const ChatGptCredentials({
    required this.email,
    required this.subject,
    required this.clientId,
    required this.extAgentHostId,
    required this.idToken,
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresAt,
    required this.scopes,
    required this.smartbooksUserId,
    required this.savedAt,
  });

  final String? email;
  final String? subject;
  final String clientId;
  final String extAgentHostId;
  final String idToken;
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresAt;
  final List<String> scopes;
  final String smartbooksUserId;
  final DateTime savedAt;

  bool get hasPlanUsage => scopes.contains('chatgpt.tokens.use.direct');

  Map<String, dynamic> toJson() => {
    'email': email,
    'subject': subject,
    'client_id': clientId,
    'ext_agent_host_id': extAgentHostId,
    'id_token': idToken,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'token_type': tokenType,
    'expires_at': expiresAt,
    'scopes': scopes,
    'smartbooks_user_id': smartbooksUserId,
    'saved_at': savedAt.toIso8601String(),
  };

  factory ChatGptCredentials.fromJson(Map<String, dynamic> json) {
    return ChatGptCredentials(
      email: json['email'] as String?,
      subject: json['subject'] as String?,
      clientId: json['client_id'] as String,
      extAgentHostId: json['ext_agent_host_id'] as String,
      idToken: json['id_token'] as String? ?? '',
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresAt: (json['expires_at'] as num?)?.toInt() ?? 0,
      scopes:
          (json['scopes'] as List?)?.map((e) => e.toString()).toList() ?? [],
      smartbooksUserId: json['smartbooks_user_id'] as String,
      savedAt:
          DateTime.tryParse(json['saved_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static ChatGptCredentials fromTokenResponse({
    required Map<String, dynamic> token,
    required String clientId,
    required String hostId,
    required String smartbooksUserId,
    String? email,
    String? subject,
  }) {
    final scopeRaw = token['scope']?.toString() ?? '';
    final scopes = scopeRaw
        .split(RegExp(r'[\s+]+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final expiresIn = (token['expires_in'] as num?)?.toInt() ?? 3600;
    return ChatGptCredentials(
      email: email,
      subject: subject,
      clientId: clientId,
      extAgentHostId: hostId,
      idToken: token['id_token']?.toString() ?? '',
      accessToken: token['access_token']?.toString() ?? '',
      refreshToken: token['refresh_token']?.toString() ?? '',
      tokenType: token['token_type']?.toString() ?? 'Bearer',
      expiresAt:
          DateTime.now().millisecondsSinceEpoch + expiresIn * 1000 - 60000,
      scopes: scopes,
      smartbooksUserId: smartbooksUserId,
      savedAt: DateTime.now(),
    );
  }

  String encode() => jsonEncode(toJson());

  static ChatGptCredentials decode(String raw) =>
      ChatGptCredentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
