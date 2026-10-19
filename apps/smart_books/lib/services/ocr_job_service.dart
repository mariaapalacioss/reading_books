import 'dart:async';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../data/models/book.dart';
import '../domain/chapters.dart';
import '../domain/chunks.dart';
import '../domain/ocr_layout.dart';
import '../data/models/text_item.dart';
import '../data/repositories/books_repository.dart';
import 'platform_ocr.dart';
import 'analysis_service.dart';

class OcrEvent {
  const OcrEvent({
    required this.bookId,
    required this.message,
    required this.done,
    required this.total,
    this.error,
  });

  final String bookId;
  final String message;
  final int done;
  final int total;
  final String? error;
}

const ocrBatchSize = 6;

class OcrJobService {
  OcrJobService(this._repo, this._analysis);

  final BooksRepository _repo;
  final AnalysisService _analysis;
  final _listeners = <void Function(OcrEvent)>[];
  final _running = <String, Future<void>>{};
  final _cancel = <String, bool>{};
  final _priority = <String, Set<int>>{};
  final _lastAnalysisKick = <String, DateTime>{};
  String? _primaryBookId;

  void subscribe(void Function(OcrEvent) listener) => _listeners.add(listener);

  void unsubscribe(void Function(OcrEvent) listener) =>
      _listeners.remove(listener);

  void prioritizePages(String bookId, Iterable<int> pages) {
    final set = _priority.putIfAbsent(bookId, () => {});
    for (final p in pages) {
      if (p >= 1) set.add(p);
    }
  }

  void cancel(String bookId) => _cancel[bookId] = true;

  bool isRunning(String bookId) => _running.containsKey(bookId);

  /// Solo un OCR pesado a la vez; el lector marca su libro como prioritario.
  void setPrimaryBook(String? bookId) => _primaryBookId = bookId;

  Future<void> ensureOcr(Book book) {
    if (book.status != 'extracting' && book.status != 'needs_ocr')
      return Future.value();
    if (_primaryBookId != null &&
        book.id != _primaryBookId &&
        _running.isNotEmpty) {
      return Future.value();
    }
    return _running.putIfAbsent(book.id, () {
      _cancel[book.id] = false;
      return _run(book).whenComplete(() => _running.remove(book.id));
    });
  }

  void resumeForLibrary(List<Book> books) {
    final pending = books
        .where((b) => b.status == 'extracting' || b.status == 'needs_ocr')
        .toList();
    if (pending.isEmpty) return;
    if (_primaryBookId != null) {
      final focused = pending.where((b) => b.id == _primaryBookId).toList();
      for (final book in focused) {
        if (!isRunning(book.id)) unawaited(ensureOcr(book));
      }
      return;
    }
    if (_running.isNotEmpty) return;
    final next = pending.first;
    if (!isRunning(next.id)) unawaited(ensureOcr(next));
  }

