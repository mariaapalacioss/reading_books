import '../data/models/book.dart';
import '../data/repositories/books_repository.dart';
import '../features/workspace/document_profile.dart';

class DocumentProfileService {
  DocumentProfileService(this._repo);

  final BooksRepository _repo;

  Future<DocumentProfile> loadOrAnalyze(Book book) async {
    final cached = DocumentProfile.fromBookColumn(book.workspaceProfile);
    if (cached != null && cached.sampledPages > 0) return cached;
    return analyzeAndPersist(book);
  }

  Future<DocumentProfile> analyzeAndPersist(Book book) async {
    final end = book.pageCount > 0 ? book.pageCount.clamp(1, 24) : 12;
    final pages = await _repo.listPagesInRange(book.id, 1, end);
    final texts = pages.map((p) => p['text']?.toString() ?? '');
    final profile = analyzePageTexts(texts);
    await _repo.updateBook(book.id, {
      'workspace_profile': profile.toJson(),
    });
    return profile;
  }
}
