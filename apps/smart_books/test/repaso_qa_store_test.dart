import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/data/models/highlight.dart';
import 'package:smart_books/features/review/repaso_models.dart';
import 'package:smart_books/features/review/repaso_qa_store.dart';

void main() {
  test('highlight repaso key matches fragment generation key', () {
    const bookId = 'book-1';
    const highlightId = 'hl-abc';

    final entry = ReviewListEntry.fromHighlight(
      const Highlight(
        id: highlightId,
        bookId: bookId,
        pageNumber: 36,
        quote: 'Las osteítis son lesiones circunscritas',
        category: 'manual',
        origin: 'user',
      ),
      bookTitle: 'Libro',
    );

    expect(
      repasoSourceKeyForEntry(entry),
      repasoSourceKeyFragmentSet(bookId, [highlightId]),
    );
  });

  test('capture card uses fragment key when context_question is set', () {
    const bookId = 'book-1';
    const highlightId = 'hl-abc';
    const ctx = 'repaso_src:fragments:book-1:hl-abc';
    final entry = ReviewListEntry.fromStudyCard({
      'id': 'card-capture',
      'book_id': bookId,
      'kind': 'capture',
      'source': 'capture',
      'title': 'Resaltado',
      'body': 'Texto del resaltado',
      'quote': 'Texto del resaltado',
      'context_question': ctx,
    }, bookTitle: 'Libro');
    expect(entry, isNotNull);
    expect(repasoSourceKeyForEntry(entry!), ctx);
  });

  test('qa bundle entry id is the stored context_question key', () {
    const ctx = 'repaso_src:fragments:book-1:hl-abc';
    final entry = ReviewListEntry.fromQaSourceKey(
      sourceKey: ctx,
      bookId: 'book-1',
      bookTitle: 'Libro',
      title: 'Preguntas',
      excerpt: '¿Qué son las osteítis?',
    );
    expect(repasoSourceKeyForEntry(entry), ctx);
  });
}
