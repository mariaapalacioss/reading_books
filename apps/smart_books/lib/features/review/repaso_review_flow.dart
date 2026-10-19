import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/ui/app_snackbar.dart';
import '../../domain/content_language.dart';
import '../../data/models/book.dart';
import '../../data/repositories/books_repository.dart';
import '../../data/models/chapter.dart';
import '../../features/chatgpt/chatgpt_platform.dart';
import '../../domain/study_scope.dart';
import '../../services/review_questions_service.dart';
import 'repaso_feedback.dart';
import 'repaso_flashcard_session.dart';
import 'repaso_models.dart';
import 'repaso_qa_store.dart';
import 'repaso_source_text.dart';

enum GenerateMoreChoice { cancel, useSaved, generateMore }

bool _repasoGenerationInProgress = false;

Future<T?> showRepasoDialog<T>(
  BuildContext context,
  Widget Function(BuildContext ctx) builder,
) {
  final theme = Theme.of(context);
  return showDialog<T>(
    context: context,
    builder: (ctx) => Theme(data: theme, child: builder(ctx)),
  );
}

List<int> _countPickerOptions(int? maxRecommended) {
  const defaults = [3, 5, 8, 10, 15, 20];
  if (maxRecommended == null) return [5, 10, 15, 20];
  final filtered = defaults.where((n) => n <= maxRecommended).toList();
  if (filtered.isEmpty) return [maxRecommended];
  return filtered;
}

/// Cuántas preguntas quiere repasar el usuario (objetivo de sesión).
Future<int?> pickQuestionCount(
  BuildContext context, {
  int? savedAvailable,
  int? maxRecommended,
}) {
  return showRepasoDialog<int>(
    context,
    (ctx) => _CountPickerDialog(
      savedAvailable: savedAvailable,
      maxRecommended: maxRecommended,
    ),
  );
}

class _CountPickerDialog extends StatefulWidget {
  const _CountPickerDialog({this.savedAvailable, this.maxRecommended});
  final int? savedAvailable;
  final int? maxRecommended;

  @override
  State<_CountPickerDialog> createState() => _CountPickerDialogState();
}

class _CountPickerDialogState extends State<_CountPickerDialog> {
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _pick(int? v) => Navigator.pop(context, v);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('¿Cuántas preguntas quieres repasar?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.savedAvailable != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${widget.savedAvailable} preguntas guardadas disponibles para esta fuente.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (widget.maxRecommended != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Para este texto, lo ideal es hasta ${widget.maxRecommended} preguntas (más rápido).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in _countPickerOptions(widget.maxRecommended))
                OutlinedButton(onPressed: () => _pick(n), child: Text('$n')),
              if (widget.maxRecommended == null || widget.maxRecommended! > 8)
                OutlinedButton(
                  onPressed: () => _pick(9999),
                  child: const Text('Todas'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _customCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Personalizado',
              hintText: 'Ej. 12',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final n = int.tryParse(_customCtrl.text.trim());
            if (n != null && n > 0) _pick(n);
          },
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

Future<RepasoGenerateScope?> pickGenerateScope(
  BuildContext context, {
  required bool hasChapter,
  required bool hasFragment,
}) {
  final options = <(RepasoGenerateScope, String)>[];
  if (hasChapter) {
    options.add((RepasoGenerateScope.currentChapter, 'Capítulo actual'));
    options.add((
      RepasoGenerateScope.savedChapterContent,
      'Contenido guardado del capítulo',
    ));
  }
  options.add((RepasoGenerateScope.currentPage, 'Página actual'));
  if (hasFragment) {
    options.add((
      RepasoGenerateScope.selectedFragment,
      'Fragmento seleccionado',
    ));
  }

  return showDialog<RepasoGenerateScope>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('¿Qué quieres repasar?'),
      children: [
        for (final (scope, label) in options)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, scope),
            child: Text(label),
          ),
      ],
    ),
  );
}

Future<GenerateMoreChoice?> confirmGenerateMore(
  BuildContext context, {
  required int saved,
  required int missing,
}) {
  return showDialog<GenerateMoreChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Preguntas guardadas'),
      content: Text(
        'Hay $saved preguntas guardadas. ¿Quieres generar $missing más con IA?\n\n'
        'No se generará nada sin tu confirmación.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, GenerateMoreChoice.cancel),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, GenerateMoreChoice.useSaved),
          child: Text('Repasar las $saved'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, GenerateMoreChoice.generateMore),
          child: Text('Generar $missing más'),
        ),
      ],
    ),
  );
}

