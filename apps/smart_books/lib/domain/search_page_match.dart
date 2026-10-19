import '../data/models/text_item.dart';
import 'rects.dart';

class SearchPageMatch {
  const SearchPageMatch({
    required this.matchedText,
    required this.start,
    required this.end,
    required this.rects,
  });

  final String matchedText;
  final int start;
  final int end;
  final List<NormRect> rects;
}

/// Localiza en la página la coincidencia de búsqueda (coords vía [TextItem.start]).
SearchPageMatch? findSearchMatchOnPage({
  required String pageText,
  required List<TextItem> items,
  required String query,
  String? snippet,
}) {
  final q = query.trim();
  if (q.isEmpty || pageText.isEmpty || items.isEmpty) return null;

  final page = _FoldedText.from(pageText);
  final snippetRange = _snippetFoldRange(page, snippet);

  final queryFold = _FoldedText.from(q).folded;
  if (queryFold.isEmpty) return null;

  final pattern = _flexPattern(queryFold);
  final reg = RegExp(pattern);

  int? foldStart;
  int? foldEnd;
  if (snippetRange != null) {
    final slice = page.folded.substring(
      snippetRange.$1,
      snippetRange.$2.clamp(0, page.folded.length),
    );
    final local = reg.firstMatch(slice);
    if (local != null) {
      foldStart = snippetRange.$1 + local.start;
      foldEnd = snippetRange.$1 + local.end;
    }
  }
  if (foldStart == null || foldEnd == null) {
    final m = reg.firstMatch(page.folded);
    if (m == null) return null;
    foldStart = m.start;
    foldEnd = m.end;
  }

  final start = page.originalIndex(foldStart);
  final end = page.originalEndExclusive(foldEnd);
  if (end <= start) return null;

  final rects = rectsForRange(items, start, end);
  if (rects.isEmpty) return null;

  final matched = pageText
      .substring(start, end.clamp(0, pageText.length))
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  return SearchPageMatch(
    matchedText: matched,
    start: start,
    end: end,
    rects: rects,
  );
}

(int, int)? _snippetFoldRange(_FoldedText page, String? snippet) {
  final raw = snippet?.trim();
  if (raw == null || raw.length < 4) return null;

  final sn = _FoldedText.from(raw);
  var idx = page.folded.indexOf(sn.folded);
  if (idx >= 0) {
    return (idx, idx + sn.folded.length);
  }

  // Snippet truncado en la lista de resultados: prefijo más largo que coincida.
  for (var len = sn.folded.length; len >= 12; len -= 4) {
    final prefix = sn.folded.substring(0, len);
    idx = page.folded.indexOf(prefix);
    if (idx >= 0) {
      return (idx, idx + prefix.length);
    }
  }
  return null;
}

String _flexPattern(String foldedQuery) {
  final words = foldedQuery.split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  if (words.length == 1) return RegExp.escape(words.first);
  return words.map(RegExp.escape).join(r' +');
}

class _FoldedText {
  _FoldedText._(this.folded, this._map, this._sourceLength);

  final String folded;
  final List<int> _map;
  final int _sourceLength;

  factory _FoldedText.from(String source) {
    final map = <int>[];
    final buf = StringBuffer();
    var pendingSpace = false;

    for (var i = 0; i < source.length; i++) {
      final c = source[i];
      if (RegExp(r'\s').hasMatch(c)) {
        if (buf.isNotEmpty) pendingSpace = true;
        continue;
      }
      if (pendingSpace) {
        map.add(i);
        buf.write(' ');
        pendingSpace = false;
      }
      map.add(i);
      buf.write(_foldChar(c));
    }

    return _FoldedText._(buf.toString(), map, source.length);
  }

  int originalIndex(int foldIndex) {
    if (_map.isEmpty) return 0;
    if (foldIndex <= 0) return _map.first;
    if (foldIndex >= _map.length) return _sourceLength;
    return _map[foldIndex];
  }

  int originalEndExclusive(int foldEnd) {
    if (_map.isEmpty) return 0;
    if (foldEnd <= 0) return _map.first;
    if (foldEnd >= _map.length) return _sourceLength;
    return _map[foldEnd];
  }
}

String _foldChar(String char) {
  const pairs = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'Á': 'a',
    'À': 'a',
    'Ä': 'a',
    'Â': 'a',
    'Ã': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'É': 'e',
    'È': 'e',
    'Ë': 'e',
    'Ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'Í': 'i',
    'Ì': 'i',
    'Ï': 'i',
    'Î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'Ó': 'o',
    'Ò': 'o',
    'Ö': 'o',
    'Ô': 'o',
    'Õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'Ú': 'u',
    'Ù': 'u',
    'Ü': 'u',
    'Û': 'u',
    'ñ': 'n',
    'Ñ': 'n',
    'ç': 'c',
    'Ç': 'c',
  };
  final lower = char.toLowerCase();
  return pairs[char] ?? pairs[lower] ?? lower;
}

NormRect unionNormRects(Iterable<NormRect> rects) {
  final list = rects.toList();
  if (list.isEmpty) {
    return const NormRect(x: 0, y: 0, w: 0, h: 0);
  }
  var x0 = list.first.x;
  var y0 = list.first.y;
  var x1 = list.first.x + list.first.w;
  var y1 = list.first.y + list.first.h;
  for (final r in list.skip(1)) {
    x0 = x0 < r.x ? x0 : r.x;
    y0 = y0 < r.y ? y0 : r.y;
    final rx1 = r.x + r.w;
    final ry1 = r.y + r.h;
    if (rx1 > x1) x1 = rx1;
    if (ry1 > y1) y1 = ry1;
  }
  return NormRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0);
}
