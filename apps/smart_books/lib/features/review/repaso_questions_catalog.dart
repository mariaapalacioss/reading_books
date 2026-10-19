import '../../data/models/book.dart';
import '../../data/repositories/books_repository.dart';
import 'repaso_data.dart';
import 'repaso_models.dart';
import 'repaso_qa_store.dart';

class RepasoQaGroup {
  const RepasoQaGroup({
    required this.bookId,
    required this.bookTitle,
    required this.sourceKey,
    required this.title,
    required this.count,
    this.pageNumber,
    this.chapterTitle,
  });

  final String bookId;
  final String bookTitle;
  final String sourceKey;
  final String title;
  final int count;
  final int? pageNumber;
  final String? chapterTitle;

  ReviewListEntry toEntry() {
    return ReviewListEntry.fromQaSourceKey(
      sourceKey: sourceKey,
      bookId: bookId,
      bookTitle: bookTitle,
      title: title,
      excerpt: '$count preguntas guardadas',
      pageNumber: pageNumber,
      chapterTitle: chapterTitle,
    );
  }
}

class RepasoQaCatalog {
  const RepasoQaCatalog({required this.total, required this.groups});

  final int total;
  final List<RepasoQaGroup> groups;
}

Future<RepasoQaCatalog> loadRepasoQaCatalog(
  BooksRepository repo,
  List<Book> books,
) async {
  final groups = <RepasoQaGroup>[];
  var total = 0;

  for (final book in books) {
    final cards = await repo.listStudyCards(book.id);
    final chapters = await repo.listChapters(book.id);
    final byKey = <String, List<Map<String, dynamic>>>{};

    for (final row in cards) {
      if (!isPersistedQa(row)) continue;
      total++;
      final ctx = row['context_question']?.toString().trim() ?? '';
      final key = ctx.isNotEmpty ? ctx : 'orphan:${row['id']}';
      byKey.putIfAbsent(key, () => []).add(row);
    }

    for (final entry in byKey.entries) {
      final sample = entry.value.first;
      final page = sample['page_number'];
      final pageNum = page is num ? page.toInt() : int.tryParse('$page');
      final title = entry.key.startsWith('orphan:')
          ? 'Preguntas de repaso'
          : repasoTitleForQaContextKey(entry.key);
      groups.add(
        RepasoQaGroup(
          bookId: book.id,
          bookTitle: book.title,
          sourceKey: entry.key.startsWith('orphan:') ? entry.key : entry.key,
          title: title,
          count: entry.value.length,
          pageNumber: pageNum,
          chapterTitle: chapterTitleForPage(chapters, pageNum),
        ),
      );
    }
  }

  groups.sort((a, b) => b.count.compareTo(a.count));
  return RepasoQaCatalog(total: total, groups: groups);
}

Future<List<Map<String, dynamic>>> loadAllPersistedQaRows(
  BooksRepository repo,
  List<Book> books,
) async {
  final out = <Map<String, dynamic>>[];
  for (final book in books) {
    final chapters = await repo.listChapters(book.id);
    final cards = await repo.listStudyCards(book.id);
    for (final row in cards) {
      if (!isPersistedQa(row)) continue;
      final page = row['page_number'];
      final pageNum = page is num ? page.toInt() : int.tryParse('$page');
      out.add({
        ...row,
        '_book_title': book.title,
        '_chapter_title': chapterTitleForPage(chapters, pageNum),
      });
    }
  }
  return out;
}
