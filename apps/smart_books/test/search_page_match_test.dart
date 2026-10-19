import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/data/models/text_item.dart';
import 'package:smart_books/domain/search_page_match.dart';

TextItem _lineItem(String text) {
  return TextItem(s: text, start: 0, x: 0.05, y: 0.1, w: 0.9, h: 0.04);
}

void main() {
  test('encuentra frase con espacio normal', () {
    const page = 'Texto sobre el tercer molar incluido en la página.';
    final match = findSearchMatchOnPage(
      pageText: page,
      items: [_lineItem(page)],
      query: 'tercer molar',
      snippet: 'el tercer molar incluido',
    );
    expect(match, isNotNull);
    expect(match!.matchedText.toLowerCase(), contains('tercer molar'));
    expect(match.rects, isNotEmpty);
  });

  test('encuentra frase partida por salto de línea', () {
    const page = 'Texto sobre el tercer\nmolar incluido.';
    final match = findSearchMatchOnPage(
      pageText: page,
      items: [_lineItem(page)],
      query: 'tercer molar',
    );
    expect(match, isNotNull);
    expect(match!.rects, isNotEmpty);
  });

  test('usa snippet del resultado cuando acota la búsqueda', () {
    const page = 'tercer molar al inicio. Otro tercer molar al final.';
    final match = findSearchMatchOnPage(
      pageText: page,
      items: [_lineItem(page)],
      query: 'tercer molar',
      snippet: 'Otro tercer molar al final',
    );
    expect(match, isNotNull);
    expect(match!.start, greaterThan(20));
  });
}
