import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/core/ui/friendly_errors.dart';

void main() {
  test('friendlyUserError oculta Postgrest NUL', () {
    const raw =
        r'PostgrestException(message: unsupported Unicode escape sequence, code: 22P05, details: \u0000 cannot be converted to text., hint: null)';
    final msg = friendlyUserError(raw);
    expect(msg, contains('texto incompatible'));
    expect(msg, isNot(contains('PostgrestException')));
  });

  test('friendlyUserError traduce FPDF_ERR_FORMAT', () {
    final msg = friendlyUserError(
      'PdfFailed to load PDF document (FPDF_ERR_FORMAT: 3)',
    );
    expect(msg, contains('No pudimos abrir'));
  });
}
