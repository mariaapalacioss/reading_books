import '../../data/models/book.dart';
import '../../data/models/chapter.dart';
import '../../data/repositories/books_repository.dart';
import 'repaso_models.dart';
import 'repaso_qa_store.dart';

Future<List<ReviewListEntry>> loadRepasoEntriesForBook(
  BooksRepository repo,
  Book book,
) async {
  final chapters = await repo.listChapters(book.id);
  final chapterById = {for (final c in chapters) c.id: c};

  String? titleForChapter(String? id) =>
      id == null ? null : chapterById[id]?.title;

  final points = await repo.listPoints(book.id);
  final cards = await repo.listStudyCards(book.id);
  final highlights = await repo.listHighlights(book.id);

  final entries = <ReviewListEntry>[];
  final captureQuotes = <String>{};

  final qaContextKeys = <String>{};
  for (final c in cards) {
    if (isPersistedQa(c)) {
      final ctx = c['context_question']?.toString() ?? '';
      if (ctx.startsWith(kRepasoSrcPrefix)) qaContextKeys.add(ctx);
      continue;
    }
    final chId = c['chapter_id']?.toString();
    final e = ReviewListEntry.fromStudyCard(
      c,
      bookTitle: book.title,
      chapterTitle: titleForChapter(chId),
    );
    if (e != null) {
      entries.add(e);
      if (e.sourceType == ReviewSourceType.resaltado)
        captureQuotes.add(e.excerpt);
    }
  }

  for (final h in highlights.where((h) => h.origin == 'user' && !h.dismissed)) {
    if (captureQuotes.contains(h.quote)) continue;
    entries.add(
      ReviewListEntry.fromHighlight(
        h,
        bookTitle: book.title,
        chapterTitle: titleForChapter(h.chapterId),
      ),
    );
  }

  for (final p in points) {
    final chId = p['chapter_id']?.toString();
    final e = ReviewListEntry.fromPoint(
      p,
      bookId: book.id,
      bookTitle: book.title,
      chapterTitle: titleForChapter(chId),
    );
    if (e != null) entries.add(e);
  }

  for (final ctx in qaContextKeys) {
    final sample = cards.firstWhere(
      (c) => c['context_question']?.toString() == ctx,
      orElse: () => <String, dynamic>{},
    );
    if (sample.isEmpty) continue;
    final page = sample['page_number'];
    final pageNum = page is num ? page.toInt() : int.tryParse('$page');
    entries.add(
      ReviewListEntry.fromQaSourceKey(
        sourceKey: ctx,
        bookId: book.id,
        bookTitle: book.title,
        title: repasoTitleForQaContextKey(ctx),
        excerpt: sample['body']?.toString() ?? 'Preguntas de repaso',
        pageNumber: pageNum,
        chapterTitle: chapterTitleForPage(chapters, pageNum),
      ),
    );
  }

  return entries;
}

String repasoTitleForQaContextKey(String sourceKey) {
  const fragPrefix = '${kRepasoSrcPrefix}fragments:';
  if (sourceKey.startsWith(fragPrefix)) {
    final afterBook = sourceKey.substring(fragPrefix.length);
    final idsPart = afterBook.contains(':') ? afterBook.split(':').last : '';
    final count = idsPart.split('|').where((s) => s.isNotEmpty).length;
    return count <= 1
        ? 'Preguntas · fragmento'
        : 'Preguntas · $count fragmentos';
  }
  const pagesPrefix = '${kRepasoSrcPrefix}pages:';
  if (sourceKey.startsWith(pagesPrefix)) {
    final afterBook = sourceKey.substring(pagesPrefix.length);
    if (afterBook.contains(':')) {
      return 'Preguntas · páginas ${afterBook.split(':').last}';
    }
  }
  const pagePrefix = '${kRepasoSrcPrefix}page:';
  if (sourceKey.startsWith(pagePrefix)) {
    final afterBook = sourceKey.substring(pagePrefix.length);
    if (afterBook.contains(':')) {
      return 'Preguntas · página ${afterBook.split(':').last}';
    }
  }
  return 'Preguntas de repaso';
}

String? chapterTitleForPage(List<Chapter> chapters, int? page) {
  if (page == null) return null;
  for (final c in chapters) {
    if (page >= c.startPage && page <= c.endPage) return c.title;
  }
  return null;
}
