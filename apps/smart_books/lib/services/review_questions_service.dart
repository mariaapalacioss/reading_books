import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/repositories/books_repository.dart';
import '../domain/content_language.dart';
import '../domain/study_text.dart';
import '../features/chatgpt/assist_prompts.dart';
import '../features/chatgpt/chatgpt_platform.dart';
import '../features/chatgpt/plan_api.dart';
import '../features/review/repaso_models.dart';
import '../features/review/repaso_qa_store.dart';
import '../features/review/repaso_source_text.dart';
import 'practice_mcq_metadata.dart';

enum RepasoGenerateScope {
  currentPage,
  currentChapter,
  selectedFragment,
  savedChapterContent,
}

/// Máximo útil según cuánto texto hay (fragmentos cortos → menos preguntas → más rápido).
int suggestedReviewQuestionCount(String sourceText) {
  final len = sourceText.trim().length;
  if (len < 180) return 3;
  if (len < 450) return 5;
  if (len < 1200) return 8;
  if (len < 3500) return 12;
  if (len < 8000) return 15;
  return 20;
}

class GeneratedReviewBatch {
  const GeneratedReviewBatch({
    required this.requested,
    required this.generated,
    required this.message,
    required this.insertedRows,
  });

  final int requested;
  final int generated;
  final String? message;
  final List<Map<String, dynamic>> insertedRows;
}

class ReviewQuestionsService {
  ReviewQuestionsService(this._repo, {PlanApi? planApi})
    : _planApi = planApi ?? PlanApi();

  final BooksRepository _repo;
  final PlanApi _planApi;

  static const _generationTimeout = Duration(seconds: 120);
  static const _maxSourceCharsForInvoke = 12000;

  String _humanizeGenerationError(String? raw) {
    if (raw == null || raw.isEmpty) {
      return 'No se pudieron generar preguntas de repaso.';
    }
    final lower = raw.toLowerCase();
    if (lower.contains('conecta') && lower.contains('chatgpt')) {
      return raw;
    }
    if (lower.contains('chatgpt plus') || lower.contains('chatgpt.tokens')) {
      return raw;
    }
    return raw.replaceFirst(RegExp(r'^\d+\s+'), '');
  }

  void _ensureChatGptPlusReady() {
    if (!chatGptConnectEnabled) {
      throw Exception('Conecta ChatGPT Plus en Ajustes (iPhone, iPad o Mac).');
    }
  }

  Future<String> gatherSourceText({
    required RepasoGenerateScope scope,
    required String bookId,
    int? pageNumber,
    int? chapterStartPage,
    int? chapterEndPage,
    String? quote,
    String? chapterId,
  }) async {
    switch (scope) {
      case RepasoGenerateScope.currentPage:
        final page = pageNumber ?? 1;
        final row = await _repo.getPage(bookId, page);
        final text = normalizeStudyText(row?['text'] as String? ?? '');
        if (text.length < 40) {
          throw Exception('La página actual no tiene texto suficiente.');
        }
        return 'PDF $page\n\n$text';

      case RepasoGenerateScope.selectedFragment:
        final page = pageNumber ?? 1;
        final row = await _repo.getPage(bookId, page);
        final context = normalizeStudyText(row?['text'] as String? ?? '');
        final fragment = meaningfulRepasoText(quote, minLength: 12);
        if (fragment != null && context.length >= 40) {
          final pageContext = context.length > 12000
              ? context.substring(0, 12000)
              : context;
          return 'Fragmento:\n«$fragment»\n\nContexto página $page:\n$pageContext';
        }
        if (fragment != null) return 'Fragmento:\n«$fragment»';
        if (context.length >= 40) {
          final pageText = context.length > 12000
              ? context.substring(0, 12000)
              : context;
          return 'PDF $page\n\n$pageText';
        }
        throw Exception(
          'Selecciona un fragmento con texto o usa una página con texto extraído.',
        );

      case RepasoGenerateScope.currentChapter:
      case RepasoGenerateScope.savedChapterContent:
        if (chapterStartPage == null || chapterEndPage == null) {
          throw Exception('No hay capítulo en esta página.');
        }
        final pages = await _repo.listPagesInRange(
          bookId,
          chapterStartPage,
          chapterEndPage,
        );
        final parts = <String>[];
        for (final page in pages) {
          final text = normalizeStudyText(page['text'] as String? ?? '');
          if (text.length < 30) continue;
          parts.add('[p.${page['page_number']}]\n$text');
        }
        if (scope == RepasoGenerateScope.savedChapterContent &&
            chapterId != null) {
          final cards = await _repo.listStudyCards(bookId);
          for (final card in cards) {
            if (card['chapter_id']?.toString() != chapterId) continue;
            if (card['kind']?.toString() == 'qa') continue;
            final body = card['body']?.toString().trim() ?? '';
            if (body.length < 40) continue;
            parts.add(
              '[guardado ${card['assist_mode'] ?? card['kind']}]\n$body',
            );
          }
        }
        final packed = parts.join('\n\n');
        if (packed.length < 40) {
          throw Exception('No hay contenido suficiente en este capítulo.');
        }
        return packed.length > 22000 ? packed.substring(0, 22000) : packed;
    }
  }

