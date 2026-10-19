/// Quita bytes nulos y controles que Postgres rechaza en columnas `text`.
String sanitizeDbText(String raw) {
  return raw
      .replaceAll('\u0000', '')
      .replaceAll(RegExp(r'[\u0001-\u0008\u000B\u000C\u000E-\u001F]'), '');
}

/// Normaliza texto extraído (PDF/OCR) para estudio e IA.
String normalizeStudyText(String raw) {
  var text = sanitizeDbText(raw);
  text = text.replaceAll('\u00ad', '');
  text = text.replaceAllMapped(
    RegExp(r'(\p{L})-\r?\n(\p{L})', unicode: true),
    (m) => '${m[1]}${m[2]}',
  );
  text = text.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  return text.trim();
}

class TextQuality {
  const TextQuality({
    required this.reliable,
    required this.score,
    required this.issues,
  });

  final bool reliable;
  final double score;
  final List<String> issues;
}

TextQuality assessTextQuality(String text) {
  final issues = <String>[];
  final sample = text.trim();
  if (sample.length < 40) {
    return const TextQuality(
      reliable: false,
      score: 0,
      issues: ['Muy poco texto en la página.'],
    );
  }
  final words = sample
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return const TextQuality(
      reliable: false,
      score: 0,
      issues: ['Sin palabras legibles.'],
    );
  }

  final oneChar = words
      .where(
        (w) => w.length == 1 && RegExp(r'\p{L}', unicode: true).hasMatch(w),
      )
      .length;
  if (oneChar / words.length > 0.22) {
    issues.add('Muchas palabras de una letra (posible OCR ruidoso).');
  }

  final broken = words
      .where(
        (w) =>
            w.length >= 2 &&
            !RegExp(
              r"^[\p{L}\p{N}][\p{L}\p{N}'\-.,;:()/]*$",
              unicode: true,
            ).hasMatch(w),
      )
      .length;
  if (broken / words.length > 0.18) {
    issues.add('Símbolos o cortes irregulares frecuentes.');
  }

  final letters = RegExp(r'\p{L}', unicode: true).allMatches(sample).length;
  final ratio = letters / sample.length;
  if (ratio < 0.45) issues.add('Proporción baja de letras respecto al total.');

  final lines = sample.split('\n');
  final shortLines = lines
      .where((line) => line.trim().isNotEmpty && line.trim().length < 4)
      .length;
  if (shortLines / lines.length > 0.35) {
    issues.add('Muchas líneas muy cortas (orden o columnas dudosos).');
  }

  var score = 1.0;
  score -= (oneChar / words.length).clamp(0.0, 0.35);
  score -= (broken / words.length).clamp(0.0, 0.25);
  if (ratio < 0.45) score -= 0.2;
  if (shortLines / lines.length > 0.35) score -= 0.15;
  score = score.clamp(0.0, 1.0);

  return TextQuality(
    reliable: score >= 0.62 && issues.length <= 1,
    score: score,
    issues: issues,
  );
}

String qualityPreamble(TextQuality quality, String language) {
  if (quality.reliable) return '';
  final intro = language == 'en'
      ? 'The source text may contain OCR or layout errors. Be explicit about uncertainty; do not present guesses as facts from the book.'
      : 'El texto fuente puede tener errores de OCR o de maquetación. Señala la incertidumbre; no presentes suposiciones como hechos del libro.';
  final detail = quality.issues.isEmpty
      ? ''
      : (language == 'en'
            ? 'Issues: ${quality.issues.join(' ')}'
            : 'Problemas detectados: ${quality.issues.join(' ')}');
  return [intro, detail].where((s) => s.isNotEmpty).join('\n');
}
