import '../review/repaso_models.dart';
import '../review/repaso_qa_store.dart';

enum BookMaterialKind {
  summary,
  explain,
  keyPoints,
  questions,
  capture,
  note,
  glossary,
  other,
}

extension BookMaterialKindX on BookMaterialKind {
  String get label => switch (this) {
    BookMaterialKind.summary => 'Resumen',
    BookMaterialKind.explain => 'Explicación',
    BookMaterialKind.keyPoints => 'Puntos importantes',
    BookMaterialKind.questions => 'Preguntas',
    BookMaterialKind.capture => 'Fragmento / resaltado',
    BookMaterialKind.note => 'Nota',
    BookMaterialKind.glossary => 'Glosario',
    BookMaterialKind.other => 'Material',
  };
}

class BookMaterialItem {
  const BookMaterialItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.preview,
    this.pageNumber,
    this.createdAt,
    this.studyCardId,
    this.reviewEntry,
  });

  final String id;
  final BookMaterialKind kind;
  final String title;
  final String preview;
  final int? pageNumber;
  final DateTime? createdAt;
  final String? studyCardId;
  final ReviewListEntry? reviewEntry;
}

BookMaterialKind _kindFromCard(Map<String, dynamic> c) {
  if (isPersistedQa(c)) return BookMaterialKind.questions;
  final assist = c['assist_mode']?.toString() ?? '';
  return switch (assist) {
    'summary' => BookMaterialKind.summary,
    'keyPoints' => BookMaterialKind.keyPoints,
    'explain' || 'page' || 'fragmentSummary' => BookMaterialKind.explain,
    'review' || 'reviewQuestions' => BookMaterialKind.questions,
    _ => switch (c['kind']?.toString()) {
      'capture' => BookMaterialKind.capture,
      'summary' => BookMaterialKind.summary,
      'note' => BookMaterialKind.note,
      _ => BookMaterialKind.other,
    },
  };
}

/// Agrupa materiales persistidos (`study_cards` + entradas Repaso) por libro.
List<BookMaterialItem> materialsFromRepasoEntries(List<ReviewListEntry> entries) {
  final items = <BookMaterialItem>[];
  for (final e in entries) {
    if (e.card != null && isPersistedQa(e.card!)) continue;
    final kind = switch (e.sourceType) {
      ReviewSourceType.resumen => BookMaterialKind.summary,
      ReviewSourceType.punto => BookMaterialKind.keyPoints,
      ReviewSourceType.fragmento => BookMaterialKind.capture,
      ReviewSourceType.resaltado => BookMaterialKind.capture,
      ReviewSourceType.tarjeta => BookMaterialKind.note,
    };
    items.add(
      BookMaterialItem(
        id: e.id,
        kind: kind,
        title: e.title,
        preview: e.excerpt,
        pageNumber: e.pageNumber,
        createdAt: e.createdAt,
        studyCardId: e.card?['id']?.toString(),
        reviewEntry: e,
      ),
    );
  }
  return items;
}

List<BookMaterialItem> materialsFromStudyCards(
  List<Map<String, dynamic>> cards, {
  required String bookTitle,
}) {
  final items = <BookMaterialItem>[];
  for (final c in cards) {
    if (isPersistedQa(c)) continue;
    final id = c['id']?.toString();
    if (id == null) continue;
    final meta = c['metadata'];
    final metaMap = meta is Map
        ? Map<String, dynamic>.from(meta)
        : <String, dynamic>{};
    var kind = _kindFromCard(c);
    if (metaMap['material_kind'] == 'glossary') {
      kind = BookMaterialKind.glossary;
    }
    final page = c['page_number'];
    items.add(
      BookMaterialItem(
        id: id,
        kind: kind,
        title: c['title']?.toString() ?? 'Material',
        preview: kind == BookMaterialKind.note
            ? (c['body']?.toString() ?? '')
            : ((c['quote']?.toString().isNotEmpty == true
                    ? c['quote']
                    : c['body'])
                ?.toString() ??
                ''),
        pageNumber: page is num ? page.toInt() : int.tryParse('$page'),
        createdAt: DateTime.tryParse(c['created_at']?.toString() ?? ''),
        studyCardId: id,
      ),
    );
  }
  return items;
}

List<BookMaterialItem> mergeMaterials(
  List<BookMaterialItem> fromEntries,
  List<BookMaterialItem> fromCards,
) {
  final byId = <String, BookMaterialItem>{};
  for (final m in [...fromEntries, ...fromCards]) {
    byId[m.id] = m;
  }
  final list = byId.values.toList()
    ..sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
  return list;
}