int normalizeTargetCount(int picked, int available) {
  if (picked >= 9999) return available;
  return picked;
}

Future<bool> confirmGenerateInitialQuestions(BuildContext context) async {
  final result = await showRepasoDialog<bool>(
    context,
    (ctx) => AlertDialog(
      title: const Text('Sin preguntas guardadas'),
      content: const Text(
        'No hay preguntas de repaso guardadas para este contenido.\n\n'
        '¿Quieres generarlas con IA a partir del texto real del fragmento o página?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Generar'),
        ),
      ],
    ),
  );
  return result == true;
}

Future<List<Map<String, dynamic>>> _generatePersistedQaForEntry(
  BuildContext context,
  WidgetRef ref, {
  required ReviewListEntry entry,
  required String sourceKey,
  required int requestedCount,
}) async {
  if (_repasoGenerationInProgress) {
    debugPrint(
      '[REPASO FLOW] generation already in progress, ignoring duplicate',
    );
    return [];
  }
  _repasoGenerationInProgress = true;

  final repo = ref.read(booksRepositoryProvider);
  final client = ref.read(supabaseClientProvider);
  final session = client.auth.currentSession;
  if (session == null || session.accessToken.isEmpty) {
    _repasoGenerationInProgress = false;
    showAppSnackBar('Tu sesión expiró. Vuelve a iniciar sesión.');
    return [];
  }
  final userId = session.user.id;

  if (!chatGptConnectEnabled) {
    _repasoGenerationInProgress = false;
    showAppSnackBar('Conecta ChatGPT Plus en Ajustes (iPhone, iPad o Mac).');
    return [];
  }
  final creds = await ref.read(chatGptCredentialsProvider.future);
  if (creds == null || !creds.hasPlanUsage) {
    _repasoGenerationInProgress = false;
    showAppSnackBar(
      'Conecta ChatGPT Plus antes de generar preguntas de repaso.',
    );
    return [];
  }

  final service = ref.read(reviewQuestionsServiceProvider);

  debugPrint(
    '[REPASO FLOW] calling generateAndPersist requested=$requestedCount',
  );
  showAppLoadingOverlay();

  try {
    debugPrint('[REPASO FLOW] gathering source text...');
    final sourceText = await service.gatherSourceTextFromReviewEntry(entry);
    debugPrint('[REPASO FLOW] source text ready chars=${sourceText.length}');

    final book = await repo.getBook(entry.bookId);

    final useFragmentScope =
        entry.highlight != null || isCaptureStudyCardEntry(entry);
    final fragmentQuote = meaningfulRepasoText(
      entry.highlight?.quote ?? entry.card?['quote']?.toString(),
      bookTitle: entry.bookTitle,
    );

    final batch = await service.generateAndPersist(
      userId: userId,
      bookId: entry.bookId,
      bookTitle: entry.bookTitle,
      sourceText: sourceText,
      requestedCount: requestedCount,
      sourceType: entry.sourceType.name,
      scope: useFragmentScope
          ? RepasoGenerateScope.selectedFragment
          : RepasoGenerateScope.currentPage,
      sourceKey: sourceKey,
      chapterId: entry.chapterId,
      chapterTitle: entry.chapterTitle,
      pageNumber: entry.pageNumber,
      quote: fragmentQuote,
      metadataLanguage: book?.language,
      localeFallback: book?.explanationLanguage,
    );

    debugPrint(
      '[REPASO FLOW] generation complete generated=${batch.generated}',
    );

    if (batch.generated < requestedCount) {
      showAppSnackBar(
        batch.message ??
            'Se generaron ${batch.generated} preguntas útiles de las $requestedCount solicitadas.',
      );
    }

    debugLogPersistedQaRows(batch.insertedRows);

    if (batch.insertedRows.isNotEmpty) {
      notifyRepasoSaved(ref, message: kRepasoQuestionsSavedSnackMessage);
      if (isCaptureStudyCardEntry(entry) &&
          entry.card?['id'] != null &&
          sourceKey.startsWith(kRepasoSrcPrefix)) {
        final cardCtx = entry.card!['context_question']?.toString() ?? '';
        if (!cardCtx.startsWith(kRepasoSrcPrefix)) {
          await repo.patchStudyCard(entry.card!['id'].toString(), {
            'context_question': sourceKey,
          });
        }
      }
      dismissAppLoadingOverlay();
      return batch.insertedRows.where(isPersistedQa).map((r) {
        return {
          ...r,
          '_book_title': entry.bookTitle,
          if (entry.chapterTitle != null) '_chapter_title': entry.chapterTitle,
        };
      }).toList();
    }

    dismissAppLoadingOverlay();
    return await listPersistedQaForEntry(
      repo,
      entry: entry,
      bookTitle: entry.bookTitle,
      chapterTitle: entry.chapterTitle,
    );
  } catch (e, st) {
    debugPrint('[REPASO FLOW] ERROR: $e');
    debugPrint('[REPASO FLOW] STACK: $st');
    showAppSnackBar('$e'.replaceFirst('Exception: ', ''));
    return [];
  } finally {
    dismissAppLoadingOverlay();
    _repasoGenerationInProgress = false;
    debugPrint('[REPASO FLOW] dismiss loading (finally)');
  }
}

