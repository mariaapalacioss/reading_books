import 'dart:async';

import '../data/models/book.dart';
import '../data/models/chapter.dart';
import '../domain/chunks.dart';
import '../domain/content_language.dart';
import '../domain/quotes.dart';
import '../data/repositories/books_repository.dart';
import '../features/chatgpt/plan_api.dart';

class AnalysisEvent {
  const AnalysisEvent({
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

class AnalysisService {
  AnalysisService(this._repo);

  final BooksRepository _repo;
  final _running = <String, Future<void>>{};
  final _ready = <String, Future<void>>{};
  final _listeners = <void Function(AnalysisEvent)>[];

  void subscribe(void Function(AnalysisEvent) l) => _listeners.add(l);

  void _emit(AnalysisEvent e) {
    for (final l in _listeners) {
      l(e);
    }
  }

  Future<void> ensureAnalysis(Book book) {
    if (!_bookReadyForAnalysis(book.status)) return Future.value();
    return _running.putIfAbsent(
      book.id,
      () => _run(book).whenComplete(() => _running.remove(book.id)),
    );
  }

  Future<void> analyzeReadyChapters(Book book) {
    if (!_bookReadyForAnalysis(book.status)) return Future.value();
    return _ready.putIfAbsent(
      book.id,
      () => _runReady(book).whenComplete(() => _ready.remove(book.id)),
    );
  }

  bool _bookReadyForAnalysis(String status) {
    return status == 'ready' || status == 'partial' || status == 'analyzed';
  }

  Future<void> _runReady(Book book) async {
    final chapters = await _repo.listChapters(book.id);
    for (final chapter in chapters) {
      if (chapter.analysisStatus != 'pending' &&
          chapter.analysisStatus != 'failed')
        continue;
      if (!await _chapterHasText(book.id, chapter)) continue;
      await _analyzeChapter(book, chapter);
      break;
    }
  }

  Future<void> _run(Book book) async {
    final chapters = await _repo.listChapters(book.id);
    final pending = <Chapter>[];
    for (final ch in chapters) {
      if (ch.analysisStatus == 'done') continue;
      if (await _chapterHasText(book.id, ch)) pending.add(ch);
    }
    if (pending.isEmpty) {
      _emit(
        AnalysisEvent(
          bookId: book.id,
          message: 'Análisis ya guardado.',
          done: chapters.length,
          total: chapters.length,
        ),
      );
      return;
    }
    await _repo.updateBook(book.id, {
      'status': 'analyzing',
      'analysis_progress':
          (chapters.length - pending.length) /
          (chapters.isEmpty ? 1 : chapters.length),
    });
    var done = chapters.length - pending.length;
    for (final chapter in pending) {
      _emit(
        AnalysisEvent(
          bookId: book.id,
          message: 'Analizando «${chapter.title}»',
          done: done,
          total: chapters.length,
        ),
      );
      try {
        await _analyzeChapter(book, chapter);
      } catch (e) {
        final message = e.toString().replaceFirst('Exception: ', '');
        await _repo.updateBook(book.id, {
          'status': 'partial',
          'status_detail': 'Análisis incompleto: $message',
        });
        _emit(
          AnalysisEvent(
            bookId: book.id,
            message: message,
            done: done,
            total: chapters.length,
            error: message,
          ),
        );
        return;
      }
      done++;
    }
    await _repo.updateBook(book.id, {
      'status': 'analyzed',
      'analysis_progress': 1,
    });
  }

  Future<bool> _chapterHasText(String bookId, Chapter chapter) async {
    return _repo.chapterHasReadableText(
      bookId,
      chapter.startPage,
      chapter.endPage,
    );
  }

  Future<void> _analyzeChapter(Book book, Chapter chapter) async {
    final api = PlanApi();
    await api.ensureAccessToken(book.userId);

    final rows = await _repo.listPagesInRange(
      book.id,
      chapter.startPage,
      chapter.endPage,
    );
    final pages = rows
        .map(
          (r) => PageSlice(
            page: (r['page_number'] as num).toInt(),
            text: r['text'] as String? ?? '',
          ),
        )
        .where((p) => p.text.trim().isNotEmpty)
        .toList();
    if (!pages.any((p) => p.text.trim().length > 40)) {
      throw Exception('Este capítulo aún no tiene texto leído.');
    }

    final windows = windowsForAnalysis(pages);
    final merged = <String, dynamic>{
      'summary_es': '',
      'summary_en': '',
      'highlights': <dynamic>[],
      'key_points': <dynamic>[],
    };

    final chapterLang = resolveContentLanguage(
      sourceText: windows.map((w) => w.content).join('\n'),
      metadataLanguage: book.language,
      localeFallback: contentLanguageFromCode(book.explanationLanguage),
    );

    for (final window in windows) {
      final payload = await api.completePlanJson<Map<String, dynamic>>(
        userId: book.userId,
        instructions: _analysisInstructions(
          book.highlightIntensity,
          chapterLang,
        ),
        user: 'Capítulo: ${chapter.title}\n\n${window.content}',
      );
      (merged['highlights'] as List).addAll(
        payload['highlights'] as List? ?? [],
      );
      (merged['key_points'] as List).addAll(
        payload['key_points'] as List? ?? [],
      );
      if ((merged['summary_es'] as String).isEmpty)
        merged['summary_es'] = payload['summary_es'] ?? '';
      if ((merged['summary_en'] as String).isEmpty)
        merged['summary_en'] = payload['summary_en'] ?? '';
    }

    await _persistAnalysis(
      book: book,
      chapter: chapter,
      merged: merged,
      pages: pages,
      contentLanguage: chapterLang,
    );
  }

  Future<void> _persistAnalysis({
    required Book book,
    required Chapter chapter,
    required Map<String, dynamic> merged,
    required List<PageSlice> pages,
    required ContentLanguage contentLanguage,
  }) async {
    final client = _repo.client;
    await client
        .from('chapters')
        .update({'analysis_status': 'processing', 'analysis_error': null})
        .eq('id', chapter.id);
    await client.from('analysis_jobs').upsert({
      'book_id': book.id,
      'chapter_id': chapter.id,
      'user_id': book.userId,
      'intensity': book.highlightIntensity,
      'status': 'processing',
      'started_at': DateTime.now().toIso8601String(),
    }, onConflict: 'chapter_id,intensity');

    final highlights = (merged['highlights'] as List?) ?? [];
    await client
        .from('highlights')
        .delete()
        .eq('chapter_id', chapter.id)
        .eq('intensity', book.highlightIntensity)
        .eq('origin', 'ai');

    for (final raw in highlights) {
      final map = Map<String, dynamic>.from(raw as Map);
      final quote = (map['quote'] as String? ?? '').trim();
      if (quote.length < 12) continue;
      var pageNumber = pages.first.page;
      for (final p in pages) {
        if (p.text.contains(quote)) {
          pageNumber = p.page;
          break;
        }
      }
      final hash = await quoteHash(quote);
      final explanationEs = contentLanguage == ContentLanguage.es
          ? (map['explanation_es'] ?? map['explanation'])
          : null;
      final explanationEn = contentLanguage == ContentLanguage.en
          ? (map['explanation_en'] ?? map['explanation'])
          : null;
      await client
          .from('highlights')
          .upsert(
            {
              'book_id': book.id,
              'chapter_id': chapter.id,
              'user_id': book.userId,
              'page_number': pageNumber,
              'quote': quote,
              'quote_hash': hash,
              'category': map['category'] ?? 'idea',
              'explanation_es': explanationEs,
              'explanation_en': explanationEn,
              'origin': 'ai',
              'intensity': book.highlightIntensity,
            },
            onConflict: 'chapter_id,intensity,quote_hash',
            ignoreDuplicates: true,
          );
    }

    final points = (merged['key_points'] as List?) ?? [];
    await client.from('chapter_points').delete().eq('chapter_id', chapter.id);
    var pos = 1;
    for (final raw in points.take(12)) {
      final map = Map<String, dynamic>.from(raw as Map);
      String clip(String? s) {
        final t = (s ?? '').trim();
        return t.length <= 500 ? t : t.substring(0, 500);
      }

      final textEs = contentLanguage == ContentLanguage.es
          ? clip(map['text_es'] as String? ?? map['text'] as String?)
          : '';
      final textEn = contentLanguage == ContentLanguage.en
          ? clip(map['text_en'] as String? ?? map['text'] as String?)
          : '';
      if (textEs.isEmpty && textEn.isEmpty) continue;
      await client.from('chapter_points').insert({
        'book_id': book.id,
        'chapter_id': chapter.id,
        'user_id': book.userId,
        'position': pos++,
        'text_es': textEs,
        'text_en': textEn,
        'quote': map['quote'],
      });
    }

    final summaryEs = contentLanguage == ContentLanguage.es
        ? merged['summary_es'] ?? merged['summary']
        : '';
    final summaryEn = contentLanguage == ContentLanguage.en
        ? merged['summary_en'] ?? merged['summary']
        : '';

    await client
        .from('chapters')
        .update({
          'analysis_status': 'done',
          'analysis_error': null,
          'summary_es': summaryEs,
          'summary_en': summaryEn,
        })
        .eq('id', chapter.id);

    await client
        .from('analysis_jobs')
        .update({
          'status': 'done',
          'finished_at': DateTime.now().toIso8601String(),
        })
        .eq('chapter_id', chapter.id)
        .eq('intensity', book.highlightIntensity);
  }

  String _analysisInstructions(String intensity, ContentLanguage language) {
    final langBlock = sourceLanguagePromptBlock(language);
    if (language == ContentLanguage.en) {
      return '''
You are the Smart Books academic analyst. Return JSON with:
- summary_en: chapter summary in English (leave summary_es empty string)
- summary_es: empty string
- highlights: [{quote, category, explanation_en, explanation_es: ""}]
- key_points: [{text_en, text_es: "", quote}]
$langBlock
Intensity: $intensity. Do not invent quotes; use literal fragments from the chapter.''';
    }
    return '''
Eres el analista académico de Smart Books. Devuelve JSON con:
- summary_es: resumen del capítulo en español (summary_en cadena vacía)
- summary_en: cadena vacía
- highlights: [{quote, category, explanation_es, explanation_en: ""}]
- key_points: [{text_es, text_en: "", quote}]
$langBlock
Intensidad: $intensity. No inventes citas; usa fragmentos literales del capítulo.''';
  }
}
