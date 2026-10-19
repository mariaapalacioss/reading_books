import '../../domain/study_text.dart';
import 'repaso_models.dart';

const _capturePlaceholder = 'Recorte visual del PDF';

/// Texto que no debe usarse como fuente para IA ni como título semántico.
bool isPlaceholderRepasoText(String? text, {String? bookTitle}) {
  if (text == null) return true;
  final t = text.trim();
  if (t.isEmpty) return true;
  if (t == _capturePlaceholder) return true;
  if (t.startsWith('Recorte:') && t.contains(_capturePlaceholder)) return true;
  final book = bookTitle?.trim();
  if (book != null && book.isNotEmpty && t == book) return true;
  if (t.toLowerCase() == 'sin título') return true;
  return false;
}

String? meaningfulRepasoText(
  String? text, {
  String? bookTitle,
  int minLength = 12,
}) {
  if (isPlaceholderRepasoText(text, bookTitle: bookTitle)) return null;
  final t = normalizeStudyText(text!);
  if (t.length < minLength) return null;
  return t;
}

/// Prioridad: quote → body → excerpt → texto de página (vía [pageTextLoader]).
Future<String> resolveSourceTextForReviewEntry(
  ReviewListEntry entry, {
  required Future<String?> Function(int page) pageTextLoader,
  int minLength = 40,
}) async {
  final bookTitle = entry.bookTitle;
  final card = entry.card;

  String? quote;
  String? body;
  if (card != null) {
    quote = meaningfulRepasoText(
      card['quote']?.toString(),
      bookTitle: bookTitle,
    );
    body = meaningfulRepasoText(
      card['body']?.toString(),
      bookTitle: bookTitle,
      minLength: minLength,
    );
  }

  if (entry.highlight != null) {
    final h = entry.highlight!;
    final hQuote = meaningfulRepasoText(h.quote, bookTitle: bookTitle);
    final explain = meaningfulRepasoText(
      h.explanationEs,
      bookTitle: bookTitle,
      minLength: 20,
    );
    if (hQuote != null && explain != null) {
      return 'Resaltado:\n«$hQuote»\n\nExplicación:\n$explain';
    }
    if (explain != null) return explain;
    if (hQuote != null) return 'Resaltado:\n«$hQuote»';
  }

  if (quote != null && body != null) {
    return 'Fragmento:\n«$quote»\n\nContenido:\n$body';
  }
  if (body != null) {
    if (entry.pageNumber != null) {
      final pageText = await pageTextLoader(entry.pageNumber!);
      final ctx = meaningfulRepasoText(
        pageText,
        bookTitle: bookTitle,
        minLength: minLength,
      );
      if (ctx != null) {
        return 'Contenido guardado:\n$body\n\nContexto PDF ${entry.pageNumber}:\n${ctx.length > 12000 ? ctx.substring(0, 12000) : ctx}';
      }
    }
    return body;
  }
  if (quote != null) {
    if (entry.pageNumber != null) {
      final pageText = await pageTextLoader(entry.pageNumber!);
      final ctx = meaningfulRepasoText(
        pageText,
        bookTitle: bookTitle,
        minLength: minLength,
      );
      if (ctx != null) {
        return 'Fragmento:\n«$quote»\n\nContexto PDF ${entry.pageNumber}:\n${ctx.length > 12000 ? ctx.substring(0, 12000) : ctx}';
      }
    }
    if (quote.length >= minLength) return 'Fragmento:\n«$quote»';
  }

  if (entry.point != null) {
    final pBody = meaningfulRepasoText(
      entry.point!['body']?.toString() ?? entry.excerpt,
      bookTitle: bookTitle,
      minLength: minLength,
    );
    if (pBody != null) return pBody;
  }

  final excerpt = meaningfulRepasoText(
    entry.excerpt,
    bookTitle: bookTitle,
    minLength: minLength,
  );
  if (excerpt != null) return excerpt;

  if (entry.pageNumber != null) {
    final pageText = await pageTextLoader(entry.pageNumber!);
    final ctx = meaningfulRepasoText(
      pageText,
      bookTitle: bookTitle,
      minLength: minLength,
    );
    if (ctx != null) return 'PDF ${entry.pageNumber}\n\n$ctx';
  }

  if (entry.sourceType == ReviewSourceType.fragmento) {
    throw Exception(
      'No hay suficiente texto disponible para generar preguntas de este fragmento.',
    );
  }
  throw Exception(
    'No hay suficiente texto disponible para generar preguntas de este contenido.',
  );
}

