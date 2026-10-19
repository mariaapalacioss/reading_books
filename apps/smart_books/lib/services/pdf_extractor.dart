import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../data/models/text_item.dart';
import '../domain/chapters.dart';
import '../domain/ocr_layout.dart';

class ExtractedPage {
  const ExtractedPage({
    required this.page,
    required this.text,
    required this.items,
    required this.printedLabel,
    required this.charCount,
  });

  final int page;
  final String text;
  final List<TextItem> items;
  final String? printedLabel;
  final int charCount;
}

class ExtractedPdf {
  const ExtractedPdf({
    required this.title,
    required this.author,
    required this.pageCount,
    required this.language,
    required this.needsOcr,
    required this.pages,
    required this.chapters,
  });

  final String title;
  final String author;
  final int pageCount;
  final String language;
  final bool needsOcr;
  final List<ExtractedPage> pages;
  final List<ChapterDraft> chapters;
}

Future<ExtractedPdf> extractPdfBytes(
  Uint8List data, {
  void Function(int page, int total)? onProgress,
}) async {
  if (data.isEmpty) {
    throw Exception('El PDF está vacío o no se descargó por completo.');
  }
  final PdfDocument doc;
  try {
    doc = await PdfDocument.openData(data, sourceName: 'memory:ingest');
  } catch (e) {
    throw Exception(
      'No pudimos abrir este PDF (${e.toString().replaceFirst('Exception: ', '')}). '
      'Si viene de iCloud, ábrelo en Archivos y espera a que termine de descargarse.',
    );
  }
  try {
    await doc.loadPagesProgressively();
    final pageCount = doc.pages.length;
    final pages = <ExtractedPage>[];
    for (var n = 1; n <= pageCount; n++) {
      pages.add(await _extractPage(doc, n));
      onProgress?.call(n, pageCount);
    }
    final outline = await _readOutline(doc);
    final sample = pages.take(8).map((p) => p.text).join('\n');
    return ExtractedPdf(
      title: 'Libro sin título',
      author: '',
      pageCount: pageCount,
      language: _detectLanguage(sample),
      needsOcr: documentNeedsOcr(pages.map((p) => p.charCount).toList()),
      pages: pages,
      chapters: detectChapters(
        pageCount: pageCount,
        outline: outline,
        pageTexts: pages.map((p) => p.text).toList(),
      ),
    );
  } finally {
    await doc.dispose();
  }
}

/// Extrae texto e items de una página ya abierta (lector / reparación de capa de texto).
Future<ExtractedPage> extractPageFromDocument(
  PdfDocument doc,
  int pageNumber,
) => _extractPage(doc, pageNumber);

Future<ExtractedPage> _extractPage(PdfDocument doc, int pageNumber) async {
  final page = doc.pages[pageNumber - 1];
  await page.ensureLoaded();
  final structured = await page.loadStructuredText();
  final w = page.width;
  final h = page.height;
  final items = <TextItem>[];
  for (final frag in structured.fragments) {
    final b = frag.bounds;
    items.add(
      TextItem(
        s: frag.text,
        start: frag.index,
        x: _round(b.left / w),
        y: _round(b.top / h),
        w: _round(b.width / w),
        h: _round(b.height / h),
      ),
    );
  }
  final text = structured.fullText.replaceAll(RegExp(r'[ \t]+\n'), '\n').trim();
  return ExtractedPage(
    page: pageNumber,
    text: text,
    items: items,
    printedLabel: _findPrintedLabel(items),
    charCount: text.length,
  );
}

Future<List<OutlineEntry>> _readOutline(PdfDocument doc) async {
  final nodes = await doc.loadOutline();
  final entries = <OutlineEntry>[];
  void walk(List<PdfOutlineNode> list) {
    for (final node in list) {
      final page = node.dest?.pageNumber;
      if (page != null && page >= 1) {
        entries.add(
          OutlineEntry(
            title: node.title.isEmpty ? 'Capítulo' : node.title,
            page: page,
          ),
        );
      }
      if (node.children.isNotEmpty) walk(node.children);
    }
  }

  walk(nodes);
  return entries;
}

String? _findPrintedLabel(List<TextItem> items) {
  for (final item in items) {
    if (RegExp(r'^\d{1,4}$').hasMatch(item.s.trim()) &&
        (item.y < 0.08 || item.y > 0.9)) {
      return item.s.trim();
    }
  }
  return null;
}

String _detectLanguage(String sample) {
  final lower = sample.toLowerCase();
  final es = RegExp(
    r'\b(el|la|de|que|y|en|los|las|un|una|por|con)\b',
  ).allMatches(lower).length;
  final en = RegExp(
    r'\b(the|and|of|to|in|that|is|for|with|on)\b',
  ).allMatches(lower).length;
  if (es > en + 3) return 'es';
  if (en > es + 3) return 'en';
  return 'unknown';
}

double _round(double v) => (v * 10000).roundToDouble() / 10000;
