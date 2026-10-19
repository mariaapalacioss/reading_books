import '../data/models/text_item.dart';

class NormRect {
  const NormRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
  final double x;
  final double y;
  final double w;
  final double h;

  Map<String, double> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};
}

List<NormRect> rectsForRange(List<TextItem> items, int start, int end) {
  final selected = items
      .where(
        (item) =>
            item.s.isNotEmpty &&
            item.start < end &&
            item.start + item.s.length > start &&
            item.w > 0 &&
            item.h > 0,
      )
      .toList();
  if (selected.isEmpty) return [];

  final lines = <List<TextItem>>[];
  for (final item in selected) {
    List<TextItem>? match;
    for (final group in lines) {
      if ((group.first.y - item.y).abs() <
          (item.h > group.first.h ? item.h : group.first.h) * 0.6) {
        match = group;
        break;
      }
    }
    if (match != null) {
      match.add(item);
    } else {
      lines.add([item]);
    }
  }

  return lines
      .map((line) {
        final x = line.map((i) => i.x).reduce((a, b) => a < b ? a : b);
        final y = line.map((i) => i.y).reduce((a, b) => a < b ? a : b);
        final right = line
            .map((i) => i.x + i.w)
            .reduce((a, b) => a > b ? a : b);
        final bottom = line
            .map((i) => i.y + i.h)
            .reduce((a, b) => a > b ? a : b);
        return NormRect(
          x: _clamp01(x),
          y: _clamp01(y),
          w: _clamp01(right) - _clamp01(x),
          h: _clamp01(bottom) - _clamp01(y),
        );
      })
      .where((r) => r.w > 0.001 && r.h > 0.001)
      .toList();
}

double _clamp01(double v) => v.clamp(0.0, 1.0);

String quoteFromRange(String text, int start, int end) =>
    text.substring(start, end.clamp(0, text.length)).trim();
