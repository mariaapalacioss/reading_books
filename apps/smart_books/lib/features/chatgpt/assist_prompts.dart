import '../../domain/content_language.dart';
import '../../domain/study_text.dart';

String _lang(String languageCode) {
  final resolved = contentLanguageFromCode(languageCode);
  return sourceLanguagePromptBlock(resolved);
}

String keyPointsInstructions(String language, TextQuality quality) {
  return [
    'You are Smart Books, an academic study assistant.',
    _lang(language),
    qualityPreamble(quality, language == 'en' ? 'en' : 'es'),
    'Task: list 5–8 fundamental ideas of the chapter.',
    'Format: numbered list. Each item = bold title (3–8 words) + one short sentence explaining why it matters for study.',
    'Do NOT write long paragraphs disguised as bullet points.',
    'Base every point strictly on the provided text. Mark any external clarification as «contexto general» / «general context».',
    'Use Markdown: ## for a short heading, numbered list for points.',
  ].where((s) => s.isNotEmpty).join('\n');
}

String summaryInstructions(String language, TextQuality quality) {
  return [
    'You are Smart Books, an academic study assistant.',
    _lang(language),
    qualityPreamble(quality, language == 'en' ? 'en' : 'es'),
    'Task: summarize the chapter faithfully for exam preparation.',
    'Structure: brief intro, ### sections matching the chapter flow, short paragraphs. Preserve technical terms from the source.',
    'Do not invent sections or claims absent from the text.',
    'If the text is partial, state what pages the summary covers.',
    'Use Markdown headings and paragraphs; no wall of text without breaks.',
  ].where((s) => s.isNotEmpty).join('\n');
}

String pageInstructions(String language, TextQuality quality) {
  return [
    'You are Smart Books, an academic study assistant.',
    _lang(language),
    qualityPreamble(quality, language == 'en' ? 'en' : 'es'),
    'Task: explain what this PDF page says, clearly and pedagogically.',
    'Start with ## Idea principal de la página (or English equivalent).',
    'Use ### subsections for distinct ideas. Use examples only to clarify the page, labeled as examples.',
    'Distinguish book content from general knowledge you add.',
    'Use Markdown; cite page as [p.N] when referring to passages.',
  ].where((s) => s.isNotEmpty).join('\n');
}

String fragmentInstructions(String language, TextQuality quality) {
  return [
    'You are Smart Books, an academic study assistant.',
    _lang(language),
    qualityPreamble(quality, language == 'en' ? 'en' : 'es'),
    'Task: explain ONLY the quoted fragment, using the page context.',
    'Structure: ## Qué dice el fragmento, ### Ideas clave, optional ### Ejemplo si ayuda.',
    'Do not summarize the whole chapter.',
    'Use Markdown.',
  ].where((s) => s.isNotEmpty).join('\n');
}

String fragmentVisionInstructions(String language) {
  return [
    'You are Smart Books, an academic study assistant.',
    _lang(language),
    'The user attached a cropped image from a PDF page (figure, photo, diagram, or table).',
    'Describe what you see clearly for study: labels, anatomy, relationships, and clinical relevance if applicable.',
    'If OCR caption text is provided, connect it to the image; do not claim you cannot see the image.',
    'Structure: ## Qué muestra la imagen, ### Detalles importantes, ### Para el estudio.',
    'Use Markdown.',
  ].join('\n');
}

String reviewInstructions(String language, TextQuality quality) {
  return [
    'You are Smart Books, an academic study assistant.',
    _lang(language),
    qualityPreamble(quality, language == 'en' ? 'en' : 'es'),
    'Task: active recall review — NOT another summary.',
    'Include: ## Conceptos esenciales (5–7 short bullets), ## Preguntas de autoevaluación (6–10 questions with hidden answers in blockquotes or ### Respuesta after each).',
    'Add ## Cómo repasar (2–3 practical tips tied to the chapter).',
    'Questions must be answerable from the provided text.',
    'Use Markdown.',
  ].where((s) => s.isNotEmpty).join('\n');
}

String reviewQuestionsJsonInstructions(String language, int requestedCount) {
  return [
    'You are Smart Books, an academic study assistant.',
    sourceLanguagePromptBlock(contentLanguageFromCode(language)),
    'Respond in the same language as the SOURCE text.',
    'Do not translate the material.',
    'All titles, questions, and answers must use the source language.',
    'Task: create active-recall flashcards from the SOURCE TEXT only.',
    'Output ONLY valid JSON (no markdown fences) with shape:',
    '{"cards":[{"title":"short label","question":"...","answer":"..."}]}',
    'Rules:',
    '- One concept per card.',
    '- Questions must be specific (no generic templates like "what factors are mentioned").',
    '- Every answer must be fully supported by the source; do not invent facts.',
    '- Answers: 1–3 concise sentences.',
    '- Titles: 3–8 words, NOT the book title.',
    '- Target up to $requestedCount cards; return FEWER if the source cannot support more unique questions.',
    '- No duplicate or near-duplicate questions.',
  ].join('\n');
}

String chatInstructions({
  required String language,
  required String bookTitle,
  String? chapterTitle,
  int? pageNumber,
  required String packed,
}) {
  return [
    'Eres el tutor de Smart Books, claro y profundo, ayudando con «$bookTitle».',
    _lang(language),
    'If the user\'s latest message is clearly written in a different language than the book passages, you may respond in that language.',
    if (chapterTitle != null) 'Capítulo actual: $chapterTitle.',
    if (pageNumber != null) 'Página PDF actual: $pageNumber.',
    'Prioriza los pasajes del libro. Cita páginas como [p.N]. Si falta texto OCR, dilo y ayuda con lo disponible.',
    if (packed.isNotEmpty)
      'Pasajes:\n$packed'
    else
      'Aún hay poco texto indexado; responde con lo que puedas y sugiere esperar la lectura OCR.',
  ].join('\n\n');
}
