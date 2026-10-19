import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/domain/study_text.dart';

void main() {
  test('sanitizeDbText elimina NUL sin tocar Unicode válido', () {
    expect(sanitizeDbText('hola\u0000mundo'), 'holamundo');
    expect(sanitizeDbText('añí é ü'), 'añí é ü');
  });

  test('normalizeStudyText quita guión de corte de línea', () {
    expect(normalizeStudyText('extra-\nacción'), 'extraacción');
  });

  test('assessTextQuality marca poco texto como no fiable', () {
    final q = assessTextQuality('hola');
    expect(q.reliable, isFalse);
    expect(q.issues, isNotEmpty);
  });

  test('assessTextQuality acepta párrafo académico legible', () {
    final sample =
        'La extracción de terceros molares incluidos requiere evaluación radiográfica '
        'y planificación quirúrgica basada en evidencia científica publicada recientemente.';
    final q = assessTextQuality(sample);
    expect(q.score, greaterThan(0.5));
  });

  test('qualityPreamble vacío cuando el texto es fiable', () {
    final sample = List.filled(20, 'palabra clínica relevante').join(' ');
    final q = assessTextQuality(sample);
    expect(q.reliable, isTrue);
    expect(qualityPreamble(q, 'es'), isEmpty);
  });
}
