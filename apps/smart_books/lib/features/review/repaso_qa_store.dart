import '../../data/models/highlight.dart';
import '../../data/repositories/books_repository.dart';
import '../../domain/study_scope.dart';
import 'repaso_models.dart';

const kReviewQuestionsAssistMode = 'reviewQuestions';
const kRepasoSrcPrefix = 'repaso_src:';

String repasoSourceKeyStudyCard(String studyCardId) =>
    '${kRepasoSrcPrefix}study_card:$studyCardId';

String repasoSourceKeyChapter(String chapterId) =>
    '${kRepasoSrcPrefix}chapter:$chapterId';

String repasoSourceKeyPage(String bookId, int page) =>
    '${kRepasoSrcPrefix}page:$bookId:$page';

String repasoSourceKeyFragment(String bookId, int page, String quote) {
  final q = quote.trim().length > 80
      ? quote.trim().substring(0, 80)
      : quote.trim();
  return '${kRepasoSrcPrefix}fragment:$bookId:$page:${q.hashCode}';
}

String repasoSourceKeyPageRange(String bookId, int startPage, int endPage) =>
    '${kRepasoSrcPrefix}pages:$bookId:$startPage-$endPage';

String repasoSourceKeyFragmentSet(String bookId, List<String> fragmentIds) {
  final sorted =
      fragmentIds
          .where((id) => id.isNotEmpty && id != kLiveStudyFragmentId)
          .toList()
        ..sort();
  if (sorted.isEmpty) {
    return '${kRepasoSrcPrefix}fragments:$bookId:';
  }
  return '${kRepasoSrcPrefix}fragments:$bookId:${sorted.join('|')}';
}

/// Misma clave al guardar preguntas desde [StudyScope] y al buscarlas en Repaso.
String repasoSourceKeyForStudyScope(StudyScope scope) {
  switch (scope.kind) {
    case StudyScopeKind.currentPage:
      return repasoSourceKeyPage(scope.bookId, scope.startPage);
    case StudyScopeKind.pageRange:
      return repasoSourceKeyPageRange(
        scope.bookId,
        scope.startPage,
        scope.endPage,
      );
    case StudyScopeKind.fragments:
      final realIds = scope.fragments
          .map((f) => f.id)
          .where((id) => id.isNotEmpty && id != kLiveStudyFragmentId)
          .toList();
      if (realIds.length == 1) {
        return repasoSourceKeyFragmentSet(scope.bookId, [realIds.single]);
      }
      if (realIds.length > 1) {
        return repasoSourceKeyFragmentSet(scope.bookId, realIds);
      }
      if (scope.fragments.length == 1) {
        final f = scope.fragments.first;
        return repasoSourceKeyFragment(scope.bookId, f.pageNumber, f.quote);
      }
      if (scope.fragments.isNotEmpty) {
        return repasoSourceKeyFragment(
          scope.bookId,
          scope.fragments.first.pageNumber,
          scope.fragments.first.quote,
        );
      }
      return repasoSourceKeyPage(scope.bookId, scope.startPage);
  }
}

bool isPersistedQa(Map<String, dynamic> row) {
  final kind = row['kind']?.toString();
  final back = row['back']?.toString().trim();
  return kind == 'qa' && back != null && back.isNotEmpty;
}

RepasoFlashcard flashcardFromQaRow(
  Map<String, dynamic> row,
  ReviewSourceType sourceType,
) {
  return RepasoFlashcard(
    question: row['body']?.toString() ?? '',
    answer: row['back']?.toString() ?? '',
    sourceType: sourceType,
    bookTitle: row['_book_title']?.toString() ?? '',
    chapterTitle: row['_chapter_title']?.toString(),
    pageNumber: (row['page_number'] is num)
        ? (row['page_number'] as num).toInt()
        : int.tryParse('${row['page_number']}'),
    studyCardId: row['id']?.toString(),
  );
}

bool isCaptureStudyCardEntry(ReviewListEntry entry) {
  final c = entry.card;
  if (c == null) return false;
  final kind = c['kind']?.toString();
  final source = c['source']?.toString();
  return kind == 'capture' || source == 'capture';
}

/// Resaltado manual en `highlights` que corresponde a una tarjeta capture o cita.
Future<Highlight?> findHighlightMatchingRepasoEntry(
  BooksRepository repo,
  ReviewListEntry entry,
) async {
  final highlight = entry.highlight;
  if (highlight != null) return highlight;

  final quote = (entry.card?['quote']?.toString() ?? entry.excerpt).trim();
  if (quote.isEmpty) return null;

  final page = entry.pageNumber;
  final highlights = await repo.listHighlights(entry.bookId);
  for (final h in highlights) {
    if (page != null && h.pageNumber != page) continue;
    final hq = h.quote.trim();
    if (hq.isEmpty) continue;
    if (hq == quote || hq.contains(quote) || quote.contains(hq)) return h;
  }
  return null;
}

