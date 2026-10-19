import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../core/ui/pdf_file_bytes.dart';
import '../data/models/text_item.dart';
import '../domain/chunks.dart';
import '../domain/study_text.dart';
import '../data/repositories/books_repository.dart';
import 'pdf_extractor.dart';

class IngestService {
  IngestService(this._repo);

  final BooksRepository _repo;

  Future<String> savePdf({
    required String userId,
    required Uint8List bytes,
    required String title,
    required String author,
    void Function(String message)? onProgress,
  }) async {
    if (!looksLikePdf(bytes)) {
      throw Exception(
        'El archivo no parece un PDF válido. Descárgalo por completo desde Archivos e inténtalo otra vez.',
      );
    }

    onProgress?.call('Extrayendo texto del PDF…');
    final extracted = await extractPdfBytes(
      bytes,
      onProgress: (p, t) {
        onProgress?.call('Extrayendo texto, página $p de $t');
      },
    );

    final bookId = const Uuid().v4();
    final storagePath = await _repo.persistPdfBytes(
      userId,
      bookId,
      bytes,
      onProgress: onProgress,
    );

    final status = extracted.needsOcr ? 'needs_ocr' : 'extracting';
    final statusDetail = extracted.needsOcr
        ? 'El PDF parece escaneado. Iniciando OCR…'
        : null;

    await _repo.insertBook({
      'id': bookId,
      'user_id': userId,
      'title': title.trim().isEmpty ? extracted.title : title.trim(),
      'author': author.trim().isEmpty
          ? (extracted.author.isEmpty ? null : extracted.author)
          : author.trim(),
      'language': extracted.language,
      'storage_path': storagePath,
      'page_count': extracted.pageCount,
      'status': status,
      'status_detail': statusDetail,
      'highlight_intensity': 'balanced',
      'explanation_language': 'es',
    });

    onProgress?.call('Guardando páginas y capítulos…');
    await _repo.insertPages(
      bookId: bookId,
      userId: userId,
      pages: extracted.pages.map((p) {
        final clean = normalizeStudyText(p.text);
        final items = p.items
            .map(
              (it) => TextItem(
                s: sanitizeDbText(it.s),
                start: it.start,
                x: it.x,
                y: it.y,
                w: it.w,
                h: it.h,
              ),
            )
            .toList();
        return (
          page: p.page,
          text: clean,
          items: items,
          printedLabel: p.printedLabel != null
              ? sanitizeDbText(p.printedLabel!)
              : null,
          charCount: clean.length,
        );
      }).toList(),
    );

    await _repo.insertChapters(
      bookId: bookId,
      userId: userId,
      chapters: extracted.chapters,
    );

    final chunks = buildChunks(
      extracted.pages
          .map((p) => PageSlice(page: p.page, text: p.text))
          .toList(),
    );
    await _repo.insertSearchChunks(
      bookId: bookId,
      userId: userId,
      chunks: chunks,
    );

    await _repo.updateBook(bookId, {
      'status': extracted.needsOcr ? 'needs_ocr' : 'ready',
      'status_detail': statusDetail,
    });
    return bookId;
  }
}

typedef PageInsert = ({
  int page,
  String text,
  List<TextItem> items,
  String? printedLabel,
  int charCount,
});
