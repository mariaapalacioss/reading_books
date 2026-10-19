import '../../data/models/book.dart';
import '../../data/repositories/books_repository.dart';
import '../review/repaso_data.dart';
import '../review/repaso_models.dart';
import '../review/repaso_qa_store.dart';

class ProfileUserStats {
  const ProfileUserStats({
    required this.bookCount,
    required this.fragmentCount,
    required this.questionCount,
  });

  final int bookCount;
  final int fragmentCount;
  final int questionCount;

  static const empty = ProfileUserStats(
    bookCount: 0,
    fragmentCount: 0,
    questionCount: 0,
  );
}

Future<ProfileUserStats> computeProfileUserStats(
  BooksRepository repo,
  List<Book> books,
) async {
  if (books.isEmpty) return ProfileUserStats.empty;

  var fragments = 0;
  var questions = 0;

  for (final book in books) {
    final cards = await repo.listStudyCards(book.id);
    for (final row in cards) {
      if (isPersistedQa(row)) questions++;
    }
    final entries = await loadRepasoEntriesForBook(repo, book);
    fragments += RepasoCounts.fromEntries(entries).fragmentos;
  }

  return ProfileUserStats(
    bookCount: books.length,
    fragmentCount: fragments,
    questionCount: questions,
  );
}
