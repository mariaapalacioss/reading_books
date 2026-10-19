import 'package:flutter/material.dart';

import '../../data/repositories/books_repository.dart';
import '../shared/bookifi_ui.dart';

/// Estados del botón «Guardar en Repaso».
enum RepasoSaveUiState { ready, saving, saved, error }

const kRepasoSaveIdleLabel = 'Guardar para repaso';
const kRepasoSaveSavingLabel = 'Guardando…';
const kRepasoSaveSavedLabel = '✓ Guardado';
const kRepasoSaveErrorMessage =
    'No se pudo guardar. Intenta nuevamente.';

String repasoSaveButtonLabel(RepasoSaveUiState state) {
  return switch (state) {
    RepasoSaveUiState.ready => kRepasoSaveIdleLabel,
    RepasoSaveUiState.saving => kRepasoSaveSavingLabel,
    RepasoSaveUiState.saved => kRepasoSaveSavedLabel,
    RepasoSaveUiState.error => kRepasoSaveIdleLabel,
  };
}

/// Busca tarjeta ya persistida (mismo libro + ancla + modo asistencia).
Future<Map<String, dynamic>?> findStudyCardForRepasoSave(
  BooksRepository repo, {
  required String bookId,
  required String contextQuestion,
  String? assistMode,
}) async {
  if (contextQuestion.isEmpty) return null;
  final cards = await repo.listStudyCards(bookId);
  for (final row in cards) {
    if (row['context_question']?.toString() != contextQuestion) continue;
    if (assistMode != null &&
        row['assist_mode']?.toString() != assistMode) {
      continue;
    }
    return row;
  }
  return null;
}

class RepasoSaveButton extends StatelessWidget {
  const RepasoSaveButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.compact = false,
  });

  final RepasoSaveUiState state;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final saved = state == RepasoSaveUiState.saved;
    final saving = state == RepasoSaveUiState.saving;
    return BookifiGhostButton(
      label: repasoSaveButtonLabel(state),
      compact: compact,
      loading: saving,
      onPressed: saved || saving ? null : onPressed,
    );
  }
}

enum RepasoReviewUiState { pending, reviewed, reviewAgain }

RepasoReviewUiState repasoReviewUiStateFromRow(Map<String, dynamic>? row) {
  if (row == null) return RepasoReviewUiState.pending;
  if (row['review_again'] == true) return RepasoReviewUiState.reviewAgain;
  if (row['reviewed'] == true) return RepasoReviewUiState.reviewed;
  return RepasoReviewUiState.pending;
}

String repasoReviewUiStateLabel(RepasoReviewUiState state) {
  return switch (state) {
    RepasoReviewUiState.pending => 'Pendiente',
    RepasoReviewUiState.reviewed => 'Revisada',
    RepasoReviewUiState.reviewAgain => 'Revisar de nuevo',
  };
}

Color repasoReviewUiStateColor(RepasoReviewUiState state, BuildContext context) {
  return switch (state) {
    RepasoReviewUiState.pending => Theme.of(context).colorScheme.onSurfaceVariant,
    RepasoReviewUiState.reviewed => const Color(0xFF22C55E),
    RepasoReviewUiState.reviewAgain => const Color(0xFFE89200),
  };
}

class RepasoReviewStatusChip extends StatelessWidget {
  const RepasoReviewStatusChip({super.key, required this.state});

  final RepasoReviewUiState state;

  @override
  Widget build(BuildContext context) {
    final color = repasoReviewUiStateColor(state, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        repasoReviewUiStateLabel(state),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
