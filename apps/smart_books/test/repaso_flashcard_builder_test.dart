import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/features/review/repaso_flashcard_builder.dart';
import 'package:smart_books/features/review/repaso_models.dart';

void main() {
  test('legacy fallback uses English templates for English excerpt', () {
    const excerpt =
        'The mandibular third molar may remain impacted when space is limited and bone development restricts eruption.';
    final entry = ReviewListEntry(
      id: '1',
      sourceType: ReviewSourceType.punto,
      bookId: 'b',
      bookTitle: 'Oral Surgery',
      title: 'Point',
      excerpt: excerpt,
      point: {'text_en': excerpt},
    );
    final cards = buildFlashcardsFromEntry(entry, legacyFallback: true);
    expect(cards, isNotEmpty);
    expect(cards.first.question.startsWith('What'), isTrue);
  });

  test('legacy fallback uses Spanish templates for Spanish excerpt', () {
    const excerpt =
        'La erupción del tercer molar depende del espacio disponible en el maxilar y del desarrollo óseo alrededor.';
    final entry = ReviewListEntry(
      id: '2',
      sourceType: ReviewSourceType.punto,
      bookId: 'b',
      bookTitle: 'Cirugía',
      title: 'Punto',
      excerpt: excerpt,
      point: {'text_es': excerpt},
    );
    final cards = buildFlashcardsFromEntry(entry, legacyFallback: true);
    expect(cards, isNotEmpty);
    expect(cards.first.question.startsWith('¿'), isTrue);
  });
}
