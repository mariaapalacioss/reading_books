import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../domain/region_select.dart';
import '../domain/rects.dart';
import 'platform_ocr.dart';

const _renderDpi = 150.0;

Future<({Uint8List pixels, int width, int height})?> renderPdfPage(
  PdfDocument document,
  int pageNumber,
) async {
  final page = document.pages[pageNumber - 1];
  await page.ensureLoaded();
  final scale = _renderDpi / 72.0;
  final image = await page.render(
    fullWidth: page.width * scale,
    fullHeight: page.height * scale,
  );
  if (image == null) return null;
  try {
    return (
      pixels: Uint8List.fromList(image.pixels),
      width: image.width,
      height: image.height,
    );
  } finally {
    image.dispose();
  }
}

Future<String> recognizeRegionOnPage({
  required PdfDocument document,
  required int pageNumber,
  required NormRect region,
}) async {
  final rendered = await renderPdfPage(document, pageNumber);
  if (rendered == null) return '';
  final crop = cropBgraRegion(
    pixels: rendered.pixels,
    width: rendered.width,
    height: rendered.height,
    region: region,
  );
  if (crop == null) return '';
  final words = await recognizeBgraPage(
    width: crop.width,
    height: crop.height,
    pixels: crop.pixels,
  );
  return words
      .map((w) => w.text)
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
