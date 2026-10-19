/// Idioma del contenido de estudio (fuente), no del shell de la app.
enum ContentLanguage { es, en }

ContentLanguage contentLanguageFromCode(String? code) {
  final normalized = (code ?? '').trim().toLowerCase();
  if (normalized == 'en' ||
      normalized == 'english' ||
      normalized.startsWith('en-')) {
    return ContentLanguage.en;
  }
  if (normalized == 'es' ||
      normalized == 'spanish' ||
      normalized == 'español' ||
      normalized.startsWith('es-')) {
    return ContentLanguage.es;
  }
  return ContentLanguage.es;
}

String contentLanguageCode(ContentLanguage language) =>
    language == ContentLanguage.en ? 'en' : 'es';

/// Prioridad: texto fuente → metadatos del libro → locale de la app / preferencia.
ContentLanguage resolveContentLanguage({
  required String sourceText,
  String? metadataLanguage,
  ContentLanguage? localeFallback,
}) {
  final fromText = _detectFromText(sourceText);
  if (fromText != null) return fromText;

  final meta = (metadataLanguage ?? '').trim().toLowerCase();
  if (meta == 'en' || meta == 'english') return ContentLanguage.en;
  if (meta == 'es' || meta == 'spanish' || meta == 'español') {
    return ContentLanguage.es;
  }

  return localeFallback ?? ContentLanguage.es;
}

ContentLanguage? _detectFromText(String raw) {
  final sample = raw.trim();
  if (sample.length < 24) return null;

  final lower = sample.toLowerCase();
  final esStop = RegExp(
    r'\b(el|la|de|que|y|en|los|las|un|una|por|con|del|al|es|son|para|como|más|molar|diente)\b',
  ).allMatches(lower).length;
  final enStop = RegExp(
    r'\b(the|and|of|to|in|that|is|for|with|on|are|was|be|this|tooth|mandibular|may|can)\b',
  ).allMatches(lower).length;

  final spanishMarkers = RegExp(r'[áéíóúñ¿¡]').allMatches(sample).length;
  final spanishScore = esStop + spanishMarkers * 2;
  final englishScore = enStop;

  if (spanishScore >= englishScore + 2) return ContentLanguage.es;
  if (englishScore >= spanishScore + 2) return ContentLanguage.en;
  return null;
}

String sourceLanguagePromptBlock(ContentLanguage resolved) {
  return [
    'Respond in the same language as the SOURCE text.',
    'Do not translate the material.',
    'All headings, titles, questions, and answers must use the predominant language of the source.',
    if (resolved == ContentLanguage.en)
      'Use English question forms (What, How, Why, Which).'
    else
      'Usa formas interrogativas en español (¿Qué?, ¿Cómo?, ¿Por qué?, ¿Cuál?).',
  ].join('\n');
}

String reviewQuestionDefaultTitle(ContentLanguage language) =>
    language == ContentLanguage.en ? 'Review question' : 'Pregunta de repaso';

String reviewQuestionsPartialCountMessage(
  ContentLanguage language,
  int generated,
  int requested,
) {
  if (language == ContentLanguage.en) {
    return 'Only $generated useful questions could be generated from the $requested requested without repeating information.';
  }
  return 'Se generaron $generated preguntas útiles de las $requested solicitadas para evitar repetir información.';
}

String reviewQuestionsNoneUsefulMessage(ContentLanguage language) {
  if (language == ContentLanguage.en) {
    return 'No useful questions could be generated without repeating information.';
  }
  return 'No se pudieron generar preguntas útiles sin repetir información.';
}

String reviewQuestionsNoneValidMessage(ContentLanguage language) {
  if (language == ContentLanguage.en) {
    return 'No valid questions could be generated from this content.';
  }
  return 'No se pudieron generar preguntas válidas de este contenido.';
}

String flashcardEmptyAnswerFallback(ContentLanguage language) =>
    language == ContentLanguage.en
    ? 'No answer available.'
    : 'Sin respuesta disponible.';
