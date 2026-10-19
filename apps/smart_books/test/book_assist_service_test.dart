import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/data/repositories/books_repository.dart';
import 'package:smart_books/services/book_assist_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeRepo extends BooksRepository {
  _FakeRepo() : super(SupabaseClient('http://localhost', 'anon'));

  @override
  Future<Map<String, dynamic>?> getPage(String bookId, int pageNumber) async {
    return {'text': 'x', 'printed_label': null, 'char_count': 1};
  }

  @override
  Future<List<Map<String, dynamic>>> listPagesInRange(
    String bookId,
    int startPage,
    int endPage,
  ) async => [];

  @override
  Future<List<Map<String, dynamic>>> listReadablePages(
    String bookId, {
    int limit = 6,
  }) async => [];
}

void main() {
  test('explain página sin texto lanza error claro', () async {
    final service = BookAssistService(_FakeRepo());
    await expectLater(
      service.streamAssist(
        userId: 'u',
        mode: AssistMode.page,
        bookId: 'b',
        bookTitle: 'Libro',
        language: 'es',
        pageNumber: 3,
        messages: [],
        onDelta: (_) {},
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('texto seleccionable'),
        ),
      ),
    );
  });

  test('explain fragmento corto lanza error de selección', () async {
    final service = BookAssistService(_FakeRepo());
    await expectLater(
      service.streamAssist(
        userId: 'u',
        mode: AssistMode.explain,
        bookId: 'b',
        bookTitle: 'Libro',
        language: 'es',
        pageNumber: 1,
        quote: 'corto',
        messages: [],
        onDelta: (_) {},
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Selecciona'),
        ),
      ),
    );
  });
}
