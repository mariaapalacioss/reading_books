import '../../data/models/highlight.dart';

/// Origen unificado del ítem en el workspace Repaso.
enum ReviewSourceType { resaltado, tarjeta, resumen, punto, fragmento }

extension ReviewSourceTypeX on ReviewSourceType {
  String get label => switch (this) {
    ReviewSourceType.resaltado => 'Resaltado',
    ReviewSourceType.tarjeta => 'Tarjeta',
    ReviewSourceType.resumen => 'Resumen',
    ReviewSourceType.punto => 'Punto importante',
    ReviewSourceType.fragmento => 'Fragmento',
  };
}

class ReviewListEntry {
  ReviewListEntry({
    required this.id,
    required this.sourceType,
    required this.bookId,
    required this.bookTitle,
    required this.title,
    required this.excerpt,
    this.chapterId,
    this.chapterTitle,
    this.pageNumber,
    this.reviewed = false,
    this.pending = false,
    this.createdAt,
    this.card,
    this.highlight,
    this.point,
  });

  final String id;
  final ReviewSourceType sourceType;
  final String bookId;
  final String bookTitle;
  final String title;
  final String excerpt;
  final String? chapterId;
  final String? chapterTitle;
  final int? pageNumber;
  final bool reviewed;
  final bool pending;
  final DateTime? createdAt;
  final Map<String, dynamic>? card;
  final Highlight? highlight;
  final Map<String, dynamic>? point;

  static ReviewSourceType _classifyStudyCard(Map<String, dynamic> c) {
    final kind = c['kind']?.toString() ?? 'note';
    final source = c['source']?.toString() ?? '';
    final assist = c['assist_mode']?.toString() ?? '';
    if (kind == 'capture' || source == 'capture')
      return ReviewSourceType.resaltado;
    if (kind == 'summary' || assist == 'summary')
      return ReviewSourceType.resumen;
    if (assist == 'explain' ||
        assist == 'page' ||
        assist == 'fragmentSummary') {
      return ReviewSourceType.fragmento;
    }
    if (assist == 'keyPoints') return ReviewSourceType.punto;
    if (assist == 'reviewQuestions' || kind == 'qa')
      return ReviewSourceType.tarjeta;
    return ReviewSourceType.tarjeta;
  }

  static ReviewListEntry? fromStudyCard(
    Map<String, dynamic> c, {
    required String bookTitle,
    String? chapterTitle,
  }) {
    final id = c['id']?.toString();
    if (id == null) return null;
    final sourceType = _classifyStudyCard(c);
    final body = c['body']?.toString() ?? '';
    final title = c['title']?.toString() ?? 'Sin título';
    final quote = c['quote']?.toString();
    final page = c['page_number'];
    final pageNum = page is num ? page.toInt() : int.tryParse('$page');
    final created = DateTime.tryParse(c['created_at']?.toString() ?? '');
    final chapterId = c['chapter_id']?.toString();
    final preview = quote?.isNotEmpty == true ? quote! : body;
    return ReviewListEntry(
      id: id,
      sourceType: sourceType,
      bookId: c['book_id']?.toString() ?? '',
      bookTitle: bookTitle,
      title: title,
      excerpt: preview,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      pageNumber: pageNum,
      reviewed: c['reviewed'] == true,
      pending: c['review_again'] == true || c['reviewed'] != true,
      createdAt: created,
      card: c,
    );
  }

  /// Entrada agrupada para preguntas guardadas (p. ej. desde Fragmentos en Asistencia).
  static ReviewListEntry fromQaSourceKey({
    required String sourceKey,
    required String bookId,
    required String bookTitle,
    required String title,
    required String excerpt,
    int? pageNumber,
    String? chapterTitle,
  }) {
    final fromFragments = sourceKey.contains(':fragments:');
    return ReviewListEntry(
      id: sourceKey,
      sourceType: fromFragments
          ? ReviewSourceType.fragmento
          : ReviewSourceType.tarjeta,
      bookId: bookId,
      bookTitle: bookTitle,
      title: title,
      excerpt: excerpt,
      pageNumber: pageNumber,
      chapterTitle: chapterTitle,
      pending: true,
    );
  }

