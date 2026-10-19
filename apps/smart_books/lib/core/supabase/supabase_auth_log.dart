import 'package:flutter/foundation.dart';

void supabaseAuthLog(String message) {
  if (kDebugMode) {
    debugPrint('[Supabase Auth] $message');
  }
}