Future<String> repasoPrimarySourceKeyForEntry(
  BooksRepository repo,
  ReviewListEntry entry,
) async {
  if (entry.id.startsWith(kRepasoSrcPrefix)) return entry.id;

  final cardCtx = entry.card?['context_question']?.toString() ?? '';
  if (cardCtx.startsWith(kRepasoSrcPrefix)) return cardCtx;

  if (entry.highlight != null) {
    return repasoSourceKeyFragmentSet(entry.bookId, [entry.highlight!.id]);
  }

  final matched = await findHighlightMatchingRepasoEntry(repo, entry);
  if (matched != null) {
    return repasoSourceKeyFragmentSet(entry.bookId, [matched.id]);
  }

  return repasoSourceKeyForEntry(entry);
}

Future<List<String>> repasoSourceKeysForEntryResolved(
  BooksRepository repo,
  ReviewListEntry entry,
) async {
  final keys = repasoSourceKeysForEntry(entry).toSet();
  keys.add(await repasoPrimarySourceKeyForEntry(repo, entry));

  final hl =
      entry.highlight ?? await findHighlightMatchingRepasoEntry(repo, entry);
  if (hl != null) {
    keys.add(repasoSourceKeyFragmentSet(entry.bookId, [hl.id]));
    keys.add(repasoSourceKeyFragment(entry.bookId, hl.pageNumber, hl.quote));
  }
  return keys.toList();
}

String repasoSourceKeyForEntry(ReviewListEntry entry) {
  if (entry.id.startsWith(kRepasoSrcPrefix)) {
    return entry.id;
  }
  if (entry.highlight != null) {
    return repasoSourceKeyFragmentSet(entry.bookId, [entry.highlight!.id]);
  }
  if (entry.card != null && entry.card!['id'] != null) {
    final ctx = entry.card!['context_question']?.toString() ?? '';
    if (ctx.startsWith(kRepasoSrcPrefix)) return ctx;
    return repasoSourceKeyStudyCard(entry.card!['id'].toString());
  }
  if (entry.chapterId != null && entry.chapterId!.isNotEmpty) {
    return repasoSourceKeyChapter(entry.chapterId!);
  }
  if (entry.pageNumber != null) {
    return repasoSourceKeyPage(entry.bookId, entry.pageNumber!);
  }
  return '${kRepasoSrcPrefix}entry:${entry.id}';
}

/// Claves posibles al buscar preguntas guardadas para una entrada de Repaso.
List<String> repasoSourceKeysForEntry(ReviewListEntry entry) {
  final keys = <String>{repasoSourceKeyForEntry(entry)};
  if (entry.highlight != null) {
    final h = entry.highlight!;
    keys.add(repasoSourceKeyFragmentSet(entry.bookId, [h.id]));
    keys.add(repasoSourceKeyFragment(entry.bookId, h.pageNumber, h.quote));
  }
  if (entry.pageNumber != null) {
    keys.add(repasoSourceKeyPage(entry.bookId, entry.pageNumber!));
  }
  return keys.toList();
}

bool _quotesAlignForRepaso(String a, String b) {
  final x = a.trim();
  final y = b.trim();
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  if (x.length >= 20 && y.contains(x)) return true;
  if (y.length >= 20 && x.contains(y)) return true;
  final short = x.length <= y.length ? x : y;
  final long = x.length <= y.length ? y : x;
  if (short.length >= 12 && long.contains(short)) return true;
  return false;
}

bool _qaContextMatchesEntry({
  required String contextQuestion,
  required ReviewListEntry entry,
  required String bookId,
  required List<String> resolvedKeys,
}) {
  if (resolvedKeys.contains(contextQuestion)) {
    return true;
  }
  if (repasoSourceKeysForEntry(entry).contains(contextQuestion)) {
    return true;
  }
  final highlightId = entry.highlight?.id;
  if (highlightId != null &&
      contextQuestion.startsWith('${kRepasoSrcPrefix}fragments:$bookId:')) {
    final suffix = contextQuestion.substring(
      '${kRepasoSrcPrefix}fragments:$bookId:'.length,
    );
    return suffix.split('|').contains(highlightId);
  }
  return false;
}

