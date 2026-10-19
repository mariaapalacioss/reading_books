import 'dart:developer' as developer;

/// Mensaje para UI; el detalle técnico queda en logs.
String friendlyUserError(Object error, {String? logTag}) {
  final raw = error.toString();
  if (logTag != null) {
    developer.log(raw, name: logTag);
  } else {
    developer.log(raw, name: 'smart_books');
  }

  if (raw.contains(r'\u0000') ||
      raw.contains('22P05') ||
      raw.contains('unsupported Unicode escape')) {
    return 'Este PDF contiene texto incompatible y no pudo guardarse. '
        'Prueba exportarlo de nuevo como PDF estándar o usa otro archivo.';
  }

  if (raw.contains('PostgrestException') || raw.contains('PostgresException')) {
    return 'No pudimos guardar el libro en la nube. Revisa tu conexión e inténtalo otra vez.';
  }

  if (raw.contains('FPDF_ERR_FORMAT') ||
      raw.contains('Failed to load PDF') ||
      raw.contains('PdfException')) {
    return 'No pudimos abrir este PDF. Descárgalo por completo desde Archivos o iCloud '
        'y vuelve a subirlo, o prueba con otro archivo.';
  }

  if (raw.contains('storage_size_after_compress')) {
    return 'Incluso después de comprimir, el PDF sigue siendo demasiado grande para tu plan de Supabase. '
        'En el panel de Supabase ejecuta el SQL de límite 500 MB (docs/SUPABASE_PDF_UPLOAD.md) o sube a plan Pro.';
  }

  if (raw.contains('413') ||
      raw.contains('payload too large') ||
      raw.contains('maximum allowed size') ||
      raw.contains('límite de la nube')) {
    return 'No se pudo subir el PDF a la nube (tamaño). '
        'Espera a que termine la optimización automática o revisa el límite del bucket en Supabase (docs/SUPABASE_PDF_UPLOAD.md).';
  }

  if (raw.contains('solo estaba en este dispositivo')) {
    return 'El archivo original ya no está en este dispositivo. Vuelve a subir el PDF.';
  }

  final cleaned = raw
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^PostgrestException\([^)]*\):\s*'), '')
      .trim();

  if (cleaned.length > 160) {
    return '${cleaned.substring(0, 157)}…';
  }
  if (cleaned.isEmpty) {
    return 'Algo salió mal. Inténtalo de nuevo.';
  }
  return cleaned;
}
