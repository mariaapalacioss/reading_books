import 'dart:math';

import '../features/workspace/practice_question_types.dart';

/// Añade `metadata` de opción múltiple a filas nuevas (sin tocar las que ya tienen formato).
void attachMultipleChoiceMetadataToRows(List<Map<String, dynamic>> rows) {
  if (rows.length < 2) return;
  final answers = rows.map((r) => r['back']?.toString().trim() ?? '').toList();
  final rng = Random();

  for (var i = 0; i < rows.length; i++) {
    if (rows[i]['metadata'] != null) continue;
    if (i.isOdd) continue;

    final answer = answers[i];
    if (answer.isEmpty) continue;

    final distractors = <String>[];
    for (var j = 0; j < answers.length && distractors.length < 3; j++) {
      if (j == i) continue;
      final d = answers[j];
      if (d.isNotEmpty && d != answer && !distractors.contains(d)) {
        distractors.add(d.length > 120 ? '${d.substring(0, 117)}…' : d);
      }
    }
    const fillers = [
      'No se menciona en el texto',
      'Ninguna de las anteriores',
      'Depende del contexto del pasaje',
    ];
    var fillerIdx = 0;
    while (distractors.length < 3 && fillerIdx < fillers.length) {
      final f = fillers[fillerIdx++];
      if (!distractors.contains(f)) distractors.add(f);
    }
    if (distractors.length < 3) continue;

    final options = [answer, ...distractors.take(3)];
    options.shuffle(rng);
    final correctIndex = options.indexOf(answer);
    if (correctIndex < 0) continue;

    final payload = PracticeQuestionPayload(
      format: PracticeQuestionFormat.multipleChoice,
      prompt: rows[i]['body']?.toString() ?? '',
      options: options,
      correctIndex: correctIndex,
    );
    rows[i]['metadata'] = payload.toMetadata();
  }
}

Map<String, dynamic>? metadataFromAiCard(
  Map<String, dynamic> card,
  String question,
  String answer,
) {
  final optionsRaw = card['options'];
  if (optionsRaw is! List || optionsRaw.length < 2) return null;
  var options = optionsRaw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
  if (options.length < 2) return null;

  var correctIndex = (card['correct_index'] as num?)?.toInt();
  if (correctIndex == null ||
      correctIndex < 0 ||
      correctIndex >= options.length) {
    correctIndex = options.indexWhere((o) => o.trim() == answer.trim());
  }
  if (correctIndex < 0) {
    if (options.length >= 4) {
      options = options.take(3).toList();
    }
    options = [...options, answer];
    correctIndex = options.length - 1;
  }

  return PracticeQuestionPayload(
    format: PracticeQuestionFormat.multipleChoice,
    prompt: question,
    options: options,
    correctIndex: correctIndex,
  ).toMetadata();
}
