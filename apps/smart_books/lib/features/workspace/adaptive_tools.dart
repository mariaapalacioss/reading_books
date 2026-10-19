import '../../services/book_assist_service.dart';
import 'document_profile.dart';

class AdaptiveToolOption {
  const AdaptiveToolOption({
    required this.mode,
    required this.label,
    required this.hint,
  });

  final AssistMode mode;
  final String label;
  final String hint;
}

/// Herramientas sugeridas según perfil del documento (pocas, relevantes).
List<AdaptiveToolOption> adaptiveToolsForProfile(DocumentProfile profile) {
  final out = <AdaptiveToolOption>[];
  void add(AssistMode mode, String label, String hint) {
    if (out.any((o) => o.mode == mode)) return;
    out.add(AdaptiveToolOption(mode: mode, label: label, hint: hint));
  }

  if (profile.narrative) {
    add(AssistMode.summary, 'Resumen', 'Ideas del capítulo o página');
    add(AssistMode.explain, 'Explicar', 'Aclara pasajes complejos');
  }
  if (profile.technical || profile.hasFormulas || profile.hasCode) {
    add(AssistMode.keyPoints, 'Puntos clave', 'Definiciones y pasos');
    add(AssistMode.explain, 'Explicar', 'Desglosa conceptos técnicos');
    add(AssistMode.review, 'Generar preguntas', 'Practica con Q/A');
  }
  if (profile.hasTables || profile.hasDiagramsHint) {
    add(AssistMode.fragmentSummary, 'Fragmento visual', 'Selecciona región en Leer');
    add(AssistMode.explain, 'Explicar', 'Tablas, figuras o bloques');
  }
  if (out.isEmpty) {
    add(AssistMode.summary, 'Resumen', 'Vista general');
    add(AssistMode.keyPoints, 'Puntos importantes', 'Lo esencial');
    add(AssistMode.review, 'Generar preguntas', 'Repaso activo');
  }
  return out.take(4).toList();
}