  Future<GeneratedReviewBatch> generateAndPersist({
    required String userId,
    required String bookId,
    required String bookTitle,
    required String sourceText,
    required int requestedCount,
    required String sourceType,
    required RepasoGenerateScope scope,
    required String sourceKey,
    String? chapterId,
    String? chapterTitle,
    int? pageNumber,
    String? quote,
    String? metadataLanguage,
    String? localeFallback,
  }) async {
    debugPrint('[REVIEW QUESTIONS] ChatGPT Plus generation START');
    _ensureChatGptPlusReady();

    final normalizedSource = sourceText.trim();
    debugPrint(
      '[REVIEW QUESTIONS] source chars=${normalizedSource.length} requestedCount=$requestedCount',
    );

    if (normalizedSource.length < 40) {
      throw Exception(
        'El contenido no tiene suficiente texto para generar preguntas.',
      );
    }

    final capBySource = suggestedReviewQuestionCount(normalizedSource);
    final safeRequestedCount = requestedCount
        .clamp(1, 30)
        .clamp(1, capBySource);
    final cappedSource = normalizedSource.length > _maxSourceCharsForInvoke
        ? normalizedSource.substring(0, _maxSourceCharsForInvoke)
        : normalizedSource;

    final resolved = resolveContentLanguage(
      sourceText: normalizedSource,
      metadataLanguage: metadataLanguage,
      localeFallback: localeFallback != null
          ? contentLanguageFromCode(localeFallback)
          : null,
    );
    final langCode = contentLanguageCode(resolved);
    final instructions = reviewQuestionsJsonInstructions(
      langCode,
      safeRequestedCount,
    );
    final userPayload = [
      'book_title: $bookTitle',
      'source_type: $sourceType',
      'scope: ${scope.name}',
      if (chapterTitle != null) 'chapter: $chapterTitle',
      if (pageNumber != null) 'page_number: $pageNumber',
      'requested_count (target): $safeRequestedCount',
      '',
      'SOURCE TEXT:',
      cappedSource,
    ].join('\n');

    final sw = Stopwatch()..start();
    Map<String, dynamic> data;
    try {
      data = await _planApi
          .completePlanJson<Map<String, dynamic>>(
            userId: userId,
            instructions: instructions,
            user: userPayload,
            preferSingleRequest: true,
          )
          .timeout(_generationTimeout);
    } on TimeoutException {
      throw Exception(
        'La generación tardó más de 2 minutos. Prueba con menos preguntas (5).',
      );
    } catch (e, st) {
      debugPrint('[REVIEW QUESTIONS] ChatGPT ERROR: $e');
      debugPrint('[REVIEW QUESTIONS] STACK: $st');
      throw Exception(_humanizeGenerationError(e.toString()));
    }

    debugPrint(
      '[REVIEW QUESTIONS] ChatGPT OK elapsedMs=${sw.elapsedMilliseconds}',
    );

    final rawCards = data['cards'];
    final cards = rawCards is List
        ? rawCards
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];

