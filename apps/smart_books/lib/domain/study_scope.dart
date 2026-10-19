import '../data/repositories/books_repository.dart';
import 'content_language.dart';
import 'study_text.dart';

/// Qué contenido está estudiando el usuario en Asistencia (Páginas / Fragmentos).
enum StudyScopeKind { currentPage, pageRange, fragments }

/// Id efímero de selección en vivo (no usar en claves persistidas de repaso).
const kLiveStudyFragmentId = '__live_selection__';

class StudyFragmentRef {
  const StudyFragmentRef({
    required this.id,
    required this.pageNumber,
    required this.quote,
  });

  final String id;
  final int pageNumber;
  final String quote;
}

class StudyScope {
  const StudyScope({
    required this.kind,
    required this.bookId,
    required this.startPage,
    required this.endPage,
    this.fragments = const [],
    this.sourceText = '',
  });

  final StudyScopeKind kind;
  final String bookId;
  final int startPage;
  final int endPage;
  final List<StudyFragmentRef> fragments;
  final String sourceText;

  StudyScope copyWith({String? sourceText}) {
    return StudyScope(
      kind: kind,
      bookId: bookId,
      startPage: startPage,
      endPage: endPage,
      fragments: fragments,
      sourceText: sourceText ?? this.sourceText,
    );
  }

  bool get isValidSource => sourceText.trim().length >= 40;

  List<int> get pageNumbers {
    if (kind == StudyScopeKind.fragments) {
      return fragments.map((f) => f.pageNumber).toSet().toList()..sort();
    }
    return [for (var p = startPage; p <= endPage; p++) p];
  }

  List<String> get fragmentIds =>
      fragments.map((f) => f.id).where((id) => id.isNotEmpty).toList();
}

Future<StudyScope> buildStudyScope({
  required BooksRepository repo,
  required StudyScopeKind kind,
  required String bookId,
  required int currentPage,
  required int totalPages,
  int? rangeStart,
  int? rangeEnd,
  List<StudyFragmentRef> fragments = const [],
}) async {
  switch (kind) {
    case StudyScopeKind.currentPage:
      final page = currentPage.clamp(
        1,
        totalPages > 0 ? totalPages : currentPage,
      );
      final text = await _packPages(repo, bookId, page, page);
      return StudyScope(
        kind: kind,
        bookId: bookId,
        startPage: page,
        endPage: page,
        sourceText: text.packed,
      );
    case StudyScopeKind.pageRange:
      final start = (rangeStart ?? currentPage).clamp(
        1,
        totalPages > 0 ? totalPages : 1,
      );
      final end = (rangeEnd ?? start).clamp(
        start,
        totalPages > 0 ? totalPages : start,
      );
      final rangeText = await _packPages(repo, bookId, start, end);
      return StudyScope(
        kind: kind,
        bookId: bookId,
        startPage: start,
        endPage: end,
        sourceText: rangeText.packed,
      );
    case StudyScopeKind.fragments:
      if (fragments.isEmpty) {
        return StudyScope(
          kind: kind,
          bookId: bookId,
          startPage: currentPage,
          endPage: currentPage,
          fragments: fragments,
          sourceText: '',
        );
      }
      final parts = <String>[];
      for (final f in fragments) {
        final q = normalizeStudyText(f.quote);
        if (q.length < 8) continue;
        parts.add('[p.${f.pageNumber}]\n$q');
      }
      final packed = parts.join('\n\n');
      final trimmed = packed.length > 18000
          ? packed.substring(0, 18000)
          : packed;
      final pages = fragments.map((f) => f.pageNumber).toList()..sort();
      return StudyScope(
        kind: kind,
        bookId: bookId,
        startPage: pages.first,
        endPage: pages.last,
        fragments: fragments,
        sourceText: trimmed,
      );
  }
}

String studyScopeActionLabel(StudyScope scope, ContentLanguage lang) {
  if (lang == ContentLanguage.en) {
    return switch (scope.kind) {
      StudyScopeKind.currentPage => 'page ${scope.startPage}',
      StudyScopeKind.pageRange =>
        scope.startPage == scope.endPage
            ? 'page ${scope.startPage}'
            : 'pages ${scope.startPage}–${scope.endPage}',
      StudyScopeKind.fragments =>
        scope.fragments.length == 1
            ? '1 fragment'
            : '${scope.fragments.length} fragments',
    };
  }
  return switch (scope.kind) {
    StudyScopeKind.currentPage => 'página ${scope.startPage}',
    StudyScopeKind.pageRange =>
      scope.startPage == scope.endPage
          ? 'página ${scope.startPage}'
          : 'páginas ${scope.startPage}–${scope.endPage}',
    StudyScopeKind.fragments =>
      scope.fragments.length == 1
          ? '1 fragmento'
          : '${scope.fragments.length} fragmentos',
  };
}

String studyScopeResultTitle({
  required AssistResultKind result,
  required StudyScope scope,
  required ContentLanguage lang,
}) {
  final target = studyScopeActionLabel(scope, lang);
  if (lang == ContentLanguage.en) {
    return switch (result) {
      AssistResultKind.summary => 'Summary · $target',
      AssistResultKind.keyPoints => 'Important points · $target',
      AssistResultKind.explain => 'Explanation · $target',
    };
  }
  return switch (result) {
    AssistResultKind.summary => 'Resumen · $target',
    AssistResultKind.keyPoints => 'Puntos importantes · $target',
    AssistResultKind.explain => 'Explicación · $target',
  };
}

enum AssistResultKind { summary, keyPoints, explain }

Future<({String packed, int readableCount, int expected})> _packPages(
  BooksRepository repo,
  String bookId,
  int startPage,
  int endPage,
) async {
  final pages = await repo.listPagesInRange(bookId, startPage, endPage);
  final readable = pages
      .map(
        (p) => (
          normalizeStudyText(p['text'] as String? ?? ''),
          (p['page_number'] as num).toInt(),
        ),
      )
      .where((p) => p.$1.length > 40)
      .toList();
  final expected = endPage - startPage + 1;
  final packed = readable.map((p) => '[p.${p.$2}]\n${p.$1}').join('\n\n');
  final trimmed = packed.length > 18000 ? packed.substring(0, 18000) : packed;
  return (packed: trimmed, readableCount: readable.length, expected: expected);
}

String validatePageRange({
  required int start,
  required int end,
  required int totalPages,
}) {
  if (totalPages < 1) return 'Este libro aún no tiene páginas indexadas.';
  if (start < 1) return 'La página inicial debe ser al menos 1.';
  if (end > totalPages) return 'La página final no puede superar $totalPages.';
  if (start > end) {
    return 'La página inicial debe ser menor o igual que la final.';
  }
  return '';
}
