import 'dart:convert';

/// Señales heurísticas del documento (sin preguntar profesión al usuario).
class DocumentProfile {
  const DocumentProfile({
    this.technical = false,
    this.narrative = false,
    this.hasCode = false,
    this.hasFormulas = false,
    this.hasTables = false,
    this.hasDiagramsHint = false,
    this.sampledPages = 0,
    this.analyzedAt,
  });

  final bool technical;
  final bool narrative;
  final bool hasCode;
  final bool hasFormulas;
  final bool hasTables;
  final bool hasDiagramsHint;
  final int sampledPages;
  final DateTime? analyzedAt;

  factory DocumentProfile.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const DocumentProfile();
    return DocumentProfile(
      technical: json['technical'] == true,
      narrative: json['narrative'] == true,
      hasCode: json['has_code'] == true,
      hasFormulas: json['has_formulas'] == true,
      hasTables: json['has_tables'] == true,
      hasDiagramsHint: json['has_diagrams_hint'] == true,
      sampledPages: (json['sampled_pages'] as num?)?.toInt() ?? 0,
      analyzedAt: DateTime.tryParse(json['analyzed_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
    'technical': technical,
    'narrative': narrative,
    'has_code': hasCode,
    'has_formulas': hasFormulas,
    'has_tables': hasTables,
    'has_diagrams_hint': hasDiagramsHint,
    'sampled_pages': sampledPages,
    'analyzed_at': analyzedAt?.toIso8601String(),
  };

  static DocumentProfile? fromBookColumn(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return DocumentProfile.fromJson(raw);
    if (raw is Map) {
      return DocumentProfile.fromJson(Map<String, dynamic>.from(raw));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        return DocumentProfile.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

DocumentProfile analyzePageTexts(Iterable<String> pages) {
  final buffer = StringBuffer();
  var count = 0;
  for (final t in pages) {
    if (t.trim().isEmpty) continue;
    buffer.writeln(t);
    count++;
  }
  final text = buffer.toString();
  if (text.isEmpty) return DocumentProfile(sampledPages: count);

  final code = RegExp(
    r'\b(def |class |function |#include|import |console\.|=>|\{\s*\n)',
    caseSensitive: false,
  ).hasMatch(text);
  final formulas = RegExp(r'(\$[^$]+\$|\\frac|\bintegral\b|∑|∫|√)', caseSensitive: false)
      .hasMatch(text);
  final tables = RegExp(r'(\|.+\|.+\||\t.+\t.+)', multiLine: true).hasMatch(text);
  final technical = RegExp(
    r'\b(algoritmo|theorem|lemma|API|HTTP|SQL|protocolo|ecuación|modelo)\b',
    caseSensitive: false,
  ).hasMatch(text);
  final narrative = RegExp(
    r'("[^"]{12,}"|—| dijo | narrador )',
    caseSensitive: false,
  ).hasMatch(text);
  final diagrams = RegExp(
    r'\b(figura|diagrama|gráfico|fig\.|table \d|tabla \d)\b',
    caseSensitive: false,
  ).hasMatch(text);

  return DocumentProfile(
    technical: technical || code || formulas,
    narrative: narrative && !code,
    hasCode: code,
    hasFormulas: formulas,
    hasTables: tables,
    hasDiagramsHint: diagrams,
    sampledPages: count,
    analyzedAt: DateTime.now().toUtc(),
  );
}
