class Highlight {
  const Highlight({
    required this.id,
    required this.bookId,
    this.chapterId,
    required this.pageNumber,
    required this.quote,
    required this.category,
    this.explanationEs,
    this.explanationEn,
    required this.origin,
    this.intensity,
    this.note,
    this.rects,
    this.reviewed = false,
    this.reviewAgain = false,
    this.dismissed = false,
  });

  final String id;
  final String bookId;
  final String? chapterId;
  final int pageNumber;
  final String quote;
  final String category;
  final String? explanationEs;
  final String? explanationEn;
  final String origin;
  final String? intensity;
  final String? note;
  final List<Map<String, double>>? rects;
  final bool reviewed;
  final bool reviewAgain;
  final bool dismissed;

  factory Highlight.fromJson(Map<String, dynamic> json) {
    final rawRects = json['rects'];
    List<Map<String, double>>? rects;
    if (rawRects is List) {
      rects = rawRects.map((r) {
        final m = Map<String, dynamic>.from(r as Map);
        return {
          'x': (m['x'] as num).toDouble(),
          'y': (m['y'] as num).toDouble(),
          'w': (m['w'] as num).toDouble(),
          'h': (m['h'] as num).toDouble(),
        };
      }).toList();
    }
    return Highlight(
      id: json['id'] as String,
      bookId: json['book_id'] as String,
      chapterId: json['chapter_id'] as String?,
      pageNumber: (json['page_number'] as num).toInt(),
      quote: json['quote'] as String,
      category: json['category'] as String? ?? 'manual',
      explanationEs: json['explanation_es'] as String?,
      explanationEn: json['explanation_en'] as String?,
      origin: json['origin'] as String? ?? 'user',
      intensity: json['intensity'] as String?,
      note: json['note'] as String?,
      rects: rects,
      reviewed: json['reviewed'] as bool? ?? false,
      reviewAgain: json['review_again'] as bool? ?? false,
      dismissed: json['dismissed'] as bool? ?? false,
    );
  }
}
