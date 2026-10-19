import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

/// Genera un PDF más liviano (páginas rasterizadas) para caber en Storage.
/// El texto ya extraído en BD no se pierde; la lectura en app sigue usando esa capa.
Future<Uint8List> optimizePdfForCloudUpload(
  Uint8List source, {
  required int targetBytes,
  void Function(String message)? onProgress,
}) async {
  final doc = await PdfDocument.openData(source, sourceName: 'memory:optimize');
  try {
    await doc.loadPagesProgressively();
    final pageCount = doc.pages.length;
    if (pageCount == 0) {
      throw Exception('El PDF no tiene páginas.');
    }

    final attempts = _compressionAttempts(
      sourceBytes: source.length,
      pageCount: pageCount,
    );

    Uint8List? smallest;
    for (var i = 0; i < attempts.length; i++) {
      final attempt = attempts[i];
      if (i == 0) {
        onProgress?.call(
          'Comprimiendo PDF (${attempt.dpi.round()} DPI, $pageCount páginas)…',
        );
      } else {
        onProgress?.call(
          'Ajustando para la nube (${attempt.dpi.round()} DPI, '
          'paso ${i + 1}/${attempts.length})…',
        );
      }

      final built = await _buildRasterPdf(
        doc,
        dpi: attempt.dpi,
        jpegQuality: attempt.quality,
        onPage: (n, total) {
          if (n == 1 || n == total || n % 24 == 0) {
            onProgress?.call('Comprimiendo… página $n/$total');
          }
        },
      );
      smallest = built;
      developer.log(
        'PDF optimize ${attempt.dpi}dpi q=${attempt.quality} → ${built.length} bytes (target $targetBytes)',
        name: 'pdf_storage_optimizer',
      );
      if (built.length <= targetBytes) {
        return built;
      }
    }

    if (smallest != null) {
      return smallest;
    }
    throw Exception('No se pudo comprimir el PDF.');
  } finally {
    await doc.dispose();
  }
}

Future<Uint8List> _buildRasterPdf(
  PdfDocument document, {
  required double dpi,
  required int jpegQuality,
  void Function(int page, int total)? onPage,
}) async {
  final out = pw.Document(compress: true);
  final scale = dpi / 72.0;
  final total = document.pages.length;

  for (var n = 1; n <= total; n++) {
    onPage?.call(n, total);
    final page = document.pages[n - 1];
    await page.ensureLoaded();
    final pageW = page.width;
    final pageH = page.height;

    final rendered = await page.render(
      fullWidth: pageW * scale,
      fullHeight: pageH * scale,
    );
    if (rendered == null) {
      throw Exception('No se pudo renderizar la página $n.');
    }

    try {
      final rgba = img.Image.fromBytes(
        width: rendered.width,
        height: rendered.height,
        bytes: rendered.pixels.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
      final jpeg = Uint8List.fromList(
        img.encodeJpg(rgba, quality: jpegQuality.clamp(40, 95)),
      );

      out.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageW, pageH, marginAll: 0),
          build: (_) => pw.Center(
            child: pw.Image(
              pw.MemoryImage(jpeg),
              width: pageW,
              height: pageH,
              fit: pw.BoxFit.fill,
            ),
          ),
        ),
      );
    } finally {
      rendered.dispose();
    }
  }

  return Uint8List.fromList(await out.save());
}

List<({double dpi, int quality})> _compressionAttempts({
  required int sourceBytes,
  required int pageCount,
}) {
  // Calidad alta primero; solo baja DPI/JPEG si la pasada anterior no cabe en Storage.
  final mb = sourceBytes / (1024 * 1024);
  if (mb > 90 || pageCount > 260) {
    return const [
      (dpi: 110, quality: 82),
      (dpi: 100, quality: 78),
      (dpi: 92, quality: 74),
      (dpi: 84, quality: 70),
      (dpi: 76, quality: 66),
      (dpi: 68, quality: 62),
      (dpi: 60, quality: 56),
    ];
  }
  return const [
    (dpi: 132, quality: 86),
    (dpi: 120, quality: 84),
    (dpi: 110, quality: 80),
    (dpi: 100, quality: 76),
    (dpi: 92, quality: 72),
    (dpi: 84, quality: 68),
    (dpi: 76, quality: 64),
  ];
}