String repasoDisplayTitle(ReviewListEntry entry) {
  final raw = entry.title.trim();
  if (raw.isNotEmpty &&
      !isPlaceholderRepasoText(raw, bookTitle: entry.bookTitle) &&
      raw != entry.bookTitle.trim()) {
    return raw;
  }

  final card = entry.card;
  if (card != null) {
    final assist = card['assist_mode']?.toString() ?? '';
    final page = entry.pageNumber;
    final pageSuffix = page != null ? ' · PDF $page' : '';
    switch (assist) {
      case 'fragmentSummary':
        return 'Fragmento explicado$pageSuffix';
      case 'page':
        return 'Explicación de página$pageSuffix';
      case 'explain':
        return 'Explicación del fragmento$pageSuffix';
      case 'summary':
        return entry.chapterTitle != null
            ? 'Resumen · ${entry.chapterTitle}'
            : 'Resumen del capítulo';
      case 'keyPoints':
        return entry.chapterTitle != null
            ? 'Puntos clave · ${entry.chapterTitle}'
            : 'Puntos importantes';
      case 'review':
        return 'Repaso activo$pageSuffix';
    }
    final quote = meaningfulRepasoText(
      card['quote']?.toString(),
      bookTitle: entry.bookTitle,
      minLength: 8,
    );
    if (quote != null) {
      return quote.length > 72 ? '${quote.substring(0, 69)}…' : quote;
    }
    final body = meaningfulRepasoText(
      card['body']?.toString(),
      bookTitle: entry.bookTitle,
      minLength: 20,
    );
    if (body != null) {
      return body.length > 72 ? '${body.substring(0, 69)}…' : body;
    }
  }

  if (entry.sourceType == ReviewSourceType.fragmento) {
    return 'Fragmento${entry.pageNumber != null ? ' · PDF ${entry.pageNumber}' : ''}';
  }

  return entry.sourceType.label;
}

String repasoDisplayExcerpt(ReviewListEntry entry) {
  final card = entry.card;
  if (card != null) {
    final body = meaningfulRepasoText(
      card['body']?.toString(),
      bookTitle: entry.bookTitle,
      minLength: 8,
    );
    if (body != null) return body;
    final quote = meaningfulRepasoText(
      card['quote']?.toString(),
      bookTitle: entry.bookTitle,
      minLength: 8,
    );
    if (quote != null) return quote;
  }
  final excerpt = meaningfulRepasoText(
    entry.excerpt,
    bookTitle: entry.bookTitle,
    minLength: 8,
  );
  if (excerpt != null) return excerpt;
  return '';
}

void debugLogRepasoEntry(ReviewListEntry entry) {
  // ignore: avoid_print
  print(
    '[repaso] entry.id=${entry.id} sourceType=${entry.sourceType.name} '
    'page=${entry.pageNumber} chapterId=${entry.chapterId}',
  );
  final c = entry.card;
  if (c != null) {
    // ignore: avoid_print
    print(
      '[repaso] study_card id=${c['id']} kind=${c['kind']} assist_mode=${c['assist_mode']} '
      'title=${c['title']} back=${c['back']} quote=${c['quote']} '
      'page_number=${c['page_number']} chapter_id=${c['chapter_id']}',
    );
  }
}

void debugLogPersistedQaRows(List<Map<String, dynamic>> rows) {
  for (final r in rows) {
    // ignore: avoid_print
    print(
      '[repaso] qa id=${r['id']} title=${r['title']} body=${r['body']} back=${r['back']} '
      'context_question=${r['context_question']}',
    );
  }
}
