import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/book.dart';
import '../models/chapter.dart';
import '../models/highlight.dart';
import '../models/text_item.dart';
import '../../core/config/pdf_upload_config.dart';
import '../../core/storage/local_pdf_store.dart';
import '../../domain/chapters.dart';
import '../../domain/chunks.dart';
import '../../domain/quotes.dart';
import '../../domain/study_text.dart';
import '../../services/pdf_storage_optimizer.dart';

class BooksRepository {
  BooksRepository(this._client);

  final SupabaseClient _client;

  SupabaseClient get client => _client;

  Future<List<Book>> listBooks() async {
    final rows = await _client
        .from('books')
        .select()
        .order('updated_at', ascending: false);
    return (rows as List)
        .map((r) => Book.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<Book?> getBook(String id) async {
    final row = await _client.from('books').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return Book.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> updateBook(String id, Map<String, dynamic> patch) async {
    await _client.from('books').update(patch).eq('id', id);
  }

  Future<void> deleteBook(Book book) async {
    if (book.isLocalStorage) {
      await LocalPdfStore.instance.delete(
        LocalPdfStore.keyFromLocalPath(book.storagePath),
      );
    } else {
      await _client.storage.from('books').remove([book.storagePath]);
    }
    await _client.from('books').delete().eq('id', book.id);
  }

  Future<void> uploadBinary(String path, Uint8List bytes) async {
    await _client.storage
        .from('books')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        );
  }

  /// Sube a Supabase Storage (comprime y reintenta si Storage devuelve 413).
  Future<String> persistPdfBytes(
    String userId,
    String bookId,
    Uint8List bytes, {
    void Function(String message)? onProgress,
  }) async {
    final cloudKey = '$userId/$bookId.pdf';
    await _uploadPdfWithCompressionFallback(
      cloudKey: cloudKey,
      bytes: bytes,
      onProgress: onProgress,
    );
    onProgress?.call('Guardando copia local en calidad original…');
    // Lectura en este dispositivo usa el PDF original; la nube puede llevar versión optimizada.
    await LocalPdfStore.instance.put(cloudKey, bytes);
    return cloudKey;
  }

  Future<Uint8List> _uploadPdfWithCompressionFallback({
    required String cloudKey,
    required Uint8List bytes,
    void Function(String message)? onProgress,
  }) async {
    var usedCompressed = false;

    Future<Uint8List> uploadPayload(Uint8List payload, String progress) async {
      onProgress?.call(progress);
      await uploadBinary(cloudKey, payload);
      return payload;
    }

    Future<Uint8List> compressThenUpload() async {
      usedCompressed = true;
      onProgress?.call(
        'La nube rechazó el tamaño; creando versión optimizada para sincronizar '
        '(en este iPhone/Mac seguirás leyendo el original)…',
      );
      final compressed = await optimizePdfForCloudUpload(
        bytes,
        targetBytes: PdfUploadConfig.compressTargetBytes,
        onProgress: onProgress,
      );
      final mb = (compressed.length / (1024 * 1024)).toStringAsFixed(1);
      try {
        return await uploadPayload(
          compressed,
          'Subiendo PDF optimizado ($mb MB)…',
        );
      } catch (e) {
        if (isStorageSizeError(e)) {
          throw Exception('storage_size_after_compress:${compressed.length}');
        }
        rethrow;
      }
    }

    try {
      return await uploadPayload(bytes, 'Subiendo el PDF original a la nube…');
    } catch (e) {
      final hint = storageSizeErrorHint(e);
      developer.log(
        'Upload original falló (${hint ?? e.runtimeType}): $e',
        name: 'books_repository',
      );
      if (usedCompressed || !isStorageSizeError(e)) rethrow;
      return compressThenUpload();
    }
  }

  /// Libros antiguos con `local/…` en BD: sube el PDF y actualiza la misma fila.
  Future<bool> promoteLocalBookToCloud(Book book) async {
    if (!book.isLocalStorage) return false;
    final cloudKey = LocalPdfStore.keyFromLocalPath(book.storagePath);
    final bytes = await LocalPdfStore.instance.get(cloudKey);
    if (bytes == null || bytes.isEmpty) {
      developer.log(
        'Sin bytes locales para ${book.id} ($cloudKey)',
        name: 'books_repository',
      );
      return false;
    }
    try {
      await _uploadPdfWithCompressionFallback(
        cloudKey: cloudKey,
        bytes: bytes,
        onProgress: null,
      );
      await LocalPdfStore.instance.put(cloudKey, bytes);
      await updateBook(book.id, {
        'storage_path': cloudKey,
        'status_detail': null,
      });
      developer.log(
        'PDF ${book.id} sincronizado a Storage',
        name: 'books_repository',
      );
      return true;
    } catch (e, st) {
      developer.log(
        'No se pudo subir PDF local ${book.id}: $e',
        name: 'books_repository',
        stackTrace: st,
      );
      return false;
    }
  }

  Future<void> syncLocalBooksToCloud(Iterable<Book> books) async {
    for (final book in books) {
      if (book.isLocalStorage) {
        await promoteLocalBookToCloud(book);
      }
    }
  }

  Future<void> insertBook(Map<String, dynamic> row) async {
    await _client.from('books').insert(row);
  }

  Future<Uint8List> downloadPdfBytes(String storagePath) async {
    if (LocalPdfStore.isLocalPath(storagePath)) {
      final key = LocalPdfStore.keyFromLocalPath(storagePath);
      final cached = await LocalPdfStore.instance.get(key);
      if (cached != null && cached.isNotEmpty) return cached;
      final remote = await _client.storage.from('books').download(key);
      await LocalPdfStore.instance.put(key, remote);
      return remote;
    }

    final cached = await LocalPdfStore.instance.get(storagePath);
    if (cached != null && cached.isNotEmpty) return cached;

    final remote = await _client.storage.from('books').download(storagePath);
    await LocalPdfStore.instance.put(storagePath, remote);
    return remote;
  }

  Future<void> insertPages({
    required String bookId,
    required String userId,
    required List<
      ({
        int page,
        String text,
        List<TextItem> items,
        String? printedLabel,
        int charCount,
      })
    >
    pages,
  }) async {
    for (var i = 0; i < pages.length; i += 12) {
      final slice = pages.skip(i).take(12).map((p) {
        final text = sanitizeDbText(p.text);
        return {
          'book_id': bookId,
          'user_id': userId,
          'page_number': p.page,
          'printed_label': p.printedLabel != null
              ? sanitizeDbText(p.printedLabel!)
              : null,
          'text': text,
          'items': p.items
              .map(
                (it) => TextItem(
                  s: sanitizeDbText(it.s),
                  start: it.start,
                  x: it.x,
                  y: it.y,
                  w: it.w,
                  h: it.h,
                ).toJson(),
              )
              .toList(),
          'char_count': p.charCount > 0 ? p.charCount : text.length,
        };
      }).toList();
      await _client.from('book_pages').insert(slice);
    }
  }

  Future<void> upsertPages({
    required String bookId,
    required String userId,
    required List<
      ({
        int page,
        String text,
        List<TextItem> items,
        String? printedLabel,
        int charCount,
      })
    >
    pages,
  }) async {
    for (var i = 0; i < pages.length; i += 8) {
      final slice = pages.skip(i).take(8).map((p) {
        final text = sanitizeDbText(p.text);
        return {
          'book_id': bookId,
          'user_id': userId,
          'page_number': p.page,
          'printed_label': p.printedLabel != null
              ? sanitizeDbText(p.printedLabel!)
              : null,
          'text': text,
          'items': p.items
              .map(
                (it) => TextItem(
                  s: sanitizeDbText(it.s),
                  start: it.start,
                  x: it.x,
                  y: it.y,
                  w: it.w,
                  h: it.h,
                ).toJson(),
              )
              .toList(),
          'char_count': p.charCount > 0 ? p.charCount : text.length,
        };
      }).toList();
      await _client
          .from('book_pages')
          .upsert(slice, onConflict: 'book_id,page_number');
    }
  }

  Future<void> insertChapters({
    required String bookId,
    required String userId,
    required List<ChapterDraft> chapters,
  }) async {
    if (chapters.isEmpty) return;
    await _client
        .from('chapters')
        .insert(
          chapters
              .asMap()
              .entries
              .map(
                (e) => {
                  'book_id': bookId,
                  'user_id': userId,
                  'position': e.key + 1,
                  'title': e.value.title,
                  'start_page': e.value.startPage,
                  'end_page': e.value.endPage,
                  'source': e.value.source,
                  'analysis_status': 'pending',
                },
              )
              .toList(),
        );
  }

  Future<void> replaceChapters({
    required String bookId,
    required String userId,
    required List<ChapterDraft> chapters,
  }) async {
    await _client.from('chapters').delete().eq('book_id', bookId);
    await insertChapters(bookId: bookId, userId: userId, chapters: chapters);
  }

  Future<void> insertSearchChunks({
    required String bookId,
    required String userId,
    required List<ChunkDraft> chunks,
  }) async {
    for (var i = 0; i < chunks.length; i += 40) {
      final slice = chunks
          .skip(i)
          .take(40)
          .map(
            (c) => {
              'book_id': bookId,
              'user_id': userId,
              'page_start': c.pageStart,
              'page_end': c.pageEnd,
              'content': sanitizeDbText(c.content),
            },
          )
          .toList();
      if (slice.isEmpty) continue;
      await _client.from('search_chunks').insert(slice);
    }
  }

  Future<List<Map<String, dynamic>>> listPageSummaries(String bookId) async {
    final rows = await _client
        .from('book_pages')
        .select('page_number, char_count, text')
        .eq('book_id', bookId)
        .order('page_number');
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<String?> signedPdfUrl(String storagePath) async {
    if (storagePath.startsWith('local/')) return null;
    return _client.storage.from('books').createSignedUrl(storagePath, 3600);
  }

  Future<List<Chapter>> listChapters(String bookId) async {
    final rows = await _client
        .from('chapters')
        .select()
        .eq('book_id', bookId)
        .order('position');
    return (rows as List)
        .map((r) => Chapter.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listBookmarks(String bookId) async {
    final rows = await _client.from('bookmarks').select().eq('book_id', bookId);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<void> toggleBookmark(
    String bookId,
    String userId,
    int page,
    bool exists,
  ) async {
    if (exists) {
      await _client
          .from('bookmarks')
          .delete()
          .eq('book_id', bookId)
          .eq('page_number', page);
    } else {
      await _client.from('bookmarks').insert({
        'book_id': bookId,
        'user_id': userId,
        'page_number': page,
      });
    }
  }

  Future<Map<String, dynamic>?> getPage(String bookId, int pageNumber) async {
    return _client
        .from('book_pages')
        .select()
        .eq('book_id', bookId)
        .eq('page_number', pageNumber)
        .maybeSingle();
  }

  Future<List<Map<String, dynamic>>> listReadablePages(
    String bookId, {
    int limit = 6,
  }) async {
    final rows = await _client
        .from('book_pages')
        .select('page_number, printed_label, text, char_count')
        .eq('book_id', bookId)
        .gt('char_count', 40)
        .order('page_number')
        .limit(limit);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<bool> chapterHasReadableText(
    String bookId,
    int startPage,
    int endPage,
  ) async {
    final rows = await _client
        .from('book_pages')
        .select('page_number')
        .eq('book_id', bookId)
        .gte('page_number', startPage)
        .lte('page_number', endPage)
        .gt('char_count', 40)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> listPagesInRange(
    String bookId,
    int startPage,
    int endPage,
  ) async {
    final rows = await _client
        .from('book_pages')
        .select('page_number, text, printed_label, char_count')
        .eq('book_id', bookId)
        .gte('page_number', startPage)
        .lte('page_number', endPage)
        .order('page_number');
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> textSearchLibrary(String query) async {
    final safe = query.replaceAll(RegExp(r'[%_\\]'), '').trim();
    if (safe.length < 2) return [];
    final rows = await _client
        .from('book_pages')
        .select('book_id, page_number, text, printed_label, books(title)')
        .ilike('text', '%$safe%')
        .limit(40);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<List<Highlight>> listHighlights(String bookId) async {
    final rows = await _client
        .from('highlights')
        .select()
        .eq('book_id', bookId)
        .order('page_number');
    return (rows as List)
        .map((r) => Highlight.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<Highlight> createManualHighlight({
    required String bookId,
    required String userId,
    required String? chapterId,
    required int pageNumber,
    required String quote,
    required List<Map<String, double>> rects,
  }) async {
    final hash = await quoteHash('$quote${const Uuid().v4()}');
    final row = await _client
        .from('highlights')
        .insert({
          'book_id': bookId,
          'user_id': userId,
          'chapter_id': chapterId,
          'page_number': pageNumber,
          'quote': quote,
          'quote_hash': hash,
          'category': 'manual',
          'origin': 'user',
          'rects': rects,
        })
        .select()
        .single();
    return Highlight.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> patchHighlight(String id, Map<String, dynamic> patch) async {
    await _client.from('highlights').update(patch).eq('id', id);
  }

  Future<Map<String, dynamic>> insertStudyCard(Map<String, dynamic> row) async {
    final result = await _client
        .from('study_cards')
        .insert(row)
        .select()
        .maybeSingle();
    if (result == null) {
      throw Exception('No se pudo guardar el repaso.');
    }
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> insertStudyCards(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return [];
    final result = await _client.from('study_cards').insert(rows).select();
    return (result as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<void> patchStudyCard(String id, Map<String, dynamic> patch) async {
    await _client.from('study_cards').update(patch).eq('id', id);
  }

  Future<void> deleteStudyCard(String id) async {
    await _client.from('study_cards').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> listPoints(String bookId) async {
    final rows = await _client
        .from('chapter_points')
        .select()
        .eq('book_id', bookId);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listStudyCards(String bookId) async {
    final rows = await _client
        .from('study_cards')
        .select()
        .eq('book_id', bookId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }
}
