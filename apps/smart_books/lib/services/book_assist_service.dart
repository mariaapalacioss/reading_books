import 'dart:typed_data';

import '../data/repositories/books_repository.dart';
import '../domain/content_language.dart';
import '../domain/selection_image.dart';
import '../domain/study_scope.dart';
import '../domain/study_text.dart';
import '../features/chatgpt/assist_prompts.dart';
import '../features/chatgpt/plan_api.dart';

enum AssistMode {
  summary,
  keyPoints,
  explain,
  fragmentSummary,
  page,
  review,
  chat,
}

class BookAssistService {
  BookAssistService(this._repo, {PlanApi? api}) : _api = api ?? PlanApi();

  final BooksRepository _repo;
  final PlanApi _api;

  Future<void> streamAssist({
    required String userId,
    required AssistMode mode,
    required String bookId,
    required String bookTitle,
    required String language,
    String? bookLanguage,
    String? chapterId,
    String? chapterTitle,
    int? chapterStartPage,
    int? chapterEndPage,
    int? pageNumber,
    String? quote,
    Uint8List? selectionImagePixels,
    int? selectionImageWidth,
    int? selectionImageHeight,
    required List<Map<String, String>> messages,
    required void Function(String delta) onDelta,
    StudyScope? studyScope,
    bool fragmentSourceOnly = false,
  }) async {
    final localeFallback = contentLanguageFromCode(language);
    final selectionImageUrl = await _selectionImageDataUrl(
      selectionImagePixels,
      selectionImageWidth,
      selectionImageHeight,
    );

    if (mode == AssistMode.chat) {
      final lastUser = messages.lastWhere(
        (m) => m['role'] == 'user',
        orElse: () => {'content': ''},
      );
      final question = lastUser['content'] ?? '';
      final passages = await _retrievePassages(bookId, question);
      final packed = passages
          .map(
            (p) =>
                '[p.${p['page_number']}]\n${normalizeStudyText(p['text'] as String? ?? '')}',
          )
          .join('\n\n');
      final resolved = resolveContentLanguage(
        sourceText: packed.isNotEmpty ? packed : question,
        metadataLanguage: bookLanguage,
        localeFallback: localeFallback,
      );
      final langCode = contentLanguageCode(resolved);
      var instructions = chatInstructions(
        language: langCode,
        bookTitle: bookTitle,
        chapterTitle: chapterTitle,
        pageNumber: pageNumber,
        packed: packed,
      );
      if (selectionImageUrl != null) {
        instructions = [
          instructions,
          resolved == ContentLanguage.en
              ? 'The user attached a cropped image from the PDF. Describe what you see and answer in the context of the book.'
              : 'El usuario adjuntó un recorte del PDF. Describe lo que ves y responde en el contexto del libro.',
        ].join('\n\n');
      }
      final input = _chatInputMessages(
        messages,
        attachImageToLastUser: selectionImageUrl,
      );
      await _api.streamResponse(
        userId: userId,
        instructions: instructions,
        input: input,
        onDelta: onDelta,
      );
      return;
    }

    if (mode == AssistMode.summary ||
        mode == AssistMode.keyPoints ||
        mode == AssistMode.review) {
      if (studyScope != null && studyScope.sourceText.trim().length >= 40) {
        final packed = studyScope.sourceText.trim();
        final quality = assessTextQuality(packed);
        final resolved = resolveContentLanguage(
          sourceText: packed,
          metadataLanguage: bookLanguage,
          localeFallback: localeFallback,
        );
        final langCode = contentLanguageCode(resolved);
        final scopeNote = resolved == ContentLanguage.en
            ? 'Study scope: ${studyScopeActionLabel(studyScope, resolved)}'
            : 'Ámbito de estudio: ${studyScopeActionLabel(studyScope, resolved)}';
        final instructions = switch (mode) {
          AssistMode.summary => summaryInstructions(langCode, quality),
          AssistMode.keyPoints => keyPointsInstructions(langCode, quality),
          AssistMode.review => reviewInstructions(langCode, quality),
          _ => summaryInstructions(langCode, quality),
        };
        final body = '$scopeNote\n\n$packed';
        await _api.streamResponse(
          userId: userId,
          instructions: instructions,
          input: [
            {'role': 'user', 'content': body},
          ],
          onDelta: onDelta,
        );
        return;
      }
      if (chapterStartPage == null || chapterEndPage == null) {
        throw Exception('No hay capítulo en esta página.');
      }
      final packedInfo = await _packChapterText(
        bookId,
        chapterStartPage,
        chapterEndPage,
      );
      if (packedInfo.packed.trim().length < 40) {
        throw Exception(
          'Todavía no hay texto leído en este capítulo. Espera unos segundos o cambia de página.',
        );
      }
      final quality = assessTextQuality(packedInfo.packed);
      final resolved = resolveContentLanguage(
        sourceText: packedInfo.packed,
        metadataLanguage: bookLanguage,
        localeFallback: localeFallback,
      );
      final langCode = contentLanguageCode(resolved);
      final readableNote = packedInfo.partial
          ? (resolved == ContentLanguage.en
                ? 'Only ${packedInfo.readableCount}/${packedInfo.expected} chapter pages have readable text.'
                : 'Solo ${packedInfo.readableCount}/${packedInfo.expected} páginas del capítulo tienen texto legible.')
          : '';
      final prefix = [
        if (readableNote.isNotEmpty) readableNote,
        if (packedInfo.partial)
          resolved == ContentLanguage.en
              ? 'Partial chapter: ${packedInfo.readableCount}/${packedInfo.expected} pages.'
              : 'Capítulo parcial: ${packedInfo.readableCount}/${packedInfo.expected} páginas.',
      ].where((s) => s.isNotEmpty).join('\n');
      final instructions = switch (mode) {
        AssistMode.summary => summaryInstructions(langCode, quality),
        AssistMode.keyPoints => keyPointsInstructions(langCode, quality),
        AssistMode.review => reviewInstructions(langCode, quality),
        _ => summaryInstructions(langCode, quality),
      };
      final body =
          '${prefix.isNotEmpty ? '$prefix\n\n' : ''}Capítulo: ${chapterTitle ?? ''}\n\n${packedInfo.packed}';
      await _api.streamResponse(
        userId: userId,
        instructions: instructions,
        input: [
          {'role': 'user', 'content': body},
        ],
        onDelta: onDelta,
      );
      if (packedInfo.partial) {
        final footer = resolved == ContentLanguage.en
            ? '\n\n---\n*Based on ${packedInfo.readableCount}/${packedInfo.expected} pages with readable text.*'
            : '\n\n---\n*Basado en ${packedInfo.readableCount}/${packedInfo.expected} páginas con texto legible.*';
        onDelta(footer);
      }
      return;
    }

    if (mode == AssistMode.page) {
      if (studyScope != null && studyScope.sourceText.trim().length >= 40) {
        final packed = studyScope.sourceText.trim();
        final quality = assessTextQuality(packed);
        final resolved = resolveContentLanguage(
          sourceText: packed,
          metadataLanguage: bookLanguage,
          localeFallback: localeFallback,
        );
        final langCode = contentLanguageCode(resolved);
        final instructions = pageInstructions(langCode, quality);
        final scopeNote = resolved == ContentLanguage.en
            ? 'Study scope: ${studyScopeActionLabel(studyScope, resolved)}'
            : 'Ámbito de estudio: ${studyScopeActionLabel(studyScope, resolved)}';
        final body =
            '$scopeNote\n\n${packed.substring(0, packed.length.clamp(0, 14000))}';
        await _api.streamResponse(
          userId: userId,
          instructions: instructions,
          input: [
            {'role': 'user', 'content': body},
          ],
          onDelta: onDelta,
        );
        return;
      }
      final page = pageNumber ?? 1;
      final packed = await _packPageText(bookId, page);
      if (packed.text.length < 40) {
        throw Exception(
          'Esta página todavía no tiene texto seleccionable. Arrastra sobre el PDF para capturar una zona o espera el OCR.',
        );
      }
      final quality = assessTextQuality(packed.text);
      final resolved = resolveContentLanguage(
        sourceText: packed.text,
        metadataLanguage: bookLanguage,
        localeFallback: localeFallback,
      );
      final langCode = contentLanguageCode(resolved);
      final instructions = pageInstructions(langCode, quality);
      final label = packed.printedLabel;
      final body =
          'PDF p.$page${label != null ? ' · $label' : ''}\n\n${packed.text.substring(0, packed.text.length.clamp(0, 14000))}';
      await _api.streamResponse(
        userId: userId,
        instructions: instructions,
        input: [
          {'role': 'user', 'content': body},
        ],
        onDelta: onDelta,
      );
      return;
    }

    if (mode == AssistMode.explain || mode == AssistMode.fragmentSummary) {
      if (fragmentSourceOnly &&
          studyScope != null &&
          studyScope.kind == StudyScopeKind.fragments &&
          studyScope.sourceText.trim().length >= 12) {
        final fragmentBody = studyScope.sourceText.trim();
        final quality = assessTextQuality(fragmentBody);
        final resolved = resolveContentLanguage(
          sourceText: fragmentBody,
          metadataLanguage: bookLanguage,
          localeFallback: localeFallback,
        );
        final langCode = contentLanguageCode(resolved);
        final instructions = mode == AssistMode.fragmentSummary
            ? resolved == ContentLanguage.en
                  ? '${fragmentInstructions(langCode, quality)}\nSummarize ONLY the selected fragments in 2–4 sentences.'
                  : '${fragmentInstructions(langCode, quality)}\nResume SOLO los fragmentos seleccionados en 2–4 frases.'
            : fragmentInstructions(langCode, quality);
        final intro = resolved == ContentLanguage.en
            ? 'Selected fragments (use ONLY this text, not full pages):\n\n'
            : 'Fragmentos seleccionados (usa SOLO este texto, no páginas completas):\n\n';
        await _api.streamResponse(
          userId: userId,
          instructions: instructions,
          input: [
            {'role': 'user', 'content': '$intro$fragmentBody'},
          ],
          onDelta: onDelta,
        );
        return;
      }
      final page = pageNumber ?? 1;
      final fragment = quote?.trim() ?? '';
      if (selectionImageUrl == null && fragment.length < 12) {
        throw Exception(
          'Selecciona al menos unas palabras en el PDF (arrastra una zona si es escaneado).',
        );
      }
      final packed = await _packPageText(bookId, page);
      final sourceForLang = fragment.isNotEmpty ? fragment : packed.text;
      final quality = assessTextQuality(
        packed.text.isNotEmpty ? packed.text : fragment,
      );
      final resolved = resolveContentLanguage(
        sourceText: sourceForLang,
        metadataLanguage: bookLanguage,
        localeFallback: localeFallback,
      );
      final langCode = contentLanguageCode(resolved);
      final String instructions;
      final String body;
      if (selectionImageUrl != null) {
        instructions = mode == AssistMode.fragmentSummary
            ? resolved == ContentLanguage.en
                  ? '${fragmentVisionInstructions(langCode)}\nSummarize the essentials of the image in 2–4 sentences.'
                  : '${fragmentVisionInstructions(langCode)}\nResume lo esencial de la imagen en 2–4 frases.'
            : fragmentVisionInstructions(langCode);
        final caption = fragment.isNotEmpty
            ? fragment
            : (langCode == 'en' ? '(visual crop)' : '(recorte visual)');
        body = langCode == 'en'
            ? 'PDF page $page\nOCR / caption near selection:\n«$caption»\n\nPage text context:\n${packed.text.substring(0, packed.text.length.clamp(0, 8000))}'
            : 'Página PDF $page\nTexto detectado cerca de la selección:\n«$caption»\n\nContexto de la página:\n${packed.text.substring(0, packed.text.length.clamp(0, 8000))}';
      } else {
        instructions = mode == AssistMode.fragmentSummary
            ? resolved == ContentLanguage.en
                  ? '${fragmentInstructions(langCode, quality)}\nSummarize ONLY the selected fragment in 2–4 sentences.'
                  : '${fragmentInstructions(langCode, quality)}\nResume SOLO el fragmento seleccionado en 2–4 frases.'
            : fragmentInstructions(langCode, quality);
        body = langCode == 'en'
            ? 'PDF page $page\nSelected fragment:\n«$fragment»\n\nPage context:\n${packed.text.substring(0, packed.text.length.clamp(0, 10000))}'
            : 'Página PDF $page\nFragmento seleccionado:\n«$fragment»\n\nContexto de la página:\n${packed.text.substring(0, packed.text.length.clamp(0, 10000))}';
      }
      await _api.streamResponse(
        userId: userId,
        instructions: instructions,
        input: [planUserMessage(body, imageDataUrl: selectionImageUrl)],
        onDelta: onDelta,
      );
      return;
    }

    throw Exception('Modo de asistencia desconocido.');
  }

