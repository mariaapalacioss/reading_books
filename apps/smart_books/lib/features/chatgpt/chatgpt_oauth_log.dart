import 'package:flutter/foundation.dart';

/// Logs de diagnóstico OAuth (nunca tokens, códigos ni secretos).
void chatGptOAuthLog(String message) {
  if (kDebugMode) {
    debugPrint('[ChatGPT OAuth] $message');
  }
}
