import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/margen_scaffold.dart';
import '../../core/providers.dart';
import '../../core/ui/app_snackbar.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/models/book.dart';
import '../../data/models/chapter.dart';
import '../../data/models/highlight.dart';
import '../../services/document_profile_service.dart';
import '../assist/assist_panel.dart';
import '../review/repaso_data.dart';
import '../shared/bookifi_ui.dart';
import 'adaptive_tools.dart';
import 'book_materials.dart';
import 'book_notes_service.dart';
import 'book_progress.dart';
import 'book_workspace_context_bar.dart';
import 'book_workspace_nav.dart';
import 'document_profile.dart';

class BookStudyPage extends ConsumerStatefulWidget {
  const BookStudyPage({
    super.key,
    required this.bookId,
    this.initialPage,
  });

  final String bookId;
  final int? initialPage;

  @override
  ConsumerState<BookStudyPage> createState() => _BookStudyPageState();
}

class _BookStudyPageState extends ConsumerState<BookStudyPage> {
  Book? _book;
  List<Chapter> _chapters = [];
  List<Highlight> _highlights = [];
  List<BookMaterialItem> _materials = [];
  BookLearningProgress? _progress;
  DocumentProfile _profile = const DocumentProfile();
  var _loading = true;
  String? _error;
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

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
      final chapters = await repo.listChapters(widget.bookId);
      final highlights = await repo.listHighlights(widget.bookId);
      final cards = await repo.listStudyCards(widget.bookId);
      final entries = await loadRepasoEntriesForBook(repo, book);
      final fromEntries = materialsFromRepasoEntries(entries);
      final fromCards = materialsFromStudyCards(cards, bookTitle: book.title);
      final materials = mergeMaterials(fromEntries, fromCards);
      final profileSvc = DocumentProfileService(repo);
      final profile = await profileSvc.loadOrAnalyze(book);
      if (!mounted) return;
      setState(() {
        _book = book;
        _chapters = chapters;
        _highlights = highlights;
        _materials = materials;
        _profile = profile;
        _progress = computeBookLearningProgress(
          book: book,
          repasoEntries: entries,
          studyCards: cards,
          materials: materials,
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

  Future<void> _saveQuickNote() async {
    final book = _book;
    final text = _noteCtrl.text.trim();
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (book == null || userId == null || text.isEmpty) return;
    final page = widget.initialPage ?? book.currentPage;
    String? chapterId;
    for (final ch in _chapters) {
      if (page >= ch.startPage && page <= ch.endPage) {
        chapterId = ch.id;
        break;
      }
    }
    await BookNotesService(ref.read(booksRepositoryProvider)).savePageNote(
      bookId: book.id,
      userId: userId,
      pageNumber: page,
      chapterId: chapterId,
      body: text,
    );
    _noteCtrl.clear();
    if (!mounted) return;
    await _load();
    bumpRepasoReloadTick(ref);
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
    final tools = adaptiveToolsForProfile(_profile);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return MargenScaffold(
      bookContextBar: BookWorkspaceContextBar(
        bookId: book.id,
        title: book.title,
        subtitle: 'Estudiar · p. $page',
        page: page,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BookWorkspaceNav(
            bookId: book.id,
            current: BookWorkspaceMode.estudiar,
            page: page,
          ),
          if (_progress != null) _ProgressStrip(progress: _progress!),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tools
                  .map(
                    (t) => ActionChip(
                      label: Text(t.label),
                      onPressed: () {
                        showAppSnackBar(
                          '${t.label}: usa Asistencia abajo o abre Leer para seleccionar en el PDF.',
                        );
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _materialsPane(book)),
                      const VerticalDivider(width: 1),
                      Expanded(
                        flex: 2,
                        child: _assistPane(book, page),
                      ),
                    ],
                  )
                : DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const TabBar(
                          tabs: [
                            Tab(text: 'Materiales'),
                            Tab(text: 'Asistencia'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _materialsPane(book),
                              _assistPane(book, page),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          _quickNoteBar(),
        ],
      ),
    );
  }

  Widget _materialsPane(Book book) {
    if (_materials.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Aún no hay materiales guardados para este libro.\n'
            'Genera resúmenes, explicaciones o preguntas con Asistencia y guárdalos en Repaso.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _materials.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final m = _materials[i];
        return BookifiCard(
          padding: const EdgeInsets.all(12),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${m.kind.label}${m.pageNumber != null ? ' · p.${m.pageNumber}' : ''}\n${m.preview}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: m.pageNumber != null
                ? IconButton(
                    icon: const Icon(Icons.menu_book_outlined),
                    onPressed: () => context.push(
                      '/libro/${book.id}?page=${m.pageNumber}',
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _assistPane(Book book, int page) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: AssistPanel(
        book: book,
        page: page,
        chapters: _chapters,
        highlights: _highlights,
        embedded: true,
      ),
    );
  }

  Widget _quickNoteBar() {
    return Material(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  hintText: 'Nota rápida ligada a la página actual…',
                  isDense: true,
                ),
                minLines: 1,
                maxLines: 2,
              ),
            ),
            const SizedBox(width: 8),
            BookifiPrimaryButton(
              label: 'Nota',
              onPressed: _saveQuickNote,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.progress});

  final BookLearningProgress progress;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: BookifiCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Progreso del libro',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: progress.readingPercent,
                    backgroundColor: AppTokens.purple.withValues(alpha: 0.12),
                    color: AppTokens.purple,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${progress.materialsCreated} materiales',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                Text(
                  '${progress.questionsReviewed}/${progress.questionsTotal} preguntas revisadas',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                Text(
                  '${progress.repasoItemsPending} repaso pendiente',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
