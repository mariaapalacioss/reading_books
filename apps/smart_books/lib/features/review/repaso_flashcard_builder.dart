import '../../domain/content_language.dart';
import 'repaso_models.dart';
import 'repaso_qa_store.dart';

/// Genera flashcards para repaso. Por defecto solo Q/A persistidas; heurística legacy opcional.
List<RepasoFlashcard> buildFlashcardsFromEntry(
  ReviewListEntry entry, {
  bool legacyFallback = false,
}) {
  if (entry.card != null && isPersistedQa(entry.card!)) {
    return [
      flashcardFromQaRow({
        ...entry.card!,
        '_book_title': entry.bookTitle,
        '_chapter_title': entry.chapterTitle,
      }, entry.sourceType),
    ];
  }

  if (entry.card != null) {
    final legacy = _legacyFromStudyCard(entry, entry.card!);
    if (legacy.isNotEmpty) return legacy;
  }
  if (entry.highlight != null) {
    final h = _fromHighlight(entry);
    if (h != null) return [h];
  }
  if (entry.point != null) {
    return [_fromPoint(entry)];
  }

  if (!legacyFallback) return [];
  return _legacyFromStudyCard(entry, entry.card ?? {});
}

List<RepasoFlashcard> _legacyFromStudyCard(
  ReviewListEntry entry,
  Map<String, dynamic> c,
) {
  if (c.isEmpty) return [];
  final kind = c['kind']?.toString() ?? 'note';
  final title = (c['title']?.toString() ?? '').trim();
  final body = (c['body']?.toString() ?? '').trim();
  final backRaw = c['back']?.toString();
  final back = backRaw == null ? null : backRaw.trim();

  if (kind == 'qa' && back != null && back.isNotEmpty) {
    final q = body.isNotEmpty ? body : title;
    if (!_isBadQuestion(q, entry.bookTitle)) {
      return [_single(entry, q, _conciseAnswer(back, q))];
    }
  }

  final longText = body.isNotEmpty ? body : title;
  if (longText.length < 35) return [];

  if (entry.sourceType == ReviewSourceType.resaltado) {
    final quoteRaw = c['quote']?.toString();
    final quote = quoteRaw == null ? null : quoteRaw.trim();
    final text = (quote != null && quote.isNotEmpty) ? quote : longText;
    final lang = resolveContentLanguage(sourceText: text);
    return [
      _single(
        entry,
        _specificHighlightQuestion(text, lang),
        _conciseAnswer(text, text, lang: lang),
      ),
    ];
  }

  final lang = resolveContentLanguage(sourceText: longText);
  final specific = _trySpecificQuestion(
    longText,
    entry.sourceType,
    entry.bookTitle,
    lang,
  );
  if (specific != null) {
    return [_single(entry, specific.$1, specific.$2)];
  }

  return [];
}

RepasoFlashcard? _fromHighlight(ReviewListEntry entry) {
  final h = entry.highlight!;
  final explain = h.explanationEs?.trim();
  final quote = h.quote.trim();
  final lang = resolveContentLanguage(
    sourceText: explain != null && explain.isNotEmpty ? explain : quote,
  );
  if (explain != null && explain.isNotEmpty) {
    return RepasoFlashcard(
      question: _specificHighlightQuestion(quote, lang),
      answer: _conciseAnswer(explain, quote, lang: lang),
      sourceType: ReviewSourceType.resaltado,
      bookTitle: entry.bookTitle,
      chapterTitle: entry.chapterTitle,
      pageNumber: entry.pageNumber,
    );
  }
  if (quote.length < 20) return null;
  return RepasoFlashcard(
    question: _specificHighlightQuestion(quote, lang),
    answer: _conciseAnswer(quote, quote, lang: lang),
    sourceType: ReviewSourceType.resaltado,
    bookTitle: entry.bookTitle,
    chapterTitle: entry.chapterTitle,
    pageNumber: entry.pageNumber,
  );
}