Future<void> _startQaSession(
  BuildContext context,
  BooksRepository repo, {
  required ReviewListEntry entry,
  required List<Map<String, dynamic>> saved,
  required int target,
  VoidCallback? onReviewedLegacy,
  VoidCallback? onRepasarLegacy,
}) async {
  if (saved.isEmpty) return;
  final selected = selectQaForSession(
    saved,
    normalizeTargetCount(target, saved.length),
  );
  final cards = flashcardsFromQaRows(selected, entry.sourceType);
  if (cards.isEmpty) return;

  if (!context.mounted) return;
  await showRepasoReviewSession(
    context,
    entry: entry,
    bookId: entry.bookId,
    cards: cards,
    onReviewed: () async {
      for (final row in selected) {
        final id = row['id']?.toString();
        if (id != null) {
          await repo.patchStudyCard(id, {
            'reviewed': true,
            'review_again': false,
          });
        }
      }
      onReviewedLegacy?.call();
    },
    onRepasar: () async {
      for (final row in selected) {
        final id = row['id']?.toString();
        if (id != null) await repo.patchStudyCard(id, {'review_again': true});
      }
      onRepasarLegacy?.call();
    },
  );
}

/// Flujo Repaso al pulsar «Repasar» en una entrada.
Future<void> runRepasoReviewFlow(
  BuildContext context,
  WidgetRef ref, {
  required ReviewListEntry entry,
  required VoidCallback? onReviewedLegacy,
  required VoidCallback? onRepasarLegacy,
  VoidCallback? onRepasoDataChanged,
}) async {
  debugPrint('[REPASO FLOW] start entry=${entry.id}');
  debugLogRepasoEntry(entry);
  final repo = ref.read(booksRepositoryProvider);
  final sourceKey = await repasoPrimarySourceKeyForEntry(repo, entry);

  var saved = await listPersistedQaForEntry(
    repo,
    entry: entry,
    bookTitle: entry.bookTitle,
    chapterTitle: entry.chapterTitle,
  );

  final entryIsPersistedQa = entry.card != null && isPersistedQa(entry.card!);
  if (saved.isEmpty && entryIsPersistedQa) {
    saved = [
      {
        ...entry.card!,
        '_book_title': entry.bookTitle,
        '_chapter_title': entry.chapterTitle,
      },
    ];
  }

  if (saved.isEmpty && !entryIsPersistedQa) {
    if (!context.mounted) return;
    final wantsGenerate = await confirmGenerateInitialQuestions(context);
    if (!wantsGenerate || !context.mounted) return;

    final picked = await pickQuestionCount(context);
    if (picked == null || !context.mounted) return;
    final requested = picked >= 9999 ? 20 : picked;
    debugPrint('[REPASO FLOW] count selected = $requested');

    saved = await _generatePersistedQaForEntry(
      context,
      ref,
      entry: entry,
      sourceKey: sourceKey,
      requestedCount: requested,
    );
    onRepasoDataChanged?.call();
    if (saved.isEmpty) return;

    if (!context.mounted) return;
    debugPrint('[REPASO FLOW] opening session cards=${saved.length}');
    await _startQaSession(
      context,
      repo,
      entry: entry,
      saved: saved,
      target: picked,
      onReviewedLegacy: onReviewedLegacy,
      onRepasarLegacy: onRepasarLegacy,
    );
    return;
  }

  final picked = await pickQuestionCount(context, savedAvailable: saved.length);
  debugPrint('[REPASO FLOW] count selected = $picked');
  if (picked == null || !context.mounted) return;

  var target = picked >= 9999 ? saved.length : picked;

  if (saved.length < target) {
    final missing = target - saved.length;
    final choice = await confirmGenerateMore(
      context,
      saved: saved.length,
      missing: missing,
    );
    if (!context.mounted) return;
    if (choice == GenerateMoreChoice.cancel || choice == null) return;
    if (choice == GenerateMoreChoice.useSaved) {
      target = saved.length;
    } else if (choice == GenerateMoreChoice.generateMore) {
      saved = await _generatePersistedQaForEntry(
        context,
        ref,
        entry: entry,
        sourceKey: sourceKey,
        requestedCount: missing,
      );
      onRepasoDataChanged?.call();
      if (saved.isEmpty) return;
      target = normalizeTargetCount(
        picked >= 9999 ? saved.length : picked,
        saved.length,
      );
    }
  }

  await _startQaSession(
    context,
    repo,
    entry: entry,
    saved: saved,
    target: target,
    onReviewedLegacy: onReviewedLegacy,
    onRepasarLegacy: onRepasarLegacy,
  );
}

