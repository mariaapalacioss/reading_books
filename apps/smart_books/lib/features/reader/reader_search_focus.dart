/// Contexto temporal al abrir el lector desde Buscar (no se persiste).
class ReaderSearchFocus {
  const ReaderSearchFocus({required this.query, this.snippet});

  final String query;
  final String? snippet;

  static ReaderSearchFocus? fromRouteExtra(Object? extra) {
    if (extra is! Map) return null;
    final query = extra['searchQuery']?.toString().trim() ?? '';
    if (query.isEmpty) return null;
    final snippet = extra['searchSnippet']?.toString().trim();
    return ReaderSearchFocus(
      query: query,
      snippet: snippet != null && snippet.isEmpty ? null : snippet,
    );
  }
}