RepasoFlashcard _fromPoint(ReviewListEntry entry) {
  final body = entry.excerpt.trim();
  final lang = resolveContentLanguage(sourceText: body);
  final specific = _trySpecificQuestion(
    body,
    ReviewSourceType.punto,
    entry.bookTitle,
    lang,
  );
  return RepasoFlashcard(
    question: specific?.$1 ?? _genericPointQuestion(lang),
    answer: specific?.$2 ?? _conciseAnswer(body, body, lang: lang),
    sourceType: ReviewSourceType.punto,
    bookTitle: entry.bookTitle,
    chapterTitle: entry.chapterTitle,
    pageNumber: entry.pageNumber,
  );
}

RepasoFlashcard _single(ReviewListEntry entry, String q, String a) {
  return RepasoFlashcard(
    question: q,
    answer: a,
    sourceType: entry.sourceType,
    bookTitle: entry.bookTitle,
    chapterTitle: entry.chapterTitle,
    pageNumber: entry.pageNumber,
  );
}

(String, String)? _trySpecificQuestion(
  String text,
  ReviewSourceType type,
  String bookTitle,
  ContentLanguage lang,
) {
  final flat = text.replaceAll('\n', ' ').trim();
  if (flat.length < 35 || _isBadQuestion(flat, bookTitle)) return null;
  final lower = flat.toLowerCase();
  if (lang == ContentLanguage.en) {
    if (lower.contains('indication') && lower.contains('extract')) {
      return (
        'What are the main indications described in this content?',
        _conciseAnswer(flat, flat, lang: lang),
      );
    }
    if (RegExp(r'\bindicated\b').hasMatch(lower)) {
      return (
        'When is the action or procedure described in the text indicated?',
        _conciseAnswer(flat, flat, lang: lang),
      );
    }
    return null;
  }
  if (lower.contains('indicad') && lower.contains('extracc')) {
    return (
      '¿Cuáles son las principales indicaciones descritas en este contenido?',
      _conciseAnswer(flat, flat, lang: lang),
    );
  }
  if (RegExp(r'\best[aá] indicad').hasMatch(lower)) {
    return (
      '¿Cuándo está indicada la acción o procedimiento descrito en el texto?',
      _conciseAnswer(flat, flat, lang: lang),
    );
  }
  return null;
}

String _genericPointQuestion(ContentLanguage lang) {
  return lang == ContentLanguage.en
      ? 'What important point should you remember from this content?'
      : '¿Qué punto importante debes recordar de este contenido?';
}

String _specificHighlightQuestion(String quote, ContentLanguage lang) {
  final flat = quote.replaceAll('\n', ' ').trim();
  if (flat.length > 90) {
    return lang == ContentLanguage.en
        ? 'What specific statement from the text should you remember (from the highlight)?'
        : '¿Qué afirmación concreta del texto debes recordar (según el resaltado)?';
  }
  final snippet = flat.substring(0, flat.length.clamp(0, 60));
  return lang == ContentLanguage.en
      ? 'Complete the highlighted idea: «$snippet…»'
      : 'Completa la idea del resaltado: «$snippet…»';
}

String _conciseAnswer(String text, String langSample, {ContentLanguage? lang}) {
  final resolved = lang ?? resolveContentLanguage(sourceText: langSample);
  final flat = text
      .replaceAll('\n', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (flat.isEmpty) return flashcardEmptyAnswerFallback(resolved);
  final sentences = flat
      .split(RegExp(r'(?<=[.!?])\s+'))
      .where((s) => s.trim().isNotEmpty)
      .toList();
  final take = sentences.take(4).join(' ');
  if (take.length <= 420) return take;
  return '${take.substring(0, 417)}…';
}

bool _isBadQuestion(String q, String bookTitle) {
  final t = q.trim().toLowerCase();
  if (t.isEmpty || t == 'sin título') return true;
  final b = bookTitle.trim().toLowerCase();
  if (b.isNotEmpty &&
      (t == b || (t.startsWith(b) && t.length < b.length + 24))) {
    return true;
  }
  return false;
}
