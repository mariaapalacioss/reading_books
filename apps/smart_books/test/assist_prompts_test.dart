import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/domain/study_text.dart';
import 'package:smart_books/features/chatgpt/assist_prompts.dart';

void main() {
  final quality = assessTextQuality(
    'Texto clínico suficientemente largo para evaluar calidad de OCR y estudio académico del capítulo.',
  );

  test('cada modo de asistencia tiene instrucciones distintas', () {
    final keyPoints = keyPointsInstructions('es', quality);
    final summary = summaryInstructions('es', quality);
    final page = pageInstructions('es', quality);
    final fragment = fragmentInstructions('es', quality);
    final review = reviewInstructions('es', quality);

    expect(keyPoints.contains('5–8 fundamental ideas'), isTrue);
    expect(summary.contains('summarize the chapter'), isTrue);
    expect(page.contains('explain what this PDF page'), isTrue);
    expect(fragment.contains('ONLY the quoted fragment'), isTrue);
    expect(review.contains('active recall'), isTrue);

    final set = {keyPoints, summary, page, fragment, review};
    expect(set.length, 5);
  });

  test('puntos clave prohíbe párrafos largos disfrazados', () {
    final text = keyPointsInstructions('es', quality);
    expect(text.toLowerCase(), contains('do not write long paragraphs'));
  });

  test('repaso activo no es otro resumen', () {
    final text = reviewInstructions('es', quality);
    expect(text, contains('NOT another summary'));
    expect(text, contains('Preguntas de autoevaluación'));
  });
}
