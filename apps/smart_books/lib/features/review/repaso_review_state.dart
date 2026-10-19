import 'repaso_save_ui.dart';

/// Parches unificados para `study_cards.reviewed` / `review_again`.
Map<String, dynamic> repasoReviewPatch(RepasoReviewUiState state) {
  return switch (state) {
    RepasoReviewUiState.pending => {
      'reviewed': false,
      'review_again': false,
    },
    RepasoReviewUiState.reviewed => {
      'reviewed': true,
      'review_again': false,
    },
    RepasoReviewUiState.reviewAgain => {
      'reviewed': false,
      'review_again': true,
    },
  };
}
