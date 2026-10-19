/// Formatos de práctica avanzados (modelo; la sesión actual sigue usando Q/A).
enum PracticeQuestionFormat {
  openQa,
  multipleChoice,
  trueFalse,
  ordering,
  matching,
  fillBlank,
  codeExercise,
  predictOutput,
  debugging,
  applicationCase,
}

extension PracticeQuestionFormatX on PracticeQuestionFormat {
  String get label => switch (this) {
    PracticeQuestionFormat.openQa => 'Pregunta abierta (actual)',
    PracticeQuestionFormat.multipleChoice => 'Opción múltiple',
    PracticeQuestionFormat.trueFalse => 'Verdadero / falso',
    PracticeQuestionFormat.ordering => 'Ordenar',
    PracticeQuestionFormat.matching => 'Emparejar',
    PracticeQuestionFormat.fillBlank => 'Completar',
    PracticeQuestionFormat.codeExercise => 'Ejercicio de código',
    PracticeQuestionFormat.predictOutput => 'Predecir salida',
    PracticeQuestionFormat.debugging => 'Debugging',
    PracticeQuestionFormat.applicationCase => 'Caso de aplicación',
  };

  /// Clave persistible en `study_cards.metadata` cuando se use.
  String get metadataKey => name;
}

class PracticeQuestionPayload {
  const PracticeQuestionPayload({
    required this.format,
    this.prompt = '',
    this.options = const [],
    this.correctIndex,
    this.pairs = const {},
    this.blanks = const [],
  });

  final PracticeQuestionFormat format;
  final String prompt;
  final List<String> options;
  final int? correctIndex;
  final Map<String, String> pairs;
  final List<String> blanks;

  Map<String, dynamic> toMetadata() => {
    'practice_format': format.metadataKey,
    'prompt': prompt,
    if (options.isNotEmpty) 'options': options,
    if (correctIndex != null) 'correct_index': correctIndex,
    if (pairs.isNotEmpty) 'pairs': pairs,
    if (blanks.isNotEmpty) 'blanks': blanks,
  };

  factory PracticeQuestionPayload.fromMetadata(Map<String, dynamic>? meta) {
    if (meta == null || meta.isEmpty) {
      return const PracticeQuestionPayload(format: PracticeQuestionFormat.openQa);
    }
    final key = meta['practice_format']?.toString() ?? 'openQa';
    final format = PracticeQuestionFormat.values.firstWhere(
      (f) => f.metadataKey == key,
      orElse: () => PracticeQuestionFormat.openQa,
    );
    return PracticeQuestionPayload(
      format: format,
      prompt: meta['prompt']?.toString() ?? '',
      options: (meta['options'] as List?)?.map((e) => e.toString()).toList() ?? [],
      correctIndex: (meta['correct_index'] as num?)?.toInt(),
      pairs: (meta['pairs'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          {},
      blanks: (meta['blanks'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}
