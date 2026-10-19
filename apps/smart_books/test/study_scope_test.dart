import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/domain/content_language.dart';
import 'package:smart_books/domain/study_scope.dart';

void main() {
  test('validatePageRange rejects invalid bounds', () {
    expect(validatePageRange(start: 0, end: 5, totalPages: 100), isNotEmpty);
    expect(validatePageRange(start: 10, end: 5, totalPages: 100), isNotEmpty);
    expect(validatePageRange(start: 1, end: 101, totalPages: 100), isNotEmpty);
    expect(validatePageRange(start: 36, end: 42, totalPages: 100), isEmpty);
  });

  test('studyScopeActionLabel for page range', () {
    final scope = StudyScope(
      kind: StudyScopeKind.pageRange,
      bookId: 'b',
      startPage: 36,
      endPage: 42,
      sourceText: 'x' * 50,
    );
    expect(studyScopeActionLabel(scope, ContentLanguage.es), 'páginas 36–42');
    expect(
      studyScopeResultTitle(
        result: AssistResultKind.summary,
        scope: scope,
        lang: ContentLanguage.es,
      ),
      'Resumen · páginas 36–42',
    );
  });
}