  void _maybeAnalyzeReadyChapters(Book book) {
    final last = _lastAnalysisKick[book.id];
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(seconds: 45))
      return;
    _lastAnalysisKick[book.id] = now;
    unawaited(_analysis.analyzeReadyChapters(book));
  }

  void _emit(OcrEvent e) {
    for (final l in _listeners) {
      l(e);
    }
  }

  Future<void> _run(Book book) async {
    var fresh = (await _repo.getBook(book.id)) ?? book;
    if (fresh.status == 'needs_ocr') {
      await _repo.updateBook(fresh.id, {
        'status': 'extracting',
        'status_detail': 'Reanudando lectura…',
      });
    }
    _emit(
      OcrEvent(
        bookId: fresh.id,
        message: 'Abriendo el PDF…',
        done: 0,
        total: fresh.pageCount,
      ),
    );

    final data = await _repo.downloadPdfBytes(fresh.storagePath);
    final summaries = await _repo.listPageSummaries(fresh.id);
    var targets = summaries
        .where((r) => isSparsePage((r['char_count'] as num?)?.toInt() ?? 0))
        .map((r) => (r['page_number'] as num).toInt())
        .toList();
    if (targets.isEmpty && summaries.isEmpty) {
      targets = List.generate(fresh.pageCount, (i) => i + 1);
    }
    targets = _orderTargets(fresh.id, targets);
    if (targets.isEmpty) {
      await _repo.updateBook(fresh.id, {
        'status': 'ready',
        'status_detail': null,
      });
      unawaited(_analysis.analyzeReadyChapters(fresh));
      return;
    }

    _emit(
      OcrEvent(
        bookId: fresh.id,
        message: 'Reconociendo texto (Vision)…',
        done: 0,
        total: targets.length,
      ),
    );
    final doc = await PdfDocument.openData(data, sourceName: fresh.storagePath);
    var done = 0;
    try {
      for (var i = 0; i < targets.length; i += ocrBatchSize) {
        if (_cancel[fresh.id] == true) throw Exception('Lectura cancelada.');
        final batch = targets.skip(i).take(ocrBatchSize).toList();
        final pages =
            <
              ({
                int page,
                String text,
                List<TextItem> items,
                String? printedLabel,
                int charCount,
              })
            >[];
        for (final pageNumber in batch) {
          pages.add(await _ocrPage(doc, pageNumber));
        }
        await _repo.upsertPages(
          bookId: fresh.id,
          userId: fresh.userId,
          pages: pages,
        );
        done += batch.length;
        await _repo.updateBook(fresh.id, {
          'analysis_progress': done / targets.length,
          'status_detail': 'Leyendo texto: $done/${targets.length} páginas',
        });
        _emit(
          OcrEvent(
            bookId: fresh.id,
            message: 'Leyendo página ${batch.last} de ${fresh.pageCount}',
            done: done,
            total: targets.length,
          ),
        );
        _maybeAnalyzeReadyChapters(fresh);
      }
    } catch (e) {
      final message = _friendlyOcrError(e);
      _emit(
        OcrEvent(
          bookId: fresh.id,
          message: message,
          done: done,
          total: targets.length,
          error: message,
        ),
      );
      if (message == 'Lectura cancelada.') return;
      await _repo.updateBook(fresh.id, {
        'status': 'needs_ocr',
        'status_detail': message,
      });
      return;
    } finally {
      await doc.dispose();
    }

    final all = await _repo.listPageSummaries(fresh.id);
    final stillSparse = all
        .where((r) => isSparsePage((r['char_count'] as num?)?.toInt() ?? 0))
        .length;
    if (documentNeedsOcr(
      all.map((r) => (r['char_count'] as num?)?.toInt() ?? 0).toList(),
    )) {
      await _repo.updateBook(fresh.id, {
        'status': 'needs_ocr',
        'status_detail':
            'El reconocimiento no pudo leer suficiente texto en este PDF.',
        'analysis_progress':
            1 - stillSparse / (all.length > 0 ? all.length : 1),
      });
      return;
    }

    await _maybeRefreshChapters(
      fresh,
      all.map((r) => r['text'] as String? ?? '').toList(),
    );
    final sample = all
        .where((r) => !isSparsePage((r['char_count'] as num?)?.toInt() ?? 0))
        .take(12)
        .map((r) => r['text'] as String? ?? '')
        .join('\n');
    await _repo.updateBook(fresh.id, {
      'status': 'ready',
      'status_detail': null,
      'analysis_progress': 0,
      'language': fresh.language == 'unknown'
          ? _detectLanguage(sample)
          : fresh.language,
    });
    fresh = (await _repo.getBook(fresh.id)) ?? fresh;
    unawaited(_analysis.analyzeReadyChapters(fresh));
  }

  List<int> _orderTargets(String bookId, List<int> targets) {
    final pri = _priority[bookId];
    return [...targets]..sort((a, b) {
      final pa = pri?.contains(a) == true ? 0 : 1;
      final pb = pri?.contains(b) == true ? 0 : 1;
      if (pa != pb) return pa.compareTo(pb);
      return a.compareTo(b);
    });
  }

  Future<
    ({
      int page,
      String text,
      List<TextItem> items,
      String? printedLabel,
      int charCount,
    })
  >
  _ocrPage(PdfDocument doc, int pageNumber) async {
    final page = doc.pages[pageNumber - 1];
    await page.ensureLoaded();
    const dpi = 150.0;
    final scale = dpi / 72.0;
    final image = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (image == null) {
      return (
        page: pageNumber,
        text: '',
        items: <TextItem>[],
        printedLabel: null,
        charCount: 0,
      );
    }
    try {
      final words = await recognizeBgraPage(
        width: image.width,
        height: image.height,
        pixels: image.pixels,
      );
      final laid = layoutOcrWords(
        words,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      return (
        page: pageNumber,
        text: laid.text.trim(),
        items: laid.items,
        printedLabel: null,
        charCount: laid.text.trim().length,
      );
    } finally {
      image.dispose();
    }
  }

  Future<void> _maybeRefreshChapters(Book book, List<String> pageTexts) async {
    final chapters = await _repo.listChapters(book.id);
    final fallbackOnly =
        chapters.length <= 1 &&
        (chapters.isEmpty || chapters.first.title == 'Documento completo');
    if (!fallbackOnly) return;
    final detected = detectChapters(
      pageCount: book.pageCount,
      outline: [],
      pageTexts: pageTexts,
    );
    if (detected.length <= 1) return;
    await _repo.replaceChapters(
      bookId: book.id,
      userId: book.userId,
      chapters: detected,
    );
  }

  String _detectLanguage(String sample) {
    final lower = sample.toLowerCase();
    final es = RegExp(r'\b(el|la|de|que|y|en)\b').allMatches(lower).length;
    final en = RegExp(r'\b(the|and|of|to|in)\b').allMatches(lower).length;
    if (es > en + 3) return 'es';
    if (en > es + 3) return 'en';
    return 'unknown';
  }

  String _friendlyOcrError(Object e) {
    final raw = e.toString().replaceFirst('Exception: ', '');
    if (raw.contains('23505') || raw.contains('duplicate key')) {
      return 'No se pudo guardar una página duplicada. Reintenta abrir el libro.';
    }
    if (raw.contains('PostgrestException')) {
      return 'Error al guardar el texto reconocido. Vuelve a abrir el libro para reintentar.';
    }
    return raw.length > 160 ? '${raw.substring(0, 157)}…' : raw;
  }
}
