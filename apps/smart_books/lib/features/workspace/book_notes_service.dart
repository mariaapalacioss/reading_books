import '../../data/repositories/books_repository.dart';
import '../review/repaso_qa_store.dart';

/// Notas ligadas a página, fragmento o región (reutiliza `study_cards`).
class BookNotesService {
  BookNotesService(this._repo);

  final BooksRepository _repo;

  Future<Map<String, dynamic>> savePageNote({
    required String bookId,
    required String userId,
    required int pageNumber,
    required String body,
    String? chapterId,
    String title = 'Nota',
  }) {
    return _repo.insertStudyCard({
      'book_id': bookId,
      'user_id': userId,
      'chapter_id': chapterId,
      'page_number': pageNumber,
      'kind': 'note',
      'source': 'assist',
      'title': title,
      'body': body,
      'context_question': repasoSourceKeyPage(bookId, pageNumber),
      'metadata': {'material_kind': 'note', 'anchor': 'page'},
    });
  }

  Future<Map<String, dynamic>> saveFragmentNote({
    required String bookId,
    required String userId,
    required int pageNumber,
    required String quote,
    required String body,
    String? chapterId,
  }) {
    return _repo.insertStudyCard({
      'book_id': bookId,
      'user_id': userId,
      'chapter_id': chapterId,
      'page_number': pageNumber,
      'kind': 'note',
      'source': 'assist',
      'title': 'Nota · fragmento',
      'body': body,
      'quote': quote,
      'context_question': repasoSourceKeyFragment(bookId, pageNumber, quote),
      'metadata': {'material_kind': 'note', 'anchor': 'fragment'},
    });
  }

  Future<Map<String, dynamic>> saveVisualRegionNote({
    required String bookId,
    required String userId,
    required int pageNumber,
    required String body,
    String? previewUrl,
    String? chapterId,
  }) {
    return _repo.insertStudyCard({
      'book_id': bookId,
      'user_id': userId,
      'chapter_id': chapterId,
      'page_number': pageNumber,
      'kind': 'note',
      'source': 'capture',
      'title': 'Nota · región visual',
      'body': body,
      'preview_url': previewUrl,
      'context_question': repasoSourceKeyPage(bookId, pageNumber),
      'metadata': {
        'material_kind': 'note',
        'anchor': 'visual_region',
      },
    });
  }
}
