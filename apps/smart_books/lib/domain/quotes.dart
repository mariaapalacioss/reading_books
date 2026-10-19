import 'dart:convert';

import 'package:crypto/crypto.dart';

Future<String> quoteHash(String quote) async {
  final normalized = quote.replaceAll(RegExp(r'\s+'), ' ').trim();
  final digest = sha256.convert(utf8.encode(normalized));
  return digest.bytes
      .take(16)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

({int start, int end})? locateQuote(String haystack, String quote) {
  final needle = quote.replaceAll('\u00ad', '').trim();
  if (needle.length < 12) return null;
  final exact = haystack.indexOf(needle);
  if (exact >= 0) return (start: exact, end: exact + needle.length);
  final source = _collapseWithMap(haystack);
  final target = _collapseWithMap(needle).text;
  if (target.length < 12) return null;
  final at = source.text.indexOf(target);
  if (at < 0) return null;
  final start = source.map[at];
  final last = source.map[at + target.length - 1];
  if (start == null || last == null) return null;
  return (start: start, end: last + 1);
}

({String text, List<int> map}) _collapseWithMap(String input) {
  var text = '';
  final map = <int>[];
  var pendingSpace = false;
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (ch == '\u00ad') continue;
    if (ch == '-' &&
        i + 1 < input.length &&
        (input[i + 1] == '\n' || input[i + 1] == '\r')) {
      if (input[i + 1] == '\r' &&
          i + 2 < input.length &&
          input[i + 2] == '\n') {
        i += 2;
      } else {
        i += 1;
      }
      pendingSpace = false;
      continue;
    }
    if (RegExp(r'\s').hasMatch(ch)) {
      pendingSpace = true;
      continue;
    }
    if (pendingSpace && text.isNotEmpty && !text.endsWith(' ')) {
      text += ' ';
      map.add(i);
    }
    pendingSpace = false;
    text += ch;
    map.add(i);
  }
  return (text: text, map: map);
}