  static ReviewListEntry fromHighlight(
    Highlight h, {
    required String bookTitle,
    String? chapterTitle,
  }) {
    return ReviewListEntry(
      id: h.id,
      sourceType: ReviewSourceType.resaltado,
      bookId: h.bookId,
      bookTitle: bookTitle,
      title: h.quote.length > 64 ? '${h.quote.substring(0, 61)}…' : h.quote,
      excerpt: h.quote,
      chapterId: h.chapterId,
      chapterTitle: chapterTitle,
      pageNumber: h.pageNumber,
      reviewed: h.reviewed,
      pending: h.reviewAgain || !h.reviewed,
      highlight: h,
    );
  }

  static ReviewListEntry? fromPoint(
    Map<String, dynamic> p, {
    required String bookId,
    required String bookTitle,
    String? chapterTitle,
  }) {
    final id = p['id']?.toString() ?? p['chapter_id']?.toString();
    if (id == null) return null;
    final body = p['body']?.toString() ?? '';
    final page = p['page_number'];
    final pageNum = page is num ? page.toInt() : int.tryParse('$page');
    return ReviewListEntry(
      id: 'point-$id-${p['page_number']}',
      sourceType: ReviewSourceType.punto,
      bookId: bookId,
      bookTitle: bookTitle,
      title: body.length > 72
          ? '${body.substring(0, 69)}…'
          : (body.isEmpty ? 'Punto importante' : body),
      excerpt: body,
      chapterId: p['chapter_id']?.toString(),
      chapterTitle: chapterTitle,
      pageNumber: pageNum,
      point: p,
    );
  }
}

class RepasoFlashcard {
  const RepasoFlashcard({
    required this.question,
    required this.answer,
    required this.sourceType,
    required this.bookTitle,
    this.chapterTitle,
    this.pageNumber,
    this.studyCardId,
    this.reviewed = false,
    this.reviewAgain = false,
  });

  final String question;
  final String answer;
  final ReviewSourceType sourceType;
  final String bookTitle;
  final String? chapterTitle;
  final int? pageNumber;

  /// Fila `study_cards` persistida (kind qa); repaso no regenera si existe.
  final String? studyCardId;
  final bool reviewed;
  final bool reviewAgain;

  RepasoFlashcard copyWithReview({bool? reviewed, bool? reviewAgain}) {
    return RepasoFlashcard(
      question: question,
      answer: answer,
      sourceType: sourceType,
      bookTitle: bookTitle,
      chapterTitle: chapterTitle,
      pageNumber: pageNumber,
      studyCardId: studyCardId,
      reviewed: reviewed ?? this.reviewed,
      reviewAgain: reviewAgain ?? this.reviewAgain,
    );
  }
}

class RepasoCounts {
  const RepasoCounts({
    this.resaltados = 0,
    this.tarjetas = 0,
    this.resumenes = 0,
    this.puntos = 0,
    this.fragmentos = 0,
    this.reviewed = 0,
    this.trackable = 0,
  });

  final int resaltados;
  final int tarjetas;
  final int resumenes;
  final int puntos;
  final int fragmentos;
  final int reviewed;
  final int trackable;

  int get total => resaltados + tarjetas + resumenes + puntos + fragmentos;

  int? get progressPercent =>
      trackable == 0 ? null : ((reviewed / trackable) * 100).round();

  static RepasoCounts fromEntries(List<ReviewListEntry> entries) {
    var r = 0, t = 0, s = 0, p = 0, f = 0, rev = 0, track = 0;
    for (final e in entries) {
      if (e.sourceType == ReviewSourceType.resaltado) {
        r++;
      } else if (e.sourceType == ReviewSourceType.tarjeta) {
        t++;
      } else if (e.sourceType == ReviewSourceType.resumen) {
        s++;
      } else if (e.sourceType == ReviewSourceType.punto) {
        p++;
      } else if (e.sourceType == ReviewSourceType.fragmento) {
        f++;
      }
      if (e.sourceType != ReviewSourceType.punto) {
        track++;
        if (e.reviewed) rev++;
      }
    }
    return RepasoCounts(
      resaltados: r,
      tarjetas: t,
      resumenes: s,
      puntos: p,
      fragmentos: f,
      reviewed: rev,
      trackable: track,
    );
  }
}