  Future<
    ({
      String packed,
      bool partial,
      int readableCount,
      int expected,
      String qualityNote,
    })
  >
  _packChapterText(String bookId, int startPage, int endPage) async {
    final pages = await _repo.listPagesInRange(bookId, startPage, endPage);
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
    final partial = readable.length < expected;
    final packed = readable.map((p) => '[p.${p.$2}]\n${p.$1}').join('\n\n');
    final trimmed = packed.length > 18000 ? packed.substring(0, 18000) : packed;
    final qualityNote = partial
        ? 'Solo ${readable.length}/$expected páginas del capítulo tienen texto legible.'
        : '';
    return (
      packed: trimmed,
      partial: partial,
      readableCount: readable.length,
      expected: expected,
      qualityNote: qualityNote,
    );
  }

  Future<({String text, String? printedLabel})> _packPageText(
    String bookId,
    int pageNumber,
  ) async {
    final row = await _repo.getPage(bookId, pageNumber);
    final text = normalizeStudyText(row?['text'] as String? ?? '');
    return (text: text, printedLabel: row?['printed_label'] as String?);
  }

  Future<String?> _selectionImageDataUrl(
    Uint8List? pixels,
    int? width,
    int? height,
  ) async {
    if (pixels == null || width == null || height == null) return null;
    return bgraToPngDataUrl(pixels, width, height);
  }

  List<Map<String, dynamic>> _chatInputMessages(
    List<Map<String, String>> messages, {
    String? attachImageToLastUser,
  }) {
    if (messages.isEmpty) return [];
    var lastUserIndex = -1;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i]['role'] == 'user') {
        lastUserIndex = i;
        break;
      }
    }
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final role = m['role'] ?? 'user';
      final content = m['content'] ?? '';
      if (i == lastUserIndex && attachImageToLastUser != null) {
        out.add(planUserMessage(content, imageDataUrl: attachImageToLastUser));
      } else {
        out.add({'role': role, 'content': content});
      }
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _retrievePassages(
    String bookId,
    String query,
  ) async {
    if (query.trim().length < 3) {
      return _repo.listReadablePages(bookId);
    }
    final hits = await _repo.textSearchLibrary(query);
    return hits.where((h) => h['book_id'] == bookId).take(4).toList();
  }
}
