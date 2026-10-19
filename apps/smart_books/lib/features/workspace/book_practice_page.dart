import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/margen_scaffold.dart';
import '../../core/providers.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/models/book.dart';
import '../review/repaso_data.dart';
import '../review/repaso_models.dart';
import '../review/repaso_qa_store.dart';
import '../review/repaso_review_card.dart';
import '../review/repaso_session_page.dart';
import '../shared/bookifi_ui.dart';
import 'book_progress.dart';
import 'book_workspace_context_bar.dart';
import 'book_workspace_nav.dart';
import '../review/repaso_review_state.dart';
import '../review/repaso_save_ui.dart';
import 'practice_question_types.dart';

class BookPracticePage extends ConsumerStatefulWidget {
  const BookPracticePage({
    super.key,
    required this.bookId,
    this.initialPage,
  });

  final String bookId;
  final int? initialPage;

  @override
  ConsumerState<BookPracticePage> createState() => _BookPracticePageState();
}

class _BookPracticePageState extends ConsumerState<BookPracticePage> {
  Book? _book;
  var _loading = true;
  String? _error;
  List<ReviewListEntry> _entries = [];
  BookLearningProgress? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(booksRepositoryProvider);
      final book = await repo.getBook(widget.bookId);
      if (book == null) throw Exception('Libro no encontrado');
      final cards = await repo.listStudyCards(widget.bookId);
      final entries = await loadRepasoEntriesForBook(repo, book);
      if (!mounted) return;
      setState(() {
        _book = book;
        _entries = entries;
        _progress = computeBookLearningProgress(
          book: book,
          repasoEntries: entries,
          studyCards: cards,
          materials: const [],
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _patchCardReview(String id, RepasoReviewUiState state) async {
    await ref.read(booksRepositoryProvider).patchStudyCard(
      id,
      repasoReviewPatch(state),
    );
    bumpRepasoReloadTick(ref);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return MargenScaffold(
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _book == null) {
      return MargenScaffold(
        body: Center(child: Text(_error ?? 'Libro no disponible')),
      );
    }

    final book = _book!;
    final page = widget.initialPage ?? book.currentPage;
    return MargenScaffold(
      bookContextBar: BookWorkspaceContextBar(
        bookId: book.id,
        title: book.title,
        subtitle: 'Practicar',
        page: page,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BookWorkspaceNav(
            bookId: book.id,
            current: BookWorkspaceMode.practicar,
            page: page,
          ),
          if (_progress != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: BookifiCard(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Preguntas listas: ${_progress!.questionsTotal} · '
                  'Revisadas: ${_progress!.questionsReviewed} · '
                  'Pendientes: ${_progress!.questionsPending}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: BookifiPrimaryButton(
              label: 'Empezar repaso del libro',
              onPressed: _progress == null || _progress!.questionsTotal == 0
                  ? null
                  : () async {
                      await openRepasoSessionForBook(context, ref, book);
                      if (mounted) await _load();
                    },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Formatos avanzados (en preparación)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(
            height: 88,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: PracticeQuestionFormat.values
                  .where((f) => f != PracticeQuestionFormat.openQa)
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: Text(f.label),
                        backgroundColor:
                            AppTokens.purple.withValues(alpha: 0.08),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Text(
                      'Genera preguntas desde Estudiar o Repaso para practicar.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _entries.length,
                    itemBuilder: (_, i) {
                      final entry = _entries[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: RepasoReviewCard(
                          entry: entry,
                          onRepasoDataChanged: _load,
                          onReviewed: entry.card != null && isPersistedQa(entry.card!)
                              ? () => _patchCardReview(
                                    entry.card!['id'].toString(),
                                    RepasoReviewUiState.reviewed,
                                  )
                              : null,
                          onRepasar: entry.card != null && isPersistedQa(entry.card!)
                              ? () => _patchCardReview(
                                    entry.card!['id'].toString(),
                                    RepasoReviewUiState.reviewAgain,
                                  )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