/// Generar preguntas desde un [StudyScope] ya resuelto (sin elegir capítulo/página).
Future<void> runAssistGenerateReviewFlowForStudyScope(
  BuildContext context,
  WidgetRef ref, {
  required Book book,
  required StudyScope scope,
}) async {
  if (!scope.isValidSource) {
    showAppSnackBar(
      'El contenido no tiene suficiente texto para generar preguntas.',
    );
    return;
  }

  final client = ref.read(supabaseClientProvider);
  final session = client.auth.currentSession;
  if (session == null || session.accessToken.isEmpty) {
    showAppSnackBar('Tu sesión expiró. Vuelve a iniciar sesión.');
    return;
  }
  final userId = session.user.id;

  if (!chatGptConnectEnabled) {
    showAppSnackBar('Conecta ChatGPT Plus en Ajustes (iPhone, iPad o Mac).');
    return;
  }
  final creds = await ref.read(chatGptCredentialsProvider.future);
  if (creds == null || !creds.hasPlanUsage) {
    showAppSnackBar(
      'Conecta ChatGPT Plus antes de generar preguntas de repaso.',
    );
    return;
  }

  final repo = ref.read(booksRepositoryProvider);
  final service = ref.read(reviewQuestionsServiceProvider);
  final planApi = ref.read(planApiProvider);
  final sourceText = scope.sourceText.trim();
  final maxForSource = suggestedReviewQuestionCount(sourceText);

  final sourceKey = repasoSourceKeyForStudyScope(scope);

  final sourceType = scope.kind == StudyScopeKind.fragments
      ? 'fragments'
      : 'pages';
  final pageNumber = scope.kind == StudyScopeKind.fragments
      ? scope.fragments.firstOrNull?.pageNumber ?? scope.startPage
      : scope.startPage;

  final savedFuture = listPersistedQaForSource(
    repo,
    bookId: book.id,
    sourceKey: sourceKey,
    bookTitle: book.title,
  );
  final saved = await savedFuture;
  try {
    await planApi.preferredModel(userId);
  } catch (_) {}

  if (!context.mounted) return;

  final count = await pickQuestionCount(
    context,
    savedAvailable: saved.isEmpty ? null : saved.length,
    maxRecommended: maxForSource,
  );
  if (count == null || !context.mounted) return;

  var requested = count >= 9999 ? maxForSource : count;
  requested = requested.clamp(1, maxForSource);

  if (_repasoGenerationInProgress) return;

  if (saved.length >= requested) {
    final pseudoEntry = ReviewListEntry(
      id: sourceKey,
      sourceType: ReviewSourceType.tarjeta,
      bookId: book.id,
      bookTitle: book.title,
      title: 'Preguntas de repaso',
      excerpt: sourceText.length <= 120
          ? sourceText
          : sourceText.substring(0, 120),
      pageNumber: pageNumber,
    );
    await _startQaSession(
      context,
      repo,
      entry: pseudoEntry,
      saved: saved,
      target: requested,
    );
    return;
  }

  _repasoGenerationInProgress = true;
  showAppLoadingOverlay();

  try {
    final fragmentQuote = scope.kind == StudyScopeKind.fragments
        ? scope.fragments.map((f) => f.quote).join('\n\n')
        : null;
    final batch = await service.generateAndPersist(
      userId: userId,
      bookId: book.id,
      bookTitle: book.title,
      sourceText: sourceText,
      requestedCount: requested,
      sourceType: sourceType,
      scope: RepasoGenerateScope.currentPage,
      sourceKey: sourceKey,
      pageNumber: pageNumber,
      quote: fragmentQuote,
      metadataLanguage: book.language,
      localeFallback: book.explanationLanguage,
    );

    if (!context.mounted) return;

    final resolved = resolveContentLanguage(
      sourceText: sourceText,
      metadataLanguage: book.language,
      localeFallback: contentLanguageFromCode(book.explanationLanguage),
    );
    final msg = batch.generated < requested
        ? batch.message ??
              reviewQuestionsPartialCountMessage(
                resolved,
                batch.generated,
                requested,
              )
        : resolved == ContentLanguage.en
        ? '${batch.generated} review questions were generated.'
        : 'Se generaron ${batch.generated} preguntas de repaso.';

    final inserted = batch.insertedRows;
    if (inserted.isNotEmpty) {
      notifyRepasoSaved(ref, message: kRepasoQuestionsSavedSnackMessage);
    }

    dismissAppLoadingOverlay();

    final sessionCards = inserted.isEmpty
        ? null
        : flashcardsFromQaRows(
            inserted
                .map((r) => {...r, '_book_title': book.title})
                .toList(),
            ReviewSourceType.tarjeta,
          );

    if (!context.mounted) return;
    await showRepasoDialog<void>(
      context,
      (ctx) => AlertDialog(
        title: const Text('Preguntas listas'),
        content: Text(batch.message != null ? '${batch.message}\n\n$msg' : msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/repaso');
            },
            child: const Text('Ver en Repaso'),
          ),
          if (sessionCards != null && sessionCards.isNotEmpty)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                final pseudoEntry = ReviewListEntry(
                  id: sourceKey,
                  sourceType: ReviewSourceType.tarjeta,
                  bookId: book.id,
                  bookTitle: book.title,
                  title: 'Preguntas de repaso',
                  excerpt: sourceText.length <= 120
                      ? sourceText
                      : sourceText.substring(0, 120),
                  pageNumber: pageNumber,
                );
                showRepasoReviewSession(
                  context,
                  entry: pseudoEntry,
                  bookId: book.id,
                  cards: sessionCards,
                  onReviewed: () {},
                  onRepasar: () {},
                );
              },
              child: const Text('Empezar repaso'),
            ),
        ],
      ),
    );
  } catch (e, st) {
    debugPrint('[REPASO FLOW] ERROR: $e');
    debugPrint('[REPASO FLOW] STACK: $st');
    showAppSnackBar('$e'.replaceFirst('Exception: ', ''));
  } finally {
    dismissAppLoadingOverlay();
    _repasoGenerationInProgress = false;
  }
}

