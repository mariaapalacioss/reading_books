import 'repaso_models.dart';

/// Argumentos para `/repaso/sesion` (go_router `extra`).
class RepasoSessionExtra {
  const RepasoSessionExtra({
    required this.entry,
    required this.bookId,
    required this.cards,
    this.onReviewed,
    this.onRepasar,
  });

  final ReviewListEntry entry;
  final String bookId;
  final List<RepasoFlashcard> cards;
  final void Function()? onReviewed;
  final void Function()? onRepasar;
}

/// Sesión con todas las preguntas guardadas (varios libros).
class RepasoSessionAllExtra {
  const RepasoSessionAllExtra({
    required this.cards,
    this.bookIdByStudyCardId = const {},
  });

  final List<RepasoFlashcard> cards;
  final Map<String, String> bookIdByStudyCardId;
}
