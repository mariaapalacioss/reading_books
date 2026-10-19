import '../../domain/rects.dart';

/// Nota de margen persistida en `study_cards` (origen: selección en el lector).
class ReaderMarginNote {
  const ReaderMarginNote({
    required this.id,
    required this.bookId,
    required this.pageNumber,
    required this.body,
    this.quote,
    this.rects = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String bookId;
  final int pageNumber;
  final String body;
  final String? quote;
  final List<NormRect> rects;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static bool isMarginNoteRow(Map<String, dynamic> row) {
    if (row['kind']?.toString() != 'note') return false;
    final meta = row['metadata'];
    if (meta is! Map) return false;
    final map = Map<String, dynamic>.from(meta);
    return map['origin'] == 'reader_selection';
  }

  factory ReaderMarginNote.fromStudyCard(Map<String, dynamic> row) {
    final meta = row['metadata'] is Map
        ? Map<String, dynamic>.from(row['metadata'] as Map)
        : <String, dynamic>{};
    final rawRects = meta['rects'];
    final rects = <NormRect>[];
    if (rawRects is List) {
      for (final r in rawRects) {
        if (r is! Map) continue;
        final m = Map<String, dynamic>.from(r);
        final x = (m['x'] as num?)?.toDouble();
        final y = (m['y'] as num?)?.toDouble();
        final w = (m['w'] as num?)?.toDouble();
        final h = (m['h'] as num?)?.toDouble();
        if (x != null && y != null && w != null && h != null) {
          rects.add(NormRect(x: x, y: y, w: w, h: h));
        }
      }
    }
    return ReaderMarginNote(
      id: row['id']?.toString() ?? '',
      bookId: row['book_id']?.toString() ?? '',
      pageNumber: (row['page_number'] as num?)?.toInt() ?? 1,
      body: row['body']?.toString() ?? '',
      quote: row['quote']?.toString(),
      rects: rects,
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
    );
  }
}
