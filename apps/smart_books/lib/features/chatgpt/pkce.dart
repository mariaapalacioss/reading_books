import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

String _base64Url(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

String randomState() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return _base64Url(bytes);
}

({String verifier, String challenge}) createPkce() {
  final random = Random.secure();
  final verifierBytes = List<int>.generate(32, (_) => random.nextInt(256));
  final verifier = _base64Url(verifierBytes);
  final digest = sha256.convert(utf8.encode(verifier));
  final challenge = _base64Url(digest.bytes);
  return (verifier: verifier, challenge: challenge);
}
