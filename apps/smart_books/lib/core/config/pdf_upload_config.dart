/// Límites de subida de PDF (paridad con `VITE_MAX_PDF_CLOUD_MB` en la web).
class PdfUploadConfig {
  PdfUploadConfig._();

  /// `--dart-define=MAX_PDF_CLOUD_MB=500` o en `dart_defines.json`.
  static const _maxMbRaw = String.fromEnvironment(
    'MAX_PDF_CLOUD_MB',
    defaultValue: '500',
  );

  static int get maxCloudMegabytes {
    final parsed = int.tryParse(_maxMbRaw.trim());
    if (parsed == null || parsed < 1) return 500;
    return parsed.clamp(1, 5120);
  }

  static int get maxCloudBytes => maxCloudMegabytes * 1024 * 1024;

  /// Debe coincidir con `storage.buckets.file_size_limit` (migración Supabase).
  static int get bucketLimitBytes => 524288000; // 500 MiB

  /// Objetivo al comprimir (plan Free suele limitar ~50 MiB por objeto).
  static int get compressTargetBytes {
    const freeTierObjectLimit = 50 * 1024 * 1024;
    final configured = maxCloudBytes;
    final cap = configured < freeTierObjectLimit ? configured : freeTierObjectLimit;
    return (cap * 0.94).floor();
  }
}
