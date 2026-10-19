import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/core/storage/local_pdf_store.dart';

void main() {
  test('isStorageSizeError detecta 413', () {
    expect(
      isStorageSizeError(
        Exception(
          'StorageException(message: Payload too large, statusCode: 413)',
        ),
      ),
      isTrue,
    );
    expect(
      isStorageSizeError(
        Exception('The object exceeded the maximum allowed size'),
      ),
      isTrue,
    );
    expect(shouldCompressBeforeUpload(50 * 1024 * 1024), isTrue);
  });

  test('rutas local/', () {
    expect(LocalPdfStore.isLocalPath('local/u/b.pdf'), isTrue);
    expect(LocalPdfStore.keyFromLocalPath('local/u/b.pdf'), 'u/b.pdf');
    expect(LocalPdfStore.localPathForKey('u/b.pdf'), 'local/u/b.pdf');
  });
}
