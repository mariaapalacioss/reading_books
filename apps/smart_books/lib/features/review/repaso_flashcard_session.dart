import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'repaso_flashcard_builder.dart';
import 'repaso_models.dart';
import 'repaso_session_route.dart';

Future<void> showRepasoReviewSession(
  BuildContext context, {
  required ReviewListEntry entry,
  required String bookId,
  required VoidCallback onReviewed,
  required VoidCallback onRepasar,
  List<RepasoFlashcard>? cards,
}) {
  final resolved =
      cards ?? buildFlashcardsFromEntry(entry, legacyFallback: false);
  if (resolved.isEmpty) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sin preguntas'),
        content: const Text(
          'No hay preguntas de repaso disponibles. Genera preguntas desde Repaso o Asistencia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
  return context.push<void>(
    '/repaso/sesion',
    extra: RepasoSessionExtra(
      entry: entry,
      bookId: bookId,
      cards: resolved,
      onReviewed: onReviewed,
      onRepasar: onRepasar,
    ),
  );
}
