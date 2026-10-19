import '../data/repositories/books_repository.dart';

/// Búsqueda ampliada: conserva `textSearchLibrary` y agrega coincidencias por términos relacionados.
class SemanticSearchService {
  SemanticSearchService(this._repo);

  final BooksRepository _repo;

  Future<List<Map<String, dynamic>>> search(String query) async {
    final primary = await _repo.textSearchLibrary(query);
    if (primary.length >= 12) return _rank(primary, query);

    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(RegExp(r'[^\wáéíóúñ]'), ''))
        .where((t) => t.length >= 3)
        .toSet();

    final merged = <String, Map<String, dynamic>>{};
    void absorb(List<Map<String, dynamic>> rows, {required int weight}) {
      for (final row in rows) {
        final key =
            '${row['book_id']}:${row['page_number']}';
        final prev = merged[key];
        if (prev == null) {
          merged[key] = {...row, '_score': weight};
        } else {
          prev['_score'] = (prev['_score'] as int? ?? 0) + weight;
        }
      }
    }

    absorb(primary, weight: 3);
    for (final token in tokens) {
      absorb(await _repo.textSearchLibrary(token), weight: 1);
    }

    final list = merged.values.toList();
    return _rank(list, query);
  }

  List<Map<String, dynamic>> _rank(
    List<Map<String, dynamic>> rows,
    String query,
  ) {
    final q = query.toLowerCase();
    rows.sort((a, b) {
      final sa = a['_score'] as int? ?? 0;
      final sb = b['_score'] as int? ?? 0;
      if (sa != sb) return sb.compareTo(sa);
      final ta = (a['text']?.toString() ?? '').toLowerCase();
      final tb = (b['text']?.toString() ?? '').toLowerCase();
      final ha = ta.contains(q) ? 1 : 0;
      final hb = tb.contains(q) ? 1 : 0;
      return hb.compareTo(ha);
    });
    return rows.take(40).toList();
  }
}
