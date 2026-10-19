import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../domain/ocr_layout.dart';

const _channel = MethodChannel('smart_books/ocr');

Future<List<OcrWord>> recognizeBgraPage({
  required int width,
  required int height,
  required Uint8List pixels,
}) async {
  final raw = await _channel.invokeMethod<List<Object?>>('recognizeBgra', {
    'width': width,
    'height': height,
    'pixels': pixels,
  });
  if (raw == null) return [];
  return raw
      .map((item) {
        final map = Map<String, dynamic>.from(item! as Map);
        return OcrWord(
          text: map['text'] as String? ?? '',
          x0: (map['x0'] as num).toDouble(),
          y0: (map['y0'] as num).toDouble(),
          x1: (map['x1'] as num).toDouble(),
          y1: (map['y1'] as num).toDouble(),
        );
      })
      .where((w) => w.text.trim().isNotEmpty)
      .toList();
}
