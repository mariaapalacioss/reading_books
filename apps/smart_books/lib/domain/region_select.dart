import 'dart:typed_data';

import '../data/models/text_item.dart';
import 'rects.dart';

NormRect normRectFromPoints(double x0, double y0, double x1, double y1) {
  final x = x0 < x1 ? x0 : x1;
  final y = y0 < y1 ? y0 : y1;
  return NormRect(
    x: x,
    y: y,
    w: (x1 - x0).abs().clamp(0.002, 1.0),
    h: (y1 - y0).abs().clamp(0.002, 1.0),
  );
}

bool _itemInRegion(TextItem item, NormRect region) {
  const pad = 0.008;
  final cx = item.x + item.w / 2;
  final cy = item.y + item.h / 2;
  return cx >= region.x - pad &&
      cx <= region.x + region.w + pad &&
      cy >= region.y - pad &&
      cy <= region.y + region.h + pad;
}

({String quote, List<NormRect> rects, int start, int end}) textFromRegion(
  List<TextItem> items,
  NormRect region, {
  String pageText = '',
}) {
  final hits =
      items
          .where(
            (item) => item.s.trim().isNotEmpty && _itemInRegion(item, region),
          )
          .toList()
        ..sort((a, b) {
          final dy = a.y.compareTo(b.y);
          return dy != 0 ? dy : a.x.compareTo(b.x);
        });

  if (hits.isEmpty) {
    return (quote: '', rects: [], start: -1, end: -1);
  }

  final start = hits.map((i) => i.start).reduce((a, b) => a < b ? a : b);
  final end = hits
      .map((i) => i.start + i.s.length)
      .reduce((a, b) => a > b ? a : b);

  var quote = '';
  if (pageText.isNotEmpty && start >= 0 && end > start) {
    quote = pageText
        .substring(start, end.clamp(0, pageText.length))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
  if (quote.length < 8) {
    quote = hits
        .map((i) => i.s)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  return (
    quote: quote,
    rects: rectsForRange(hits, start, end),
    start: start,
    end: end,
  );
}

/// Recorta región normalizada (0–1) de un buffer BGRA premultiplicado.
({Uint8List pixels, int width, int height})? cropBgraRegion({
  required Uint8List pixels,
  required int width,
  required int height,
  required NormRect region,
}) {
  final sx = (region.x * width).floor().clamp(0, width - 1);
  final sy = (region.y * height).floor().clamp(0, height - 1);
  final sw = (region.w * width).ceil().clamp(0, width - sx);
  final sh = (region.h * height).ceil().clamp(0, height - sy);
  if (sw < 8 || sh < 8) return null;

  final out = Uint8List(sw * sh * 4);
  for (var row = 0; row < sh; row++) {
    final srcStart = ((sy + row) * width + sx) * 4;
    final dstStart = row * sw * 4;
    out.setRange(
      dstStart,
      dstStart + sw * 4,
      pixels.sublist(srcStart, srcStart + sw * 4),
    );
  }
  return (pixels: out, width: sw, height: sh);
}
