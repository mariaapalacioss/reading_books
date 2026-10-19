/// Concepto principal del libro (persistencia vía `book_concepts` en Supabase).
class BookConcept {
  const BookConcept({
    required this.id,
    required this.bookId,
    required this.label,
    this.summary,
    this.pageRefs = const [],
    this.relatedConceptIds = const [],
  });

  final String id;
  final String bookId;
  final String label;
  final String? summary;
  final List<int> pageRefs;
  final List<String> relatedConceptIds;

  factory BookConcept.fromRow(Map<String, dynamic> row) {
    final pages = row['page_refs'];
    return BookConcept(
      id: row['id']?.toString() ?? '',
      bookId: row['book_id']?.toString() ?? '',
      label: row['label']?.toString() ?? '',
      summary: row['summary']?.toString(),
      pageRefs: pages is List
          ? pages.map((e) => (e as num).toInt()).toList()
          : const [],
      relatedConceptIds: (row['related_concept_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

/// Punto de extensión para extracción de conceptos / mapa (fase posterior).
abstract class BookConceptExtractor {
  Future<List<BookConcept>> extractFromBook(String bookId);
}

/// Implementación vacía hasta conectar pipeline de IA.
class StubBookConceptExtractor implements BookConceptExtractor {
  @override
  Future<List<BookConcept>> extractFromBook(String bookId) async => [];
}