    final message = data['message']?.toString();

    if (cards.isEmpty) {
      return GeneratedReviewBatch(
        requested: safeRequestedCount,
        generated: 0,
        message: message ?? reviewQuestionsNoneUsefulMessage(resolved),
        insertedRows: const [],
      );
    }

    final rows = <Map<String, dynamic>>[];
    final seenQuestions = <String>{};

    for (final card in cards) {
      final rawTitle =
          (card['title']?.toString() ?? reviewQuestionDefaultTitle(resolved))
              .trim();
      final question = card['question']?.toString().trim() ?? '';
      final answer = card['answer']?.toString().trim() ?? '';

      if (question.length < 12 || answer.length < 8) continue;

      final normalizedQuestion = question
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (seenQuestions.contains(normalizedQuestion)) continue;
      seenQuestions.add(normalizedQuestion);

      final safeTitle = rawTitle.isEmpty
          ? reviewQuestionDefaultTitle(resolved)
          : rawTitle.substring(0, math.min(rawTitle.length, 200));

      final safeQuote = quote == null
          ? null
          : quote.substring(0, math.min(quote.length, 2000));

      final metadata = metadataFromAiCard(card, question, answer);

      rows.add({
        'book_id': bookId,
        'user_id': userId,
        'chapter_id': chapterId,
        'page_number': pageNumber,
        'kind': 'qa',
        'source': 'assist',
        'title': safeTitle,
        'body': question,
        'back': answer,
        'quote': safeQuote,
        'context_question': sourceKey,
        'assist_mode': kReviewQuestionsAssistMode,
        'reviewed': false,
        'review_again': false,
        if (metadata != null) 'metadata': metadata,
      });

      if (rows.length >= safeRequestedCount) break;
    }

    attachMultipleChoiceMetadataToRows(rows);

    if (rows.isEmpty) {
      return GeneratedReviewBatch(
        requested: safeRequestedCount,
        generated: 0,
        message: message ?? reviewQuestionsNoneValidMessage(resolved),
        insertedRows: const [],
      );
    }

    debugPrint('[REVIEW QUESTIONS] inserting ${rows.length} cards');
    List<Map<String, dynamic>> inserted;
    try {
      inserted = await _repo.insertStudyCards(rows);
    } catch (e, st) {
      debugPrint('[REVIEW QUESTIONS] insert ERROR: $e');
      debugPrint('[REVIEW QUESTIONS] STACK: $st');
      throw Exception('No se pudieron guardar las preguntas: $e');
    }
    debugPrint('[REVIEW QUESTIONS] insert complete count=${inserted.length}');

    final effectiveMessage = inserted.length < safeRequestedCount
        ? message ??
              reviewQuestionsPartialCountMessage(
                resolved,
                inserted.length,
                safeRequestedCount,
              )
        : message;

    return GeneratedReviewBatch(
      requested: safeRequestedCount,
      generated: inserted.length,
      message: effectiveMessage,
      insertedRows: inserted,
    );
  }

  Future<String> gatherSourceTextFromReviewEntry(ReviewListEntry entry) async {
    debugPrint(
      '[REPASO SOURCE] gathering for entry=${entry.id} page=${entry.pageNumber}',
    );
    final text = await resolveSourceTextForReviewEntry(
      entry,
      pageTextLoader: (page) async {
        debugPrint('[REPASO SOURCE] page=$page');
        final row = await _repo.getPage(entry.bookId, page);
        final raw = normalizeStudyText(row?['text'] as String? ?? '');
        debugPrint('[REPASO SOURCE] page=$page chars=${raw.length}');
        return raw;
      },
    );
    debugPrint('[REPASO SOURCE] ready chars=${text.length}');
    return text;
  }
}
