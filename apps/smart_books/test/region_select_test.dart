import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/data/models/text_item.dart';
import 'package:smart_books/domain/region_select.dart';
import 'package:smart_books/domain/rects.dart';

void main() {
  test('textFromRegion une ítems dentro del rectángulo', () {
    const items = [
      TextItem(start: 0, s: 'Preámbulo', x: 0.1, y: 0.2, w: 0.3, h: 0.02),
      TextItem(start: 10, s: 'clínico', x: 0.12, y: 0.22, w: 0.2, h: 0.02),
    ];
    const region = NormRect(x: 0.05, y: 0.15, w: 0.5, h: 0.2);
    const pageText = 'Preámbulo clínico extendido';
    final picked = textFromRegion(items, region, pageText: pageText);
    expect(picked.quote.length, greaterThanOrEqualTo(8));
    expect(picked.rects, isNotEmpty);
  });

  test('cropBgraRegion recorta dimensiones mínimas', () {
    final pixels = Uint8List.fromList(List.filled(100 * 100 * 4, 200));
    final crop = cropBgraRegion(
      pixels: pixels,
      width: 100,
      height: 100,
      region: normRectFromPoints(0.1, 0.1, 0.5, 0.5),
    );
    expect(crop, isNotNull);
    expect(crop!.width, greaterThan(8));
    expect(crop.height, greaterThan(8));
  });
}
