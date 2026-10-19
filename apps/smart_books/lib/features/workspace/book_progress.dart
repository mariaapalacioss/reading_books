import '../../data/models/book.dart';
import '../review/repaso_models.dart';
import '../review/repaso_qa_store.dart';
import 'book_materials.dart';

class BookLearningProgress {
  const BookLearningProgress({
    required this.readingPercent,
    required this.materialsCreated,
    required this.questionsTotal,
    required this.questionsReviewed,
    required this.questionsPending,
    required this.repasoItemsPending,
  });

  final double readingPercent;
  final int materialsCreated;
  final int questionsTotal;
  final int questionsReviewed;
  final int questionsPending;
  final int repasoItemsPending;

  int get practiceReadyCount => questionsTotal;
}

BookLearningProgress computeBookLearningProgress({
  required Book book,
  required List<ReviewListEntry> repasoEntries,
  required List<Map<String, dynamic>> studyCards,
  required List<BookMaterialItem> materials,
}) {
  var qaTotal = 0;
  var qaReviewed = 0;
  var qaPending = 0;
  for (final row in studyCards) {
    if (!isPersistedQa(row)) continue;
    qaTotal++;
    if (row['reviewed'] == true) {
      qaReviewed++;
    } else {
      qaPending++;
    }
  }

  var repasoPending = 0;
  for (final e in repasoEntries) {
    if (e.pending && !e.reviewed) repasoPending++;
  }

  final pages = book.pageCount > 0 ? book.pageCount : 1;
  final readPct = (book.currentPage / pages).clamp(0.0, 1.0);

  return BookLearningProgress(
    readingPercent: readPct,
    materialsCreated: materials.length,
    questionsTotal: qaTotal,
    questionsReviewed: qaReviewed,
    questionsPending: qaPending,
    repasoItemsPending: repasoPending,
  );
}
