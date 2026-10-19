import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../config/pdf_upload_config.dart';

/// PDFs demasiado grandes para Supabase Storage (paridad con `local/` en la web).
class LocalPdfStore {
  LocalPdfStore._();
  static final LocalPdfStore instance = LocalPdfStore._();

  static const localPrefix = 'local/';

  static bool isLocalPath(String storagePath) =>
      storagePath.startsWith(localPrefix);

  /// Clave interna `{userId}/{bookId}.pdf` (sin prefijo `local/`).
  static String keyFromLocalPath(String storagePath) {
    if (!isLocalPath(storagePath)) {
      throw ArgumentError('Ruta de PDF local inválida: $storagePath');
    }
    return storagePath.substring(localPrefix.length);
  }

  static String localPathForKey(String cloudKey) => '$localPrefix$cloudKey';

  Future<Directory> _rootDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/smart_books_pdfs');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _fileForKey(String key) async {
    final root = await _rootDir();
    final safeKey = key.replaceAll('..', '').replaceAll(RegExp(r'^/+'), '');
    final file = File('${root.path}/$safeKey');
    await file.parent.create(recursive: true);
    return file;
  }

  Future<void> put(String key, Uint8List bytes) async {
    final file = await _fileForKey(key);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<Uint8List?> get(String key) async {
    final file = await _fileForKey(key);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> delete(String key) async {
    final file = await _fileForKey(key);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Tope cliente antes de intentar Storage (alineado con bucket y `MAX_PDF_CLOUD_MB`).
int maxCloudPdfBytes() => PdfUploadConfig.maxCloudBytes;

bool isStorageSizeError(Object error) {
  return storageSizeErrorHint(error) != null;
}

/// Indicio de rechazo por tamaño (Supabase Storage / gateway).
String? storageSizeErrorHint(Object error) {
  final text = error.toString().toLowerCase();
  const needles = [
    '413',
    'payload too large',
    'maximum allowed size',
    'exceeded the maximum',
    'entity too large',
    'file too large',
    'file_size_limit',
    'size limit',
    'too large',
    'object exceeded',
  ];
  for (final n in needles) {
    if (text.contains(n)) return n;
  }
  return null;
}

/// Solo informativo (tests); la app intenta siempre el original primero.
bool shouldCompressBeforeUpload(int byteLength) =>
    byteLength > PdfUploadConfig.compressTargetBytes;
