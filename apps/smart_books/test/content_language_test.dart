import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/domain/content_language.dart';

void main() {
  group('resolveContentLanguage', () {
    test('Spanish source wins over English metadata', () {
      final lang = resolveContentLanguage(
        sourceText:
            'La erupción del tercer molar depende del espacio disponible en el maxilar.',
        metadataLanguage: 'en',
      );
      expect(lang, ContentLanguage.es);
    });

    test('English source wins over Spanish metadata', () {
      final lang = resolveContentLanguage(
        sourceText:
            'The mandibular third molar may remain impacted when space is limited.',
        metadataLanguage: 'es',
      );
      expect(lang, ContentLanguage.en);
    });

    test('metadata fallback when source is ambiguous', () {
      final lang = resolveContentLanguage(
        sourceText: '12345',
        metadataLanguage: 'en',
      );
      expect(lang, ContentLanguage.en);
    });

    test('locale fallback when text and metadata unknown', () {
      final lang = resolveContentLanguage(
        sourceText: 'abc',
        metadataLanguage: 'unknown',
        localeFallback: ContentLanguage.en,
      );
      expect(lang, ContentLanguage.en);
    });
  });
}