/// Flujo Asistencia: generar y persistir preguntas.
Future<void> runAssistGenerateReviewFlow(
  BuildContext context,
  WidgetRef ref, {
  required Book book,
  required int page,
  required Chapter? chapter,
  required String? quote,
}) async {
  final client = ref.read(supabaseClientProvider);
  final session = client.auth.currentSession;
  if (session == null || session.accessToken.isEmpty) {
    showAppSnackBar('Tu sesión expiró. Vuelve a iniciar sesión.');
    return;
  }
  final userId = session.user.id;

  if (!chatGptConnectEnabled) {
    showAppSnackBar('Conecta ChatGPT Plus en Ajustes (iPhone, iPad o Mac).');
    return;
  }
  final creds = await ref.read(chatGptCredentialsProvider.future);
  if (creds == null || !creds.hasPlanUsage) {
    showAppSnackBar(
      'Conecta ChatGPT Plus antes de generar preguntas de repaso.',
    );
    return;
  }

  final count = await pickQuestionCount(context);
  if (count == null || !context.mounted) return;
  final requested = count >= 9999 ? 20 : count;
  debugPrint('[REPASO FLOW] count selected = $requested');

  final hasChapter = chapter != null;
  final hasFragment = quote != null && quote.trim().length >= 12;
  final scope = await pickGenerateScope(
    context,
    hasChapter: hasChapter,
    hasFragment: hasFragment,
  );
  if (scope == null || !context.mounted) return;
  debugPrint('[REPASO FLOW] scope selected = ${scope.name}');

  if (_repasoGenerationInProgress) return;

  final service = ref.read(reviewQuestionsServiceProvider);

  _repasoGenerationInProgress = true;
  showAppLoadingOverlay();

  try {
    debugPrint('[REPASO FLOW] gathering source text...');
    final sourceText = await service.gatherSourceText(
      scope: scope,
      bookId: book.id,
      pageNumber: page,
      chapterStartPage: chapter?.startPage,
      chapterEndPage: chapter?.endPage,
      quote: quote,
      chapterId: chapter?.id,
    );

    final sourceKey = switch (scope) {
      RepasoGenerateScope.selectedFragment => repasoSourceKeyFragment(
        book.id,
        page,
        quote ?? '',
      ),
      RepasoGenerateScope.currentPage => repasoSourceKeyPage(book.id, page),
      RepasoGenerateScope.currentChapter ||
      RepasoGenerateScope.savedChapterContent =>
        chapter != null
            ? repasoSourceKeyChapter(chapter.id)
            : repasoSourceKeyPage(book.id, page),
    };

    debugPrint('[REPASO FLOW] source text ready chars=${sourceText.length}');

    final batch = await service.generateAndPersist(
      userId: userId,
      bookId: book.id,
      bookTitle: book.title,
      sourceText: sourceText,
      requestedCount: requested,
      sourceType: scope.name,
      scope: scope,
      sourceKey: sourceKey,
      chapterId: chapter?.id,
      chapterTitle: chapter?.title,
      pageNumber: page,
      quote: quote,
      metadataLanguage: book.language,
      localeFallback: book.explanationLanguage,
    );

    debugPrint(
      '[REPASO FLOW] generation complete generated=${batch.generated}',
    );

    if (!context.mounted) return;

    final resolved = resolveContentLanguage(
      sourceText: sourceText,
      metadataLanguage: book.language,
      localeFallback: contentLanguageFromCode(book.explanationLanguage),
    );
    final msg = batch.generated < requested
        ? batch.message ??
              reviewQuestionsPartialCountMessage(
                resolved,
                batch.generated,
                requested,
              )
        : resolved == ContentLanguage.en
        ? '${batch.generated} review questions were generated.'
        : 'Se generaron ${batch.generated} preguntas de repaso.';

    final inserted = batch.insertedRows;
    if (inserted.isNotEmpty) {
      notifyRepasoSaved(ref, message: kRepasoQuestionsSavedSnackMessage);
    }

    dismissAppLoadingOverlay();

    final sessionCards = inserted.isEmpty
        ? null
        : flashcardsFromQaRows(
            inserted
                .map(
                  (r) => {
                    ...r,
                    '_book_title': book.title,
                    '_chapter_title': chapter?.title,
                  },
                )
                .toList(),
            ReviewSourceType.tarjeta,
          );

    if (!context.mounted) return;
    await showRepasoDialog<void>(
      context,
      (ctx) => AlertDialog(
        title: const Text('Preguntas listas'),
        content: Text(batch.message != null ? '${batch.message}\n\n$msg' : msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/repaso');
            },
            child: const Text('Ver en Repaso'),
          ),
          if (sessionCards != null && sessionCards.isNotEmpty)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                final pseudoEntry = ReviewListEntry(
                  id: sourceKey,
                  sourceType: ReviewSourceType.tarjeta,
                  bookId: book.id,
                  bookTitle: book.title,
                  title: 'Preguntas de repaso',
                  excerpt: sourceText.length <= 120
                      ? sourceText
                      : sourceText.substring(0, 120),
                  chapterId: chapter?.id,
                  chapterTitle: chapter?.title,
                  pageNumber: page,
                );
                showRepasoReviewSession(
                  context,
                  entry: pseudoEntry,
                  bookId: book.id,
                  cards: sessionCards,
                  onReviewed: () {},
                  onRepasar: () {},
                );
              },
              child: const Text('Empezar repaso'),
            ),
        ],
      ),
    );
  } catch (e, st) {
    debugPrint('[REPASO FLOW] ERROR: $e');
    debugPrint('[REPASO FLOW] STACK: $st');
    showAppSnackBar('$e'.replaceFirst('Exception: ', ''));
  } finally {
    dismissAppLoadingOverlay();
    _repasoGenerationInProgress = false;
    debugPrint('[REPASO FLOW] dismiss loading (finally)');
  }
}