bool _qaRowMatchesHighlightLegacy({
  required Map<String, dynamic> row,
  required String contextQuestion,
  required Highlight highlight,
  required String bookId,
}) {
  final fragKey = repasoSourceKeyFragment(
    bookId,
    highlight.pageNumber,
    highlight.quote,
  );
  if (contextQuestion == fragKey) return true;

  if (contextQuestion.contains(kLiveStudyFragmentId)) {
    final stored = row['quote']?.toString().trim() ?? '';
    final hq = highlight.quote.trim();
    if (stored.isNotEmpty && hq.isNotEmpty) {
      if (stored == hq) return true;
      final a = hq.length > 80 ? hq.substring(0, 80) : hq;
      final b = stored.length > 80 ? stored.substring(0, 80) : stored;
      if (stored.contains(a) || hq.contains(b)) return true;
    }
  }
  return false;
}

Future<List<Map<String, dynamic>>> listPersistedQaForEntry(
  BooksRepository repo, {
  required ReviewListEntry entry,
  String? bookTitle,
  String? chapterTitle,
}) async {
  final bookId = entry.bookId;
  final resolvedKeys = await repasoSourceKeysForEntryResolved(repo, entry);
  final matchedHighlight =
      entry.highlight ?? await findHighlightMatchingRepasoEntry(repo, entry);
  final rows = await repo.listStudyCards(bookId);
  final out = <Map<String, dynamic>>[];
  final seenIds = <String>{};
  final entryQuote =
      (matchedHighlight?.quote ?? entry.card?['quote'] ?? entry.excerpt)
          .toString()
          .trim();

  for (final r in rows) {
    if (!isPersistedQa(r)) continue;
    final id = r['id']?.toString();
    if (id != null && seenIds.contains(id)) continue;

    final ctx = r['context_question']?.toString() ?? '';
    var match = _qaContextMatchesEntry(
      contextQuestion: ctx,
      entry: entry,
      bookId: bookId,
      resolvedKeys: resolvedKeys,
    );
    if (!match && entryQuote.isNotEmpty) {
      final rowQuote = r['quote']?.toString() ?? '';
      if (_quotesAlignForRepaso(rowQuote, entryQuote)) match = true;
    }
    if (!match && matchedHighlight != null) {
      match = _qaRowMatchesHighlightLegacy(
        row: r,
        contextQuestion: ctx,
        highlight: matchedHighlight,
        bookId: bookId,
      );
    }
    if (!match) continue;

    if (id != null) seenIds.add(id);
    out.add({
      ...r,
      if (bookTitle != null) '_book_title': bookTitle,
      if (chapterTitle != null) '_chapter_title': chapterTitle,
    });
  }
  return out;
}

Future<List<Map<String, dynamic>>> listPersistedQaForSource(
  BooksRepository repo, {
  required String bookId,
  required String sourceKey,
  String? bookTitle,
  String? chapterTitle,
}) async {
  final rows = await repo.listStudyCards(bookId);
  final out = <Map<String, dynamic>>[];
  for (final r in rows) {
    if (!isPersistedQa(r)) continue;
    final ctx = r['context_question']?.toString() ?? '';
    if (ctx != sourceKey) continue;
    out.add({
      ...r,
      if (bookTitle != null) '_book_title': bookTitle,
      if (chapterTitle != null) '_chapter_title': chapterTitle,
    });
  }
  return out;
}

/// Prioridad: pendientes / review_again, luego no revisadas, luego resto (más antiguas primero para variar).
List<Map<String, dynamic>> selectQaForSession(
  List<Map<String, dynamic>> all,
  int target,
) {
  if (target <= 0 || all.isEmpty) return [];
  final copy = List<Map<String, dynamic>>.from(all);
  int rank(Map<String, dynamic> r) {
    final reviewed = r['reviewed'] == true;
    final again = r['review_again'] == true;
    if (again && !reviewed) return 0;
    if (!reviewed) return 1;
    return 2;
  }

  copy.sort((a, b) {
    final ra = rank(a);
    final rb = rank(b);
    if (ra != rb) return ra.compareTo(rb);
    final ca =
        DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(1970);
    final cb =
        DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(1970);
    return ca.compareTo(cb);
  });

  if (target >= copy.length) return copy;
  return copy.take(target).toList();
}

List<RepasoFlashcard> flashcardsFromQaRows(
  List<Map<String, dynamic>> rows,
  ReviewSourceType sourceType,
) {
  return rows
      .map((r) => flashcardFromQaRow(r, sourceType))
      .where((c) => c.question.isNotEmpty && c.answer.isNotEmpty)
      .toList();
}
